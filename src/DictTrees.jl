export DictTree, DictBranch, get_tree, hasdepth, add_tree!

"""
    DictTree()
    DictTree(trees::Dict{Int, <:SDTree})
    DictTree(tree::SDTree)
    DictTree(args...)

A tree with dynamic depth to manage a collection of static depth `SDTree` objects. It automatically routes data assignments and lookups to the proper `SDTree` based on the length of the provided `Tuple` key.

Also, it accepts all the parameters typically used to build a dictionary, namely a standard `AbstractDict`, a list of pairs, or separate arrays of keys and values.
"""
struct DictTree <: AbstractDict{Tuple, Any}
    trees::Dict{Int, SDTree}

    DictTree() = new(Dict{Int, SDTree}())
    DictTree(trees::Dict{Int, <:SDTree}) = new(trees)
    DictTree(tree::SDTree) = new(Dict{Int, SDTree}(depth(tree) => tree))
end

DictTree(dict::AbstractDict) = _populate_dict!(DictTree(), dict)
DictTree(p::Vararg{Pair}) = _populate_dict!(DictTree(), p...)
DictTree(keys::AbstractVector, values::AbstractVector) = _populate_dict!(DictTree(), keys, values)

# ------------------------------------------------------------------------------
# Routing API
# ------------------------------------------------------------------------------
function Base.setindex!(dt::DictTree, value, key::Tuple)
    target_depth = length(key)
    if !haskey(dt.trees, target_depth)
        dt.trees[target_depth] = SDTree{typeof(key), Any}()  # trees created here always have `Any` values
    end
    target_tree = dt.trees[target_depth]
    target_tree[key] = value
end
Base.setindex!(dt::DictTree, value, key) = setindex!(dt, value, (key,))

function Base.getindex(dt::DictTree, key::Tuple)
    target_depth = length(key)
    if haskey(dt.trees, target_depth) && haskey(dt.trees[target_depth], key)
        return dt.trees[target_depth][key]
    end
    throw(KeyError(key))
end
Base.getindex(dt::DictTree, key) = getindex(dt, (key,))

function Base.haskey(dt::DictTree, key::Tuple)
    target_depth = length(key)
    if haskey(dt.trees, target_depth)
        return haskey(dt.trees[target_depth], key)
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
    get_tree(db::DictBranch, depth::Int)

Retrieves the underlying `SDTree` (or `SDBranch` view) that exists at the requested `depth`.
Throws a `KeyError` if no data has been initialized at that depth.
"""
get_tree(dt::DictTree, depth::Int) = dt.trees[depth]
get_tree(db::DictBranch, depth::Int) = db.branches[depth]

"""
    hasdepth(dt::DictTree, depth::Int)
    hasdepth(db::DictBranch, depth::Int)

Returns `true` if the shell currently manages a tree or branch at the explicitly requested `depth`.
"""
hasdepth(dt::DictTree, depth::Int) = haskey(dt.trees, depth)
hasdepth(db::DictBranch, depth::Int) = haskey(db.branches, depth)


# ------------------------------------------------------------------------------
# Tree Injection / Initialization
# ------------------------------------------------------------------------------
"""
    add_tree!(dt::DictTree, tree::SDTree)

Manually injects an existing `SDTree` into the `DictTree` shell.
Throws an `ArgumentError` if the shell already manages a tree at that specific depth.
"""
function add_tree!(dt::DictTree, tree::SDTree)
    d = depth(tree)
    if haskey(dt.trees, d)
        throw(ArgumentError("DictTree already contains a tree at depth $d."))
    end
    dt.trees[d] = tree
    return dt
end

"""
    add_tree!(dt::DictTree, ::Type{KT}, ::Type{VT}=Any)

Pre-initializes an empty `SDTree` within the `DictTree` with a specific tuple key type (`KT`) and value type (`VT`).
"""
function add_tree!(dt::DictTree, ::Type{KT}, ::Type{VT}=Any) where {KT <: Tuple, VT}
    d = fieldcount(KT)
    if haskey(dt.trees, d)
        throw(ArgumentError("DictTree already contains a tree at depth $d."))
    end

    new_tree = SDTree{KT, VT}()
    dt.trees[d] = new_tree
    return dt
end
