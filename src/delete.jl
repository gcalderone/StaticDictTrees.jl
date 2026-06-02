import Base: delete!

@generated function _update_branch_on_delete!(d::SDTree{KT}, key::KT, key_to_update::KT, new_pos::Int) where {KT <: Tuple}
    N = fieldcount(KT)
    exprs = Expr[]

    for depth in 1:(N-1)
        prefix_type = Tuple{fieldtypes(KT)[1:depth]...}
        branch_type = Tuple{fieldtypes(KT)[depth+1:end]...}

        push!(exprs, quote
            prefix = $(Expr(:tuple, [:(key[$i]) for i in 1:depth]...))::$prefix_type
            suffix = $(Expr(:tuple, [:(key[$i]) for i in (depth+1):N]...))::$branch_type

            lookups_at_depth = d.branch_lookup[$depth]::Dict{$prefix_type, OrderedDict{$branch_type, Int}}
            if haskey(lookups_at_depth, prefix)
                br_lookup = lookups_at_depth[prefix]
                delete!(br_lookup, suffix)
                if isempty(br_lookup)
                    delete!(lookups_at_depth, prefix)
                end
            end

            if new_pos > 0
                prefix = $(Expr(:tuple, [:(key_to_update[$i]) for i in 1:depth]...))::$prefix_type
                suffix = $(Expr(:tuple, [:(key_to_update[$i]) for i in (depth+1):N]...))::$branch_type
                lookups_at_depth[prefix][suffix] = new_pos
            end
        end)
    end
    return Expr(:block, exprs...)
end


"""
    delete!(d::SDTree, key::Tuple)
    delete!(v::SDBranch, key::Tuple)
    delete!(d::DictTree, key::Tuple)
    delete!(d::DictBranch, key::Tuple)

Removes a specific value from the tree.

*Note:* For `SDTree`, this will trigger the `on_delete` hook before the data is destroyed. For `DictTree`, this will also trigger upward garbage collection on parent layers if `clean_on_empty_branch` is enabled.
"""
function delete!(d::SDTree{KT}, key::KT) where {KT <: Tuple}
    vacant_pos = get(d.lookup, key, nothing)
    isnothing(vacant_pos)  &&  return d

    # deletion hook
    d.hooks.on_delete(key, d.values[vacant_pos])

    empty!(d.viewid)
    delete!(d.lookup, key)

    if vacant_pos == length(d.values)
        pop!(d.keys)
        pop!(d.values)
        _update_branch_on_delete!(d, key, key, 0)
    else
        key_to_keep = pop!(d.keys)
        d.keys[vacant_pos] = key_to_keep
        d.values[vacant_pos] = pop!(d.values)
        d.lookup[key_to_keep] = vacant_pos
        _update_branch_on_delete!(d, key, key_to_keep, vacant_pos)
    end

    return d
end
delete!(d::SDTree{KT}, key::T) where {KT <: Tuple, T <: Tuple} = throw(ArgumentError("Invalid key type: $KT != $T"))
delete!(d::SDTree, key) = delete!(d, (key,))


# ------------------------------------------------------------------------------
# SDBranch & SDLeaf Views
# ------------------------------------------------------------------------------
@generated function delete!(v::SDBranch{KT, PT, ST}, key::ST) where {KT <: Tuple, PT <: Tuple, ST <: Tuple}
    M = fieldcount(PT)
    L = fieldcount(ST)
    combined_tuple = Expr(:tuple, [:(v.prefix[$i]) for i in 1:M]..., [:(key[$i]) for i in 1:L]...)
    return quote
        delete!(v.root, $combined_tuple)
        return v
    end
end
delete!(v::SDBranch{KT, PT, ST}, key::T) where {KT <: Tuple, PT <: Tuple, ST <: Tuple, T <: Tuple} = throw(ArgumentError("Invalid key type: $ST != $T"))
delete!(v::SDBranch, key) = delete!(v, (key,))

delete!(v::SDLeaf, key::Tuple{}) = (delete!(v.root, v.key); v)

# ------------------------------------------------------------------------------
# DictTree Deletions
# ------------------------------------------------------------------------------
function Base.delete!(dt::DictTree, key::Tuple)
    target_depth = length(key)
    if haskey(dt.layers, target_depth)
        delete!(dt.layers[target_depth].tree, key)
    end

    for d in (target_depth - 1):-1:1
        if haskey(dt.layers, d)
            if dt.layers[d].clean_on_empty_branch
                t = get_tree(dt, d)
                prefix = key[1:d]
                if haskey(t, prefix)
                    if length(view(dt, prefix)) == 1
                        delete!(t, prefix)
                    end
                end
            end
        end
    end
    return dt
end
Base.delete!(dt::DictTree, key) = delete!(dt, (key,))

function Base.delete!(db::DictBranch, key::Tuple)
    full_key = (db.prefix..., key...)
    delete!(db.dt, full_key)
    return db
end
Base.delete!(db::DictBranch, key) = delete!(db, (key,))
