# ==========================================================================
# Corner cases: internal invariants, randomized model checking, and the
# behavior at the boundaries of the API.
# ==========================================================================

# Verify the consistency of all internal structures of an `SDTree`.
function check_invariants(t::SDTree)
    KT = keytype(t)
    N = fieldcount(KT)
    n = length(t.values)
    (length(t.keys) == n == length(t.lookup))  ||  return false
    for (k, i) in t.lookup
        (1 <= i <= n)  &&  (t.keys[i] == k)  ||  return false
    end
    for depth in 1:(N-1)
        for (prefix, bl) in t.branch_lookup[depth]
            isempty(bl)  &&  return false  # empty branches must be removed
            for (suffix, i) in bl
                (get(t.lookup, (prefix..., suffix...), 0) == i)  ||  return false
            end
        end
        # each leaf is registered in the branch dictionaries at every depth
        for k in keys(t.lookup)
            bl = get(t.branch_lookup[depth], k[1:depth], nothing)
            (!isnothing(bl)  &&  haskey(bl, k[(depth+1):end]))  ||  return false
        end
        # the cached view indices are either invalidated (empty) or correct
        for (prefix, bv) in t.branch_viewids[depth]
            haskey(t.branch_lookup[depth], prefix)  ||  return false
            isempty(bv)  ||  (bv == collect(values(t.branch_lookup[depth][prefix])))  ||  return false
        end
    end
    isempty(t.viewid)  ||  (t.viewid == collect(values(t.lookup)))  ||  return false
    return true
end

# Simple deterministic pseudo-random generator (avoids a dependency on Random)
mutable struct XorShift
    s::UInt64
end
function next!(r::XorShift, n::Int)
    r.s ⊻= r.s << 13; r.s ⊻= r.s >> 7; r.s ⊻= r.s << 17
    return Int(r.s % UInt64(n)) + 1
end

@testset "20. Randomized model check (SDTree vs OrderedDict)" begin
    KT = Tuple{Symbol, Int, String}
    A1 = [:a, :b, :c]; A2 = [1, 2]; A3 = ["x", "y", "z"]  # small alphabets: branches are often emptied and refilled
    rnd = XorShift(0x9e3779b97f4a7c15)
    randkey() = (A1[next!(rnd, 3)], A2[next!(rnd, 2)], A3[next!(rnd, 3)])

    deleted_by_hook = Ref(0)
    t = SDTree{KT, Int}(on_delete = (k, v) -> (deleted_by_hook[] += 1))
    ref = OrderedDict{KT, Int}()
    expected_deleted = 0

    all_prefixes = vcat([()], [(p1,) for p1 in A1], [(p1, p2) for p1 in A1 for p2 in A2])
    held_views = Dict{Any, Any}()       # long-lived branch views, created when the branch existed
    held_vv    = Dict{Any, Any}()       # long-lived values_view on the above
    root_vv = values_view(t)

    for step in 1:4000
        op = next!(rnd, 20)
        if op <= 9                       # insert or update
            k = randkey(); v = step
            t[k] = v; ref[k] = v
        elseif op <= 15                  # delete (possibly a missing key)
            k = randkey()
            haskey(ref, k)  &&  (expected_deleted += 1)
            delete!(t, k); delete!(ref, k)
        elseif op <= 19                  # prune a random prefix (including the empty one)
            p = all_prefixes[next!(rnd, length(all_prefixes))]
            if next!(rnd, 4) == 1  &&  length(p) > 0
                # prune from within a branch view
                M = length(p)
                haspath(t, p[1:1])  &&  prune!(view(t, p[1:1]), p[2:end])
            else
                prune!(t, p)
            end
            for k in collect(keys(ref))
                if k[1:length(p)] == p
                    delete!(ref, k); expected_deleted += 1
                end
            end
        else                             # occasionally refresh the views
            root_vv = values_view(t)
            for p in all_prefixes[2:end]
                if haspath(t, p)
                    held_views[p] = view(t, p)
                    held_vv[p] = values_view(held_views[p])
                end
            end
        end

        # Checks
        @test check_invariants(t)
        @test collect(t) == collect(ref)                    # same content and same insertion order
        @test length(t) == length(ref)
        @test collect(values_view(t)) == collect(values(ref))
        @test isempty(root_vv)  ||  (collect(root_vv) == collect(values(ref)))
        @test deleted_by_hook[] == expected_deleted

        for p in all_prefixes[2:end]
            expected = [k[(length(p)+1):end] => v for (k, v) in ref if k[1:length(p)] == p]
            @test haspath(t, p) == !isempty(expected)
            if !isempty(expected)
                b = view(t, p)
                @test collect(b) == expected
                @test collect(values_view(b)) == last.(expected)
            end
            if haskey(held_views, p)
                hv = held_views[p]
                if is_stale(hv)
                    @test length(hv) == 0
                    @test isempty(collect(hv))
                    @test isempty(values_view(hv))
                    @test isempty(held_vv[p])           # a stale view never exposes foreign data
                else
                    @test collect(hv) == expected
                    @test isempty(held_vv[p])  ||  (collect(held_vv[p]) == last.(expected))
                end
            end
        end
    end
end


@testset "21. Corner cases: failed insertions leave the tree unchanged" begin
    # on_insert rejecting a value
    t = SDTree{Tuple{Symbol, Int}, Float64}(on_insert = (k, v) -> v >= 0 ? v : throw(ArgumentError("negative")))
    t[:a, 1] = 1.0; t[:a, 2] = 2.0
    @test_throws ArgumentError t[:b, 1] = -1.0
    @test check_invariants(t)
    @test !haskey(t, (:b, 1))
    @test !haspath(t, (:b,))
    t[:c, 1] = 3.0
    delete!(t, (:a, 1))
    delete!(t, (:c, 1))
    @test check_invariants(t)
    @test collect(t) == [(:a, 2) => 2.0]

    # value not convertible to the value type
    t = SDTree{Tuple{Symbol}, Float64}()
    t[:a] = 1.0
    @test_throws MethodError t[:b] = "string"
    @test check_invariants(t)
    @test collect(keys(t)) == [(:a,)]

    # on_insert returning a non-convertible value
    t = SDTree{Tuple{Symbol}, Float64}(on_insert = (k, v) -> "bad")
    @test_throws MethodError t[:a] = 1.0
    @test check_invariants(t)
    @test isempty(t)

    # on_update throwing: the old value is preserved
    t = SDTree{Tuple{Symbol}, Int}(on_update = (k, o, n) -> n > o ? n : throw(ArgumentError("must increase")))
    t[:a] = 5
    @test_throws ArgumentError t[:a] = 1
    @test t[:a] == 5
    @test check_invariants(t)

    # on_delete throwing: the entry is not removed
    t = SDTree{Tuple{Symbol}, Int}(on_delete = (k, v) -> throw(ArgumentError("protected")))
    t[:a] = 1
    @test_throws ArgumentError delete!(t, (:a,))
    @test haskey(t, (:a,))
    @test check_invariants(t)

    # typed DictTree layer rejecting a value
    dt = DictTree()
    add_layer!(dt, SDTree{Tuple{Symbol}, Float64}())
    dt[(:x,)] = 1.0
    @test_throws MethodError dt[(:y,)] = "string"
    @test check_invariants(get_layer(dt, 1))
    @test collect(keys(dt)) == [(:x,)]
end


@testset "22. Corner cases: hook semantics" begin
    log = []
    t = SDTree{Tuple{Symbol, Int}, Int}(on_insert = (k, v) -> 10v,
                                        on_update = (k, o, n) -> o + n,
                                        on_delete = (k, v) -> push!(log, k))
    # setindex! returns the assigned value, not the stored one
    @test (t[:a, 1] = 1) == 1
    @test t[:a, 1] == 10
    @test (t[:a, 1] = 2) == 2
    @test t[:a, 1] == 12

    # merge! goes through on_update / on_insert
    merge!(t, Dict((:a, 1) => 3, (:a, 2) => 4))
    @test t[:a, 1] == 15
    @test t[:a, 2] == 40

    # delete! of a missing key does not trigger the hook
    delete!(t, (:zz, 1))
    @test isempty(log)

    # on_delete is triggered by delete!, pop!, prune!, empty!(SDBranch) and empty!(SDLeaf)
    t[:b, 1] = 1; t[:c, 1] = 1; t[:d, 1] = 1; t[:e, 1] = 1; t[:f, 1] = 1
    delete!(t, (:a, 1));           @test log[end] == (:a, 1)
    pop!(t, (:a, 2));              @test log[end] == (:a, 2)
    prune!(t, (:b,));              @test log[end] == (:b, 1)
    empty!(view(t, (:c,)));        @test log[end] == (:c, 1)
    empty!(view(t, (:d, 1)));      @test log[end] == (:d, 1)
    prune!(t, ());                 @test sort(log[end-1:end]) == [(:e, 1), (:f, 1)]
    @test isempty(t)

    # ... but NOT by empty!(::SDTree), which resets the tree in one go
    t[:g, 1] = 1
    n = length(log)
    empty!(t)
    @test length(log) == n
    @test isempty(t)
    @test check_invariants(t)

    # hooks are applied while populating the tree in the constructor
    t = SDTree{Tuple{Int}, Int}((1,) => 1, (1,) => 2; on_update = (k, o, n) -> o + n)
    @test t[1] == 3
end


@testset "23. Corner cases: depth, empty prefixes and path lengths" begin
    # depth-0 tree
    t0 = SDTree{Tuple{}, Int}()
    @test depth(t0) == 0
    @test is_leaf_level(t0)
    t0[()] = 5
    @test t0[()] == 5
    @test length(t0) == 1
    l0 = view(t0, ())
    @test l0 isa SDLeaf
    @test l0[()] == 5
    @test collect(values_view(t0)) == [5]
    @test haspath(t0, ())
    prune!(t0, ())
    @test isempty(t0)
    @test is_stale(l0)

    # depth-1 tree
    t1 = SDTree{Tuple{Symbol}, Int}()
    t1[:a] = 1; t1[:b] = 2
    @test view(t1, :a) isa SDLeaf
    @test parent(view(t1, :a)) === t1
    @test_throws KeyError view(t1, :zz)
    @test_throws ArgumentError SDBranch(t1, (:a,))
    prune!(t1, (:a,))
    @test collect(keys(t1)) == [(:b,)]
    prune!(t1, ())
    @test isempty(t1)
    @test check_invariants(t1)
    @test sizehint!(t1, 10) === t1

    # deeper tree
    t = SDTree{Tuple{Symbol, Int, String}, Int}()
    t[:a, 1, "x"] = 1; t[:a, 2, "y"] = 2; t[:b, 1, "x"] = 3
    @test view(t, ()) === t
    @test_throws ArgumentError SDBranch(t, ())
    @test_throws ArgumentError view(t, (:a, 1, "x", 0))
    @test_throws KeyError view(t, (:zz,))
    @test_throws KeyError view(t, (:a, 1, "missing"))       # missing leaf
    b = view(t, (:a,))
    @test view(b, ()) === b
    @test view(b, (1, "x")) isa SDLeaf
    @test view(b, (1,)) isa SDBranch
    @test_throws KeyError view(b, (1, "missing"))
    @test_throws KeyError view(b, (9,))
    @test haspath(t, ())
    @test haspath(t, (:a, 1, "x"))
    @test !haspath(t, (:a, 1, "missing"))
    @test !haspath(t, (:a, 1, "x", 0))
    @test !haspath(t, ("wrong type",))
    @test haspath(b, (1,))
    @test !haspath(b, (9,))
    @test_throws ArgumentError prune!(t, (:a, 1, "x", 0))
    @test_throws ArgumentError prune!(b, (1, "x", 0))
    prune!(b, ())                                           # empty suffix: the whole branch
    @test !haspath(t, (:a,))
    @test is_stale(b)
    @test collect(keys(t)) == [(:b, 1, "x")]
    prune!(t, (:zz,))                                       # pruning a missing path is a no-op
    prune!(t, (:b, 9))
    @test length(t) == 1
    @test check_invariants(t)

    # depth-6 tree (exercises the generated functions)
    t6 = SDTree{NTuple{6, Int}, Int}()
    for i in 1:2, j in 1:2
        t6[i, j, 3, 4, 5, 6] = 10i + j
    end
    @test length(view(t6, (1,))) == 2
    @test view(t6, (1, 2, 3, 4, 5))[6] == 12
    delete!(t6, (1, 1, 3, 4, 5, 6))
    prune!(view(t6, (2,)), (1,))
    @test collect(keys(t6)) == [(1, 2, 3, 4, 5, 6), (2, 2, 3, 4, 5, 6)]
    @test check_invariants(t6)
end


@testset "24. Corner cases: key types" begin
    t = SDTree{Tuple{Int}, Int}()
    t[1] = 1
    # keys of a different (even if convertible) type are rejected, unlike `Dict`
    @test !haskey(t, (Int32(1),))
    @test get(t, (Int32(1),), 0) == 0
    @test_throws ArgumentError t[Int32(1)]
    @test_throws ArgumentError t[Int32(2)] = 2
    @test_throws ArgumentError delete!(t, (Int32(1),))
    @test !haskey(t, (1, 2))
    @test !haskey(t, "1")

    # tuple-valued key elements must be wrapped explicitly
    tt = SDTree{Tuple{Tuple{Int, Int}}, Int}()
    tt[((1, 2),)] = 1
    @test tt[((1, 2),)] == 1
    @test_throws ArgumentError tt[(1, 2)]

    # abstract key types
    ta = SDTree{Tuple{Any, Any}, Int}()
    ta[:a, 1] = 1; ta[1, :b] = 2; ta["s", 2.5] = 3
    @test ta[1, :b] == 2
    @test length(view(ta, (:a,))) == 1
    delete!(ta, (1, :b))
    @test check_invariants(ta)

    # isequal semantics, as in Dict
    tf = SDTree{Tuple{Float64}, Int}()
    tf[NaN] = 1; tf[0.0] = 2; tf[-0.0] = 3
    @test tf[NaN] == 1
    @test length(tf) == 3
end


@testset "25. Corner cases: views" begin
    t = SDTree{Tuple{Symbol, Int}, Int}()
    t[:a, 1] = 1; t[:a, 2] = 2

    # leaf views
    l = view(t, (:a, 1))
    @test haskey(l, ())
    @test !haskey(l, (1,))
    @test collect(keys(l)) == [()]
    @test collect(values(l)) == [1]
    @test collect(l) == [() => 1]
    @test length(l) == 1
    @test collect(values_view(l)) == [1]
    @test StaticDictTrees.children(l) == ()
    @test depth(l) == 2
    @test is_leaf_level(l)
    @test root(l) === t
    l[()] = 7
    @test t[:a, 1] == 7
    @test get(l, (), 0) == 7
    delete!(l, ())
    @test is_stale(l)
    @test !haskey(l, ())
    @test isempty(collect(keys(l)))
    @test isempty(collect(values(l)))
    @test isempty(collect(l))
    @test length(l) == 0
    @test isempty(values_view(l))
    @test get(l, (), 0) == 0
    @test_throws KeyError l[()]
    @test sprint(show, MIME"text/plain"(), l) == "Object is stale"
    # a leaf view becomes valid again when its key is re-inserted...
    t[:a, 1] = 8
    @test !is_stale(l)
    @test l[()] == 8
    empty!(l)
    @test !haskey(t, (:a, 1))

    # ... while a branch view, once stale, stays stale
    b = view(t, (:a,))
    delete!(t, (:a, 2))
    @test is_stale(b)
    @test_throws KeyError b[1]
    b[1] = 5                                    # writes to the root tree...
    @test t[:a, 1] == 5
    @test is_stale(b)                           # ... but the view does not see it
    @test length(b) == 0
    @test isempty(collect(b))
    @test !is_stale(view(t, (:a,)))
    @test sprint(show, MIME"text/plain"(), b) == "Object is stale"
    @test isempty(StaticDictTrees.children(b))
    @test parent(b) === t
    delete!(b, 1)                               # mutations are forwarded to the root as well
    @test !haskey(t, (:a, 1))
    t[:a, 1] = 5; t[:a, 2] = 6
    prune!(b, ())
    @test !haspath(t, (:a,))

    # parent of a stale deep branch whose parent was removed
    t3 = SDTree{Tuple{Symbol, Int, Int}, Int}()
    t3[:a, 1, 1] = 1
    b3 = view(t3, (:a, 1))
    delete!(t3, (:a, 1, 1))
    @test_throws KeyError parent(b3)

    # partial deletion does not make a branch stale
    t[:a, 2] = 2
    b = view(t, (:a,))
    delete!(t, (:a, 1))
    @test !is_stale(b)
    @test collect(keys(b)) == [(2,)]

    # a branch view only accepts suffixes, not full root keys (neither inside nor outside its prefix)
    @test_throws ArgumentError b[(:a, 2)]
    @test_throws ArgumentError b[(:other, 1)] = 42
    @test_throws ArgumentError delete!(b, (:a, 2))
    @test !haskey(b, (:a, 2))
    @test get(b, (:a, 2), 0) == 0
    @test !haskey(t, (:other, 1))
    @test length(b) == 1
    # the whole tree remains reachable through `root`
    root(b)[(:other, 1)] = 42
    @test t[:other, 1] == 42

    # branch views on the same prefix share their state
    b1 = view(t, (:a,)); b2 = view(t, (:a,))
    b1[3] = 3
    @test b2[3] == 3

    # values_view writes through, and keeps working after updates
    vv = values_view(view(t, (:a,)))
    vv[1] = 100
    @test t[:a, 2] == 100
    t[:a, 3] = 30
    @test collect(vv) == [100, 30]

    # held root values_view: invalidated (empty) by a deletion, until values_view is called again
    rv = values_view(t)
    @test length(rv) == length(t)
    delete!(t, (:other, 1))
    @test isempty(rv)
    rv = values_view(t)
    @test collect(rv) == collect(values(t))
    t[:z, 1] = 0
    @test collect(rv) == collect(values(t))     # insertions are reflected without refreshing

    # iteration order: updates keep the position, re-insertions go to the end
    t = SDTree{Tuple{Symbol, Int}, Int}()
    for i in 1:3; t[:a, i] = i; end
    t[:a, 1] = 10
    @test collect(keys(view(t, (:a,)))) == [(1,), (2,), (3,)]
    delete!(t, (:a, 1)); t[:a, 1] = 1
    @test collect(keys(view(t, (:a,)))) == [(2,), (3,), (1,)]
    @test collect(keys(t)) == [(:a, 2), (:a, 3), (:a, 1)]
    @test collect(values_view(t)) == [2, 3, 1]

    # chained branch construction
    t = SDTree{Tuple{Symbol, Int, String}, Int}()
    t[:a, 1, "x"] = 1
    @test SDBranch(view(t, (:a,)), (1,)).prefix == (:a, 1)
    @test SDLeaf(view(t, (:a,)), (1, "x"))[()] == 1
end


@testset "26. Corner cases: constructors and AbstractDict interface" begin
    @test_throws ArgumentError SDTree()
    @test isempty(SDTree(Dict{Tuple{Int}, Int}()))
    @test_throws DimensionMismatch SDTree([(1,)], [1, 2])
    @test collect(SDTree([(1,), (1,)], [1, 2])) == [(1,) => 2]        # duplicate keys: last wins
    @test_throws MethodError SDTree((:a, 1) => 1, (:b, 2) => 2.0)    # pairs must have the same type...
    t = SDTree{Tuple{Symbol, Int}, Float64}((:a, 1) => 1, (:b, 2) => 2.0)   # ... unless types are explicit
    @test t[:a, 1] === 1.0
    @test_throws MethodError SDTree(Dict(1 => 2))                    # keys must be tuples

    t = SDTree{Tuple{Symbol, Int}, Int}()
    for i in 1:4; t[:a, i] = i; end
    @test keytype(t) == Tuple{Symbol, Int}
    @test valtype(t) == Int
    @test t == Dict((:a, i) => i for i in 1:4)
    @test ((:a, 2) => 2) in t
    @test !(((:a, 2) => 3) in t)
    @test copy(t) isa Dict                                          # generic AbstractDict fallback
    @test Dict(t) == copy(t)
    filter!(p -> iseven(p.second), t)
    @test collect(keys(t)) == [(:a, 2), (:a, 4)]
    @test check_invariants(t)
    @test get!(t, (:z, 1), 9) == 9
    @test t[:z, 1] == 9
    @test get(() -> -1, view(t, (:a,)), 9) == -1
    @test pop!(view(t, (:a,)), 9, :none) == :none
    @test_throws KeyError pop!(view(t, (:a,)), 9)
    @test sizehint!(t, 100) === t
    @test isempty(empty!(t))
    @test check_invariants(t)
    t[:a, 1] = 1                                                    # usable after empty!
    @test collect(t) == [(:a, 1) => 1]
end


@testset "27. Corner cases: DictTree and DictBranch" begin
    dt = DictTree()
    @test length(dt) == 0
    @test isempty(collect(dt))
    @test !haskey(dt, (:a,))
    @test_throws KeyError dt[(:a,)]
    prune!(dt, ())                                                  # no-op on an empty tree
    delete!(dt, (:a,))

    # views on missing prefixes are empty (no error) and writable
    db = view(dt, (:nope,))
    @test length(db) == 0
    @test isempty(collect(db))
    @test_throws KeyError db[()]
    db[(:x,)] = 1
    @test dt[(:nope, :x)] == 1
    @test length(db) == 1

    # iteration order: by depth, then by insertion
    dt = DictTree()
    dt[(:a, :b)] = 2; dt[(:a,)] = 1; dt[()] = 0; dt[(:c,)] = 3
    @test collect(keys(dt)) == [(), (:a,), (:c,), (:a, :b)]
    @test collect(keys(view(dt, (:a,)))) == [(), (:b,)]
    @test view(dt, (:a,))[()] == 1

    # prune! with an empty prefix removes everything, at all depths
    prune!(dt, ())
    @test length(dt) == 0

    # prune! of an intermediate node removes it and all its descendants, across layers
    dt = DictTree()
    dt[(:a,)] = 1; dt[(:a, :b)] = 2; dt[(:a, :b, :c)] = 3; dt[(:a, :x)] = 4
    prune!(dt, (:a, :b))
    @test collect(keys(dt)) == [(:a,), (:a, :x)]
    # empty!(DictBranch) also removes the branch node itself
    dt[(:z,)] = 0
    empty!(view(dt, (:a,)))
    @test collect(keys(dt)) == [(:z,)]

    # get / haskey / pop! on DictBranch
    dt = DictTree()
    dt[(:a, :b)] = 2
    db = view(dt, (:a,))
    @test haskey(db, (:b,))
    @test haskey(db, :b)
    @test get(db, :b, 0) == 2
    @test get(db, :zz, 0) == 0
    @test pop!(db, :b) == 2
    @test !haskey(dt, (:a, :b))
    @test pop!(dt, (:a, :b), :none) == :none

    # typed layers: wrong key type
    dt = DictTree()
    add_layer!(dt, SDTree{Tuple{Int}, Float64}(); label=:L1)
    @test_throws ArgumentError dt[(:sym,)] = 1.0
    @test_throws ArgumentError add_layer!(dt, SDTree{Tuple{Symbol}, Float64}())   # same depth twice
    # labels: missing label, label re-assigned to another depth
    @test_throws KeyError get_layer(dt, :nope)
    @test !haslayer(dt, :nope)
    add_layer!(dt, SDTree{Tuple{Int, Int}, Int}(); label=:L1)
    @test getlabels(dt) == Dict(:L1 => 2)
    dt[(1, 2)] = 3
    @test haslayer(view(dt, (1,)), :L1)
    @test haslayer(view(dt, (1,)), 2)
    @test !haslayer(view(dt, (9,)), 2)
    @test !haslayer(view(dt, (1,)), :nope)
    @test getlabels(view(dt, (1,))) === getlabels(dt)

    # on_new_branch: argument shape depends on depth (() at depth 0, scalar at depth 1, tuple otherwise)
    args = []
    dt = DictTree()
    add_layer!(dt, SDTree{Tuple{}, Any}(); on_new_branch = x -> (push!(args, x); 0))
    add_layer!(dt, SDTree{Tuple{Symbol}, Any}(); on_new_branch = x -> (push!(args, x); 1))
    add_layer!(dt, SDTree{Tuple{Symbol, Symbol}, Any}(); on_new_branch = x -> (push!(args, x); 2))
    dt[(:a, :b, :c)] = 3
    @test args == [(), :a, (:a, :b)]
    # ... it is not invoked again for existing nodes, and does not overwrite values
    dt[(:a,)] = "custom"
    dt[(:a, :b, :d)] = 4
    @test length(args) == 3
    @test dt[(:a,)] == "custom"

    # on_new_branch throwing: no partial insertion
    dt = DictTree()
    add_layer!(dt, SDTree{Tuple{Symbol}, Any}(); on_new_branch = x -> error("boom"))
    @test_throws ErrorException dt[(:a, :b)] = 1
    @test length(dt) == 0

    # clean_on_empty_branch: multi-level cascade
    mk() = (d = DictTree();
            add_layer!(d, SDTree{Tuple{Symbol}, Any}(); on_new_branch = identity, clean_on_empty_branch = true);
            add_layer!(d, SDTree{Tuple{Symbol, Symbol}, Any}(); on_new_branch = identity, clean_on_empty_branch = true);
            d)
    dt = mk()
    dt[(:a, :b, :c)] = 1
    delete!(dt, (:a, :b, :c))
    @test length(dt) == 0
    # ... blocked by a sibling
    dt = mk()
    dt[(:a, :b, :c)] = 1; dt[(:a, :x, :y)] = 1
    delete!(dt, (:a, :b, :c))
    @test collect(keys(dt)) == [(:a,), (:a, :x), (:a, :x, :y)]
    # ... triggered through a DictBranch
    dt = mk()
    dt[(:a, :b, :c)] = 1
    delete!(view(dt, (:a,)), (:b, :c))
    @test length(dt) == 0
    # ... blocked by an intermediate layer without the flag
    dt = DictTree()
    add_layer!(dt, SDTree{Tuple{Symbol}, Any}(); clean_on_empty_branch = true)
    dt[(:a,)] = 1; dt[(:a, :b)] = 2; dt[(:a, :b, :c)] = 3
    delete!(dt, (:a, :b, :c))
    @test haskey(dt, (:a,))
    @test haskey(dt, (:a, :b))
    # ... not triggered by deleting/pruning missing keys
    dt = mk()
    dt[(:a,)] = 1
    delete!(dt, (:a, :zz))
    prune!(dt, (:a, :zz))
    prune!(view(dt, (:a,)), (:zz,))
    @test haskey(dt, (:a,))
    # ... depth-0 layer
    dt = DictTree()
    add_layer!(dt, SDTree{Tuple{}, Any}(); on_new_branch = x -> "root", clean_on_empty_branch = true)
    dt[(:a,)] = 1
    @test dt[()] == "root"
    delete!(dt, (:a,))
    @test !haskey(dt, ())
end


@testset "28. Corner cases: display" begin
    @test occursin("0 entries", sprint(show, MIME"text/plain"(), SDTree{Tuple{Symbol}, Int}()))
    @test occursin("0 active layer", sprint(show, MIME"text/plain"(), DictTree()))
    t0 = SDTree{Tuple{}, Int}(); t0[()] = 1
    @test occursin("() => 1", sprint(show, MIME"text/plain"(), t0))
    # non-comparable keys
    dt = DictTree()
    dt[(:a,)] = 1; dt[(1,)] = 2; dt[(1, :x)] = 3; dt[(1, 2)] = 4; dt[()] = 0
    s = sprint(show, MIME"text/plain"(), dt)
    @test occursin("() => 0", s)
    @test occursin(":x => 3", s)
    @test occursin("(branch)", sprint(show, MIME"text/plain"(), view(DictTree((:a, :b) => 1), (:a,))))
    ta = SDTree{Tuple{Any, Any}, Int}()
    ta[:a, 1] = 1; ta[1, :b] = 2; ta[1, 2] = 3
    @test occursin(":b => 2", sprint(show, MIME"text/plain"(), ta))
    @test occursin("(branch)", sprint(show, MIME"text/plain"(), view(ta, (1,))))
end
