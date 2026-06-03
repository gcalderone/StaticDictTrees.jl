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

*Note:* This operation performs a batch deletion, meaning the `on_delete` hook will be triggered individually for every leaf that is pruned.
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
    target_depth = length(prefix)

    for (d, layer) in dt.layers
        if d >= target_depth
            prune!(layer.tree, prefix)
        end
    end

    # Upward cascade: automatically clean up orphaned parent metadata
    for d in (target_depth - 1):-1:0
        if haskey(dt.layers, d)
            if dt.layers[d].clean_on_empty_branch
                t = get_layer(dt, d)
                pref = prefix[1:d]
                if haskey(t, pref)
                    if length(view(dt, pref)) == 1
                        delete!(t, pref)
                    end
                end
            end
        end
    end
    return dt
end
prune!(dt::DictTree, prefix) = prune!(dt, (prefix,))

function prune!(db::DictBranch, prefix::Tuple)
    full_key = (db.prefix..., prefix...)
    prune!(db.dt, full_key)
    return db
end
prune!(db::DictBranch, prefix) = prune!(db, (prefix,))
