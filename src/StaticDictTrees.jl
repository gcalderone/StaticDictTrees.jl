module StaticDictTrees

using DataStructures

import Base: empty!, length, iterate, getindex, setindex!, haskey, keys, values, parent, show, delete!, view
export AbstractSDTree, SDTree, SDBranch, SDLeaf, prune!, is_leaf_level, depth

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
    for d in d.branch_lookup
        empty!(d)
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
depth( d::SDBranch{KT, PT, ST, VT}) where {KT, PT, ST, VT} = fieldcount(PT)
is_leaf_level(::SDBranch{KT, PT, ST}) where {KT, PT, ST <: Tuple} = fieldcount(ST) == 1

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
    return nothing
end

keys(  v::SDLeaf) = [v.key]
values(v::SDLeaf) = [v.parent[v.key]]
length(v::SDLeaf) = 1
haskey(v::SDLeaf{KT, VT}, key::KT) where {KT, VT} = (v.key == key)
depth( v::SDLeaf{KT, VT}) where {KT, VT} = fieldcount(KT)
is_leaf_level(::SDLeaf) = true

function parent(v::SDLeaf{KT, VT}) where {KT, VT}
    (fieldcount(KT) == 1) && return v.parent
    return SDBranch(v.parent, v.key[1:(end-1)])
end

function iterate(v::SDLeaf, state=nothing)
    isnothing(state)  &&  (return (v.key => v.parent[v.key], 1))
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
view(d::SDTree, key) = view(d, (key,))

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
view(v::SDBranch, key) = view(v, (key,))

# ------------------------------------------------------------------------------
# Deletion and pruning logic
# ------------------------------------------------------------------------------
"""
    delete!(d::SDTree{KT, VT}, key::KT)
    delete!(v::SDBranch, key::ST)

Removes a specific leaf `key` from the tree.

Because values are stored in a flat array, deleting a leaf forces all subsequent elements to shift, making this an O(E) operation (where E is the number of elements). For removing entire sub-trees efficiently, use `prune!`.
"""
function delete!(d::SDTree{KT, VT}, key::KT) where {KT, VT}
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

delete!(v::SDBranch{KT, PT, ST, VT}, key::ST) where {KT, PT, ST, VT} = delete!(v.parent, (v.prefix..., key...))

"""
    prune!(d::SDTree, prefix::Tuple)
    prune!(v::SDBranch, prefix::Tuple)

Removes an entire branch (identified by `prefix`) and all of its associated leaves from the tree.

This safely orchestrates the deletion of multiple leaves, ensuring internal memory indices and branch caches are properly shifted and maintained.
"""
function prune!(d::SDTree{KT, VT}, prefix::PT) where {KT, VT, PT <: Tuple}
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

function prune!(v::SDBranch, prefix::Tuple)
    prune!(v.parent, (v.prefix..., prefix...))
    return v
end


# ------------------------------------------------------------------------------
# AbstractTrees.jl Integration
# ------------------------------------------------------------------------------

using AbstractTrees
import AbstractTrees: children, printnode

function children(d::SDTree{KT}) where {KT <: Tuple}
    if is_leaf_level(d)
        return [SDLeaf(d, k) for (k, v) in d]
    else
        return [SDBranch(d, p) for p in keys(d.branch_lookup[1])]
    end
end

function children(v::SDBranch{KT}) where {KT <: Tuple}
    if is_leaf_level(v)
        return [SDLeaf(v.parent, (v.prefix..., k...)) for (k, idx) in v.node]
    else
        unique_next_steps = unique(k[1] for k in keys(v.node))
        return [SDBranch(v.parent, (v.prefix..., step)) for step in unique_next_steps]
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

end # module AbstractStaticTrees
