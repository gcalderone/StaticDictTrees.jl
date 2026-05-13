module StaticDictTrees

using DataStructures

import Base: empty!, length, iterate, getindex, setindex!, keys, values, parent, show, delete!
export AbstractStaticDictTree, StaticDictTree, StaticDictBranch, key_length

"""
    AbstractStaticDictTree{N, K, V} <: AbstractDict{NTuple{N, K}, V}

The abstract supertype for fixed-depth hierarchical dictionary structures.
It requires keys of type `NTuple{N, K}` and values of type `V`.
"""
abstract type AbstractStaticDictTree{N, K, V} <: AbstractDict{NTuple{N, K}, V} end


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
struct StaticDictTree{N, K, V} <: AbstractStaticDictTree{N, K, V}
    values::Vector{V}
    lookup::OrderedDict{NTuple{N, K}, Int}
    branchinds::Vector{OrderedDict{Tuple, Vector{Int}}}
    branchkeys::Vector{OrderedDict{Tuple, Vector{Tuple}}}

    function StaticDictTree{N, K, V}() where {N, K, V}
        branchinds = [OrderedDict{Tuple, Vector{Int}}()   for i in 1:(N-1)]
        branchkeys = [OrderedDict{Tuple, Vector{Tuple}}() for i in 1:(N-1)]
        new{N, K, V}(Vector{V}(), OrderedDict{NTuple{N, K}, Int}(), branchinds, branchkeys)
    end
end

function empty!(d::StaticDictTree)
    empty!(d.values)
    empty!(d.lookup)
    empty!.(d.branchinds)
    empty!.(d.branchkeys)
    return d
end

keys(d::StaticDictTree) = keys(d.lookup)
values(d::StaticDictTree) = d.values
length(d::StaticDictTree) = length(d.values)

"""
    parent(d::AbstractStaticDictTree)

Navigate up one level in the tree hierarchy.

Calling parent on a StaticDictBranch returns the immediate parent branch or the root StaticDictTree. Calling parent on the root returns nothing.
"""
parent(d::StaticDictTree) = nothing


"""
    key_length(d::AbstractStaticDictTree)

Return the number of remaining key segments required to access a leaf value in the tree or branch.
"""
key_length(d::StaticDictTree{N, K, V}) where {N, K, V} = N

getindex(d::StaticDictTree{N, K, V}, key::NTuple{N, K}) where {N, K, V} = d.values[d.lookup[key]]
getindex(d::StaticDictTree{1, K, V}, key::K) where {K, V} = d[(key,)]

function setindex!(d::StaticDictTree{N, K, V}, value, key::NTuple{N, K}) where {N, K, V}
    if haskey(d.lookup, key)
        d.values[d.lookup[key]] = value
    else
        push!(d.values, value)
        I = length(d.values)
        d.lookup[key] = I

        for M in 1:(N-1)
            F = N - M
            if !haskey(d.branchinds[F], key[1:M])
                d.branchinds[F][key[1:M]] = Vector{Int}()
                d.branchkeys[F][key[1:M]] = Vector{Tuple}()
            end
            push!(d.branchinds[F][key[1:M]], I)
            push!(d.branchkeys[F][key[1:M]], key[M+1:end])
        end
    end
    return value
end
setindex!(d::StaticDictTree{1, K, V}, value, key::K) where {K, V} = setindex!(d, value, (key,))

function iterate(d::StaticDictTree, state=iterate(d.lookup))
    (state === nothing)  &&  (return nothing)
    (key, i), next_state = state
    return (key => d.values[i], iterate(d.lookup, next_state))
end

function delete!(d::StaticDictTree{N, K, V}, key::NTuple{N, K}) where {N, K, V}
    if !haskey(d.lookup, key)
        return d
    end

    I = d.lookup[key]

    # Remove from flat vector and primary lookup
    deleteat!(d.values, I)
    delete!(d.lookup, key)

    # Shift indices in the primary lookup
    for (k, idx) in d.lookup
        if idx > I
            d.lookup[k] = idx - 1
        end
    end

    # Update and prune branch caches
    for M in 1:(N-1)
        F = N - M
        prefix = key[1:M]

        if haskey(d.branchinds[F], prefix)
            inds = d.branchinds[F][prefix]
            keys_vec = d.branchkeys[F][prefix]

            pos = findfirst(==(I), inds)
            if pos !== nothing
                deleteat!(inds, pos)
                deleteat!(keys_vec, pos)
            end

            if isempty(inds)
                delete!(d.branchinds[F], prefix)
                delete!(d.branchkeys[F], prefix)
            end
        end

        for inds in values(d.branchinds[F])
            for i in eachindex(inds)
                if inds[i] > I
                    inds[i] -= 1
                end
            end
        end
    end
    return d
end

delete!(d::StaticDictTree{1, K, V}, key::K) where {K, V} = delete!(d, (key,))

# ------------------------------------------------------------------------------
"""
    StaticDictBranch(d::StaticDictTree{N, K, V}, prefix::Vararg{K, F})

Create a zero-cost, type-stable view into a sub-tree of a StaticDictTree.

The StaticDictBranch acts exactly like a dictionary, but expects M keys (where M = N - F). Mutating a branch will safely mutate the underlying root tree.

# Examples
```julia-repl
julia> dt = StaticDictTree{3, String, Float64}()
julia> dt["server", "db", "latency"] = 12.5
julia> branch = StaticDictBranch(dt, "server")
julia> branch["db", "latency"]
12.5
```
"""
struct StaticDictBranch{N, M, K, V} <: AbstractStaticDictTree{M, K, V}
    parent::StaticDictTree{N, K, V}
    prefix::Tuple

    function StaticDictBranch(d::StaticDictTree{N, K, V}, prefix::Vararg{K, F}) where {N, K, V, F}
        @assert F < N "Too many keys provided ($F >= $N)"
        return new{N, N-F, K, V}(d, prefix)
    end
end

keys(v::StaticDictBranch{N, M, K, V}) where {N, M, K, V} = get(v.parent.branchkeys[M], v.prefix, Tuple[])
values(v::StaticDictBranch{N, M, K, V}) where {N, M, K, V} = view(v.parent.values, get(v.parent.branchinds[M], v.prefix, Int[]))
length(v::StaticDictBranch) = length(keys(v))

function parent(v::StaticDictBranch{N, M, K, V}) where {N, M, K, V}
    (key_length(v.parent) == M + 1)  &&  (return v.parent)
    return StaticDictBranch(v.parent, v.prefix[1:(end-1)]...)
end
key_length(d::StaticDictBranch{N, M, K, V}) where {N, M, K, V} = M

getindex(v::StaticDictBranch{N, M, K, V}, key::NTuple{M, K}) where {N, M, K, V} = v.parent[(v.prefix..., key...)]
getindex(v::StaticDictBranch{N, 1, K, V}, key::K) where {N, K, V} = v[(key,)]

setindex!(v::StaticDictBranch{N, M, K, V}, value, key::NTuple{M, K}) where {N, M, K, V} = v.parent[(v.prefix..., key...)] = value
setindex!(v::StaticDictBranch{N, 1, K, V}, value, key::K) where {N, K, V} = setindex!(v, value, (key,))

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

function delete!(v::StaticDictBranch{N, M, K, V}, key::NTuple{M, K}) where {N, M, K, V}
    delete!(v.parent, (v.prefix..., key...))
    return v
end
function delete!(v::StaticDictBranch{N, 1, K, V}, key::K) where {N, K, V}
    delete!(v, (key,))
    return v
end

# ------------------------------------------------------------------------------
show(io::IO, d::StaticDictTree{N, K, V}) where {N, K, V} =
    print(io, "StaticDictTree{$N, $K, $V} with $(length(d)) entries")

show(io::IO, v::StaticDictBranch{N, M, K, V}) where {N, M, K, V} =
    print(io, "StaticDictBranch{$N, $M, $K, $V} (prefix = $(v.prefix)) with $(length(v)) entries")

function show(io::IO, ::MIME"text/plain", d::AbstractStaticDictTree)
    SEP = "    "
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
