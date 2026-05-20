module StaticDictTrees

using DataStructures

import Base: empty!, length, iterate, getindex, setindex!, haskey, keys, values, parent, show, delete!, view, sizehint!
export AbstractSDTree, SDTree, SDBranch, SDLeaf, prune!, is_leaf_level, depth, is_stale, root, values_view

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

A high-performance, flattened hierarchical dictionary that maps fixed-depth `Tuple` keys of type `KT` to values of type `VT`.
"""
struct SDTree{KT <: Tuple, VT} <: AbstractSDTree{KT, VT}
    keys::Vector{KT}
    values::Vector{VT}
    lookup::OrderedDict{KT, Int}
    branch_lookup::Tuple
    viewid::Vector{Int}

    function SDTree{KT, VT}() where {KT <: Tuple, VT}
        bl = ntuple(fieldcount(KT)-1) do i
            types = fieldtypes(KT)
            prefix_type = Tuple{types[1:i]...}
            branch_type = Tuple{types[i+1:end]...}
            Dict{prefix_type, OrderedDict{branch_type, Int}}()
        end
        new{KT, VT}(KT[], VT[], OrderedDict{KT, Int}(), bl, Int[])
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

            lookups_at_depth = d.branch_lookup[$depth]::Dict{$prefix_type, OrderedDict{$branch_type, Int}}
            br_lookup = get(lookups_at_depth, prefix, nothing)

            if br_lookup === nothing
                br_lookup = OrderedDict{$branch_type, Int}()
                lookups_at_depth[prefix] = br_lookup
            end

            br_lookup[suffix] = I
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
        isempty(d.viewid)  ||  push!(d.viewid, I)
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
"""
struct SDBranch{KT, PT <: Tuple, ST <: Tuple, VT} <: AbstractSDTree{ST, VT}
    root::SDTree{KT, VT}
    prefix::PT
    lookup::OrderedDict{ST, Int}
    viewid::Vector{Int}

    function SDBranch(d::SDTree{KT, VT}, prefix::PT) where {KT, VT, PT <: Tuple}
        depth = fieldcount(PT)
        N = fieldcount(KT)
        @assert depth < N "The tree has a fixed depth of $N, can't accomodate a prefix key of length $(depth)"
        ST = Tuple{fieldtypes(KT)[depth+1:end]...}

        lookups_at_depth = d.branch_lookup[depth]::Dict{PT, OrderedDict{ST, Int}}
        if !haskey(lookups_at_depth, prefix)
            throw(KeyError(prefix))
        end
        lookup = lookups_at_depth[prefix]::OrderedDict{ST, Int}
        return new{KT, PT, ST, VT}(d, prefix, lookup, Int[])
    end
end

SDBranch(v::SDBranch, prefix::Tuple) = SDBranch(v.root, (v.prefix..., prefix...))

function empty!(v::SDBranch)
    for k in collect(keys(v.lookup))
        delete!(v, k)
    end
    return v
end

setindex!(v::SDBranch{KT, PT, ST, VT}, value, key::ST) where {KT, PT, ST, VT} = (@assert !is_stale(v); v.root[(v.prefix..., key...)] = value; value)
setindex!(v::SDBranch{KT, PT, ST, VT}, value, key)     where {KT, PT, ST, VT} = (@assert !is_stale(v); setindex!(v, value, (key,)))


# ------------------------------------------------------------------------------
# SDLeaf structure
# ------------------------------------------------------------------------------
struct SDLeaf{KT, VT} <: AbstractSDTree{Tuple{}, VT}
    root::SDTree{KT, VT}
    key::KT

    SDLeaf(d::SDTree{KT, VT}, key::KT) where {KT, VT} = new{KT, VT}(d, key)
    SDLeaf(v::SDBranch{KT, PT, ST, VT}, suffix::ST) where {KT, PT, ST, VT} = new{KT, VT}(v.root, (v.prefix..., suffix...))
end

function empty!(v::SDLeaf)
    delete!(v.root, v.key)
    return v
end

setindex!(v::SDLeaf{KT, VT}, value, key::Tuple{}) where {KT, VT} = (@assert !is_stale(v); v.root[v.key] = value; value)


# ------------------------------------------------------------------------------
# Method implementations
# ------------------------------------------------------------------------------

function keys(d::SDTree{KT, VT}, level::Int) where {KT <: Tuple, VT}
    N = fieldcount(KT)
    if level == N
        return keys(d)
    elseif 1 <= level < N
        return keys(d.branch_lookup[level])
    else
        throw(ArgumentError("Level ($level) must be between 1 and tree depth ($N)."))
    end
end

function keys(v::SDBranch{KT, PT, ST, VT}, level::Int) where {KT, PT, ST, VT}
    max_level = fieldcount(ST)
    if level == max_level
        return keys(v)
    elseif 1 <= level < max_level
        return unique(k[1:level] for k in keys(v))
    else
        throw(ArgumentError("Level ($level) must be between 1 and branch depth ($max_level)."))
    end
end

keys(d::SDTree) = keys(d.lookup)
keys(v::SDBranch) = keys(v.lookup)
keys(v::SDLeaf{KT, VT}) where {KT, VT} = is_stale(v) ? Tuple{}[] : [()]

values(d::SDTree) = (d.values[i] for i in values(d.lookup))
values(v::SDBranch) = (v.root.values[i] for i in values(v.lookup))
values(v::SDLeaf{KT, VT}) where {KT, VT} = is_stale(v) ? VT[] : [v.root[v.key]]

"""
    values_view(d::SDTree)
    values_view(v::SDBranch)
    values_view(l::SDLeaf)

Returns a zero-allocation `SubArray` view into the tree's values, strictly preserving the original insertion order.

Unlike `values()`, which returns a standard lazy Julia iterator, `values_view` returns an `AbstractArray`. This makes it ideal for broadcasting, linear algebra, or passing to functions that require array-like indexing.

Under the hood, it uses a lazy dirty-flag cache which is automatically updated when inserting new entries, but it is entirely invalidated whenever a `delete!` or `prune!` operations is invoked tree.
"""
function values_view(d::SDTree)
    isempty(d.viewid)  &&  append!(d.viewid, values(d.lookup))
    return view(d.values, d.viewid)
end

function values_view(v::SDBranch)
    is_stale(v)  &&  return view(v.root.values, 1:0)
    if length(v.viewid) != length(v.lookup)
        empty!(v.viewid)
        append!(v.viewid, values(v.lookup))
    end
    return view(v.root.values, v.viewid)
end

values_view(v::SDLeaf) = is_stale(v) ? view(v.root.values, 1:0) : view(v.root.values, v.root.lookup[v.key]:v.root.lookup[v.key])

length(d::SDTree) = length(d.lookup)
length(v::SDBranch) = length(v.lookup)
length(v::SDLeaf) = is_stale(v) ? 0 : 1

haskey(d::SDTree{KT, VT}, key::KT) where {KT, VT} = haskey(d.lookup, key)
haskey(v::SDBranch{KT, PT, ST, VT}, key::ST) where {KT, PT, ST, VT} = haskey(v.lookup, key)
haskey(v::SDLeaf{KT, VT}, key::Tuple) where {KT, VT} = !is_stale(v)  &&  (key == Tuple{}())

depth(::SDTree{KT, VT}) where {KT, VT} = fieldcount(KT)
depth(::SDBranch{KT, PT, ST, VT}) where {KT, PT, ST, VT} = fieldcount(PT)
depth(::SDLeaf{KT, VT}) where {KT, VT} = fieldcount(KT)

is_leaf_level(::SDTree{KT}) where {KT <: Tuple} = fieldcount(KT) == 1
is_leaf_level(::SDBranch{KT, PT, ST}) where {KT, PT, ST <: Tuple} = fieldcount(ST) == 1
is_leaf_level(::SDLeaf) = true

is_stale(v::SDBranch) = length(v.lookup) == 0
is_stale(v::SDLeaf) = !haskey(v.root.lookup, v.key)

parent(d::SDTree) = nothing

function parent(v::SDBranch{KT, PT, ST, VT}) where {KT, PT, ST, VT}
    (fieldcount(PT) == 1) && return v.root
    return SDBranch(v.root, v.prefix[1:(end-1)])
end

function parent(v::SDLeaf{KT, VT}) where {KT, VT}
    (fieldcount(KT) == 1) && return v.root
    return SDBranch(v.root, v.key[1:(end-1)])
end

root(d::SDTree) = d
root(v::SDBranch) = v.root
root(v::SDLeaf) = v.root

function iterate(d::SDTree, state=nothing)
    res = state === nothing ? iterate(d.lookup) : iterate(d.lookup, state)
    res === nothing && return nothing
    (key, idx), next_state = res
    return (key => d.values[idx], next_state)
end

function iterate(v::SDLeaf, state=nothing)
    (isnothing(state) && !is_stale(v)) && (return (Tuple{}() => v.root[v.key], 1))
    return nothing
end

function iterate(v::SDBranch, state=nothing)
    res = state === nothing ? iterate(v.lookup) : iterate(v.lookup, state)
    res === nothing && return nothing
    (key, idx), next_state = res
    return (key => v.root.values[idx], next_state)
end

getindex(d::SDTree{KT, VT}, key::KT) where {KT, VT} = d.values[d.lookup[key]]
getindex(d::SDTree{KT, VT}, key) where {KT, VT} = getindex(d, (key,))

getindex(v::SDBranch{KT, PT, ST, VT}, key::ST) where {KT, PT, ST, VT} = (@assert !is_stale(v); v.root.values[v.lookup[key]])
getindex(v::SDBranch{KT, PT, ST, VT}, key)     where {KT, PT, ST, VT} = getindex(v, (key,))

getindex(v::SDLeaf{KT, VT}, key::Tuple{})      where {KT, VT} = (@assert !is_stale(v); v.root[v.key])

"""
    sizehint!(d::SDTree, n::Integer)

Suggest that the tree `d` reserve memory capacity for at least `n` elements.

Calling `sizehint!` before performing large, bulk insertions pre-allocates the necessary memory blocks for the internal data structures, improving insertion performance.
"""
function sizehint!(d::SDTree{KT, VT}, n::Integer) where {KT, VT}
    sizehint!(d.keys, n)
    sizehint!(d.values, n)
    sizehint!(d.lookup, n)
    if !isempty(d.branch_lookup)
        sizehint!(d.branch_lookup[1], n)
    end
    return d
end

# ------------------------------------------------------------------------------
# View Integration
# ------------------------------------------------------------------------------
function view(d::SDTree{KT, VT}, prefix::Tuple) where {KT <: Tuple, VT}
    N = fieldcount(KT)
    L = length(prefix)

    if L < N
        return SDBranch(d, prefix)
    elseif L == N
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
        return SDBranch(v.root, full_prefix)
    elseif L == N
        return SDLeaf(v.root, convert(KT, full_prefix))
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
        return [SDLeaf(v.root, (v.prefix..., k...)) for k in sort(collect(keys(v.lookup)))]
    else
        unique_next_steps = unique(k[1] for k in keys(v.lookup))
        return [SDBranch(v.root, (v.prefix..., step)) for step in sort(unique_next_steps)]
    end
end

children(::SDLeaf) = ()

printnode(io::IO, d::SDTree) = print(io, "SDTree (Root)")
printnode(io::IO, v::SDBranch) = print(io, repr(v.prefix[end]))
printnode(io::IO, e::SDLeaf) = print(io, repr(e.key[end]), " => ", repr(e[()]))


# ------------------------------------------------------------------------------
# Display Methods (REPL integration)
# ------------------------------------------------------------------------------
Base.show(io::IO, d::SDTree{KT, VT}) where {KT, VT} =
    print(io, "SDTree{$KT, $VT} with $(length(d)) entries")

Base.show(io::IO, v::SDBranch{KT, PT, ST, VT}) where {KT, PT, ST, VT} =
    print(io, "SDBranch{$KT, $ST, $VT} (prefix = $(v.prefix)) with $(length(v)) entries")

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

end # module StaticDictTrees
