using Test
using DataStructures
using AbstractTrees

using StaticDictTrees

@testset "StaticDictTrees & DictTree Full Suite" begin

    # ==========================================================================
    # PART 1: The Core (SDTree, SDBranch, SDLeaf)
    # ==========================================================================

    @testset "1. SDTree Constructors & Edge Cases" begin
        t1 = SDTree{Tuple{Int, Int}, String}()
        @test isempty(t1)
        @test depth(t1) == 2
        @test length(t1) == 0

        t2 = SDTree((1, 2) => "A", (3, 4) => "B")
        @test length(t2) == 2
        @test t2[(1, 2)] == "A"

        d = Dict((1,) => 10, (2,) => 20)
        t3 = SDTree(d)
        @test length(t3) == 2
        @test t3[(2,)] == 20

        keys_vec = [(1, 1), (2, 2)]
        vals_vec = [100, 200]
        t4 = SDTree(keys_vec, vals_vec)
        @test length(t4) == 2
        @test t4[(2, 2)] == 200

        @test sizehint!(t4, 100) === t4

        t0 = SDTree{Tuple{}, Int}()
        @test depth(t0) == 0
        @test is_leaf_level(t0)
        t0[()] = 42
        @test t0[()] == 42
        @test length(t0) == 1
    end

    @testset "2. Tree Properties (depth, is_leaf_level, parent, root)" begin
        dt = SDTree{Tuple{Int, Symbol, String}, Float64}()
        dt[1, :server, "latency"] = 12.5

        br1 = SDBranch(dt, (1,))
        br2 = SDBranch(dt, (1, :server))
        lf  = SDLeaf(dt, (1, :server, "latency"))

        @test depth(dt)  == 3
        @test depth(br1) == 1
        @test depth(br2) == 2
        @test depth(lf)  == 3

        @test !is_leaf_level(dt)
        @test !is_leaf_level(br1)
        @test is_leaf_level(br2)
        @test is_leaf_level(lf)

        @test parent(dt) === nothing
        @test parent(br1) === dt
        @test parent(br2).prefix == (1,)
        @test parent(lf).prefix == (1, :server)

        dt_flat = SDTree{Tuple{Int}, Float64}()
        @test is_leaf_level(dt_flat)
        @test parent(SDLeaf(dt_flat, (1,))) === dt_flat

        @test root(dt) === dt
        @test root(br1) === dt
        @test root(br2) === dt
        @test root(lf) === dt

        br_nested = view(br1, (:server,))
        @test root(br_nested) === dt
    end

    @testset "3. SDTree Base API & Type Boundaries" begin
        t = SDTree{Tuple{Int, Int}, Float64}()

        t[(1, 1)] = 1.0
        t[(1, 2)] = 2.0
        @test length(t) == 2
        @test t[(1, 1)] == 1.0
        @test_throws KeyError t[(2, 2)]
        @test_throws ArgumentError t[(1,)]

        @test haskey(t, (1, 1))
        @test !haskey(t, (2, 2))
        @test !haskey(t, (1,))

        t[(1, 1)] = 5.0
        @test length(t) == 2
        @test t[(1, 1)] == 5.0

        t[(2, 1)] = 3.0
        v_view = values_view(t)
        @test v_view == [5.0, 2.0, 3.0]

        # Type Boundaries & Safe ArgumentErrors
        sdt = SDTree{Tuple{Symbol, Int}, String}()
        sdt[:A, 1] = "Found"
        @test_throws ArgumentError sdt[:A, "WrongType"] = "Fail"
        @test_throws ArgumentError sdt[:A, "WrongType"]
        @test_throws ArgumentError delete!(sdt, (:A, "WrongType"))
        @test !haskey(sdt, (:A, "WrongType"))

        # Scalar key forwarding on SDTree
        sdt_flat = SDTree{Tuple{Symbol}, Int}()
        sdt_flat[:ScalarKey] = 42
        @test sdt_flat[:ScalarKey] == 42
        @test haskey(sdt_flat, :ScalarKey)
        delete!(sdt_flat, :ScalarKey)
        @test !haskey(sdt_flat, :ScalarKey)

        sdt_flat[:Another] = 100
        prune!(sdt_flat, :Another)
        @test length(sdt_flat) == 0
    end

    @testset "4. Core Data Lifecycle Hooks (on_insert, on_update, on_delete)" begin
        deleted_log = []

        # Create a tree that accumulates updates instead of replacing,
        # rounds insertions, and logs deletions.
        t_hooks = SDTree{Tuple{Symbol}, Float64}(
            on_insert = (k, v) -> v > 0.0 ? round(v; digits=1) : throw(ArgumentError("No negative!")),
            on_update = (k, old_v, new_v) -> old_v + new_v, # Accumulator pattern
            on_delete = (k, v) -> push!(deleted_log, (k, v))
        )

        # 1. on_insert validation/modification
        t_hooks[:Sales] = 100.56
        @test t_hooks[:Sales] == 100.6
        @test_throws ArgumentError t_hooks[:Eng] = -50.0

        # 2. on_update (Accumulation)
        t_hooks[:Sales] = 50.0
        @test t_hooks[:Sales] == 150.6 # 100.6 + 50.0

        # 3. on_delete memory tracking
        delete!(t_hooks, :Sales)
        @test length(deleted_log) == 1
        @test deleted_log[1] == ((:Sales,), 150.6)
    end

    @testset "5. Core Views (SDBranch & SDLeaf)" begin
        t = SDTree{Tuple{Int, Int, Int}, String}()
        t[(1, 1, 1)] = "A"
        t[(1, 1, 2)] = "B"
        t[(1, 2, 1)] = "C"
        t[(2, 1, 1)] = "D"

        v1 = view(t, (1,))
        @test v1 isa SDBranch
        @test length(v1) == 3
        @test haskey(v1, (1, 1))
        @test v1[(1, 1)] == "A"
        @test v1[(1, 1, 1)] == "A"  # use SDTree key

        v11 = view(v1, (1,))
        @test v11 isa SDBranch
        @test length(v11) == 2
        @test v11[(2,)] == "B"
        @test v11[(1, 1, 2,)] == "B" # use SDTree key

        l = view(t, (1, 1, 1))
        @test l isa SDLeaf
        @test length(l) == 1
        @test l[()] == "A"

        v11[(2,)] = "B_mod"
        @test t[(1, 1, 2)] == "B_mod"
        v11[(1, 1, 2,)] = "B_mod_mod" # use SDTree key
        @test t[(1, 1, 2)] == "B_mod_mod"

        l[()] = "A_mod"
        @test t[(1, 1, 1)] == "A_mod"
        @test v1[(1, 1)] == "A_mod"

        @test_throws ArgumentError view(t, (1, 1, 1, 99))
        @test_throws KeyError view(t, (99,))
        @test_throws KeyError view(v1, (99,))

        # SDBranch View mutations and nested constructors
        sdt_deep = SDTree((:A, :B, :C) => 100)
        br_deep = view(sdt_deep, (:A,))

        @test_throws ArgumentError br_deep[:B, "WrongType"] = 200
        @test_throws ArgumentError br_deep[:B, "WrongType"]
        @test_throws ArgumentError delete!(br_deep, (:B, "WrongType"))
        @test !haskey(br_deep, (:B, "WrongType"))

        br_nested = SDBranch(br_deep, (:B,))
        @test br_nested[(:C,)] == 100
        br_nested[:C] = 150
        @test sdt_deep[(:A, :B, :C)] == 150
        delete!(br_nested, :C)

        # SDLeaf constructor with offset suffix
        sdt_lf = SDTree((:X, :Y) => 1)
        br_lf = view(sdt_lf, (:X,))
        lf_obj = SDLeaf(br_lf, (:Y,))
        @test lf_obj[()] == 1
        delete!(lf_obj, ())
        @test is_leaf_level(lf_obj)
    end

    @testset "6. Iteration and Collection" begin
        dt = SDTree((1, :a) => 10, (1, :b) => 20, (2, :c) => 30)

        @test length(collect(dt)) == 3
        @test ((1, :a) => 10) in collect(dt)

        lazy_vals = values(dt)
        @test !(lazy_vals isa AbstractArray)
        @test collect(lazy_vals) == [10, 20, 30]

        br = view(dt, (1,))
        @test is_leaf_level(br)
        @test length(collect(br)) == 2
        @test ((:a,) => 10) in collect(br)
        @test collect(values(br)) == [10, 20]

        lf = view(dt, (2, :c))
        @test length(collect(lf)) == 1
        @test collect(lf)[1] == (() => 30)
        @test collect(values(lf)) == [30]
    end

    @testset "7. Core Destructive Operations & Swap-with-Last" begin
        t = SDTree{Tuple{Int, Int}, Int}()
        t[(1, 1)] = 10
        t[(1, 2)] = 20
        t[(2, 1)] = 30
        t[(2, 2)] = 40

        delete!(t, (1, 1))
        @test !haskey(t, (1, 1))
        @test length(t) == 3
        @test values_view(t) == [20, 30, 40]

        @test delete!(t, (99, 99)) === t

        br = view(t, (2,))
        delete!(br, (1,))
        @test length(t) == 2
        @test !haskey(t, (2, 1))
        @test haskey(t, (2, 2))

        v = view(t, (1,))
        empty!(v)
        @test !haskey(t, (1, 2))
        @test length(t) == 1

        empty!(t)
        @test length(t) == 0
        @test isempty(t.values)
    end

    @testset "8. Core Pruning (SDTree & SDBranch)" begin
        t = SDTree{Tuple{Int, Int, Int}, String}()
        t[(1, 1, 1)] = "A"
        t[(1, 1, 2)] = "B"
        t[(1, 2, 1)] = "C"
        t[(2, 1, 1)] = "D"

        prune!(t, (2, 1, 1))
        @test !haskey(t, (2, 1, 1))
        @test length(t) == 3

        prune!(t, (1, 1))
        @test !haskey(t, (1, 1, 1))
        @test !haskey(t, (1, 1, 2))
        @test haskey(t, (1, 2, 1))
        @test length(t) == 1

        @test_throws ArgumentError prune!(t, (1, 2, 1, 99))
        @test length(t) == 1

        t2 = SDTree{Tuple{Int, Int, Int}, String}()
        t2[(1, 1, 1)] = "A"
        t2[(1, 1, 2)] = "B"
        t2[(1, 2, 1)] = "C"
        t2[(1, 2, 2)] = "D"
        t2[(2, 1, 1)] = "E"

        br = view(t2, (1,))
        @test length(br) == 4

        prune!(br, (1,))
        @test !haskey(t2, (1, 1, 1))
        @test !haskey(t2, (1, 1, 2))
        @test length(br) == 2
        @test haskey(br, (2, 1))
        @test haskey(br, (2, 2))

        prune!(br, (2, 1))
        @test !haskey(t2, (1, 2, 1))
        @test length(br) == 1
        @test haskey(t2, (1, 2, 2))

        @test_throws ArgumentError prune!(br, (2, 2, 99))
        @test length(br) == 1
    end

    @testset "9. Stale Views & Safe Fallbacks" begin
        dt = SDTree((:A, :B, :C) => 1.0,
                    (:A, :B, :D) => 2.0,
                    (:X, :Y, :Z) => 3.0)

        branch_v = view(dt, (:A, :B))
        leaf_v   = view(dt, (:A, :B, :C))

        @test !is_stale(branch_v)
        @test !is_stale(leaf_v)
        @test length(branch_v) == 2
        @test length(leaf_v) == 1

        delete!(dt, (:X, :Y, :Z))
        @test !is_stale(branch_v)
        @test !is_stale(leaf_v)

        delete!(dt, (:A, :B, :C))
        @test is_stale(leaf_v)
        @test !is_stale(branch_v)

        delete!(dt, (:A, :B, :D))
        @test is_stale(branch_v)

        @test length(branch_v) == 0
        @test isempty(collect(keys(branch_v)))
        @test isempty(collect(values(branch_v)))
        @test !haskey(branch_v, (:D,))
        @test collect(branch_v) == []

        @test length(leaf_v) == 0
        @test isempty(collect(keys(leaf_v)))
        @test isempty(collect(values(leaf_v)))
        @test !haskey(leaf_v, ())
        @test collect(leaf_v) == []

        dt3 = SDTree((:Level1, :A) => 1.0, (:Level1, :B) => 2.0, (:Level2, :C) => 3.0)
        v3 = view(dt3, (:Level1,))
        empty!(v3)
        @test is_stale(v3)
        @test length(dt3) == 1
        @test !haskey(dt3, (:Level1, :A))

        dt4 = SDTree((:Single, :Leaf) => 1.0)
        l4 = view(dt4, (:Single, :Leaf))
        empty!(l4)
        @test is_stale(l4)
        @test length(dt4) == 0

        # values_view Operations on Stale/Valid Views
        t_vv = SDTree((1, 2) => "X", (1, 3) => "Y")
        br_vv = view(t_vv, (1,))
        lf_vv = view(t_vv, (1, 2))

        empty!(t_vv.viewid)
        @test values_view(br_vv) == ["X", "Y"]
        @test values_view(lf_vv) == ["X"]

        empty!(t_vv)
        @test isempty(values_view(br_vv))
        @test isempty(values_view(lf_vv))
    end

    # ==========================================================================
    # PART 2: The Shell (DictTree, DictBranch)
    # ==========================================================================

    @testset "10. DictTree Dynamic Routing, Inheritance & Constructors" begin
        dt = DictTree()

        # Dynamic Multi-Depth Insertion
        dt[(:Eng,)] = "Engineering"
        dt[(:Eng, :Sw)] = "Software"
        dt[(:Eng, :Sw, 1)] = 95.0

        @test length(dt) == 3
        @test haslayer(dt, 1)
        @test haslayer(dt, 3)
        @test !haslayer(dt, 4)

        @test dt[(:Eng,)] == "Engineering"
        @test dt[(:Eng, :Sw, 1)] == 95.0

        # Heterogeneous Key Routing (typeof(key) bug fix)
        dt_het = DictTree()
        dt_het[(:Eng, 1)] = "A"
        dt_het[("Sales", 2.0)] = "B"
        @test dt_het[("Sales", 2.0)] == "B"

        # Iterators and collection
        dt_keys = collect(keys(dt))
        @test length(dt_keys) == 3
        @test (:Eng,) in dt_keys

        # Initializing via dict/pairs
        dt2 = DictTree((1,) => "A", (1, 2) => "B")
        @test length(dt2) == 2
        @test dt2[(1, 2)] == "B"

        # DictTree Extra Constructors
        t_core = SDTree((1, 2) => "A")
        dt_kw = DictTree(t_core; label=:MyLayer)
        @test get_layer(dt_kw, :MyLayer) === t_core

        d_standard = Dict((1,) => "X", (2, 3) => "Y")
        dt_dict = DictTree(d_standard)
        @test dt_dict[(2, 3)] == "Y"

        dt_vecs = DictTree([(1,)], ["VectorVal"])
        @test dt_vecs[(1,)] == "VectorVal"

        # Flatten iterators for values and sequential pairs
        dt_iter = DictTree((:A,) => 1, (:A, :B) => 2)
        @test sort(collect(values(dt_iter))) == [1, 2]
        @test length(collect(dt_iter)) == 2

        # DictTree Exceptions
        dt_exc = DictTree()
        dt_exc[(1, 2)] = "A"
        @test_throws KeyError dt_exc[(1, 3)]
        @test_throws KeyError dt_exc[(1,)]
        @test_throws KeyError dt_exc[(1, 2, 3)]
    end

    @testset "11. DictBranch Cross-Layer Subsets & Scalar Forwarding" begin
        dt = DictTree()

        db = view(dt, (:A,))

        dt[(:A,)] = "A-Meta"
        dt[(:A, :B)] = "B-Meta"
        dt[(:A, :B, 1)] = 10.0
        dt[(:A, :C, 2)] = 20.0
        dt[(:Z,)] = "Z-Meta"

        @test length(db) == 4
        @test haskey(db, ())
        @test db[()] == "A-Meta"
        @test haskey(db, (:B,))
        @test db[(:B,)] == "B-Meta"
        @test db[(:C, 2)] == 20.0

        # DictBranch Iterator
        @test length(collect(db)) == 4
        @test Set(values(db)) == Set([10.0, 20.0, "A-Meta", "B-Meta"])

        # Pruning subsets
        prune!(dt, (:A, :B))
        @test !haskey(dt, (:A, :B))
        @test !haskey(dt, (:A, :B, 1))
        @test haskey(dt, (:A, :C, 2))
        @test haskey(dt, (:A,))

        prune!(db, (:C,))
        @test !haskey(dt, (:A, :C, 2))

        # DictBranch Deletion
        dt_del = DictTree()
        dt_del[(:A, :B, :C)] = 10
        db_del = view(dt_del, (:A,))
        delete!(db_del, (:B, :C))
        @test length(dt_del) == 0

        # Global Empty via branch view
        empty!(db)
        @test !haskey(dt, (:A,))
        @test haskey(dt, (:Z,))

        empty!(dt)
        @test length(dt) == 0

        # Scalar Forwarding & Mutation via Shell Views
        dt_scalar = DictTree()
        dt_scalar[:RootScalar] = "Value1"
        @test dt_scalar[:RootScalar] == "Value1"
        @test haskey(dt_scalar, :RootScalar)

        db_scalar = view(dt_scalar, (:RootScalar,))
        db_scalar[:SubLeaf] = "Value2"
        @test dt_scalar[(:RootScalar, :SubLeaf)] == "Value2"
        @test haskey(db_scalar, :SubLeaf)
        @test db_scalar[:SubLeaf] == "Value2"

        # Deletion & Pruning scalar wrappers
        delete!(dt_scalar, :RootScalar)
        @test !haskey(dt_scalar, :RootScalar)

        dt_prune_sc = DictTree((:A, :B) => 1)
        prune!(dt_prune_sc, :A)
        @test length(dt_prune_sc) == 0

        db_prune_sc = view(DictTree((:A, :B, :C) => 1), (:A,))
        prune!(db_prune_sc, :B)
        @test length(db_prune_sc) == 0
    end

    @testset "12. Explicit Typed Injection (add_layer! & get_layer)" begin
        dt = DictTree()

        add_layer!(dt, SDTree{Tuple{Int}, String}())

        dt[(1,)] = "Hello"
        @test dt[(1,)] == "Hello"

        @test_throws MethodError dt[(2,)] = 100.0
        @test_throws ArgumentError add_layer!(dt, SDTree{Tuple{Int}, Float64}())

        t1 = get_layer(dt, 1)
        @test t1 isa SDTree{Tuple{Int}, String}
        @test t1[(1,)] == "Hello"

        @test_throws KeyError get_layer(dt, 99)

        # Layer accessors from branch views
        db_scalar = view(dt, (1,))
        add_layer!(dt, SDTree{Tuple{Int, Int, Int}, Int}())
        dt[(1, 2, 3)] = 4
        @test get_layer(db_scalar, 3) isa AbstractSDTree
    end

    @testset "13. DictTree Labels & Topology Hooks (on_new_branch, clean_on_empty_branch)" begin
        dt = DictTree()

        # Depth 1: Department level
        add_layer!(dt, SDTree{Tuple{Symbol}, String}();
                  label=:Dept,
                  on_new_branch = x -> "Auto-Dept: $x",
                  clean_on_empty_branch = true)

        # Depth 2: Team level
        add_layer!(dt, SDTree{Tuple{Symbol, Symbol}, String}();
                  label=:Team,
                  on_new_branch = x -> "Auto-Team: $(x[1])-$(x[2])",
                  clean_on_empty_branch = true)

        @test haslayer(dt, :Dept)
        @test haslayer(dt, :Team)
        @test !haslayer(dt, :Unknown)
        @test getlabels(dt)[:Dept] == 1
        @test getlabels(dt)[:Team] == 2

        t_dept = get_layer(dt, :Dept)
        @test t_dept isa SDTree{Tuple{Symbol}, String}

        # Auto-Initialization
        dt[(:Eng, :Backend, :Alice)] = 95.0

        @test haskey(dt, (:Eng,))
        @test dt[(:Eng,)] == "Auto-Dept: Eng"
        @test haskey(dt, (:Eng, :Backend))
        @test dt[(:Eng, :Backend)] == "Auto-Team: Eng-Backend"

        # Label Accessors via DictBranch
        db = view(dt, (:Eng,))
        @test get_layer(db, :Team) isa AbstractSDTree
        @test haslayer(db, :Team)
        @test !haslayer(db, :FakeLabel)

        # Overwrite Protection
        dt[(:Sales,)] = "Main Sales Hub"
        dt[(:Sales, :Frontend, :Bob)] = 85.0

        @test dt[(:Sales,)] == "Main Sales Hub" # Preserved!
        @test dt[(:Sales, :Frontend)] == "Auto-Team: Sales-Frontend"

        # Autoclean (Upward Garbage Collection)
        dt[(:Eng, :Backend, :Charlie)] = 80.0

        # SCENARIO A: Delete Alice (No cleanup)
        delete!(dt, (:Eng, :Backend, :Alice))
        @test haskey(dt, (:Eng, :Backend))
        @test haskey(dt, (:Eng,))

        # SCENARIO B: Delete Charlie (Cascade autoclean)
        delete!(dt, (:Eng, :Backend, :Charlie))
        @test !haskey(dt, (:Eng, :Backend))
        @test !haskey(dt, (:Eng,))

        # SCENARIO C: Autoclean via prune!
        prune!(dt, (:Sales, :Frontend))

        @test !haskey(dt, (:Sales, :Frontend, :Bob))
        @test !haskey(dt, (:Sales, :Frontend))
        @test !haskey(dt, (:Sales,))

        @test length(dt) == 0
    end

    @testset "14. AbstractTrees Display Validation & Deep Topologies" begin
        # SDTree, SDBranch, SDLeaf Show Methods
        t = SDTree((1, 2) => "A")
        b = view(t, (1,))
        l = view(t, (1, 2))

        @test occursin("SDTree", sprint(show, t))
        @test occursin("SDTree", sprint(show, MIME("text/plain"), t))
        @test occursin("SDBranch", sprint(show, b))
        @test occursin("SDBranch", sprint(show, MIME("text/plain"), b))
        @test occursin("SDLeaf", sprint(show, l))
        @test occursin("SDLeaf", sprint(show, MIME("text/plain"), l))

        empty!(t)
        @test sprint(show, MIME("text/plain"), b) == "Object is stale"
        @test sprint(show, MIME("text/plain"), l) == "Object is stale"

        # DictTree
        dt = DictTree()
        dt[(:A,)] = "A-Meta"
        dt[(:A, :B)] = "B-Meta"
        dt[(:A, :B, 1)] = 10.0

        out_dt = sprint(print_tree, dt)
        @test occursin("(root)", out_dt)
        @test occursin(":A => \"A-Meta\"", out_dt)
        @test occursin(":B => \"B-Meta\"", out_dt)

        db = view(dt, (:A,))
        out_db = sprint(print_tree, StaticDictTrees.BranchAsRoot(db))
        @test occursin("() => \"A-Meta\"", out_db)
        @test occursin(":B => \"B-Meta\"", out_db)

        lf = view(dt, (:A, :B, 1))
        out_lf = sprint(print_tree, StaticDictTrees.BranchAsRoot(lf))
        @test occursin("() => 10.0", out_lf)

        # DictTree Root Metadata Printnode
        dt_root = DictTree()
        dt_root[()] = "RootVal"
        dt_root[(1,)] = "A"
        @test occursin("DictTree", sprint(show, dt_root))
        out_dt_root = sprint(show, MIME("text/plain"), dt_root)
        @test occursin("() => \"RootVal\"", out_dt_root)

        # DictBranch Missing Metadata Printnode
        dt2 = DictTree()
        dt2[(1, 2)] = "B"
        db2 = view(dt2, (1,))
        @test occursin("DictBranch", sprint(show, db2))
        out_db2 = sprint(show, MIME("text/plain"), db2)
        @test occursin("1", out_db2)
        @test occursin("(branch)", out_db2)

        # Deep Topologies
        t_flat = SDTree((1,) => "A")
        out_flat = sprint(show, MIME("text/plain"), t_flat)
        @test occursin("1 => \"A\"", out_flat)

        t_deep = SDTree((1, 2, 3) => "DeepValue")
        b_deep = view(t_deep, (1,))
        out_b_deep = sprint(show, MIME("text/plain"), b_deep)
        @test occursin("2", out_b_deep)
        @test occursin("3 => \"DeepValue\"", out_b_deep)

        dt_struct = DictTree()
        dt_struct[(1, 2, 3)] = "C"
        db_struct = view(dt_struct, (1,))
        out_db_struct = sprint(show, MIME("text/plain"), db_struct)
        @test occursin("2\n", out_db_struct)
        @test occursin("3 => \"C\"", out_db_struct)

        # Branch-as-Root Leaf Display
        t_dis = SDTree((1, 2) => "Display")
        lf_dis = view(t_dis, (1, 2))
        out_dis = sprint(print_tree, StaticDictTrees.BranchAsRoot(lf_dis))
        @test occursin("2 => \"Display\"", out_dis)
    end

    @testset "15. Root Views and Empty Prefixes" begin
        dt = DictTree()
        dt[(:A, :B, :C)] = 1
        dt[()] = "Root"

        # Taking a view of the absolute root should return the whole tree
        v = view(dt, ())
        @test length(v) == 2 # 1 for (), 1 for (:A, :B, :C)
        @test v[()] == "Root"
        @test v[(:A, :B, :C)] == 1
        @test v === dt # Empty prefix view on DictTree returns itself

        # Test SDTree view with empty tuple avoids BoundsError
        sdt = SDTree((:X, :Y) => 10)
        v_sdt = view(sdt, ())
        @test v_sdt === sdt # Empty prefix view on SDTree returns itself
    end

    @testset "16. Depth-0 Topology Hooks (Root Auto-Init & Clean)" begin
        dt = DictTree()

        # 1. Depth-0 Auto-Initialization
        add_layer!(dt, SDTree{Tuple{}, Float64}();
                  on_new_branch = key -> NaN,
                  clean_on_empty_branch = true)

        add_layer!(dt, SDTree{Tuple{Symbol}, Float64}())

        dt[:a] = 1.0 # Insert at depth 1

        # The depth-0 hook should have fired!
        @test haskey(dt, ())
        @test isnan(dt[()])

        # 2. Depth-0 Auto-Cleaning
        # If we delete the only leaf, the root `()` should clean itself up
        delete!(dt, :a)

        @test !haskey(dt, ())
        @test length(dt) == 0
    end

    @testset "17. SDBranch values_view Lifecycle & Cache Invalidation" begin
        # 1. Initialization
        dt = SDTree{Tuple{Symbol, Int}, String}()
        dt[:A, 1] = "A1"
        dt[:B, 1] = "B1"
        dt[:A, 2] = "A2"
        dt[:C, 1] = "C1"

        b_A = view(dt, (:A,))

        # 2. Initial cache build
        vv_A = values_view(b_A)
        @test length(vv_A) == 2
        @test collect(vv_A) == ["A1", "A2"]

        # 3. In-place Update (SubArray automatic reflection)
        # Since `vv_A` is a SubArray, updating the tree natively should instantly reflect
        # in the view without needing to call `values_view(b_A)` again!
        dt[:A, 1] = "A1_updated"
        @test vv_A[1] == "A1_updated"
        @test collect(values_view(b_A)) == ["A1_updated", "A2"]

        # 4. Insertion INSIDE branch (Eager push to cache)
        dt[:A, 3] = "A3"
        @test length(values_view(b_A)) == 3
        @test collect(values_view(b_A)) == ["A1_updated", "A2", "A3"]

        # 5. Insertion OUTSIDE branch (Should not corrupt the :A cache)
        dt[:D, 1] = "D1"
        @test collect(values_view(b_A)) == ["A1_updated", "A2", "A3"]

        # 6. Deletion INSIDE branch (Direct cache invalidation)
        delete!(dt, (:A, 2))
        @test length(values_view(b_A)) == 2
        @test collect(values_view(b_A)) == ["A1_updated", "A3"]

        # 7. Swap-With-Last Invalidation Test (The ultimate edge case)
        # Let's add an element to :A so it becomes the VERY LAST element in the physical array.
        dt[:A, 4] = "A4"

        # Right now, (:B, 1) is sitting somewhere in the middle of the physical array.
        # If we delete (:B, 1), the engine will SWAP the last element (:A, 4) into its place!
        # Even though we deleted something OUTSIDE the branch, an element INSIDE the branch
        # just had its physical index changed. The branch cache MUST invalidate!
        delete!(dt, (:B, 1))

        @test length(values_view(b_A)) == 3
        # If cache invalidation worked perfectly, it will rebuild and map to the new physical indices
        @test collect(values_view(b_A)) == ["A1_updated", "A3", "A4"]

        # Sanity check: ensure the optimized view perfectly matches the standard iterator
        @test collect(values_view(b_A)) == collect(values(b_A))

        # 8. Total branch prune (Stale view fallback)
        prune!(dt, (:A,))
        @test is_stale(b_A) == true
        @test length(values_view(b_A)) == 0
        @test collect(values_view(b_A)) == String[]
    end

    @testset "18. haspath edge cases and lifecycle" begin
        # 1. Initialization (Depth 3 Tree)
        dt = SDTree{Tuple{Symbol, Symbol, Symbol}, Int}()
        dt[:Fermion, :Quark, :up] = 2
        dt[:Fermion, :Quark, :down] = 4
        dt[:Fermion, :Lepton, :electron] = 1
        dt[:Boson, :Gauge, :photon] = 0

        # 2. Intermediate Node Lookups (Branches)
        @test haspath(dt, (:Fermion,)) == true
        @test haspath(dt, (:Fermion, :Quark)) == true
        @test haspath(dt, (:Boson,)) == true

        # 3. Terminal Node Lookups (Leaves - The Option B behavior!)
        @test haspath(dt, (:Fermion, :Quark, :up)) == true
        @test haspath(dt, (:Boson, :Gauge, :photon)) == true

        # 4. Invalid Lookups
        @test haspath(dt, (:Fermion, :Gauge)) == false           # Mixed up path
        @test haspath(dt, (:Quark,)) == false                    # Valid name, but wrong depth
        @test haspath(dt, (:Fermion, :Quark, :strange)) == false # Non-existent leaf

        # 5. Boundary Conditions
        @test haspath(dt, ()) == true                               # The root is ALWAYS a valid path
        @test haspath(dt, (:Fermion, :Quark, :up, :extra)) == false # Exceeds depth (M > N)

        # 6. SDBranch sub-lookups
        fermions = view(dt, (:Fermion,))
        @test haspath(fermions, ()) == true               # Root of the view itself
        @test haspath(fermions, (:Quark,)) == true        # Valid intermediate sub-path
        @test haspath(fermions, (:Gauge,)) == false       # Belongs to Boson, not Fermion
        @test haspath(fermions, (:Quark, :up)) == true    # Valid terminal sub-path (leaf!)
        @test haspath(fermions, (:Quark, :up, :x)) == false # Exceeds depth within view

        # 7. Lifecycle & Mutation (Checking internal cleanup)
        dt[:Boson, :Scalar, :higgs] = 125
        @test haspath(dt, (:Boson, :Scalar)) == true         # Path appears instantly on insert
        @test haspath(dt, (:Boson, :Scalar, :higgs)) == true # Leaf path appears

        # Delete the ONLY leaf in the :Scalar path
        delete!(dt, (:Boson, :Scalar, :higgs))

        # The `delete!` engine should completely wipe both the leaf and the empty branch metadata
        @test haspath(dt, (:Boson, :Scalar, :higgs)) == false # Leaf is gone
        @test haspath(dt, (:Boson, :Scalar)) == false         # Empty structural branch is gone!

        # But the parent :Boson branch still has :Gauge, so it must survive!
        @test haspath(dt, (:Boson,)) == true
    end
end



@testset "Serialization & Deserialization (TypedJSONExt)" begin
    using TypedJSON

    @testset "SDTree Round-Trip & Cache Rebuild" begin
        # 1. Build a complex tree
        dt = SDTree{Tuple{Symbol, Symbol, Symbol}, Int}()
        dt[:Fermion, :Quark, :up] = 2
        dt[:Fermion, :Quark, :down] = 4
        dt[:Boson, :Gauge, :photon] = 0

        # 3. Deserialize (Reconstruct)
        reconstructed = TypedJSON.roundtrip(dt)

        # 4. Verify Core Data Integrity
        @test reconstructed[:Fermion, :Quark, :up] == 2
        @test reconstructed[:Boson, :Gauge, :photon] == 0
        @test length(reconstructed.keys) == 3

        # 5. Verify Ephemeral Cache Rebuilding (The critical architectural test!)
        # If the constructor correctly rebuilt `branch_lookup`, `haspath` will work.
        @test haspath(reconstructed, (:Fermion, :Quark)) == true
        @test haspath(reconstructed, (:Boson,)) == true

        # If it correctly pre-allocated `branch_viewids`, the views will work.
        quark_view = view(reconstructed, (:Fermion, :Quark))
        @test length(quark_view) == 2
        @test collect(values_view(quark_view)) == [2, 4]
    end

    @testset "DictTree Multi-Layer Round-Trip" begin
        # 1. Build a dynamic multi-layer tree
        dt = DictTree()
        dt[:Alice] = 100                 # Depth 1
        dt[:Engineering, :Software] = 50 # Depth 2
        dt[:Engineering, :Hardware] = 30 # Depth 2

        reconstructed = TypedJSON.roundtrip(dt)

        # 4. Verify cross-layer integrity
        @test reconstructed[:Alice] == 100
        @test reconstructed[:Engineering, :Software] == 50
        @test reconstructed[:Engineering, :Hardware] == 30

        # 5. Verify layer structural methods
        @test haslayer(reconstructed, 1) == true
        @test haslayer(reconstructed, 2) == true
        @test haslayer(reconstructed, 3) == false

        # 6. Verify cross-layer branch tracking works on the deserialized object
        eng_view = view(reconstructed, (:Engineering,))
        @test length(eng_view) == 2
    end
end
