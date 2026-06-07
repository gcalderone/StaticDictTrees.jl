# ------------------------------------------------------------------------------
# AbstractTrees interface
# ------------------------------------------------------------------------------
using AbstractTrees
import AbstractTrees: children, printnode

"""
    children(d::SDTree)
    children(v::SDBranch)
    children(dt::DictTree)
    children(db::DictBranch)

Returns an array of views (`SDBranch`, `SDLeaf`, or `DictBranch`) representing the immediate structural children of the given tree or branch.
"""
function children(d::SDTree{KT}) where {KT <: Tuple}
    if is_leaf_level(d)
        return [SDLeaf(d, k) for k in sort(collect(keys(d.lookup)))]
    else
        return [SDBranch(d, p) for p in sort(collect(keys(d.branch_lookup[1])))]
    end
end

function children(v::SDBranch{KT, PT}) where {KT <: Tuple, PT <: Tuple}
    M = fieldcount(PT)
    if is_leaf_level(v)
        return [SDLeaf(v.root, (v.prefix..., k...)) for k in sort(collect(keys(v.lookup)))]
    else
        next_level_dict = v.root.branch_lookup[M + 1]
        next_prefixes = [p for p in keys(next_level_dict) if p[1:M] == v.prefix]
        return [SDBranch(v.root, p) for p in sort(next_prefixes)]
    end
end

children(::SDLeaf) = ()


function children(dt::DictTree)
    prefs = Set{Tuple}()
    for (d, layer) in dt.layers
        if d == 1
            for k in keys(layer.tree.lookup) push!(prefs, k) end
        elseif d > 1
            for k in keys(layer.tree.branch_lookup[1]) push!(prefs, k) end
        end
    end
    return [view(dt, p) for p in sort(collect(prefs))]
end

function children(db::DictBranch)
    M = length(db.prefix)
    prefs = Set{Tuple}()

    for (d, layer) in db.dt.layers
        if (d > M)  &&  hasbranch(layer.tree, db.prefix)
            b = view(layer.tree, db.prefix)
            if d == M + 1
                for suff in keys(b.lookup)
                    push!(prefs, (db.prefix..., suff...))
                end
            else
                next_dict = layer.tree.branch_lookup[M+1]
                for p in keys(next_dict)
                    if p[1:M] == db.prefix
                        push!(prefs, p)
                    end
                end
            end
        end
    end

    return [view(db.dt, p) for p in sort(collect(prefs))]
end

struct BranchAsRoot{T}
    s::T
end
children(s::BranchAsRoot) = children(s.s)


printnode(io::IO, d::SDTree) = printstyled(io, "(root)", bold=true)
printnode(io::IO, v::SDBranch)  = printstyled(io, repr(v.prefix[end]), bold=true)
printnode(io::IO, e::SDLeaf) =          print(io, repr(e.key[end]), " => ", repr(e[()]))
printnode(io::IO, e::SDLeaf{Tuple{}}) = print(io, repr(e.key)     , " => ", repr(e[()]))
printnode(io::IO, ::BranchAsRoot{<:SDBranch}) = printstyled(io, "(branch)", bold=true)
printnode(io::IO, w::BranchAsRoot{<:SDLeaf}) = printnode(io, w.s)

function printnode(io::IO, dt::DictTree)
    if haskey(dt, ())
        printstyled(io, "() => ", repr(dt[()]))
    else
        printstyled(io, "(root)", bold=true)
    end
end

function printnode(io::IO, db::DictBranch)
    if haskey(db.dt, db.prefix)
        printstyled(io, repr(db.prefix[end]), " => ", repr(db.dt[db.prefix]))
    else
        printstyled(io, repr(db.prefix[end]), bold=true)
    end
end

function printnode(io::IO, w::BranchAsRoot{<:DictBranch})
    if haskey(w.s.dt, w.s.prefix)
        printstyled(io, "() => ", repr(w.s.dt[w.s.prefix]))
    else
        printstyled(io, "(branch)", bold=true)
    end
end
