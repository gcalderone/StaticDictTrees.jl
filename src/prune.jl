export prune!

@generated function _get_branch_dict(d::SDTree{KT}, ::Val{L}) where {KT <: Tuple, L}
    prefix_type = Tuple{fieldtypes(KT)[1:L]...}
    branch_type = Tuple{fieldtypes(KT)[L+1:end]...}
    return :(d.branch_lookup[$L]::Dict{$prefix_type, OrderedDict{$branch_type, Int}})
end

"""
    prune!(d::SDTree, prefix::Tuple)
    prune!(v::SDBranch, prefix::Tuple)
    prune!(dt::DictTree, prefix::Tuple)
    prune!(db::DictBranch, prefix::Tuple)

Deletes all leaves having `prefix` in their keys.
"""
function prune!(d::SDTree{KT}, prefix::T) where {KT <: Tuple, T <: Tuple}
    M = fieldcount(T)
    N = fieldcount(KT)

    if M > N
        throw(ArgumentError("Path length ($M) exceeds tree depth ($N)."))
    elseif M == N
        return delete!(d, prefix)
    else
        lookups_at_depth = _get_branch_dict(d, Val(M))
        t = get(lookups_at_depth, prefix, nothing)
        if !isnothing(t)
            suffixes = collect(keys(t))
            for suff in suffixes
                full_key = (prefix..., suff...)
                delete!(d, full_key)
            end
        end
    end
    return d
end
prune!(d::SDTree{KT}, prefix) where {KT <: Tuple} = prune!(d, (prefix,))


@generated function prune!(v::SDBranch{KT, PT, ST}, path::T) where {KT <: Tuple, PT <: Tuple, ST <: Tuple, T <: Tuple}
    M = fieldcount(T)
    N = fieldcount(ST)

    if M > N
        throw(ArgumentError("Path length ($M) exceeds branch depth ($N)."))
    elseif M == N
        return :(delete!(v, path))
    else
        combined_tuple = Expr(:tuple, [:(v.prefix[$i]) for i in 1:fieldcount(PT)]..., [:(path[$i]) for i in 1:M]...)
        return quote
            prune!(v.root, $combined_tuple)
            return v
        end
    end
end
prune!(v::SDBranch{KT, PT, ST}, path) where {KT <: Tuple, PT <: Tuple, ST <: Tuple} = prune!(v, (path,))


function prune!(dt::DictTree, prefix::Tuple)
    M = length(prefix)
    for (d, t) in dt.trees
        if d == M
            delete!(t, prefix)  # just delete the leaf
        elseif d > M
            if haskey(t.branch_lookup[M], prefix)
                suffixes = collect(keys(t.branch_lookup[M][prefix]))
                for suff in suffixes
                    full_key = (prefix..., suff...)
                    delete!(t, full_key)
                end
            end
        end
    end
    return dt
end
prune!(dt::DictTree, prefix) = prune!(dt, (prefix,))

function prune!(db::DictBranch, path::Tuple)
    full_key = (db.prefix..., path...)
    prune!(db.dt, full_key)
    return db
end
prune!(db::DictBranch, path) = prune!(db, (path,))
