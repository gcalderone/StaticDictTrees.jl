# Retrieval of the specific dictionary level
@generated function get_branch_dict(d::SDTree{KT}, ::Val{L}) where {KT <: Tuple, L}
    prefix_type = Tuple{fieldtypes(KT)[1:L]...}
    branch_type = Tuple{fieldtypes(KT)[L+1:end]...}
    return :(d.branch_lookup[$L]::Dict{$prefix_type, OrderedDict{$branch_type, Int}})
end

# Batch deletion and index shifting for branches
@generated function batch_clean_and_recache_branches!(d::SDTree{KT}, keys_to_delete::Vector{KT}, inds_to_delete::Vector{Int}) where {KT <: Tuple}
    N = fieldcount(KT)
    exprs = Expr[]
    
    for depth in 1:(N-1)
        prefix_type = Tuple{fieldtypes(KT)[1:depth]...}
        branch_type = Tuple{fieldtypes(KT)[depth+1:end]...}
        
        push!(exprs, quote
            lookup_dict = d.branch_lookup[$depth]::Dict{$prefix_type, OrderedDict{$branch_type, Int}}
                  
            # Clean up deleted keys from this depth
            for key in keys_to_delete
                prefix = $(Expr(:tuple, [:(key[$i]) for i in 1:depth]...))::$prefix_type
                suffix = $(Expr(:tuple, [:(key[$i]) for i in (depth+1):N]...))::$branch_type

                if haskey(lookup_dict, prefix)
                    delete!(lookup_dict[prefix], suffix)
                    if isempty(lookup_dict[prefix])
                        delete!(lookup_dict, prefix)
                    end
                end
            end

            # Recache indices for all remaining elements at this depth
            for inner_dict in values(lookup_dict)
                for (k, v) in inner_dict
                    offset = searchsortedlast(inds_to_delete, v)
                    if offset > 0
                        inner_dict[k] = v - offset
                    end
                end
            end
        end)
    end

    return Expr(:block, exprs...)
end

"""
    prune!(d::SDTree, path::Tuple)
    prune!(v::SDBranch, path::Tuple)

Removes an entire branch (identified by `path`) and all of its associated leaves from the tree.
If the `path` provided is a full key, it gracefully deletes just that specific leaf.
"""
function prune!(d::SDTree{KT, VT}, path::PT) where {KT <: Tuple, VT, PT <: Tuple}
    L = fieldcount(PT)
    N = fieldcount(KT)

    if L > N
        throw(ArgumentError("Path length ($L) exceeds tree depth ($N)."))
    elseif L == N
        return delete!(d, convert(KT, path))
    end

    lookup_dict = get_branch_dict(d, Val(L))

    if haskey(lookup_dict, path)
        inner_dict = lookup_dict[path]
        
        inds_to_delete = sort!(collect(values(inner_dict)))
        keys_to_delete = [d.keys[i] for i in inds_to_delete]

        for key in keys_to_delete
            delete!(d.lookup, key)
        end
        deleteat!(d.values, inds_to_delete)
        deleteat!(d.keys, inds_to_delete)

        for (k, v) in d.lookup
            offset = searchsortedlast(inds_to_delete, v)
            if offset > 0
                d.lookup[k] = v - offset
            end
        end

        batch_clean_and_recache_branches!(d, keys_to_delete, inds_to_delete)
    end
    
    return d
end

function prune!(v::SDBranch, path::Tuple)
    prune!(v.root, (v.prefix..., path...))
    return v
end

prune!(d::AbstractSDTree, key) = prune!(d, (key,))
