module StaticDictTrees

using DataStructures
import Base: empty!, length, iterate, getindex, setindex!, haskey, keys, values, parent, show, view, sizehint!

export AbstractSDTree, SDTree, SDBranch, SDLeaf, prune!, is_leaf_level, depth, is_stale, root, prefix, values_view, haspath


_default_insert(key, newval) = newval
_default_update(key, oldval, newval) = newval
_default_delete(key, oldval) = nothing

#=
Conventions:
- KT: Key Type
- VT: Value Type
- PT: Prefix Type
- ST: Suffix Type
- HT: Hook Type
=#

"""
    AbstractSDTree{KT <: Tuple, VT} <: AbstractDict{KT, VT}

Abstract base type for static dictionary trees and their branch views.
"""
abstract type AbstractSDTree{KT <: Tuple, VT} <: AbstractDict{KT, VT} end

# ------------------------------------------------------------------------------
# SDTree structure
# ------------------------------------------------------------------------------
"""
    SDTree{KT <: Tuple, VT}()

A flattened hierarchical dictionary that maps fixed-depth `Tuple` keys of type `KT` to values of type `VT`, while still allowing to retrieve all values as a (view on a) `Vector`.
"""
struct SDTree{KT <: Tuple, VT, HT} <: AbstractSDTree{KT, VT}
    keys::Vector{KT}
    values::Vector{VT}
    lookup::OrderedDict{KT, Int}
    viewid::Vector{Int}
    branch_lookup::Tuple
    branch_viewids::Tuple
    hooks::HT # lifecycle hooks

"""
    SDTree{KT, VT}(args...; kwargs...)
    SDTree{KT, VT}(; kwargs...)

Constructs an `SDTree` with keys of type `KT` and leaf values of type `VT`.

**Keyword Arguments:**
* `on_insert`: A function `f(key::KT, value) -> VT` invoked when a new key is added. It must return the value that will actually be stored. Defaults to an identity function.
* `on_update`: A function `f(key::KT, old_value::VT, new_value) -> VT` invoked when an existing key is modified. It must return the updated value. Defaults to returning `new_value`.
* `on_delete`: A function `f(key::KT, value::VT)` invoked right *before* a key-value pair is deleted from the tree. The default implementation does nothing.
"""
    function SDTree{KT, VT}(args...;
                            on_insert::Function=_default_insert,
                            on_update::Function=_default_update,
                            on_delete::Function=_default_delete) where {KT <: Tuple, VT}
        N = fieldcount(KT)
        if N > 0
            bl = ntuple(N-1) do i
                types = fieldtypes(KT)
                prefix_type = Tuple{types[1:i]...}
                branch_type = Tuple{types[i+1:end]...}
                Dict{prefix_type, OrderedDict{branch_type, Int}}()
            end
            bv = ntuple(N-1) do i
                types = fieldtypes(KT)
                prefix_type = Tuple{types[1:i]...}
                Dict{prefix_type, Vector{Int}}()
            end
        else
            bl = ()
            bv = ()
        end

        hooks = (on_insert=on_insert,
                 on_update=on_update,
                 on_delete=on_delete)
        HT = typeof(hooks)

        out = new{KT, VT, typeof(hooks)}(KT[], VT[], OrderedDict{KT, Int}(), Int[], bl, bv, hooks)
        _populate_dict!(out, args...)
        return out
    end
end


"""
    SDTree(dict::AbstractDict{KT, VT})
    SDTree(p::Vararg{Pair{KT, VT}})
    SDTree(keys::AbstractVector{KT}, values::AbstractVector{VT})

Constructs an `SDTree` with `KT` keys and `VT` values from an existing dictionary, a list of pairs, or separate arrays of keys and values.
"""
SDTree() = throw(ArgumentError("Key and value types must be specified, e.g. `SDTree{Tuple{Symbol, Int}, Float64}()`."))
SDTree(dict::AbstractDict{KT, VT}) where {KT <: Tuple, VT} = _populate_dict!(SDTree{KT, VT}(), dict)
SDTree(p::Vararg{Pair{KT, VT}}) where {KT <: Tuple, VT}    = _populate_dict!(SDTree{KT, VT}(), p...)
SDTree(keys::AbstractVector{KT}, values::AbstractVector{VT}) where {KT <: Tuple, VT} = _populate_dict!(SDTree{KT, VT}(), keys, values)

"""
    empty!(d::SDTree)
    empty!(v::SDBranch)
    empty!(l::SDLeaf)

Clears all keys, values, and structures from the tree or view.
- For an `SDTree`, it completely resets the tree to an empty state. The `on_delete` hook is **not** invoked.
- For an `SDBranch`, it deletes all the entries sharing the branch prefix, invoking `on_delete` for each of them.
- For an `SDLeaf`, it removes just the leaf, invoking `on_delete`.
"""
function empty!(d::SDTree)
    empty!(d.keys)
    empty!(d.values)
    empty!(d.lookup)
    empty!(d.viewid)
    for level_dict in d.branch_lookup
        for (k, v) in level_dict
            empty!(v)
        end
        empty!(level_dict)
    end
    for level_dict in d.branch_viewids
        for (k, v) in level_dict
            empty!(v)  # invalidate cached indices shared with existing `values_view` objects
        end
        empty!(level_dict)
    end
    return d
end

# ------------------------------------------------------------------------------
# Insertion / Updates
# ------------------------------------------------------------------------------

#=
    _populate_branch_lookup!(d::SDTree, key::KT, I::Int)

A `@generated` function that fully unwinds a leaf `key` and registers its `I` index into the hierarchical `branch_lookup` dictionary at every depth, enabling fast branch views.
=#
@generated function _populate_branch_lookup!(d::SDTree{KT}, key::KT, I::Int) where {KT <: Tuple}
    N = fieldcount(KT)
    N <= 1 && return :(nothing)
    exprs = Expr[]

    for depth in 1:(N-1)
        prefix_type = Tuple{fieldtypes(KT)[1:depth]...}
        branch_type = Tuple{fieldtypes(KT)[depth+1:end]...}

        push!(exprs, quote
            prefix = $(Expr(:tuple, [:(key[$i]) for i in 1:depth]...))::$prefix_type
            suffix = $(Expr(:tuple, [:(key[$i]) for i in (depth+1):N]...))::$branch_type

            bl_at_depth = d.branch_lookup[$depth]::Dict{$prefix_type, OrderedDict{$branch_type, Int}}
            specific_bl = get(bl_at_depth, prefix, nothing)
            if isnothing(specific_bl)
                bl_at_depth[prefix] = OrderedDict{$branch_type, Int}(suffix => I)
            else
                specific_bl[suffix] = I
            end

            bv_at_depth = d.branch_viewids[$depth]::Dict{$prefix_type, Vector{Int}}
            specific_bv = get(bv_at_depth, prefix, nothing)
            if isnothing(specific_bv)
                bv_at_depth[prefix] = [I]
            else
                isempty(specific_bv)  ||  push!(specific_bv, I)
            end
        end)
    end
    return Expr(:block, exprs...)
end

"""
    setindex!(d::SDTree, value, key::Tuple)
    setindex!(v::SDBranch, value, suffix::Tuple)
    d[key] = value
    v[suffix] = value

Inserts or updates a value in the tree at the given `key`, or at the given `suffix` (used in conjunction with the branch prefix to produce the entire key).
"""
function setindex!(d::SDTree{KT, VT}, value, key::KT) where {KT <: Tuple, VT}
    idx = get(d.lookup, key, nothing)
    if !isnothing(idx)
        old_val = d.values[idx]
        d.values[idx] = d.hooks.on_update(key, old_val, value)
    else
        # Run the hook and the conversion before touching any internal structure, so that
        # an exception (e.g. a validation hook rejecting the value) leaves the tree unchanged.
        new_val = convert(VT, d.hooks.on_insert(key, value))
        push!(d.keys, key)
        push!(d.values, new_val)
        I = length(d.values)
        d.lookup[key] = I
        _populate_branch_lookup!(d, key, I)
        isempty(d.viewid)  ||  push!(d.viewid, I)
    end
    return value
end

setindex!(d::SDTree{KT}, value, key::T) where {KT <: Tuple, T <: Tuple} = throw(ArgumentError("Invalid key type: $KT != $T"))
setindex!(d::SDTree{KT}, value, key)    where {KT <: Tuple} = setindex!(d, value, (key,))

# ------------------------------------------------------------------------------
# SDBranch structure
# ------------------------------------------------------------------------------
"""
    SDBranch(d::SDTree{KT, VT}, prefix::PT) where {KT, VT, PT <: Tuple}
    SDBranch(v::SDBranch, suffix::Tuple)

Creates a view on the branch of an `SDTree` identified by an incomplete key (`prefix`), i.e. on all the entries whose key starts with `prefix`.  The second form creates a view on a sub-branch of an existing branch, identified by the concatenation of the branch prefix and `suffix`.

The returned object is concretely typed, hence all operations on it are type-stable (its construction, however, involves a runtime dispatch).  It is usually created by means of `view`.

Throws a `KeyError` if the branch does not exist, and an `ArgumentError` if the prefix is empty or not shorter than the tree keys.
"""
struct SDBranch{KT, PT, ST, VT, HT} <: AbstractSDTree{ST, VT}
    root::SDTree{KT, VT, HT}
    prefix::PT
    lookup::OrderedDict{ST, Int}
    viewid::Vector{Int}

    function SDBranch(d::SDTree{KT, VT, HT}, prefix::PT) where {KT, VT, PT <: Tuple, HT}
        N = fieldcount(KT)
        M = fieldcount(PT)
        (M < N)  ||  throw(ArgumentError("Prefix length ($M) must be strictly less than key length ($N)."))
        (M > 0)  ||  throw(ArgumentError("Prefix must not be empty: use the root tree instead (`view(tree, ())` returns the tree itself)."))
        if haskey(d.branch_lookup[M], prefix)
            ST = Tuple{fieldtypes(KT)[M+1:end]...}
            new{KT, PT, ST, VT, HT}(d, prefix, d.branch_lookup[M][prefix], d.branch_viewids[M][prefix])
        else
            throw(KeyError(prefix))
        end
    end
    SDBranch(v::SDBranch, suffix::Tuple) = SDBranch(v.root, (v.prefix..., suffix...))
end

function empty!(v::SDBranch)
    M = length(v.prefix)
    dict = get(v.root.branch_lookup[M], v.prefix, nothing)
    if !isnothing(dict)
        for suff in collect(keys(dict))
            delete!(v.root, (v.prefix..., suff...))
        end
    end
    return v
end

@generated function setindex!(v::SDBranch{KT, PT, ST}, value, key::ST) where {KT <: Tuple, PT <: Tuple, ST <: Tuple}
    M = fieldcount(PT)
    L = fieldcount(ST)
    combined_tuple = Expr(:tuple, [:(v.prefix[$i]) for i in 1:M]..., [:(key[$i]) for i in 1:L]...)
    return quote
        return setindex!(v.root, value, $combined_tuple)
    end
end


setindex!(v::SDBranch{KT, PT, ST}, value, key::T)  where {KT <: Tuple, PT <: Tuple, ST <: Tuple, T <: Tuple} = throw(ArgumentError("Invalid key type: $ST != $T"))
setindex!(v::SDBranch{KT, PT, ST}, value, key)     where {KT <: Tuple, PT <: Tuple, ST <: Tuple} = setindex!(v, value, (key,))

# ------------------------------------------------------------------------------
# SDLeaf structure
# ------------------------------------------------------------------------------
"""
    SDLeaf(root::SDTree, key::KT)

A zero-allocation view into a specific leaf of an `SDTree`. It acts as a 0-dimensional dictionary containing exactly one value.
"""
struct SDLeaf{KT, VT, HT} <: AbstractSDTree{Tuple{}, VT}
    root::SDTree{KT, VT, HT}
    key::KT

    SDLeaf(d::SDTree{KT, VT, HT}, key::KT) where {KT, VT, HT} = new{KT, VT, HT}(d, key)
    SDLeaf(v::SDBranch, suffix::Tuple) = SDLeaf(v.root, (v.prefix..., suffix...))
end

function empty!(v::SDLeaf)
    delete!(v.root, v.key)
    return v
end

setindex!(v::SDLeaf, value, key::Tuple{}) = (v.root[v.key] = value; value)

# ------------------------------------------------------------------------------
# Method implementations
# ------------------------------------------------------------------------------

"""
    keys(d::SDTree)
    keys(v::SDBranch)
    keys(l::SDLeaf)

Returns an iterator over the keys of the tree, branch or leaf.
"""
keys(d::SDTree) = keys(d.lookup)
keys(v::SDBranch) = keys(v.lookup)
keys(v::SDLeaf{KT, VT}) where {KT, VT} = is_stale(v) ? Tuple{}[] : [()]


"""
    length(d::SDTree)
    length(v::SDBranch)
    length(l::SDLeaf)

Returns the total number of **leaves** currently accessible within the tree or branch.
"""
length(d::SDTree) = length(d.values)
length(v::SDBranch) = length(v.lookup)
length(v::SDLeaf) = is_stale(v) ? 0 : 1

"""
    values(d::SDTree)
    values(v::SDBranch)
    values(l::SDLeaf)

Returns an iterator over the **leaf-level** values within the tree or view.
"""
values(d::SDTree) = (d.values[i] for i in values(d.lookup))
values(v::SDBranch) = (v.root.values[i] for i in values(v.lookup))
values(v::SDLeaf{KT, VT}) where {KT, VT} = is_stale(v) ? VT[] : [v.root[v.key]]

"""
    values_view(d::SDTree)
    values_view(v::SDBranch)
    values_view(l::SDLeaf)

Returns a `SubArray` on the internal vector of values, containing the values of the tree, branch or leaf in insertion order.

Unlike `values()`, which returns a lazy iterator, `values_view()` returns an `AbstractVector`, which can be used to read and modify the existing values (modifications are reflected in the parent tree).  Entries can not be added or removed through it.

Insertions in the tree are reflected in a previously obtained `values_view`, while a deletion invalidates it (it becomes empty): call `values_view` again to obtain an updated one.  The `values_view` of a stale view is empty.
"""
function values_view(d::SDTree)
    if isempty(d.viewid)  ||  (length(d.viewid) != length(d.values))
        empty!(d.viewid)
        append!(d.viewid, values(d.lookup))
    end
    return view(d.values, d.viewid)
end

function values_view(v::SDBranch)
    is_stale(v)  &&  return @view v.root.values[Int[]]

    if isempty(v.viewid)  ||  (length(v.viewid) != length(v.lookup))
        empty!(v.viewid)
        append!(v.viewid, values(v.lookup))
    end
    return view(v.root.values, v.viewid)
end

function values_view(v::SDLeaf{KT, VT}) where {KT, VT}
    is_stale(v)  &&  (return @view v.root.values[Int[]])
    return view(v.root.values, [v.root.lookup[v.key]])
end

"""
    haskey(d::SDTree, key::Tuple)
    haskey(v::SDBranch, key::Tuple)

Returns `true` if the specific `key` has an explicitly assigned value (i.e. a leaf).
"""
haskey(d::SDTree{KT}, key::KT)    where {KT <: Tuple} = haskey(d.lookup, key)
haskey(d::SDTree{KT}, key::Tuple) where {KT <: Tuple} = false
haskey(d::SDTree, key) = haskey(d, (key,))

haskey(v::SDBranch{KT, PT, ST}, key::ST)    where {KT <: Tuple, PT <: Tuple, ST <: Tuple} = haskey(v.lookup, key)
haskey(v::SDBranch{KT, PT, ST}, key::Tuple) where {KT <: Tuple, PT <: Tuple, ST <: Tuple} = false
haskey(v::SDBranch{KT, PT, ST}, key)        where {KT <: Tuple, PT <: Tuple, ST <: Tuple} = haskey(v, (key,))

haskey(v::SDLeaf, key::Tuple{}) = !is_stale(v)  &&  (key == Tuple{}())
haskey(v::SDLeaf, key::Tuple)   = false

"""
    depth(d::SDTree)
    depth(v::SDBranch)
    depth(l::SDLeaf)

Returns the number of key elements still needed to reach a leaf, i.e. the length of the keys accepted by the object: the key length for an `SDTree`, the suffix length for an `SDBranch`, and 0 for an `SDLeaf`.
"""
depth(::SDTree{KT})               where {KT}         = fieldcount(KT)
depth(::SDBranch{KT, PT, ST})     where {KT, PT, ST} = fieldcount(ST)
depth(::SDLeaf)                                      = 0

"""
    is_leaf_level(d::AbstractSDTree)

Returns `true` if the tree or branch is exactly one level above the leaves, i.e. if `depth(d) == 1` (its direct children are `SDLeaf` objects, and it can be indexed by a scalar).  Returns `false` for an `SDLeaf` and for a tree with depth 0.
"""
is_leaf_level(d::AbstractSDTree) = depth(d) == 1

"""
    is_stale(d::AbstractSDTree)

Returns `true` if a view (`SDBranch` or `SDLeaf`) is no longer valid because its underlying data or structural path was deleted or pruned from the root tree.
Always returns `false` for the root `SDTree`.

It is highly recommended to check `is_stale(v)` before mutating, accessing or iterating over a view, as the parent tree may have changed.
"""
is_stale( ::SDTree) = false
is_stale(v::SDBranch{KT, PT}) where {KT, PT} = (length(v.lookup) == 0)
is_stale(v::SDLeaf) = !haskey(v.root.lookup, v.key)

"""
    parent(v::SDBranch)
    parent(l::SDLeaf)

Returns an `SDBranch` view representing the immediate parent of the given branch or leaf. If the parent is the root of the tree, it returns the `SDTree` itself.
"""
parent(d::SDTree) = nothing
parent(v::SDBranch) = length(v.prefix) == 1  ?  v.root  :  SDBranch(v.root, v.prefix[1:(end-1)])
function parent(v::SDLeaf{KT}) where {KT}
    (fieldcount(KT) <= 1) && return v.root
    return SDBranch(v.root, v.key[1:(end-1)])
end

"""
    root(d::SDTree)
    root(v::SDBranch)
    root(l::SDLeaf)

Returns the root `SDTree` of a branch or leaf view (or the tree itself).  Use it to reach other parts of the tree from a view, e.g. `root(branch)[full_key]`.
"""
root(d::SDTree) = d
root(v::SDBranch) = v.root
root(v::SDLeaf) = v.root

"""
    prefix(v::SDBranch)
    prefix(db::DictBranch)

Returns the key prefix identifying the branch, i.e. the tuple which, concatenated with the branch keys, gives the full keys in the root tree.
"""
prefix(v::SDBranch) = v.prefix

"""
    iterate(d::AbstractSDTree, [state])

Iterates over the leaf-level key-value pairs of the tree or branch. Yields `(key => value)`.
"""
function iterate(d::SDTree{KT}, state=nothing) where {KT}
    res = state === nothing ? iterate(d.lookup) : iterate(d.lookup, state)
    res === nothing && return nothing
    (key, idx), next_state = res
    return (key => d.values[idx], next_state)
end

function iterate(v::SDBranch, state=nothing)
    res = state === nothing ? iterate(v.lookup) : iterate(v.lookup, state)
    res === nothing && return nothing
    (key, idx), next_state = res
    return (key => v.root.values[idx], next_state)
end

function iterate(v::SDLeaf, state=nothing)
    (isnothing(state)  &&  !is_stale(v))  &&  (return (Tuple{}() => v.root[v.key], 1))
    return nothing
end

"""
    getindex(d::SDTree, key::Tuple)
    getindex(v::SDBranch, suffix::Tuple)
    d[key]
    v[key]

Retrieves the value associated with the given `key` or the given `suffix` (used in conjunction with the branch prefix to produce the entire key).
"""
getindex(d::SDTree{KT}, key::KT) where {KT <: Tuple} = d.values[d.lookup[key]]
getindex(d::SDTree{KT}, key::T)  where {KT <: Tuple, T <: Tuple} = throw(ArgumentError("Invalid key type: $KT != $T"))
getindex(d::SDTree{KT}, key)     where {KT <: Tuple} = getindex(d, (key,))

getindex(v::SDBranch{KT, PT, ST}, key::ST) where {KT <: Tuple, PT <: Tuple, ST <: Tuple} = v.root.values[v.lookup[key]]
getindex(v::SDBranch{KT, PT, ST}, key::T)  where {KT <: Tuple, PT <: Tuple, ST <: Tuple, T <: Tuple} = throw(ArgumentError("Invalid key type: $ST != $T"))
getindex(v::SDBranch{KT, PT, ST}, key)     where {KT <: Tuple, PT <: Tuple, ST <: Tuple} = getindex(v, (key,))

getindex(v::SDLeaf, key::Tuple{}) = v.root[v.key]

"""
    sizehint!(d::SDTree, n::Integer)

Suggest that the tree `d` reserve memory capacity for at least `n` entries.

Calling `sizehint!` before large bulk insertions pre-allocates the main internal structures (the vectors of keys and values, and the key lookup dictionary), reducing reallocations.  The internal dictionaries of the individual branches are not pre-allocated.
"""
function sizehint!(d::SDTree, n::Integer)
    sizehint!(d.keys, n)
    sizehint!(d.values, n)
    sizehint!(d.lookup, n)
    if !isempty(d.branch_lookup)
        sizehint!(d.branch_lookup[1], n)
    end
    return d
end

"""
    view(d::SDTree, prefix::Tuple)
    view(v::SDBranch, suffix::Tuple)

Returns a view into a specific part of the tree: an `SDBranch` if the key is incomplete, an `SDLeaf` if it is complete, or the object itself if the key is the empty tuple.
Throws a `KeyError` if the path does not exist (use `haspath` to check beforehand), and an `ArgumentError` if the key is longer than the tree keys.
"""
function view(d::SDTree{KT}, prefix::Tuple) where {KT <: Tuple}
    if length(prefix) == fieldcount(KT)
        haskey(d, prefix)  ||  throw(KeyError(prefix))
        return SDLeaf(d, prefix)
    elseif length(prefix) == 0
        return d
    else
        return SDBranch(d, prefix)
    end
end
view(d::SDTree{KT}, prefix) where {KT <: Tuple} = view(d, (prefix,))

function view(v::SDBranch{KT, PT, ST}, suffix::Tuple) where {KT, PT, ST}
    if length(suffix) == fieldcount(ST)
        key = (v.prefix..., suffix...)
        haskey(v.root, key)  ||  throw(KeyError(key))
        return SDLeaf(v.root, key)
    elseif length(suffix) == 0
        return v
    else
        return SDBranch(v.root, (v.prefix..., suffix...))
    end
end
view(v::SDBranch{KT, PT, ST}, suffix) where {KT, PT, ST} = view(v, (suffix,))

"""
    haspath(d::SDTree, prefix::Tuple)

Returns `true` if the given key `prefix` identifies an existing path in the tree: a populated branch if the key is incomplete, or an existing entry if it is complete (in which case it is equivalent to `haskey`).  Returns `true` for the empty tuple `()` (the root), and `false` for keys longer than the tree keys.
"""
function haspath(d::SDTree{KT}, prefix::Tuple) where {KT <: Tuple}
    N = fieldcount(KT)
    M = length(prefix)
    (M == 0)  &&  (return true)  # the empty tuple () represents the root, which is always a valid branch
    (M  > N)  &&  (return false)
    (M == N)  &&  (return haskey(d, prefix))
    return haskey(d.branch_lookup[M], prefix)
end

"""
    haspath(v::SDBranch, suffix::Tuple)

Returns `true` if the given `suffix`, appended to the branch prefix, identifies an existing path in the tree (see `haspath(::SDTree, ::Tuple)`).
"""
haspath(v::SDBranch, suffix::Tuple) = haspath(v.root, (v.prefix..., suffix...))

"""
    getKT(x::SDTree)
    getKT(x::SDBranch)

Returns the full Key Type (`KT`) of the given `SDTree` or the parent tree of an `SDBranch`.
This represents the complete tuple type required to traverse from the absolute root down to a terminal leaf node.
"""
getKT(::SDTree{KT, VT}) where {KT, VT} = KT
getKT(::SDBranch{KT, PT, ST, VT}) where {KT, PT, ST, VT} = KT

"""
    getVT(x::Union{SDTree, SDBranch})

Returns the Value Type (`VT`) of the data stored at the leaves of the given `SDTree` or `SDBranch`.
"""
getVT(::SDTree{KT, VT}) where {KT, VT} = VT
getVT(::SDBranch{KT, PT, ST, VT}) where {KT, PT, ST, VT} = VT

"""
    getPT(v::SDBranch)

Returns the Prefix Type (`PT`) of an `SDBranch`.
This represents the tuple type of the fixed, incomplete path that was used to create the current view.
"""
getPT(::SDBranch{KT, PT, ST, VT}) where {KT, PT, ST, VT} = PT

"""
    getST(v::SDBranch)

Returns the Suffix Type (`ST`) of an `SDBranch`.
This represents the tuple type of the remaining, localized keys required to traverse from the current branch down to a terminal leaf node.
"""
getST(::SDBranch{KT, PT, ST, VT}) where {KT, PT, ST, VT} = ST


include("DictTrees.jl")
include("delete.jl")
include("prune.jl")
include("abstracttrees.jl")
include("show.jl")

"""
    get(d, key, default)
    get(f::Function, d, key)

Returns the value stored for `key`, or `default` (respectively `f()`) if the key is not present.
Accepts `SDTree`, `SDBranch`, `SDLeaf`, `DictTree` and `DictBranch` objects.
"""
Base.get(d::Union{AbstractSDTree, DictTree, DictBranch}, key, default) = haskey(d, key) ? d[key] : default
Base.get(f::Base.Callable, d::Union{AbstractSDTree, DictTree, DictBranch}, key) = haskey(d, key) ? d[key] : f()

"""
    pop!(d, key)
    pop!(d, key, default)

Deletes `key` and returns its associated value, or `default` if the key is not present (the version without `default` throws a `KeyError`).
Accepts `SDTree`, `SDBranch`, `SDLeaf`, `DictTree` and `DictBranch` objects.
"""
function Base.pop!(d::Union{AbstractSDTree, DictTree, DictBranch}, key)
    haskey(d, key)  ||  throw(KeyError(key))
    value = d[key]
    delete!(d, key)
    return value
end
Base.pop!(d::Union{AbstractSDTree, DictTree, DictBranch}, key, default) = haskey(d, key) ? pop!(d, key) : default

_populate_dict!(output::Union{SDTree, DictTree}) = output

function _populate_dict!(output::Union{SDTree, DictTree}, input::AbstractDict)
    for (k, v) in input; output[k] = v; end
    return output
end

function _populate_dict!(output::Union{SDTree, DictTree}, input::Vararg{Pair})
    for (k, v) in input; output[k] = v; end
    return output
end

function _populate_dict!(output::Union{SDTree, DictTree}, keys::AbstractVector, values::AbstractVector)
    (length(keys) == length(values))  ||  throw(DimensionMismatch("Number of keys ($(length(keys))) and values ($(length(values))) differ."))
    for i in 1:length(keys); output[keys[i]] = values[i]; end
    return output
end

end # module
