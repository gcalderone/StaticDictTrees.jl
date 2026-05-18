module StaticDictTrees

using DataStructures

import Base: empty!, length, iterate, getindex, setindex!, haskey, keys, values, parent, show, delete!, view
export AbstractSDTree, SDTree, SDBranch, SDLeaf, prune!, is_leaf_level, depth, is_stale

#=
Conventions:
- KT: Key Type
- VT: Value Type
- PT: Prefix Type
- ST: Suffix Type
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
    SDTree(d::AbstractDict{KT, VT})
    SDTree(p::Vararg{Pair{KT, VT}})

A high-performance, flattened hierarchical dictionary that maps fixed-depth `Tuple` keys of type `KT` to values of type `VT`.

`SDTree` stores all values contiguously in a flat vector for cache-friendly iteration and achieves O(1) lookups by hashing the full tuple path. It natively supports heterogeneous tuple keys without type instability.
"""
struct SDTree{KT <: Tuple, VT} <: AbstractSDTree{KT, VT}
    keys::Vector{KT}
    values::Vector{VT}
    lookup::Dict{KT, Int}
    branch_lookup::Tuple

    function SDTree{KT, VT}() where {KT <: Tuple, VT}
        bl = ntuple(fieldcount(KT)-1) do i
            types = fieldtypes(KT)
            prefix_type = Tuple{types[1:i]...}
            branch_type = Tuple{types[i+1:end]...}
            Dict{prefix_type, OrderedDict{branch_type, Int}}()
        end
        new{KT, VT}(KT[], VT[], Dict{KT, Int}(), bl)
    end
end

function SDTree(d::AbstractDict{KT, VT}) where {KT <: Tuple, VT}
    out = SDTree{KT, VT}()
    for (k, v) in d; out[k] = v; end
    return out
end

function SDTree(p::Vararg{Pair{KT, VT}}) where {KT <: Tuple, VT}
    out = SDTree{KT, VT}()
    for (k, v) in p; out[k] = v; end
    return out
end

function empty!(d::SDTree)
    empty!(d.keys)
    empty!(d.values)
    empty!(d.lookup)
    for level_dict in d.branch_lookup
        for (k, v) in level_dict
            empty!(v)
        end
        empty!(level_dict)
    end
    return d
end

keys(  d::SDTree) = d.keys
values(d::SDTree) = d.values
length(d::SDTree) = length(d.values)
haskey(d::SDTree{KT, VT}, key::KT) where {KT, VT} = haskey(d.lookup, key)
depth( d::SDTree{KT, VT}) where {KT, VT} = fieldcount(KT)
is_leaf_level(::SDTree{KT}) where {KT <: Tuple} = fieldcount(KT) == 1

"""
    keys(d::SDTree, level::Int)
    keys(v::SDBranch, level::Int)

Return an iterator over the unique tuple prefixes (or suffixes, for a branch)
down to the specified `level`.

When `level` equals the total depth of the tree (or the remaining depth of the branch),
this is equivalent to `keys(d)` and returns the full paths to the leaves.
For intermediate levels, it returns the unique partial paths representing the
branches at that depth.

# Arguments
- `d::SDTree` or `v::SDBranch`: The static dictionary tree or branch view.
- `level::Int`: The depth of the keys to retrieve. Must be between 1 and the
  maximum depth of the tree (or the remaining depth of the branch).

# Examples
```julia-repl
julia> dt = SDTree((:Fermion, :Quark, :up) => 2.2,
                   (:Fermion, :Lepton, :electron) => 0.51,
                   (:Boson, :Gauge, :photon) => 0.0);

# Level 1 returns the root categories
julia> collect(keys(dt, 1))
2-element Vector{Tuple{Symbol}}:
 (:Fermion,)
 (:Boson,)

# Level 2 returns the sub-categories
julia> collect(keys(dt, 2))
3-element Vector{Tuple{Symbol, Symbol}}:
 (:Fermion, :Quark)
 (:Fermion, :Lepton)
 (:Boson, :Gauge)

# For a branch, the level is relative to the branch's root
julia> fermions = view(dt, (:Fermion,))
julia> collect(keys(fermions, 1))
2-element Vector{Tuple{Symbol}}:
 (:Quark,)
 (:Lepton,)
```
"""
function keys(d::SDTree{KT, VT}, level::Int) where {KT <: Tuple, VT}
    N = fieldcount(KT)

    if level == N
        return keys(d) # Returns the full tuple keys (leaf level)
    elseif 1 <= level < N
        return keys(d.branch_lookup[level]) # Returns the intermediate prefixes
    else
        throw(ArgumentError("Level ($level) must be between 1 and tree depth ($N)."))
    end
end

"""
    parent(d::SDTree)
    parent(v::SDBranch)

Returns the parent structure of the given tree or branch.

* For a `SDTree` (the root), this always returns `nothing`.
* For a `SDBranch`, this returns the immediate parent view. If the branch is at depth 1 (e.g., prefix `(:a,)`), it returns the root `SDTree`. If the branch is deeper (e.g., prefix `(:a, :b)`), it returns a new `SDBranch` one level higher up the hierarchy.
"""
parent(d::SDTree) = nothing

function iterate(d::SDTree, state=1)
    (state > length(d.values)) && return nothing
    return (d.keys[state] => d.values[state], state + 1)
end

getindex(d::SDTree{KT, VT}, key::KT) where {KT, VT} = d.values[d.lookup[key]]
getindex(d::SDTree{KT, VT}, key) where {KT, VT} = getindex(d, (key,))

# Insertion logic
@generated function populate_branch_lookup!(d::SDTree{KT}, key::KT, I::Int) where {KT <: Tuple}
    N = fieldcount(KT)
    exprs = Expr[]

    for depth in 1:(N-1)
        prefix_type = Tuple{fieldtypes(KT)[1:depth]...}
        branch_type = Tuple{fieldtypes(KT)[depth+1:end]...}

        push!(exprs, quote
            prefix = $(Expr(:tuple, [:(key[$i]) for i in 1:depth]...))::$prefix_type
            suffix = $(Expr(:tuple, [:(key[$i]) for i in (depth+1):N]...))::$branch_type

            lookup_dict = d.branch_lookup[$depth]::Dict{$prefix_type, OrderedDict{$branch_type, Int}}
            node = get(lookup_dict, prefix, nothing)

            if node === nothing
                node = OrderedDict{$branch_type, Int}()
                lookup_dict[prefix] = node
            end

            node[suffix] = I
        end)
    end

    return Expr(:block, exprs...)
end

function setindex!(d::SDTree{KT, VT}, value, key::KT) where {KT, VT}
    if haskey(d.lookup, key)
        d.values[d.lookup[key]] = value
    else
        push!(d.keys, key)
        push!(d.values, value)
        I = length(d.values)
        d.lookup[key] = I
        populate_branch_lookup!(d, key, I)
    end
    return value
end
setindex!(d::SDTree{KT, VT}, value, key) where {KT, VT} = setindex!(d, value, (key,))


# ------------------------------------------------------------------------------
# SDBranch structure
# ------------------------------------------------------------------------------
"""
    SDBranch(d::SDTree{KT, VT}, prefix::PT) where {KT, VT, PT <: Tuple}

Creates a zero-allocation, type-stable view into a `SDTree` for a given `prefix`.

A `SDBranch` holds a direct memory pointer to the parent tree's internal caches. It allows for O(1) sub-tree lookups, iteration, and mutation without duplicating data or forcing deep recursive searches.

# Throws
* `KeyError`: If the provided `prefix` does not exist in the parent tree.
"""
struct SDBranch{KT, PT <: Tuple, ST <: Tuple, VT} <: AbstractSDTree{ST, VT}
    parent::SDTree{KT, VT}
    prefix::PT
    node::OrderedDict{ST, Int}

    function SDBranch(d::SDTree{KT, VT}, prefix::PT) where {KT, VT, PT <: Tuple}
        depth = fieldcount(PT)
        N = fieldcount(KT)
        @assert depth < N "The tree has a fixed depth of $N, can't accomodate a prefix key of length $(depth)"
        ST = Tuple{fieldtypes(KT)[depth+1:end]...}

        lookup = d.branch_lookup[depth]::Dict{PT, OrderedDict{ST, Int}}
        if !haskey(lookup, prefix)
            throw(KeyError(prefix))
        end
        node = lookup[prefix]::OrderedDict{ST, Int}
        return new{KT, PT, ST, VT}(d, prefix, node)
    end
end

SDBranch(v::SDBranch, prefix::Tuple) = SDBranch(v.parent, (v.prefix..., prefix...))

function empty!(v::SDBranch)
    for k in collect(keys(v.node))
        delete!(v, k)
    end
    return v
end

keys(  v::SDBranch) = keys(v.node)
values(v::SDBranch) = (v.parent.values[i] for i in values(v.node))
length(v::SDBranch) = length(v.node)
haskey(v::SDBranch{KT, PT, ST, VT}, key::ST) where {KT, PT, ST, VT} = haskey(v.node, key)
depth(  ::SDBranch{KT, PT, ST, VT}) where {KT, PT, ST, VT} = fieldcount(PT)
is_leaf_level(::SDBranch{KT, PT, ST}) where {KT, PT, ST <: Tuple} = fieldcount(ST) == 1

"""
    is_stale(v::SDBranch)
    is_stale(v::SDLeaf)

Check whether a branch or leaf view has become stale (invalidated).

A view becomes stale when the underlying data it points to in the parent `SDTree` 
is deleted, typically via a call to `empty!(parent)` or `prune!(parent, ...)`. 

Returns `true` if the underlying data has been destroyed. A stale view safely 
acts as an empty collection (length 0, empty iterators) and should no longer be mutated.
"""
is_stale(v::SDBranch) = length(v.node) == 0

function keys(v::SDBranch{KT, PT, ST, VT}, level::Int) where {KT, PT, ST, VT}
    max_level = fieldcount(ST)

    if level == max_level
        return keys(v) # Returns the full valid suffixes for this branch
    elseif 1 <= level < max_level
        # Extract the sub-path from the branch's leaves and return the unique ones
        return unique(k[1:level] for k in keys(v))
    else
        throw(ArgumentError("Level ($level) must be between 1 and branch depth ($max_level)."))
    end
end

function parent(v::SDBranch{KT, PT, ST, VT}) where {KT, PT, ST, VT}
    (fieldcount(PT) == 1) && return v.parent
    return SDBranch(v.parent, v.prefix[1:(end-1)])
end

function iterate(v::SDBranch, state=nothing)
    res = state === nothing ? iterate(v.node) : iterate(v.node, state)
    res === nothing && return nothing
    (key, idx), next_state = res
    return (key => v.parent.values[idx], next_state)
end

getindex(v::SDBranch{KT, PT, ST, VT}, key::ST) where {KT, PT, ST, VT} = v.parent.values[v.node[key]]
getindex(v::SDBranch{KT, PT, ST, VT}, key)     where {KT, PT, ST, VT} = getindex(v, (key,))

# Insertion logic
setindex!(v::SDBranch{KT, PT, ST, VT}, value, key::ST) where {KT, PT, ST, VT} = (v.parent[(v.prefix..., key...)] = value; value)
setindex!(v::SDBranch{KT, PT, ST, VT}, value, key)     where {KT, PT, ST, VT} = setindex!(v, value, (key,))


# ------------------------------------------------------------------------------
# SDLeaf structure
# ------------------------------------------------------------------------------
struct SDLeaf{KT, VT} <: AbstractSDTree{KT, VT}
    parent::SDTree{KT, VT}
    key::KT

    SDLeaf(d::SDTree{KT, VT}, key::KT) where {KT, VT} = new{KT, VT}(d, key)
    SDLeaf(v::SDBranch{KT, PT, ST, VT}, suffix::ST) where {KT, PT, ST, VT} = new{KT, VT}(v.parent, (v.prefix..., suffix...))
end

function empty!(v::SDLeaf)
    delete!(v.parent, v.key)
    return v
end

keys(  v::SDLeaf{KT, VT}) where {KT, VT} = is_stale(v) ? KT[] : [v.key]
values(v::SDLeaf{KT, VT}) where {KT, VT} = is_stale(v) ? VT[] : [v.parent[v.key]]
length(v::SDLeaf) = is_stale(v) ? 0 : 1
haskey(v::SDLeaf{KT, VT}, key::KT) where {KT, VT} = !is_stale(v) && (v.key == key)
depth( v::SDLeaf{KT, VT}) where {KT, VT} = fieldcount(KT)
is_leaf_level(::SDLeaf) = true
is_stale(v::SDLeaf) = !haskey(v.parent.lookup, v.key)

function parent(v::SDLeaf{KT, VT}) where {KT, VT}
    (fieldcount(KT) == 1) && return v.parent
    return SDBranch(v.parent, v.key[1:(end-1)])
end

function iterate(v::SDLeaf, state=nothing)
    (isnothing(state) && !is_stale(v)) && (return (v.key => v.parent[v.key], 1))
    return nothing
end

getindex(v::SDLeaf{KT, VT}, key::KT) where {KT, VT} = (@assert v.key == key; v.parent[v.key])
getindex(v::SDLeaf{KT, VT}, key)     where {KT, VT} = getindex(v, (key,))

setindex!(v::SDLeaf{KT, VT}, value, key::KT) where {KT, VT} = (@assert v.key == key; v.parent[v.key] = value; value)
setindex!(v::SDLeaf{KT, VT}, value, key)     where {KT, VT} = setindex!(v, value, (key,))


# ------------------------------------------------------------------------------
# View Integration
# ------------------------------------------------------------------------------
"""
    view(d::SDTree, prefix::Tuple)
    view(v::SDBranch, suffix::Tuple)
    view(tree_or_branch, key)

Creates a lightweight, non-allocating view into the tree.

Depending on the length of the provided path, it automatically returns either a
`SDBranch` (if the path is shorter than the remaining tree depth) or a `SDLeaf`
(if the path completes the full key).
"""
function view(d::SDTree{KT, VT}, prefix::Tuple) where {KT <: Tuple, VT}
    N = fieldcount(KT)
    L = length(prefix)

    if L < N
        return SDBranch(d, prefix)
    elseif L == N
        # We use `convert` to ensure the tuple exactly matches KT before making the leaf
        return SDLeaf(d, convert(KT, prefix))
    else
        throw(ArgumentError("Prefix length ($L) exceeds tree depth ($N)."))
    end
end
view(d::SDTree{KT, VT}, key) where {KT, VT} = view(d, (key,))

function view(v::SDBranch{KT, PT, ST, VT}, suffix::Tuple) where {KT, PT, ST, VT}
    N = fieldcount(KT)
    full_prefix = (v.prefix..., suffix...)
    L = length(full_prefix)

    if L < N
        return SDBranch(v.parent, full_prefix)
    elseif L == N
        return SDLeaf(v.parent, convert(KT, full_prefix))
    else
        throw(ArgumentError("Combined prefix length ($L) exceeds tree depth ($N)."))
    end
end
view(v::SDBranch{KT, PT, ST, VT}, key) where {KT, PT, ST, VT} = view(v, (key,))


# ------------------------------------------------------------------------------
# AbstractTrees.jl Integration
# ------------------------------------------------------------------------------

using AbstractTrees
import AbstractTrees: children, printnode

function children(d::SDTree{KT}) where {KT <: Tuple}
    if is_leaf_level(d)
        return [SDLeaf(d, k) for (k, v) in d]
    else
        return [SDBranch(d, p) for p in sort(collect(keys(d.branch_lookup[1])))]
    end
end

function children(v::SDBranch{KT}) where {KT <: Tuple}
    if is_leaf_level(v)
        return [SDLeaf(v.parent, (v.prefix..., k...)) for k in sort(collect(keys(v.node)))]
    else
        unique_next_steps = unique(k[1] for k in keys(v.node))
        return [SDBranch(v.parent, (v.prefix..., step)) for step in sort(unique_next_steps)]
    end
end

children(::SDLeaf) = ()

printnode(io::IO, d::SDTree) = print(io, "SDTree (Root)")
printnode(io::IO, v::SDBranch) = print(io, repr(v.prefix[end]))
printnode(io::IO, e::SDLeaf) = print(io, repr(e.key[end]), " => ", repr(e[e.key]))


# ------------------------------------------------------------------------------
# Display Methods (REPL integration)
# ------------------------------------------------------------------------------

# The 1-line summary (used when the tree is inside an array or printed inline)
Base.show(io::IO, d::SDTree{KT, VT}) where {KT, VT} =
    print(io, "SDTree{$KT, $VT} with $(length(d)) entries")

Base.show(io::IO, v::SDBranch{KT, PT, ST, VT}) where {KT, PT, ST, VT} =
    print(io, "SDBranch{$KT, $ST, $VT} (prefix = $(v.prefix)) with $(length(v)) entries")

# The REPL display (used when a user types the variable name and hits Enter)
function Base.show(io::IO, ::MIME"text/plain", d::AbstractSDTree)
    show(io, d)

    if isempty(d)
        print(io, " (empty)")
        return
    end

    println(io, ":")
    print_tree(io, d)
end


include("delete.jl")
include("prune.jl")

end # module AbstractStaticTrees
