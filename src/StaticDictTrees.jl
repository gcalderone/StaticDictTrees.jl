module StaticDictTrees

using DataStructures

import Base: empty!, length, iterate, getindex, setindex!, haskey, keys, values, parent, show, delete!
export AbstractStaticDictTree, StaticDictTree, StaticDictBranch, key_length, prune!

#=
Conventions:
TRD = Tree Depth
PRD = Prefix Depth
BRD = Branch Depth
KT  = Key Type
VT  = Value Type
=#

"""
    AbstractStaticDictTree{N, K, V} <: AbstractDict{NTuple{N, K}, V}

The abstract supertype for fixed-depth hierarchical dictionary structures.
It relies on keys of type `NTuple{N, K}` and values of type `V`.
"""
abstract type AbstractStaticDictTree{TRD, KT, VT} <: AbstractDict{NTuple{TRD, KT}, VT} end


"""
    StaticDictTree{N, K, V}()

Construct an empty, high-performance, flattened hierarchical dictionary with a strictly fixed depth of `N`.

Unlike standard nested dictionaries, a `StaticDictTree` stores all values in a single flat vector and uses `NTuple{N, K}` as composite keys. This guarantees type stability, O(1) lookups, and memory efficiency for hierarchical data.

# Examples
```julia-repl
julia> dt = StaticDictTree{3, String, Float64}()
julia> dt["server", "db", "latency"] = 12.5
julia> dt["server", "db", "latency"]
12.5
```
"""
struct StaticDictTree{TRD, KT, VT} <: AbstractStaticDictTree{TRD, KT, VT}
    values::Vector{VT}
    lookup::OrderedDict{NTuple{TRD, KT}, Int}
    branchinds::Vector{OrderedDict{Tuple, Vector{Int}}}
    branchkeys::Vector{OrderedDict{Tuple, Vector{Tuple}}}

    function StaticDictTree{TRD, KT, VT}() where {TRD, KT, VT}
        branchinds = [OrderedDict{Tuple, Vector{Int}}()   for i in 1:(TRD-1)]
        branchkeys = [OrderedDict{Tuple, Vector{Tuple}}() for i in 1:(TRD-1)]
        new{TRD, KT, VT}(Vector{VT}(), OrderedDict{NTuple{TRD, KT}, Int}(), branchinds, branchkeys)
    end
end

function empty!(d::StaticDictTree)
    empty!(d.values)
    empty!(d.lookup)
    empty!.(d.branchinds)
    empty!.(d.branchkeys)
    return d
end

keys(  d::StaticDictTree) = keys(d.lookup)
values(d::StaticDictTree) = d.values
length(d::StaticDictTree) = length(d.values)

"""
    parent(d::AbstractStaticDictTree)

Navigate up one level in the tree hierarchy.

Calling parent on a StaticDictBranch returns the immediate parent branch or the root StaticDictTree. Calling parent on the root returns `nothing`.
"""
parent(d::StaticDictTree) = nothing

"""
    key_length(d::AbstractStaticDictTree)

Return the number of key elements required to access a leaf value in the tree or branch.
"""
key_length(d::StaticDictTree{TRD, KT, VT}) where {TRD, KT, VT} = TRD

getindex(d::StaticDictTree{TRD, KT, VT}, key::NTuple{TRD, KT}) where {TRD, KT, VT} = d.values[d.lookup[key]]
getindex(d::StaticDictTree{1  , KT, VT}, key::KT)              where {     KT, VT} = d[(key,)]

function setindex!(d::StaticDictTree{TRD, KT, VT}, value, key::NTuple{TRD, KT}) where {TRD, KT, VT}
    if haskey(d.lookup, key)
        d.values[d.lookup[key]] = value
    else
        push!(d.values, value)
        I = length(d.values)
        d.lookup[key] = I

        for prd in 1:(TRD-1)
            brd = TRD - prd
            prefix = key[1:prd]
            if !haskey(d.branchinds[brd], prefix)
                d.branchinds[brd][prefix] = Vector{Int}()
                d.branchkeys[brd][prefix] = Vector{Tuple}()
            end
            push!(d.branchinds[brd][prefix], I)
            push!(d.branchkeys[brd][prefix], key[prd+1:end])
        end
    end
    return value
end
setindex!(d::StaticDictTree{1, KT, VT}, value, key::KT) where {KT, VT} = setindex!(d, value, (key,))

function iterate(d::StaticDictTree, state=iterate(d.lookup))
    (state === nothing)  &&  (return nothing)
    (key, i), next_state = state
    return (key => d.values[i], iterate(d.lookup, next_state))
end

delete!(d::StaticDictTree{1  , KT, VT}, key::KT)              where {     KT, VT} = delete!(d, (key,))
function delete!(d::StaticDictTree{TRD, KT, VT}, key::NTuple{TRD, KT}) where {TRD, KT, VT}
    if !haskey(d.lookup, key)
        return d
    end

    I = d.lookup[key]

    # Remove from values and lookup
    deleteat!(d.values, I)
    delete!(d.lookup, key)

    # Shift indices in the primary lookup
    for (k, idx) in d.lookup
        if idx > I
            d.lookup[k] = idx - 1
        end
    end

    # Update and prune branch caches
    for prd in 1:(TRD-1)
        brd = TRD - prd
        prefix = key[1:prd]

        if haskey(d.branchinds[brd], prefix)
            ii =  d.branchinds[brd][ prefix]
            kk =  d.branchkeys[brd][ prefix]

            pos = findfirst(==(I), ii)
            if pos !== nothing
                deleteat!(ii, pos)
                deleteat!(kk, pos)
            end

            if isempty(ii)
                delete!(d.branchinds[brd], prefix)
                delete!(d.branchkeys[brd], prefix)
            end
        end

        for ii in values(d.branchinds[brd])
            for i in eachindex(ii)
                if ii[i] > I
                    ii[i] -= 1
                end
            end
        end
    end
    return d
end

"""
    prune!(d::AbstractStaticDictTree, prefix...)

Delete an entire branch from a tree.

# Examples
```julia-repl
julia> dt = StaticDictTree{3, String, Float64}()
julia> dt["server", "db", "latency"] = 12.5
julia> prune!(dt, "server", "db")
"""
function prune!(d::StaticDictTree{TRD, KT, VT}, prefix::Vararg{KT, PRD}) where {TRD, KT, VT, PRD}
    @assert PRD <= TRD "Cannot prune past the leaf level"
    if PRD == TRD
        return delete!(d, prefix)
    end
    for key in collect(keys(StaticDictBranch(d, prefix...)))
        k = (prefix..., key...)
        delete!(d, k)
    end
    return d
end


# ------------------------------------------------------------------------------
"""
    StaticDictBranch(d::StaticDictTree{N, K, V}, prefix::Vararg{K, P})

Create a zero-cost, type-stable view into a sub-tree of a StaticDictTree.

The StaticDictBranch acts exactly like a dictionary, but expects M keys (where M = N - P). Mutating a branch will safely mutate the underlying root tree.

# Examples
```julia-repl
julia> dt = StaticDictTree{3, String, Float64}()
julia> dt["server", "db", "latency"] = 12.5
julia> branch = StaticDictBranch(dt, "server")
julia> branch["db", "latency"]
12.5
```
"""
struct StaticDictBranch{TRD, BRD, KT, VT} <: AbstractStaticDictTree{BRD, KT, VT}
    parent::StaticDictTree{TRD, KT, VT}
    prefix::Tuple

    function StaticDictBranch(d::StaticDictTree{TRD, KT, VT}, prefix::Vararg{KT, PRD}) where {TRD, KT, VT, PRD}
        @assert PRD < TRD "The tree has a fixed depth of $TRD, no branch can be generated with $PRD keys"
        return new{TRD, TRD - PRD, KT, VT}(d, prefix)
    end

    function StaticDictBranch(d::StaticDictBranch{TRD, BRD, KT, VT}, prefix::Vararg{KT, PRD}) where {TRD, BRD, KT, VT, PRD}
        @assert PRD < BRD "The branch has a fixed depth of $TRD, no branch can be generated with $PRD keys"
        return StaticDictBranch(d.parent, d.prefix..., prefix...)
    end
end

function Base.empty!(v::StaticDictBranch{TRD, BRD, KT, VT}) where {TRD, BRD, KT, VT}
    for k in collect(keys(v))
        delete!(v, k)
    end
    return v
end

keys(  v::StaticDictBranch{TRD, BRD, KT, VT}) where {TRD, BRD, KT, VT} = get(v.parent.branchkeys[BRD], v.prefix, Tuple[])
values(v::StaticDictBranch{TRD, BRD, KT, VT}) where {TRD, BRD, KT, VT} = view(v.parent.values, get(v.parent.branchinds[BRD], v.prefix, Int[]))
length(v::StaticDictBranch) = length(keys(v))

function parent(v::StaticDictBranch{TRD, BRD, KT, VT}) where {TRD, BRD, KT, VT}
    (key_length(v.parent) == BRD + 1)  &&  (return v.parent)
    return StaticDictBranch(v.parent, v.prefix[1:(end-1)]...)
end
key_length(d::StaticDictBranch{TRD, BRD, KT, VT}) where {TRD, BRD, KT, VT} = BRD

getindex(v::StaticDictBranch{TRD, BRD, KT, VT}, key::NTuple{BRD, KT}) where {TRD, BRD, KT, VT} = v.parent[(v.prefix..., key...)]
getindex(v::StaticDictBranch{TRD,   1, KT, VT}, key::KT)              where {TRD,      KT, VT} = v[(key,)]

setindex!(v::StaticDictBranch{TRD, BRD, KT, VT}, value, key::NTuple{BRD, KT}) where {TRD, BRD, KT, VT} = v.parent[(v.prefix..., key...)] = value
setindex!(v::StaticDictBranch{TRD,   1, KT, VT}, value, key::KT)              where {TRD,      KT, VT} = setindex!(v, value, (key,))

function iterate(v::StaticDictBranch)
    kk = keys(v)
    (length(kk) == 0)  &&  (return nothing)
    return iterate(v, (kk, iterate(kk)))
end

function iterate(v::StaticDictBranch, state)
    kk, tmp = state
    (tmp === nothing)  &&  (return nothing)
    key, next_state = tmp
    return (key => v[key], (kk, iterate(kk, next_state)))
end

delete!(v::StaticDictBranch{TRD, 1  , KT, VT}, key::KT)              where {TRD,      KT, VT} = delete!(v, (key,))
function delete!(v::StaticDictBranch{TRD, BRD, KT, VT}, key::NTuple{BRD, KT}) where {TRD, BRD, KT, VT}
    delete!(v.parent, (v.prefix..., key...))
    return v
end

function prune!(v::StaticDictBranch{TRD, BRD, KT, VT}, prefix::Vararg{KT, PRD}) where {TRD, BRD, KT, VT, PRD}
    prune!(v.parent, v.prefix..., prefix...)
    return v
end


# ------------------------------------------------------------------------------
show(io::IO, d::StaticDictTree{TRD, KT, VT}) where {TRD, KT, VT} =
    print(io, "StaticDictTree{$TRD, $KT, $VT} with $(length(d)) entries")

show(io::IO, v::StaticDictBranch{TRD, BRD, KT, VT}) where {TRD, BRD, KT, VT} =
    print(io, "StaticDictBranch{$TRD, $BRD, $KT, $VT} (prefix = $(v.prefix)) with $(length(v)) entries")

function show(io::IO, ::MIME"text/plain", d::AbstractStaticDictTree)
    SEP = " "^4
    show(io, d)
    print(io, ":")

    isempty(d) && return
    println(io)

    prev_key = ()
    is_first = true

    for (key, val) in d
        match_len = 0
        for i in 1:min(length(prev_key), length(key))
            if prev_key[i] == key[i]
                match_len += 1
            else
                break
            end
        end

        for i in (match_len + 1):(length(key) - 1)
            !is_first && println(io)
            print(io, SEP^i, repr(key[i]))
            is_first = false
        end

        !is_first && println(io)
        print(io, SEP^length(key), repr(key[end]), " => ", repr(val))
        is_first = false

        prev_key = key
    end
end

end # module StaticDictTrees
