export DictTree, DictBranch, get_layer, haslayer, add_layer!, getlabels

# ------------------------------------------------------------------------------
# TreeLayer Definition
# ------------------------------------------------------------------------------
struct TreeLayer
    tree::SDTree
    on_new_branch::Union{Nothing, Function}
    clean_on_empty_branch::Bool
end

"""
    DictTree()
    DictTree(args...)

A tree with dynamic depth to manage a collection of static depth `SDTree` objects. It automatically routes data assignments and lookups to the proper `SDTree` based on the length of the provided `Tuple` key.

Also, it accepts all the parameters typically used to build a dictionary, namely a standard `AbstractDict`, a list of pairs, or separate arrays of keys and values.
"""
struct DictTree <: AbstractDict{Tuple, Any}
    layers::Dict{Int, TreeLayer}
    labels::Dict{Symbol, Int}
end

DictTree() = DictTree(Dict{Int, TreeLayer}(), Dict{Symbol, Int}())

function DictTree(tree::SDTree; kws...)
    out = DictTree()
    add_layer!(out, tree; kws...)
    return out
end

DictTree(dict::AbstractDict) = _populate_dict!(DictTree(), dict)
DictTree(p::Vararg{Pair}) = _populate_dict!(DictTree(), p...)
DictTree(keys::AbstractVector, values::AbstractVector) = _populate_dict!(DictTree(), keys, values)

# ------------------------------------------------------------------------------
# Routing API
# ------------------------------------------------------------------------------
function Base.setindex!(dt::DictTree, value, key::Tuple)
    depth = length(key)

    if !haskey(dt.layers, depth)
        add_layer!(dt, SDTree{NTuple{length(key), Any}, Any}())  # trees created here always have `Any` values
    end

    for d in 0:(depth - 1)
        layer = get(dt.layers, d, nothing)
        if !isnothing(layer) && !isnothing(layer.on_new_branch)
            prefix = key[1:d]
            if !haskey(layer.tree, prefix)
                arg = d == 1  ?  prefix[1]  :  prefix
                layer.tree[prefix] = layer.on_new_branch(arg)
            end
        end
    end

    target_layer = dt.layers[depth]
    target_layer.tree[key] = value
    return value
end
Base.setindex!(dt::DictTree, value, key) = setindex!(dt, value, (key,))

function Base.getindex(dt::DictTree, key::Tuple)
    depth = length(key)
    layer = get(dt.layers, depth, nothing)
    if !isnothing(layer)
        haskey(layer.tree, key)  &&  (return layer.tree[key])
    end
    throw(KeyError(key))
end
Base.getindex(dt::DictTree, key) = getindex(dt, (key,))

function Base.haskey(dt::DictTree, key::Tuple)
    depth = length(key)
    layer = get(dt.layers, depth, nothing)
    if !isnothing(layer)
        return haskey(layer.tree, key)
    end
    return false
end
Base.haskey(dt::DictTree, key) = haskey(dt, (key,))

function Base.empty!(dt::DictTree)
    for layer in values(dt.layers)
        empty!(layer.tree)
    end
    return dt
end

# DictTree helpers
_sorted_trees(dt::DictTree, min_depth=0) = (dt.layers[d].tree for d in sort(collect(keys(dt.layers))) if d >= min_depth)
_sorted_branches(dt::DictTree, prefix) = (view(t, prefix) for t in _sorted_trees(dt, length(prefix)) if haspath(t, prefix))

# ------------------------------------------------------------------------------
# DictTree AbstractDict Implementations
# ------------------------------------------------------------------------------
Base.length(dt::DictTree) = sum(length(layer.tree) for layer in values(dt.layers); init=0)

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
end

_sorted_branches(db::DictBranch) = _sorted_branches(db.dt, db.prefix)

function Base.empty!(db::DictBranch)
    for b in _sorted_branches(db)
        empty!(b)
    end
    return db
end

Base.view(dt::DictTree, prefix::Tuple) = DictBranch(dt, prefix)
Base.view(dt::DictTree, key) = view(dt, (key,))
Base.view(db::DictBranch, suffix::Tuple) = view(db.dt, (db.prefix..., suffix...))
Base.view(db::DictBranch, key) = view(db, (key,))

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

Base.length(db::DictBranch) = sum(length(b) for b in _sorted_branches(db); init=0)

Base.iterate(db::DictBranch) = iterate(Iterators.flatten(_sorted_branches(db)))
Base.iterate(db::DictBranch, state) = iterate(Iterators.flatten(_sorted_branches(db)), state)

Base.keys(db::DictBranch) = Iterators.flatten(keys(b) for b in _sorted_branches(db))
Base.values(db::DictBranch) = Iterators.flatten(values(b) for b in _sorted_branches(db))

# ------------------------------------------------------------------------------
# Layer Accessors
# ------------------------------------------------------------------------------
"""
    get_layer(dt::DictTree, depth::Int)
    get_layer(dt::DictTree, label::Symbol)
    get_layer(db::DictBranch, depth::Int)
    get_layer(db::DictBranch, label::Symbol)

Retrieves the underlying `SDTree` (or `SDBranch` view) that exists at the requested `depth`, or that is identified by `label`.
Throws a `KeyError` if no data has been initialized at that depth.
"""
get_layer(dt::DictTree, depth::Int) = dt.layers[depth].tree
get_layer(dt::DictTree, label::Symbol) = get_layer(dt, dt.labels[label])

get_layer(db::DictBranch, depth::Int) = view(get_layer(db.dt, depth), db.prefix)
get_layer(db::DictBranch, label::Symbol) = view(get_layer(db.dt, label), db.prefix)

"""
    haslayer(dt::DictTree, depth::Int)
    haslayer(dt::DictTree, label::Symbol)
    haslayer(db::DictBranch, label::Symbol)

Returns `true` if the shell currently manages a tree or branch at the requested `depth`, or which is identified by `label`.
"""
haslayer(dt::DictTree, depth::Int) = haskey(dt.layers, depth)
haslayer(dt::DictTree, label::Symbol) = haskey(dt.labels, label)  &&  haskey(dt.layers, dt.labels[label])
haslayer(db::DictBranch, depth::Int) = haslayer(db.dt, depth)  &&  haspath(get_layer(db.dt, depth), db.prefix)
haslayer(db::DictBranch, label::Symbol) = haskey(db.dt.labels, label)  &&  haslayer(db, db.dt.labels[label])

"""
    getlabels(dt::DictTree)
    getlabels(db::DictBranch)

Returns the dictionary mapping `Symbol` labels to their corresponding tree depths.
"""
getlabels(dt::DictTree) = dt.labels
getlabels(db::DictBranch) = db.dt.labels


# ------------------------------------------------------------------------------
# Tree Injection / Initialization
# ------------------------------------------------------------------------------
"""
    add_layer!(dt::DictTree, tree::SDTree;
              label::Union{Nothing, Symbol}=nothing,
              on_new_branch::Union{Nothing, Function}=nothing,
              clean_on_empty_branch::Bool=false)

Manually injects an existing `SDTree` into the `DictTree` shell.

**Keyword Arguments:**
* `label`: Assigns a semantic label to the specific tree depth, allowing you to retrieve the tree later using `get_layer(dt, label)`.
* `on_new_branch`: A function mapping a partial tuple key (`KT`) to a value (`VT`). It is automatically invoked to populate this layer whenever a user sets a value at a deeper level and the intermediate branch doesn't exist.
* `clean_on_empty_branch`: If set to `true`, deleting or pruning all the deeper children of a node will automatically trigger the deletion of this layer's corresponding entries, keeping the tree free of orphaned branches.

Throws an `ArgumentError` if the shell already manages a tree at that specific depth.
"""
function add_layer!(dt::DictTree, tree::SDTree;
                   label::Union{Nothing, Symbol}=nothing,
                   on_new_branch::Union{Nothing, Function}=nothing,
                   clean_on_empty_branch::Bool=false)
    d = depth(tree)
    if haskey(dt.layers, d)
        throw(ArgumentError("DictTree already contains a tree at depth $d."))
    end

    dt.layers[d] = TreeLayer(tree, on_new_branch, clean_on_empty_branch)
    isnothing(label)  ||  (dt.labels[label] = d)

    return dt
end
