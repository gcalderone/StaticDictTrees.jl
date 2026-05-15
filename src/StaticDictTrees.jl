module StaticDictTrees

using DataStructures

import Base: empty!, length, iterate, getindex, setindex!, haskey, keys, values, parent, show, delete!

export AbstractStaticDictTree, StaticDictTree, StaticDictBranch, key_length, prune!

#=
Conventions:
KT  = Key Type (heterogeneous tuples allowed, e.g., Tuple{Int, String, Symbol})
VT  = Value Type
BRT = Branch key Type (remaining suffix of the tuple)
BRD = Branch Depth
PRD = Prefix Depth
=#

# ------------------------------------------------------------------------------
# Dummy Value Providers
# ------------------------------------------------------------------------------

"""
    default_dummy(::Type{T})

Returns a safe default value for type `T` to be used as padding in `StaticDictTree`.
You can extend this for your own custom types.
"""
default_dummy(::Type{Symbol}) = :_
default_dummy(::Type{String}) = ""
default_dummy(::Type{Char})   = '\0'
default_dummy(::Type{Bool})   = false
default_dummy(::Type{T}) where {T <: Number} = zero(T)

@generated function default_dummy(::Type{T}) where {T <: Tuple}
    exprs = [:(default_dummy($t)) for t in fieldtypes(T)]
    return :( ($(exprs...),)::T )
end

# Fallback error for custom types providing instructuions to the user
default_dummy(::Type{T}) where {T} = error(
    "No default dummy value defined for type `$T`. To fix this use the following code:\n" *
    "import StaticDictTrees: default_dummy\n" *
    "default_dummy(::Type{$T}) = ...a dummy value...\n"
)


# ------------------------------------------------------------------------------
# Core Structures
# ------------------------------------------------------------------------------

abstract type AbstractStaticDictTree{KT <: Tuple, VT} <: AbstractDict{KT, VT} end

struct StaticDictTree{KT <: Tuple, VT} <: AbstractStaticDictTree{KT, VT}
    values::Vector{VT}
    lookup::OrderedDict{KT, Int}
    branch_lookup::Vector{OrderedDict{KT, Vector{Int}}}
    branch_keys::Vector{OrderedDict{KT, Vector{KT}}} 
    dummy_key::KT  

    function StaticDictTree{KT, VT}() where {KT <: Tuple, VT}
        dummy_key = default_dummy(KT)
        N = fieldcount(KT)
        bl = [OrderedDict{KT, Vector{Int}}() for _ in 1:N-1]
        bk = [OrderedDict{KT, Vector{KT}}()  for _ in 1:N-1]
        new{KT, VT}(VT[], OrderedDict{KT, Int}(), bl, bk, dummy_key)
    end
end

function StaticDictTree(d::AbstractDict{KT, VT}) where {KT <: Tuple, VT}
    out = StaticDictTree{KT, VT}()
    for (k, v) in d
        out[k] = v
    end
end
StaticDictTree(p::Vararg{Pair{KT, VT}}) where {KT <: Tuple, VT} = StaticDictTree(OrderedDict{KT, VT}(p...))

function empty!(d::StaticDictTree)
    empty!(d.values)
    empty!(d.lookup)
    empty!.(d.branch_lookup)
    empty!.(d.branch_keys)
    return d
end

keys(  d::StaticDictTree) = keys(d.lookup)
values(d::StaticDictTree) = d.values
length(d::StaticDictTree) = length(d.values)
haskey(d::StaticDictTree{KT, VT}, key::KT) where {KT, VT} = haskey(d.lookup, key)
parent(d::StaticDictTree) = nothing

function iterate(d::StaticDictTree, state=iterate(d.lookup))
    (state === nothing) && (return nothing)
    (key, i), next_state = state
    return (key => d.values[i], iterate(d.lookup, next_state))
end

getindex(d::StaticDictTree{KT, VT}, key::KT) where {KT, VT} = d.values[d.lookup[key]]

# Insertion logic
@generated function _insert_branches!(d::StaticDictTree{KT}, key::KT, I::Int) where {KT <: Tuple}
    N = fieldcount(KT)
    exprs = Expr[]
    
    for prd in 1:(N-1)
        brd = N - prd
        
        padded_expr = Expr(:tuple)
        for i in 1:prd
            push!(padded_expr.args, :(key[$i]))
        end
        for i in (prd+1):N
            push!(padded_expr.args, :(d.dummy_key[$i]))
        end
        
        push!(exprs, quote
            padded_prefix = $(padded_expr)::KT
            
            if !haskey(d.branch_lookup[$brd], padded_prefix)
                d.branch_lookup[$brd][padded_prefix] = Int[]
                d.branch_keys[$brd][padded_prefix] = KT[]
            end
            push!(d.branch_lookup[$brd][padded_prefix], I)
            push!(d.branch_keys[$brd][padded_prefix], key) 
        end)
    end
    
    return Expr(:block, exprs...)
end

function setindex!(d::StaticDictTree{KT, VT}, value, key::KT) where {KT, VT}
    if haskey(d.lookup, key)
        d.values[d.lookup[key]] = value
    else
        push!(d.values, value)
        I = length(d.values)
        d.lookup[key] = I
        _insert_branches!(d, key, I)
    end
    return value
end


# ------------------------------------------------------------------------------
@generated function _pad_dynamic(prefix::T, dummy::KT) where {T <: Tuple, KT <: Tuple}
    P = fieldcount(T)
    N = fieldcount(KT)
    exprs = [i <= P ? :(prefix[$i]) : :(dummy[$i]) for i in 1:N]
    return :( ($(exprs...),)::KT )
end

@generated function _extract_suffix(k::KT, ::Val{PRD}) where {KT <: Tuple, PRD}
    N = fieldcount(KT)
    exprs = [:(k[$i]) for i in (PRD+1):N]
    return :( ($(exprs...),) )
end

struct StaticDictBranch{KT, BRT, VT} <: AbstractStaticDictTree{BRT, VT}
    parent::StaticDictTree{KT, VT}
    prefix::Tuple
    padded_prefix::KT
    prd::Int

    function StaticDictBranch(d::StaticDictTree{KT, VT}, prefix::Tuple) where {KT, VT}
        prd = length(prefix)
        N = fieldcount(KT)
        @assert prd < N "The tree has a fixed depth of $N, can't accomodate a prefix with length $prd"
        
        padded = _pad_dynamic(prefix, d.dummy_key)
        brt_types = fieldtypes(KT)[prd+1:end]
        BRT = Tuple{brt_types...}
        
        return new{KT, BRT, VT}(d, prefix, padded, prd)
    end
end

function StaticDictBranch(v::StaticDictBranch, prefix::Tuple)
    return StaticDictBranch(v.parent, (v.prefix..., prefix...))
end

function empty!(v::StaticDictBranch)
    for k in collect(keys(v))
        delete!(v, k)
    end
    return v
end

function keys(v::StaticDictBranch{KT, BRT, VT}) where {KT, BRT, VT}
    brd = fieldcount(KT) - v.prd
    dict_keys = v.parent.branch_keys[brd]
    full_keys = get(dict_keys, v.padded_prefix, KT[])
    return [_extract_suffix(k, Val(v.prd))::BRT for k in full_keys]
end

function values(v::StaticDictBranch{KT, BRT, VT}) where {KT, BRT, VT}
    brd = fieldcount(KT) - v.prd
    dict_lookup = v.parent.branch_lookup[brd]
    inds = get(dict_lookup, v.padded_prefix, Int[])
    return view(v.parent.values, inds)
end

function length(v::StaticDictBranch{KT, BRT, VT}) where {KT, BRT, VT}
    brd = fieldcount(KT) - v.prd
    dict_lookup = v.parent.branch_lookup[brd]
    return length(get(dict_lookup, v.padded_prefix, Int[]))
end

haskey(v::StaticDictBranch{KT, BRT, VT}, key::BRT) where {KT, BRT, VT} = haskey(v.parent, (v.prefix..., key...))

function parent(v::StaticDictBranch{KT, BRT, VT}) where {KT, BRT, VT}
    (v.prd == 1) && return v.parent
    return StaticDictBranch(v.parent, v.prefix[1:(end-1)])
end

function iterate(v::StaticDictBranch)
    kk = keys(v)
    (length(kk) == 0) && return nothing
    return iterate(v, (kk, iterate(kk)))
end

function iterate(v::StaticDictBranch, state)
    kk, tmp = state
    (tmp === nothing) && return nothing
    key, next_state = tmp
    return (key => v[key], (kk, iterate(kk, next_state)))
end

getindex(v::StaticDictBranch{KT, BRT, VT}, key::BRT) where {KT, BRT, VT} = v.parent[(v.prefix..., key...)]
getindex(v::StaticDictBranch{KT, BRT, VT}, key)      where {KT, BRT, VT} = v[(key,)]

setindex!(v::StaticDictBranch{KT, BRT, VT}, value, key::BRT) where {KT, BRT, VT} = v.parent[(v.prefix..., key...)] = value
setindex!(v::StaticDictBranch{KT, BRT, VT}, value, key)      where {KT, BRT, VT} = setindex!(v, value, (key,))

# ------------------------------------------------------------------------------
# Deletion and pruning logic
@generated function _delete_branches!(d::StaticDictTree{KT}, key::KT, I::Int) where {KT <: Tuple}
    N = fieldcount(KT)
    exprs = Expr[]
    
    for prd in 1:(N-1)
        brd = N - prd
        
        padded_expr = Expr(:tuple)
        for i in 1:prd
            push!(padded_expr.args, :(key[$i]))
        end
        for i in (prd+1):N
            push!(padded_expr.args, :(d.dummy_key[$i]))
        end
        
        push!(exprs, quote
            padded_prefix = $(padded_expr)::KT
            
            # Remove from branch_keys
            keys_vec = d.branch_keys[$brd][padded_prefix]
            k_idx = findfirst(==(key), keys_vec)
            (k_idx !== nothing) && deleteat!(keys_vec, k_idx)
            
            # Remove from branch_lookup
            inds_vec = d.branch_lookup[$brd][padded_prefix]
            i_idx = findfirst(==(I), inds_vec)
            (i_idx !== nothing) && deleteat!(inds_vec, i_idx)
            
            # Clean up memory if branch becomes empty
            if isempty(keys_vec)
                delete!(d.branch_keys[$brd], padded_prefix)
                delete!(d.branch_lookup[$brd], padded_prefix)
            end
        end)
    end
    return Expr(:block, exprs...)
end

function _shift_branch_indices!(d::StaticDictTree, I::Int)
    for brd in 1:length(d.branch_lookup)
        for inds in values(d.branch_lookup[brd])
            for i in eachindex(inds)
                if inds[i] > I
                    inds[i] -= 1
                end
            end
        end
    end
end

function delete!(d::StaticDictTree{KT, VT}, key::KT) where {KT, VT}
    !haskey(d.lookup, key) && return d
    
    I = d.lookup[key]
    
    # 1. Remove from flat values
    deleteat!(d.values, I)
    
    # 2. Remove from root lookup
    delete!(d.lookup, key)
    
    # 3. Shift all root indices > I
    for k in keys(d.lookup)
        if d.lookup[k] > I
            d.lookup[k] -= 1
        end
    end
    
    # 4. Remove from branch hierarchy
    _delete_branches!(d, key, I)
    
    # 5. Shift all branch indices > I
    _shift_branch_indices!(d, I)
    
    return d
end

delete!(v::StaticDictBranch{KT, BRT, VT}, key::BRT) where {KT, BRT, VT} = (delete!(v.parent, (v.prefix..., key...)::KT); v)
delete!(v::StaticDictBranch{KT, BRT, VT}, key)      where {KT, BRT, VT} = delete!(v, (key,))


function prune!(d::StaticDictTree{KT, VT}, prefix::Tuple) where {KT, VT}
    prd = length(prefix)
    N = fieldcount(KT)
    if prd >= N
        throw(ArgumentError("Prefix length must be less than tree depth. Use delete! for full keys."))
    end
    
    padded_prefix = _pad_dynamic(prefix, d.dummy_key)
    brd = N - prd
    
    if haskey(d.branch_keys[brd], padded_prefix)
        keys_to_delete = d.branch_keys[brd][padded_prefix]
        inds_to_delete = d.branch_lookup[brd][padded_prefix]
        
        # Sort by index descending! This prevents lower indices from shifting 
        # while we are still looping through the higher indices.
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
# Display Methods
# ------------------------------------------------------------------------------

show(io::IO, d::StaticDictTree{KT, VT}) where {KT, VT} =
    print(io, "StaticDictTree{$KT, $VT} with $(length(d)) entries")

show(io::IO, v::StaticDictBranch{KT, BRT, VT}) where {KT, BRT, VT} =
    print(io, "StaticDictBranch{$KT, $BRT, $VT} (prefix = $(v.prefix)) with $(length(v)) entries")

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
