# ------------------------------------------------------------------------------
# Display Methods
# ------------------------------------------------------------------------------
show(io::IO, d::SDTree{KT, VT})           where {KT, VT}         = print(io, "SDTree{$KT, $VT} with $(length(d)) entries")
show(io::IO, v::SDBranch{KT, PT, ST, VT}) where {KT, PT, ST, VT} = print(io, "SDBranch{$KT, $PT, $ST, $VT}, prefix = $(repr(v.prefix)) with $(length(v)) entries")
show(io::IO, e::SDLeaf)                                          = print(io, "SDLeaf, key = $(repr(e.key))")
show(io::IO, dt::DictTree)                                       = print(io, "DictTree with $(length(dt.trees)) active depth layer(s)")
show(io::IO, db::DictBranch)                                     = print(io, "DictBranch (prefix = $(repr(db.prefix))) $(length(collect(_sorted_branches(db)))) active depth layer(s)")

function show(io::IO, mime::MIME"text/plain", d::SDTree)
    show(io, d)
    println(io, ":")
    print_tree(io, d)
end

function show(io::IO, mime::MIME"text/plain", d::Union{SDBranch, SDLeaf})
    if is_stale(d)
        print(io, "Object is stale")
        return
    end
    show(io, d)
    println(io, ":")
    print_tree(io, BranchAsRoot(d))
end

function show(io::IO, mime::MIME"text/plain", dt::DictTree)
    show(io, dt)
    println(io, ":")
    print_tree(io, dt)
end

function show(io::IO, mime::MIME"text/plain", db::DictBranch)
    show(io, db)
    println(io, ":")
    print_tree(io, BranchAsRoot(db))
end
