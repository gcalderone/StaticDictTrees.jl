export DictTree, DictBranch, get_tree, hasdepth, add_tree!

"""
    DictTree()
    DictTree(tree::SDTree; label::Union{Nothing, Symbol}=nothing, initializer::Union{Nothing, Function}=nothing)
    DictTree(args...)

A tree with dynamic depth to manage a collection of static depth `SDTree` objects. It automatically routes data assignments and lookups to the proper `SDTree` based on the length of the provided `Tuple` key.

Also, it accepts all the parameters typically used to build a dictionary, namely a standard `AbstractDict`, a list of pairs, or separate arrays of keys and values.
"""
struct DictTree <: AbstractDict{Tuple, Any}
    trees::Dict{Int, SDTree}
    labels::Dict{Symbol, Int}
    initializers::Dict{Int, Union{Nothing, Function}}
    validators::Dict{Int, Union{Nothing, Function}}
    autocleans::Dict{Int, Bool}

    DictTree() = new(Dict{Int, SDTree}(), Dict{Symbol, Int}(),
                     Dict{Int, Union{Nothing, Function}}(),
                     Dict{Int, Union{Nothing, Function}}(),
                     Dict{Int, Bool}())
end

function DictTree(tree::SDTree; kws...)
    out = DictTree()
    add_tree!(out, tree; kws...)
    return out
end

DictTree(dict::AbstractDict) = _populate_dict!(DictTree(), dict)
DictTree(p::Vararg{Pair}) = _populate_dict!(DictTree(), p...)
DictTree(keys::AbstractVector, values::AbstractVector) = _populate_dict!(DictTree(), keys, values)

# ------------------------------------------------------------------------------
# Routing API
# ------------------------------------------------------------------------------
validate_and_set!(t::SDTree, value, key, f::Nothing) = t[key] = value
function validate_and_set!(t::SDTree, value, key, f::Function)
    if f(t, key, value)
        t[key] = value
    else
        throw(ArgumentError("Validation failed for key $key and value $value"))
    end
end

function Base.setindex!(dt::DictTree, value, key::Tuple)
    depth = length(key)
    if !haskey(dt.trees, depth)
        add_tree!(dt, SDTree{typeof(key), Any}())  # trees created here always have `Any` values
    end

    for d in 1:(depth - 1)
        f = get(dt.initializers, d, nothing)
        if !isnothing(f)
            t = get_tree(dt, d)
            prefix = key[1:d]
            if !haskey(t, prefix)
                arg = d == 1  ?  prefix[1]  :  prefix
                validate_and_set!(t, f(arg), prefix, get(dt.validators, d, nothing))
            end
        end
    end

    validate_and_set!(get_tree(dt, depth), value, key, get(dt.validators, depth, nothing))
    return value
end
Base.setindex!(dt::DictTree, value, key) = setindex!(dt, value, (key,))

function Base.getindex(dt::DictTree, key::Tuple)
    depth = length(key)
    if haskey(dt.trees, depth) && haskey(dt.trees[depth], key)
        return dt.trees[depth][key]
    end
    throw(KeyError(key))
end
Base.getindex(dt::DictTree, key) = getindex(dt, (key,))

function Base.haskey(dt::DictTree, key::Tuple)
    depth = length(key)
    if haskey(dt.trees, depth)
        return haskey(dt.trees[depth], key)
    end
    return false
end
Base.haskey(dt::DictTree, key) = haskey(dt, (key,))

function Base.empty!(dt::DictTree)
    for t in values(dt.trees)
        empty!(t)
    end
    return dt
end

# ------------------------------------------------------------------------------
# DictTree AbstractDict Implementations
# ------------------------------------------------------------------------------
Base.length(dt::DictTree) = sum(length(t) for t in values(dt.trees); init=0)

# Helper to ensure we iterate through the layers in a predictable top-to-bottom order
_sorted_trees(dt::DictTree) = (dt.trees[d] for d in sort(collect(keys(dt.trees))))

Base.iterate(dt::DictTree) = iterate(Iterators.flatten(_sorted_trees(dt)))
Base.iterate(dt::DictTree, state) = iterate(Iterators.flatten(_sorted_trees(dt)), state)

Base.keys(dt::DictTree) = Iterators.flatten(keys(t) for t in _sorted_trees(dt))
Base.values(dt::DictTree) = Iterators.flatten(values(t) for t in _sorted_trees(dt))

# ------------------------------------------------------------------------------
# DictBranch (Routing Views)
# ------------------------------------------------------------------------------
"""
    DictBranch(dt::DictTree, prefix::Tuple)

A view representing a subset of a `DictTree`. It behaves as a standard dictionary and dynamically spans across all applicable underlying `SDTree`s.
"""
struct DictBranch <: AbstractDict{Tuple, Any}
    dt::DictTree
    prefix::Tuple
    branches::Dict{Int, AbstractSDTree}
end

function Base.empty!(db::DictBranch)
    for b in values(db.branches)
        empty!(b)
    end
    return db
end

function Base.view(dt::DictTree, prefix::Tuple)
    matching_branches = Dict{Int, AbstractSDTree}()

    for (depth, t) in dt.trees
        if depth >= length(prefix)
            try
                matching_branches[depth] = view(t, prefix)
            catch KeyError
            end
        end
    end

    if isempty(matching_branches)
        throw(KeyError(prefix))
    end

    return DictBranch(dt, prefix, matching_branches)
end
Base.view(dt::DictTree, key) = view(dt, (key,))

function Base.getindex(db::DictBranch, key::Tuple)
    full_key = (db.prefix..., key...)
    return db.dt[full_key]
end
Base.getindex(db::DictBranch, key) = getindex(db, (key,))

function Base.setindex!(db::DictBranch, value, key::Tuple)
    full_key = (db.prefix..., key...)
    db.dt[full_key] = value
end
Base.setindex!(db::DictBranch, value, key) = setindex!(db, value, (key,))

function Base.haskey(db::DictBranch, key::Tuple)
    full_key = (db.prefix..., key...)
    return haskey(db.dt, full_key)
end
Base.haskey(db::DictBranch, key) = haskey(db, (key,))


# ------------------------------------------------------------------------------
# DictBranch AbstractDict Implementations
# ------------------------------------------------------------------------------
Base.length(db::DictBranch) = sum(length(b) for b in values(db.branches); init=0)

_sorted_branches(db::DictBranch) = (db.branches[d] for d in sort(collect(keys(db.branches))))

Base.iterate(db::DictBranch) = iterate(Iterators.flatten(_sorted_branches(db)))
Base.iterate(db::DictBranch, state) = iterate(Iterators.flatten(_sorted_branches(db)), state)

Base.keys(db::DictBranch) = Iterators.flatten(keys(b) for b in _sorted_branches(db))
Base.values(db::DictBranch) = Iterators.flatten(values(b) for b in _sorted_branches(db))

# ------------------------------------------------------------------------------
# Layer Accessors
# ------------------------------------------------------------------------------
"""
    get_tree(dt::DictTree, depth::Int)
    get_tree(dt::DictTree, label::Symbol)
    get_tree(db::DictBranch, depth::Int)
    get_tree(db::DictBranch, label::Symbol)

Retrieves the underlying `SDTree` (or `SDBranch` view) that exists at the requested `depth`, or that is identified by `label`.
Throws a `KeyError` if no data has been initialized at that depth.
"""
get_tree(dt::DictTree, depth::Int) = dt.trees[depth]
get_tree(dt::DictTree, label::Symbol) = get_tree(dt, dt.labels[label])
get_tree(db::DictBranch, depth::Int) = db.branches[depth]
get_tree(db::DictBranch, label::Symbol) = db.branches[db.dt.labels[label]]

"""
    hasdepth(dt::DictTree, depth::Int)
    hasdepth(db::DictBranch, depth::Int)

Returns `true` if the shell currently manages a tree or branch at the explicitly requested `depth`.
"""
hasdepth(dt::DictTree, depth::Int) = haskey(dt.trees, depth)
hasdepth(dt::DictTree, label::Symbol) = haskey(dt.labels, label)  &&  haskey(dt.trees, dt.labels[label])
hasdepth(db::DictBranch, depth::Int) = haskey(db.branches, depth)


# ------------------------------------------------------------------------------
# Tree Injection / Initialization
# ------------------------------------------------------------------------------
"""
    add_tree!(dt::DictTree, tree::SDTree;
              label::Union{Nothing, Symbol}=nothing,
              initializer::Union{Nothing, Function}=nothing,
              validator::Union{Nothing, Function}=nothing,
              autoclean::Bool=false)

Manually injects an existing `SDTree` into the `DictTree` shell.

**Keyword Arguments:**
* `label`: Assigns a semantic label to the specific tree depth, allowing you to retrieve the tree later using `get_tree(dt, label)`.
* `initializer`: A function mapping a partial tuple key (`KT`) to a value (`VT`). It is automatically invoked to populate this layer whenever a user sets a value at a deeper level and the intermediate branch doesn't exist.
* `validator`: A function `f(tree::SDTree, key, value) -> Bool` used to validate a value before it is inserted into the tree. If it returns `false`, an `ArgumentError` is thrown.
* `autoclean`: If set to `true`, deleting or pruning all the deeper children of a node will automatically trigger the deletion of this layer's corresponding entries, keeping the tree free of orphaned branches.

Throws an `ArgumentError` if the shell already manages a tree at that specific depth.
"""
function add_tree!(dt::DictTree, tree::SDTree;
                   label::Union{Nothing, Symbol}=nothing,
                   initializer::Union{Nothing, Function}=nothing,
                   validator::Union{Nothing, Function}=nothing,
                   autoclean::Bool=false)
    d = depth(tree)
    if haskey(dt.trees, d)
        throw(ArgumentError("DictTree already contains a tree at depth $d."))
    end
    dt.trees[d] = tree
    isnothing(label)  ||  (dt.labels[label] = d)
    isnothing(initializer)  ||  (dt.initializers[d] = initializer)
    isnothing(validator)    ||  (dt.validators[d] = validator)
    autoclean               &&  (dt.autocleans[d] = true)
    return dt
end
