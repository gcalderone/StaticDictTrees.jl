"""
    prune!(d::SDTree, path::Tuple)
    prune!(v::SDBranch, path::Tuple)

Removes an entire branch (identified by `path`) and all of its associated leaves from the tree.
"""
function prune!(v::SDBranch{KT, PT, ST, VT}) where {KT, PT, ST, VT}
    for depth in fieldcount(PT):(fieldcount(KT) - 1)
        for k in filter(k -> k[1:fieldcount(PT)] == v.prefix, collect(keys(v.root.branch_lookup[depth])))
            dict = v.root.branch_lookup[depth][k]
            if depth == fieldcount(PT)
                i = collect(values(dict))
                deleteat!(v.root.keys  , i)
                deleteat!(v.root.values, i)
                for k in keys(dict)
                    delete!(v.root.lookup, (v.prefix..., k...))
                end
            end
            empty!(dict)
            delete!(v.root.branch_lookup[depth], k)
        end
    end
    return v
end


prune!(d::SDTree, path::Tuple) = prune!(view(d, path))
prune!(d::SDTree, key) = prune!(d, (key,))

prune!(v::SDBranch, path::Tuple) = prune!(view(v, path))
prune!(v::SDBranch, key) = prune!(v, (key,))

prune!(v::SDLeaf) = delete!(v.root, v.key)
