@generated function _get_branch_dict(d::SDTree{KT}, ::Val{L}) where {KT <: Tuple, L}
    prefix_type = Tuple{fieldtypes(KT)[1:L]...}
    branch_type = Tuple{fieldtypes(KT)[L+1:end]...}
    return :(d.branch_lookup[$L]::Dict{$prefix_type, OrderedDict{$branch_type, Int}})
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

    lookups_at_depth = _get_branch_dict(d, Val(L))

    if haskey(lookups_at_depth, path)
        br_lookup = lookups_at_depth[path]

        keys_to_delete = [convert(KT, (path..., suffix...)) for suffix in keys(br_lookup)]

        for key in keys_to_delete
            delete!(d, key)
        end
    end

    return d
end

function prune!(v::SDBranch, path::Tuple)
    prune!(v.root, (v.prefix..., path...))
    return v
end

prune!(d::AbstractSDTree, key) = prune!(d, (key,))
