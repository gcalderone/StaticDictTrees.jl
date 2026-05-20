# ------------------------------------------------------------------------------
# Deletion and pruning logic
# ------------------------------------------------------------------------------
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
    delete!(d::SDTree{KT, VT}, key::KT)
    delete!(v::SDBranch, key::ST)

Removes a specific leaf `key` from the tree in O(1) time using the Swap-and-Pop pattern.
"""
function delete!(d::SDTree{KT, VT}, key::KT) where {KT, VT}
    vacant_pos = get(d.lookup, key, nothing)
    isnothing(vacant_pos)  &&  return d

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

delete!(v::SDBranch{KT, PT, ST, VT}, key::ST) where {KT, PT, ST, VT} = delete!(v.root, (v.prefix..., key...))
delete!(d::AbstractSDTree, key) = prune!(d, (key,))
