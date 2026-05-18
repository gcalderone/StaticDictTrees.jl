# ------------------------------------------------------------------------------
# Deletion and pruning logic
# ------------------------------------------------------------------------------
@generated function delete_and_shift_branches!(d::SDTree{KT}, key::KT, I::Int) where {KT <: Tuple}
    N = fieldcount(KT)
    exprs = Expr[]

    for depth in 1:(N-1)
        prefix_type = Tuple{fieldtypes(KT)[1:depth]...}
        branch_type = Tuple{fieldtypes(KT)[depth+1:end]...}

        push!(exprs, quote
            prefix = $(Expr(:tuple, [:(key[$i]) for i in 1:depth]...))::$prefix_type
            suffix = $(Expr(:tuple, [:(key[$i]) for i in (depth+1):N]...))::$branch_type

            lookup_dict = d.branch_lookup[$depth]::Dict{$prefix_type, OrderedDict{$branch_type, Int}}

            if haskey(lookup_dict, prefix)
                delete!(lookup_dict[prefix], suffix)
                if isempty(lookup_dict[prefix])
                    delete!(lookup_dict, prefix)
                end
            end

            for inner_dict in values(lookup_dict)
                for (k, v) in inner_dict
                    if v > I
                        inner_dict[k] = v - 1
                    end
                end
            end
        end)
    end

    return Expr(:block, exprs...)
end

"""
    delete!(d::SDTree{KT, VT}, key::KT)
    delete!(v::SDBranch, key::ST)

Removes a specific leaf `key` from the tree.

Because values are stored in a flat array, deleting a leaf forces all subsequent elements to shift, making this an O(E) operation (where E is the number of elements). For removing entire sub-trees efficiently, use `prune!`.
"""
function delete!(d::SDTree{KT, VT}, key::KT) where {KT, VT}
    !haskey(d.lookup, key) && return d

    I = d.lookup[key]

    # Remove from flat lists
    deleteat!(d.values, I)
    deleteat!(d.keys, I)
    delete!(d.lookup, key)

    # Shift all root indices > I
    for (k, v) in d.lookup
        if v > I
            d.lookup[k] = v - 1
        end
    end

    # Branch deletion & shifting
    delete_and_shift_branches!(d, key, I)

    return d
end

delete!(v::SDBranch{KT, PT, ST, VT}, key::ST) where {KT, PT, ST, VT} = delete!(v.parent, (v.prefix..., key...))
delete!(d::AbstractSDTree, key) = prune!(d, (key,))
