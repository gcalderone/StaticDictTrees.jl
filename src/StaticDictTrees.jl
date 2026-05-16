module StaticDictTrees

using DataStructures

import Base: empty!, length, iterate, getindex, setindex!, haskey, keys, values, parent, show, delete!
export AbstractStaticDictTree, StaticDictTree, StaticDictBranch, prune!, is_leaf_level

#=
Conventions:
- KT: Key Type
- VT: Value Type
- PT: Prefix Type
- ST: Suffix Type
=#

"""
    AbstractStaticDictTree{KT <: Tuple, VT} <: AbstractDict{KT, VT}

Abstract base type for static dictionary trees and their branch views.
"""
abstract type AbstractStaticDictTree{KT <: Tuple, VT} <: AbstractDict{KT, VT} end

# ------------------------------------------------------------------------------
# StaticDictTree structure
# ------------------------------------------------------------------------------
"""
    StaticDictTree{KT <: Tuple, VT}()
    StaticDictTree(d::AbstractDict{KT, VT})
    StaticDictTree(p::Vararg{Pair{KT, VT}})

A high-performance, flattened hierarchical dictionary that maps fixed-depth `Tuple` keys of type `KT` to values of type `VT`.

`StaticDictTree` stores all values contiguously in a flat vector for cache-friendly iteration and achieves O(1) lookups by hashing the full tuple path. It natively supports heterogeneous tuple keys without type instability.
"""
struct StaticDictTree{KT <: Tuple, VT} <: AbstractStaticDictTree{KT, VT}
    keys::Vector{KT}
    values::Vector{VT}
    lookup::Dict{KT, Int}
    branch_lookup::Tuple

    function StaticDictTree{KT, VT}() where {KT <: Tuple, VT}
        bl = ntuple(fieldcount(KT)-1) do i
            types = fieldtypes(KT)
            prefix_type = Tuple{types[1:i]...}
            branch_type = Tuple{types[i+1:end]...}
            Dict{prefix_type, OrderedDict{branch_type, Int}}()
        end
        new{KT, VT}(KT[], VT[], Dict{KT, Int}(), bl)
    end
end

function StaticDictTree(d::AbstractDict{KT, VT}) where {KT <: Tuple, VT}
    out = StaticDictTree{KT, VT}()
    for (k, v) in d; out[k] = v; end
    return out
end

function StaticDictTree(p::Vararg{Pair{KT, VT}}) where {KT <: Tuple, VT}
    out = StaticDictTree{KT, VT}()
    for (k, v) in p; out[k] = v; end
    return out
end

function empty!(d::StaticDictTree)
    empty!(d.keys)
    empty!(d.values)
    empty!(d.lookup)
    for d in d.branch_lookup
        empty!(d)
    end
    return d
end

keys(  d::StaticDictTree) = d.keys
values(d::StaticDictTree) = d.values
length(d::StaticDictTree) = length(d.values)
haskey(d::StaticDictTree{KT, VT}, key::KT) where {KT, VT} = haskey(d.lookup, key)

"""
    parent(d::StaticDictTree)
    parent(v::StaticDictBranch)

Returns the parent structure of the given tree or branch.

* For a `StaticDictTree` (the root), this always returns `nothing`.
* For a `StaticDictBranch`, this returns the immediate parent view. If the branch is at depth 1 (e.g., prefix `(:a,)`), it returns the root `StaticDictTree`. If the branch is deeper (e.g., prefix `(:a, :b)`), it returns a new `StaticDictBranch` one level higher up the hierarchy.
"""
parent(d::StaticDictTree) = nothing

function iterate(d::StaticDictTree, state=1)
    (state > length(d.values)) && return nothing
    return (d.keys[state] => d.values[state], state + 1)
end

getindex(d::StaticDictTree{KT, VT}, key::KT) where {KT, VT} = d.values[d.lookup[key]]
getindex(d::StaticDictTree{KT, VT}, key) where {KT, VT} = getindex(d, (key,))


# Insertion logic
@generated function populate_branch_lookup!(d::StaticDictTree{KT}, key::KT, I::Int) where {KT <: Tuple}
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

function setindex!(d::StaticDictTree{KT, VT}, value, key::KT) where {KT, VT}
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
setindex!(d::StaticDictTree{KT, VT}, value, key) where {KT, VT} = setindex!(d, value, (key,))


# ------------------------------------------------------------------------------
# StaticDictBranch structure
# ------------------------------------------------------------------------------
"""
    StaticDictBranch(d::StaticDictTree{KT, VT}, prefix::PT) where {KT, VT, PT <: Tuple}

Creates a zero-allocation, type-stable view into a `StaticDictTree` for a given `prefix`.

A `StaticDictBranch` holds a direct memory pointer to the parent tree's internal caches. It allows for O(1) sub-tree lookups, iteration, and mutation without duplicating data or forcing deep recursive searches.

# Throws
* `KeyError`: If the provided `prefix` does not exist in the parent tree.
"""
struct StaticDictBranch{KT, PT <: Tuple, ST <: Tuple, VT} <: AbstractStaticDictTree{ST, VT}
    parent::StaticDictTree{KT, VT}
    prefix::PT
    depth::Int
    node::OrderedDict{ST, Int}

    function StaticDictBranch(d::StaticDictTree{KT, VT}, prefix::PT) where {KT, VT, PT <: Tuple}
        depth = fieldcount(PT)
        N = fieldcount(KT)
        @assert depth < N "The tree has a fixed depth of $N, can't accomodate a prefix key of length $(depth)"
        ST = Tuple{fieldtypes(KT)[depth+1:end]...}

        lookup = d.branch_lookup[depth]::Dict{PT, OrderedDict{ST, Int}}
        if !haskey(lookup, prefix)
            throw(KeyError(prefix))
        end
        node = lookup[prefix]::OrderedDict{ST, Int}
        return new{KT, PT, ST, VT}(d, prefix, depth, node)
    end
end

StaticDictBranch(v::StaticDictBranch, prefix::Tuple) = StaticDictBranch(v.parent, (v.prefix..., prefix...))

function empty!(v::StaticDictBranch)
    for k in collect(keys(v.node))
        delete!(v, k)
    end
    return v
end

keys(  v::StaticDictBranch) = keys(v.node)
values(v::StaticDictBranch) = (v.parent.values[i] for i in values(v.node))
length(v::StaticDictBranch) = length(v.node)
haskey(v::StaticDictBranch{KT, PT, ST, VT}, key::ST) where {KT, PT, ST, VT} = haskey(v.node, key)

function parent(v::StaticDictBranch{KT, PT, ST, VT}) where {KT, PT, ST, VT}
    (v.depth == 1) && return v.parent
    return StaticDictBranch(v.parent, v.prefix[1:(end-1)])
end

function iterate(v::StaticDictBranch, state=nothing)
    res = state === nothing ? iterate(v.node) : iterate(v.node, state)
    res === nothing && return nothing
    (key, idx), next_state = res
    return (key => v.parent.values[idx], next_state)
end

getindex(v::StaticDictBranch{KT, PT, ST, VT}, key::ST) where {KT, PT, ST, VT} = v.parent.values[v.node[key]]
getindex(v::StaticDictBranch{KT, PT, ST, VT}, key)     where {KT, PT, ST, VT} = getindex(v, (key,))

# Insertion logic
setindex!(v::StaticDictBranch{KT, PT, ST, VT}, value, key::ST) where {KT, PT, ST, VT} = (v.parent[(v.prefix..., key...)] = value; value)
setindex!(v::StaticDictBranch{KT, PT, ST, VT}, value, key)     where {KT, PT, ST, VT} = setindex!(v, value, (key,))


# ------------------------------------------------------------------------------
# Deletion and pruning logic
# ------------------------------------------------------------------------------
"""
    delete!(d::StaticDictTree{KT, VT}, key::KT)
    delete!(v::StaticDictBranch, key::ST)

Removes a specific leaf `key` from the tree.

Because values are stored in a flat array, deleting a leaf forces all subsequent elements to shift, making this an O(E) operation (where E is the number of elements). For removing entire sub-trees efficiently, use `prune!`.
"""
function delete!(d::StaticDictTree{KT, VT}, key::KT) where {KT, VT}
    !haskey(d.lookup, key) && return d

    I = d.lookup[key]

    # Remove from flat lists
    deleteat!(d.values, I)
    deleteat!(d.keys, I)
    delete!(d.lookup, key)

    # Shift all root indices > I
    for (k, v) in d.lookup
        if v > I
            d.lookup[k] = v - 1
        end
    end

    # Remove from branch hierarchy
    N = fieldcount(KT)
    for depth in 1:(N-1)
        prefix = ntuple(i -> key[i], depth)
        suffix = ntuple(i -> key[depth + i], N - depth)

        lookup_dict = d.branch_lookup[depth]
        if haskey(lookup_dict, prefix)
            delete!(lookup_dict[prefix], suffix)
        end
    end
    for lookup_dict in d.branch_lookup
        for inner_dict in values(lookup_dict)
            for (k, v) in inner_dict
                if v > I
                    inner_dict[k] = v - 1
                end
            end
        end
    end
    return d
end

delete!(v::StaticDictBranch{KT, PT, ST, VT}, key::ST) where {KT, PT, ST, VT} = delete!(v.parent, (v.prefix..., key...))

"""
    prune!(d::StaticDictTree, prefix::Tuple)
    prune!(v::StaticDictBranch, prefix::Tuple)

Removes an entire branch (identified by `prefix`) and all of its associated leaves from the tree.

This safely orchestrates the deletion of multiple leaves, ensuring internal memory indices and branch caches are properly shifted and maintained.
"""
function prune!(d::StaticDictTree{KT, VT}, prefix::PT) where {KT, VT, PT <: Tuple}
    depth = fieldcount(PT)
    N = fieldcount(KT)
    if depth >= N
        throw(ArgumentError("Prefix length must be less than tree depth. Use delete! for full keys."))
    end

    ST = Tuple{fieldtypes(KT)[depth+1:end]...}
    lookup = d.branch_lookup[depth]::Dict{PT, OrderedDict{ST, Int}}

    if haskey(lookup, prefix)
        inner_dict = lookup[prefix]

        inds_to_delete = collect(values(inner_dict))
        keys_to_delete = [d.keys[i] for i in inds_to_delete]


        pairs = sort!(collect(zip(inds_to_delete, keys_to_delete)), by=x->x[1], rev=true)
        for (_, k) in pairs
            delete!(d, k)
        end
    end
    return d
end

function prune!(v::StaticDictBranch, prefix::Tuple)
    prune!(v.parent, (v.prefix..., prefix...))
    return v
end


# ------------------------------------------------------------------------------
# AbstractTrees.jl Integration
# ------------------------------------------------------------------------------

is_leaf_level(::StaticDictTree{  KT})         where {KT <: Tuple}         = fieldcount(KT) == 1
is_leaf_level(::StaticDictBranch{KT, PT, ST}) where {KT, PT, ST <: Tuple} = fieldcount(ST) == 1

using AbstractTrees
import AbstractTrees: children, printnode

struct Leaf{K, V}
    key::K
    value::V
end

function children(d::StaticDictTree{KT}) where {KT <: Tuple}
    if is_leaf_level(d)
        return [Leaf(k[1], v) for (k, v) in d]
    else
        return [StaticDictBranch(d, p) for p in keys(d.branch_lookup[1])]
    end
end

function children(v::StaticDictBranch{KT}) where {KT <: Tuple}
    if is_leaf_level(v)
        return [Leaf(k[1], v.parent.values[idx]) for (k, idx) in v.node]
    else
        unique_next_steps = unique(k[1] for k in keys(v.node))
        return [StaticDictBranch(v.parent, (v.prefix..., step)) for step in unique_next_steps]
    end
end

printnode(io::IO, d::StaticDictTree) = print(io, "StaticDictTree (Root)")
printnode(io::IO, v::StaticDictBranch) = print(io, repr(v.prefix[end]))
printnode(io::IO, e::Leaf) = print(io, repr(e.key), " => ", repr(e.value))


# ------------------------------------------------------------------------------
# Display Methods (REPL integration)
# ------------------------------------------------------------------------------

# The 1-line summary (used when the tree is inside an array or printed inline)
Base.show(io::IO, d::StaticDictTree{KT, VT}) where {KT, VT} =
    print(io, "StaticDictTree{$KT, $VT} with $(length(d)) entries")

Base.show(io::IO, v::StaticDictBranch{KT, PT, ST, VT}) where {KT, PT, ST, VT} =
    print(io, "StaticDictBranch{$KT, $ST, $VT} (prefix = $(v.prefix)) with $(length(v)) entries")

# The REPL display (used when a user types the variable name and hits Enter)
function Base.show(io::IO, ::MIME"text/plain", d::AbstractStaticDictTree)
    show(io, d)

    if isempty(d)
        print(io, " (empty)")
        return
    end

    println(io, ":")
    print_tree(io, d)
end

end # module StaticDictTrees
