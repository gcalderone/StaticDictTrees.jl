using Test
using DataStructures
using AbstractTrees

using StaticDictTrees

@testset "StaticDictTrees & DictTree Full Suite" begin

    # ==========================================================================
    # PART 1: The Core (SDTree, SDBranch, SDLeaf)
    # ==========================================================================

    @testset "1. SDTree Constructors & Edge Cases" begin
        # Empty initialization
        t1 = SDTree{Tuple{Int, Int}, String}()
        @test isempty(t1)
        @test depth(t1) == 2
        @test length(t1) == 0

        # Pair constructor
        t2 = SDTree((1, 2) => "A", (3, 4) => "B")
        @test length(t2) == 2
        @test t2[(1, 2)] == "A"

        # Dict constructor
        d = Dict((1,) => 10, (2,) => 20)
        t3 = SDTree(d)
        @test length(t3) == 2
        @test t3[(2,)] == 20

        # Vector constructor
        keys_vec = [(1, 1), (2, 2)]
        vals_vec = [100, 200]
        t4 = SDTree(keys_vec, vals_vec)
        @test length(t4) == 2
        @test t4[(2, 2)] == 200

        # sizehint! coverage
        @test sizehint!(t4, 100) === t4

        # 0-dimensional tree (Edge case)
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

        # Depth tracking
        @test depth(dt)  == 3
        @test depth(br1) == 1
        @test depth(br2) == 2
        @test depth(lf)  == 3

        # is_leaf_level tracking
        @test !is_leaf_level(dt)
        @test !is_leaf_level(br1)
        @test is_leaf_level(br2)
        @test is_leaf_level(lf)

        # Parent traversal logic
        @test parent(dt) === nothing
        @test parent(br1) === dt
        @test parent(br2).prefix == (1,)
        @test parent(lf).prefix == (1, :server)

        # Depth-1 edge case (Tree directly holds leaves)
        dt_flat = SDTree{Tuple{Int}, Float64}()
        @test is_leaf_level(dt_flat)
        @test parent(SDLeaf(dt_flat, (1,))) === dt_flat

        # Root traversal (using === to guarantee exact memory identity)
        @test root(dt) === dt
        @test root(br1) === dt
        @test root(br2) === dt
        @test root(lf) === dt

        # Test that `root` works on views created from other views
        br_nested = view(br1, (:server,))
        @test root(br_nested) === dt
    end

    @testset "3. SDTree Base API & Chronological Order" begin
        t = SDTree{Tuple{Int, Int}, Float64}()

        t[(1, 1)] = 1.0
        t[(1, 2)] = 2.0
        @test length(t) == 2

        @test t[(1, 1)] == 1.0
        @test t[(1, 2)] == 2.0
        @test_throws KeyError t[(2, 2)]
        @test_throws ArgumentError t[(1,)] # Incomplete key error fallback

        @test haskey(t, (1, 1))
        @test !haskey(t, (2, 2))
        @test !haskey(t, (1,)) # False for partial keys

        # Update an existing key
        t[(1, 1)] = 5.0
        @test length(t) == 2 # Length should NOT increase on update
        @test t[(1, 1)] == 5.0

        # Values View Chronological Order Validation
        t[(2, 1)] = 3.0
        v_view = values_view(t)
        @test v_view == [5.0, 2.0, 3.0]
    end

    @testset "4. Core Views (SDBranch & SDLeaf)" begin
        t = SDTree{Tuple{Int, Int, Int}, String}()
        t[(1, 1, 1)] = "A"
        t[(1, 1, 2)] = "B"
        t[(1, 2, 1)] = "C"
        t[(2, 1, 1)] = "D"

        # SDBranch View creation
        v1 = view(t, (1,))
        @test v1 isa SDBranch
        @test length(v1) == 3
        @test haskey(v1, (1, 1))
        @test v1[(1, 1)] == "A"

        # Nested SDBranch view
        v11 = view(v1, (1,))
        @test v11 isa SDBranch
        @test length(v11) == 2
        @test v11[(2,)] == "B"

        # SDLeaf View creation
        l = view(t, (1, 1, 1))
        @test l isa SDLeaf
        @test length(l) == 1
        @test l[()] == "A"

        # Mutating via views updates the physical dictionary
        v11[(2,)] = "B_mod"
        @test t[(1, 1, 2)] == "B_mod"

        l[()] = "A_mod"
        @test t[(1, 1, 1)] == "A_mod"
        @test v1[(1, 1)] == "A_mod"

        # View bounds & missing branch safety checking
        @test_throws ArgumentError view(t, (1, 1, 1, 99)) # Key too long
        @test_throws KeyError view(t, (99,))
        @test_throws KeyError view(v1, (99,))
    end

    @testset "5. Iteration and Collection" begin
        dt = SDTree((1, :a) => 10, (1, :b) => 20, (2, :c) => 30)

        # Tree iteration
        @test length(collect(dt)) == 3
        @test ((1, :a) => 10) in collect(dt)

        # Lazy values iterator (Ensuring values() avoids allocating standard arrays)
        lazy_vals = values(dt)
        @test !(lazy_vals isa AbstractArray)
        @test collect(lazy_vals) == [10, 20, 30]

        # Branch iteration (Keys should be relative suffixes)
        br = view(dt, (1,))
        @test is_leaf_level(br)
        @test length(collect(br)) == 2
        @test ((:a,) => 10) in collect(br)
        @test collect(values(br)) == [10, 20]

        # Leaf iteration
        lf = view(dt, (2, :c))
        @test length(collect(lf)) == 1
        @test collect(lf)[1] == (() => 30)
        @test collect(values(lf)) == [30]
    end

    @testset "6. Core Destructive Operations & Swap-with-Last" begin
        t = SDTree{Tuple{Int, Int}, Int}()
        t[(1, 1)] = 10
        t[(1, 2)] = 20
        t[(2, 1)] = 30
        t[(2, 2)] = 40

        # delete! on Root (Verifying O(1) swap logic: (2,2) moves into (1,1)'s spot)
        delete!(t, (1, 1))
        @test !haskey(t, (1, 1))
        @test length(t) == 3
        @test values_view(t) == [20, 30, 40] # Chronological cache successfully invalidated and rebuilt

        @test delete!(t, (99, 99)) === t

        # delete! via a branch view
        br = view(t, (2,))
        delete!(br, (1,))
        @test length(t) == 2
        @test !haskey(t, (2, 1))
        @test haskey(t, (2, 2))

        # empty! on SDBranch (Cleans all structural keys under the prefix)
        v = view(t, (1,))
        empty!(v)
        @test !haskey(t, (1, 2))
        @test length(t) == 1

        # empty! on Root
        empty!(t)
        @test length(t) == 0
        @test isempty(t.values)
    end

    @testset "7. Core Pruning (SDTree & SDBranch)" begin
        t = SDTree{Tuple{Int, Int, Int}, String}()
        t[(1, 1, 1)] = "A"
        t[(1, 1, 2)] = "B"
        t[(1, 2, 1)] = "C"
        t[(2, 1, 1)] = "D"

        # ----------------------------------------------------
        # 1. Pruning SDTree directly
        # ----------------------------------------------------

        # Pruning a full key (behaves exactly like delete!)
        prune!(t, (2, 1, 1))
        @test !haskey(t, (2, 1, 1))
        @test length(t) == 3

        # Pruning a partial key (cascades deletion to all matching leaves)
        prune!(t, (1, 1))
        @test !haskey(t, (1, 1, 1))
        @test !haskey(t, (1, 1, 2))
        @test haskey(t, (1, 2, 1))
        @test length(t) == 1

        # Pruning an invalid/too-long key (safe no-op bounds check)
        @test_throws ArgumentError prune!(t, (1, 2, 1, 99))
        @test length(t) == 1

        # ----------------------------------------------------
        # 2. Pruning via SDBranch
        # ----------------------------------------------------
        t2 = SDTree{Tuple{Int, Int, Int}, String}()
        t2[(1, 1, 1)] = "A"
        t2[(1, 1, 2)] = "B"
        t2[(1, 2, 1)] = "C"
        t2[(1, 2, 2)] = "D"
        t2[(2, 1, 1)] = "E"

        br = view(t2, (1,))
        @test length(br) == 4

        # Prune a partial relative key
        prune!(br, (1,))
        @test !haskey(t2, (1, 1, 1))
        @test !haskey(t2, (1, 1, 2))
        @test length(br) == 2
        @test haskey(br, (2, 1))
        @test haskey(br, (2, 2))

        # Prune a full relative key (behaves exactly like delete! on the view)
        prune!(br, (2, 1))
        @test !haskey(t2, (1, 2, 1))
        @test length(br) == 1
        @test haskey(t2, (1, 2, 2))

        # Prune an invalid/too-long relative key (safe no-op bounds check)
        @test_throws ArgumentError prune!(br, (2, 2, 99))
        @test length(br) == 1
    end

    @testset "8. Stale Views & Safe Fallbacks" begin
        # Setup a fresh tree
        dt = SDTree((:A, :B, :C) => 1.0,
                    (:A, :B, :D) => 2.0,
                    (:X, :Y, :Z) => 3.0)

        branch_v = view(dt, (:A, :B))
        leaf_v   = view(dt, (:A, :B, :C))

        @test !is_stale(branch_v)
        @test !is_stale(leaf_v)
        @test length(branch_v) == 2
        @test length(leaf_v) == 1

        # Deleting an unrelated leaf shouldn't affect our views
        delete!(dt, (:X, :Y, :Z))
        @test !is_stale(branch_v)
        @test !is_stale(leaf_v)

        # Delete the leaf of our leaf view
        delete!(dt, (:A, :B, :C))
        @test is_stale(leaf_v)

        # Branch is still valid (has :D left)
        @test !is_stale(branch_v)

        # Delete the last leaf of the branch
        delete!(dt, (:A, :B, :D))
        @test is_stale(branch_v) # No leaves left, branch lookup explicitly drops it

        # Check safe fallback behaviors for the stale SDBranch
        @test length(branch_v) == 0
        @test isempty(collect(keys(branch_v)))
        @test isempty(collect(values(branch_v)))
        @test !haskey(branch_v, (:D,))
        @test collect(branch_v) == []

        # Check safe fallback behaviors for the stale SDLeaf
        @test length(leaf_v) == 0
        @test isempty(collect(keys(leaf_v)))
        @test isempty(collect(values(leaf_v)))
        @test !haskey(leaf_v, ())
        @test collect(leaf_v) == []

        # Test empty! on a branch view making itself stale
        dt3 = SDTree((:Level1, :A) => 1.0, (:Level1, :B) => 2.0, (:Level2, :C) => 3.0)
        v3 = view(dt3, (:Level1,))
        empty!(v3)
        @test is_stale(v3)
        @test length(dt3) == 1 # Only (:Level2, :C) should remain
        @test !haskey(dt3, (:Level1, :A))

        # Test empty! on a leaf view
        dt4 = SDTree((:Single, :Leaf) => 1.0)
        l4 = view(dt4, (:Single, :Leaf))
        empty!(l4)
        @test is_stale(l4)
        @test length(dt4) == 0
    end

    # ==========================================================================
    # PART 2: The Shell (DictTree, DictBranch)
    # ==========================================================================

    @testset "9. DictTree Dynamic Routing & Inheritance" begin
        dt = DictTree()

        # Dynamic Multi-Depth Heterogeneous Insertion
        dt[(:Eng,)] = "Engineering"         # Depth 1 -> String
        dt[(:Eng, :Sw)] = "Software"        # Depth 2 -> String
        dt[(:Eng, :Sw, 1)] = 95.0           # Depth 3 -> Float64

        @test length(dt) == 3
        @test hasdepth(dt, 1)
        @test hasdepth(dt, 3)
        @test !hasdepth(dt, 4)

        @test dt[(:Eng,)] == "Engineering"
        @test dt[(:Eng, :Sw, 1)] == 95.0

        # AbstractDict Interface (Flattened iterators stitching layers together)
        dt_keys = collect(keys(dt))
        @test length(dt_keys) == 3
        @test (:Eng,) in dt_keys
        @test (:Eng, :Sw) in dt_keys
        @test (:Eng, :Sw, 1) in dt_keys

        # Initializing via dict/pairs
        dt2 = DictTree((1,) => "A", (1, 2) => "B")
        @test length(dt2) == 2
        @test dt2[(1, 2)] == "B"
    end

    @testset "10. DictBranch Cross-Layer Subsets & Pruning" begin
        dt = DictTree()

        # Early creation of a DictBranch which span multiple layers, including the exact prefix match
        db = view(dt, (:A,))

        dt[(:A,)] = "A-Meta"
        dt[(:A, :B)] = "B-Meta"
        dt[(:A, :B, 1)] = 10.0
        dt[(:A, :C, 2)] = 20.0
        dt[(:Z,)] = "Z-Meta"

        # Length is 4 representing relative keys: (), (:B,), (:B, 1), and (:C, 2)
        @test length(db) == 4

        # Accessing the exact match metadata via the empty tuple
        @test haskey(db, ())
        @test db[()] == "A-Meta"

        # Accessing deeper layers via relative suffixes
        @test haskey(db, (:B,))
        @test db[(:B,)] == "B-Meta"
        @test db[(:C, 2)] == 20.0

        # Pruning cascades down to all applicable sub-layers
        prune!(dt, (:A, :B))
        @test !haskey(dt, (:A, :B))
        @test !haskey(dt, (:A, :B, 1))
        @test haskey(dt, (:A, :C, 2))  # Sibling unaffected
        @test haskey(dt, (:A,))        # Parent unaffected

        # Prune via branch view natively
        prune!(db, (:C,))
        @test !haskey(dt, (:A, :C, 2))

        # Global Empty via branch view
        empty!(db)
        @test !haskey(dt, (:A,)) # Root of the branch should be emptied too
        @test haskey(dt, (:Z,))  # Unrelated data remains entirely intact

        # Global Empty
        empty!(dt)
        @test length(dt) == 0
    end

    @testset "11. Explicit Typed Injection (add_tree! & get_tree)" begin
        dt = DictTree()

        # Manually lock Depth 1 to String
        add_tree!(dt, SDTree{Tuple{Int}, String}())

        dt[(1,)] = "Hello"
        @test dt[(1,)] == "Hello"

        # Enforce type safety
        @test_throws MethodError dt[(2,)] = 100.0

        # Prevent duplicate tree injections on the same depth
        @test_throws ArgumentError add_tree!(dt, SDTree{Tuple{Int}, Float64}())

        # Retrieve direct pointer to the underlying tree layer
        t1 = get_tree(dt, 1)
        @test t1 isa SDTree{Tuple{Int}, String}
        @test t1[(1,)] == "Hello"

        @test_throws KeyError get_tree(dt, 99)
    end

    @testset "12. DictTree Labels & Auto-Initialization" begin
        dt = DictTree()

        # Setup trees with labels and initializers
        # Depth 1: Department level
        add_tree!(dt, SDTree{Tuple{Symbol}, String}();
                  label=:Dept,
                  initializer= x -> "Default Dept: $x") # x will be unwrapped from (:Eng,) to :Eng

        # Depth 2: Team level
        add_tree!(dt, SDTree{Tuple{Symbol, Symbol}, String}();
                  label=:Team,
                  initializer= x -> "Default Team for $(x[1])") # x remains a tuple e.g. (:Eng, :Backend)

        # Test Label Accessors (hasdepth & get_tree)
        @test hasdepth(dt, :Dept)
        @test hasdepth(dt, :Team)
        @test !hasdepth(dt, :Unknown)

        t_dept = get_tree(dt, :Dept)
        @test t_dept isa SDTree{Tuple{Symbol}, String}

        # Test Auto-Initialization (Triggered by Depth 3 insertion)
        dt[(:Eng, :Backend, :Alice)] = 95000.0

        # Check that Depth 1 was auto-populated (and 1-tuple correctly unwrapped)
        @test haskey(dt, (:Eng,))
        @test dt[(:Eng,)] == "Default Dept: Eng"

        # Check that Depth 2 was auto-populated
        @test haskey(dt, (:Eng, :Backend))
        @test dt[(:Eng, :Backend)] == "Default Team for Eng"

        # Test Label Accessors via DictBranch
        db = view(dt, (:Eng,))
        @test get_tree(db, :Team) isa AbstractSDTree # Should point to the Depth 2 branch

        # Test Overwrite Protection
        # Manually insert a depth 1 value first
        dt[(:Sales,)] = "Main Sales Hub"

        # Insert a depth 3 value to trigger initializers again
        dt[(:Sales, :Frontend, :Bob)] = 85000.0

        # The Depth 2 initializer should fire normally
        @test dt[(:Sales, :Frontend)] == "Default Team for Sales"

        # BUT the Depth 1 initializer MUST NOT overwrite our manual assignment
        @test dt[(:Sales,)] == "Main Sales Hub"
    end

    @testset "13. DictTree Shell Hooks: Initializers, Transformers, Autoclean" begin
        # 1. Transformers (Validation and Modification)
        dt_val = DictTree()

        # Add a depth 1 tree that rounds positive values and rejects negative ones
        add_tree!(dt_val, SDTree{Tuple{Symbol}, Float64}();
                  label=:Dept,
                  transformer = (t, k, v) -> v > 0.0 ? round(v; digits=1) : throw(ArgumentError("Value must be positive")))

        dt_val[(:Sales,)] = 100.56 # Valid, should be rounded
        @test dt_val[(:Sales,)] == 100.6

        # Invalid insertion should throw our custom ArgumentError and NOT insert
        @test_throws ArgumentError dt_val[(:Eng,)] = -50.0
        @test !haskey(dt_val, (:Eng,))


        # 2. Initializers & Overwrite Protection
        dt = DictTree()

        # Depth 1: Department level (testing 1-tuple unwrapping)
        add_tree!(dt, SDTree{Tuple{Symbol}, String}();
                  label=:Dept,
                  initializer = x -> "Auto-Dept: $x",
                  autoclean = true)

        # Depth 2: Team level (testing raw tuple handling)
        add_tree!(dt, SDTree{Tuple{Symbol, Symbol}, String}();
                  label=:Team,
                  initializer = x -> "Auto-Team: $(x[1])-$(x[2])",
                  autoclean = true)

        # Insert at depth 3 to trigger initializers downward
        dt[(:Eng, :Backend, :Alice)] = 95.0

        # Check auto-population
        @test haskey(dt, (:Eng,))
        @test dt[(:Eng,)] == "Auto-Dept: Eng"
        @test haskey(dt, (:Eng, :Backend))
        @test dt[(:Eng, :Backend)] == "Auto-Team: Eng-Backend"

        # Overwrite protection: Manual assignment shouldn't be overwritten
        dt[(:Sales,)] = "Main Sales Hub"
        dt[(:Sales, :Frontend, :Bob)] = 85.0

        @test dt[(:Sales,)] == "Main Sales Hub" # Preserved!
        @test dt[(:Sales, :Frontend)] == "Auto-Team: Sales-Frontend" # Auto-initialized

        # 3. Autoclean (Upward Garbage Collection)
        # Let's add a second employee to Eng -> Backend
        dt[(:Eng, :Backend, :Charlie)] = 80.0

        # SCENARIO A: Delete Alice.
        # Eng -> Backend still has Charlie, so NO cleanup should happen.
        delete!(dt, (:Eng, :Backend, :Alice))
        @test haskey(dt, (:Eng, :Backend))
        @test haskey(dt, (:Eng,))

        # SCENARIO B: Delete Charlie.
        # Now Eng -> Backend is empty. It should autoclean!
        # Because Eng -> Backend is gone, Eng is ALSO empty. It should cascade!
        delete!(dt, (:Eng, :Backend, :Charlie))
        @test !haskey(dt, (:Eng, :Backend))
        @test !haskey(dt, (:Eng,))

        # SCENARIO C: Autoclean via prune!
        # We currently still have: (:Sales,) -> (:Sales, :Frontend) -> (:Sales, :Frontend, :Bob)
        # Let's prune the Sales Frontend team directly.
        prune!(dt, (:Sales, :Frontend))

        @test !haskey(dt, (:Sales, :Frontend, :Bob)) # Leaf pruned
        @test !haskey(dt, (:Sales, :Frontend))       # Team pruned
        @test !haskey(dt, (:Sales,))                 # Dept auto-cleaned!

        # The entire tree should now be perfectly empty
        @test length(dt) == 0
    end

    @testset "14. AbstractTrees Display Validation" begin
        dt = DictTree()
        dt[(:A,)] = "A-Meta"
        dt[(:A, :B)] = "B-Meta"
        dt[(:A, :B, 1)] = 10.0

        # Root Shell Display verification
        out_dt = sprint(print_tree, dt)
        @test occursin("(root)", out_dt)
        @test occursin(":A => \"A-Meta\"", out_dt)
        @test occursin(":B => \"B-Meta\"", out_dt)

        # Branch Shell Display (Checking the () wrapper interceptor output)
        db = view(dt, (:A,))
        out_db = sprint(print_tree, StaticDictTrees.BranchAsRoot(db))
        @test occursin("() => \"A-Meta\"", out_db)
        @test occursin(":B => \"B-Meta\"", out_db)

        # Leaf Shell Display (Checking the 0D interceptor output)
        lf = view(dt, (:A, :B, 1))
        out_lf = sprint(print_tree, StaticDictTrees.BranchAsRoot(lf))
        @test occursin("() => 10.0", out_lf)
    end

    @testset "15. Corner Cases & Missing API Coverage" begin
        # 1. Heterogeneous Key Routing (The typeof(key) bug fix)
        dt_het = DictTree()
        dt_het[(:Eng, 1)] = "A"       # Tuple{Symbol, Int}
        dt_het[("Sales", 2.0)] = "B"  # Tuple{String, Float64} - Should NOT throw MethodError!
        @test dt_het[("Sales", 2.0)] == "B"

        # 2. DictBranch Deletion
        dt_del = DictTree()
        dt_del[(:A, :B, :C)] = 10
        db_del = view(dt_del, (:A,))
        delete!(db_del, (:B, :C))
        @test length(dt_del) == 0

        # 3. hasdepth via Label on DictBranch
        dt_lbl = DictTree()
        add_tree!(dt_lbl, SDTree{Tuple{Symbol, Symbol}, Any}(); label=:Team)
        dt_lbl[(:Eng, :Backend)] = 1
        db_lbl = view(dt_lbl, (:Eng,))

        @test hasdepth(db_lbl, :Team)
        @test !hasdepth(db_lbl, :FakeLabel)
    end

    @testset "16. DictTree Exceptions & Missing Coverage" begin
        # Hit the KeyError branch in getindex (DictTrees.jl Line 75)
        dt = DictTree()
        dt[(1, 2)] = "A"
        @test_throws KeyError dt[(1, 3)]       # Depth exists, key doesn't
        @test_throws KeyError dt[(1,)]         # Different depth
        @test_throws KeyError dt[(1, 2, 3)]    # Depth doesn't exist at all
    end

    @testset "17. Show Methods & AbstractTrees Edge Cases" begin
        # 1. SDTree, SDBranch, SDLeaf Show Methods
        t = SDTree((1, 2) => "A")
        b = view(t, (1,))
        l = view(t, (1, 2))

        @test occursin("SDTree", sprint(show, t))
        @test occursin("SDTree", sprint(show, MIME("text/plain"), t))

        @test occursin("SDBranch", sprint(show, b))
        @test occursin("SDBranch", sprint(show, MIME("text/plain"), b))

        @test occursin("SDLeaf", sprint(show, l))
        @test occursin("SDLeaf", sprint(show, MIME("text/plain"), l))

        # Stale views text/plain fallback
        empty!(t)
        @test sprint(show, MIME("text/plain"), b) == "Object is stale"
        @test sprint(show, MIME("text/plain"), l) == "Object is stale"

        # 2. DictTree Root Metadata Printnode (abstracttrees.jl Line 92)
        dt = DictTree()
        dt[()] = "RootVal"
        dt[(1,)] = "A"

        @test occursin("DictTree", sprint(show, dt))
        out_dt = sprint(show, MIME("text/plain"), dt)
        @test occursin("() => \"RootVal\"", out_dt)

        # 3. DictBranch Missing Metadata Printnode (abstracttrees.jl Lines 102 & 110)
        dt2 = DictTree()
        dt2[(1, 2)] = "B"
        db2 = view(dt2, (1,)) # The prefix (1,) exists structurally, but has no metadata!

        @test occursin("DictBranch", sprint(show, db2))
        out_db2 = sprint(show, MIME("text/plain"), db2)

        @test occursin("1", out_db2)       # Hits Line 102
        @test occursin("(branch)", out_db2) # Hits Line 110
    end

    @testset "18. AbstractTrees Deep Topologies" begin
        # 1. Hit leaf-level SDTree children (abstracttrees.jl Line 17)
        t_flat = SDTree((1,) => "A")
        out_flat = sprint(show, MIME("text/plain"), t_flat)
        @test occursin("1 => \"A\"", out_flat)

        # 2. Hit non-leaf-level SDBranch children (abstracttrees.jl Lines 28-30)
        t_deep = SDTree((1, 2, 3) => "DeepValue")
        b_deep = view(t_deep, (1,)) # Branch is at depth 1, leaves are at depth 3
        out_b_deep = sprint(show, MIME("text/plain"), b_deep)
        @test occursin("2", out_b_deep)
        @test occursin("3 => \"DeepValue\"", out_b_deep)

        # 3. Hit DictBranch child without metadata (abstracttrees.jl Line 102)
        dt_struct = DictTree()
        dt_struct[(1, 2, 3)] = "C"
        # Prefix (1,) exists, but its child (1, 2) is purely structural with no metadata
        db_struct = view(dt_struct, (1,))
        out_db_struct = sprint(show, MIME("text/plain"), db_struct)
        @test occursin("2\n", out_db_struct) # Tests that '2' prints without a value attached
        @test occursin("3 => \"C\"", out_db_struct)
    end

    @testset "19. LocalCoverage Absolute Completion Patch" begin
        # ==========================================
        # 1. DictTree Extra Constructors & Iteration
        # ==========================================
        t_core = SDTree((1, 2) => "A")
        dt_kw = DictTree(t_core; label=:MyLayer)
        @test get_tree(dt_kw, :MyLayer) === t_core

        d_standard = Dict((1,) => "X", (2, 3) => "Y")
        dt_dict = DictTree(d_standard)
        @test dt_dict[(2, 3)] == "Y"

        dt_vecs = DictTree([(1,)], ["VectorVal"])
        @test dt_vecs[(1,)] == "VectorVal"

        # Check flatten iterators for values and sequential pairs
        dt_iter = DictTree((:A,) => 1, (:A, :B) => 2)
        @test sort(collect(values(dt_iter))) == [1, 2]
        @test length(collect(dt_iter)) == 2

        db_iter = view(dt_iter, (:A,))
        @test sort(collect(values(db_iter))) == [1, 2]
        @test sort(collect(keys(db_iter))) == [(), (:B,)]
        @test length(collect(db_iter)) == 2

        # ==========================================
        # 2. Scalar Forwarding & Mutation via Shell Views
        # ==========================================
        dt_scalar = DictTree()
        dt_scalar[:RootScalar] = "Value1"  # Triggers fallback to (:RootScalar,)
        @test dt_scalar[:RootScalar] == "Value1"
        @test haskey(dt_scalar, :RootScalar)

        db_scalar = view(dt_scalar, (:RootScalar,))
        db_scalar[:SubLeaf] = "Value2"      # Mutating DictBranch via scalar
        @test dt_scalar[(:RootScalar, :SubLeaf)] == "Value2"
        @test haskey(db_scalar, :SubLeaf)
        @test db_scalar[:SubLeaf] == "Value2"

        # Layer accessors from branch views
        add_tree!(dt_scalar, SDTree{Tuple{Symbol, Symbol, Symbol}, Int}())
        @test get_tree(dt_scalar, 3) isa AbstractSDTree

        # Deletion & Pruning scalar wrappers
        delete!(dt_scalar, :RootScalar)
        @test !haskey(dt_scalar, :RootScalar)

        dt_prune_sc = DictTree((:A, :B) => 1)
        prune!(dt_prune_sc, :A)
        @test length(dt_prune_sc) == 0

        db_prune_sc = view(DictTree((:A, :B, :C) => 1), (:A,))
        prune!(db_prune_sc, :B)
        @test length(db_prune_sc) == 0

        # ==========================================
        # 3. StaticDictTrees Type Boundaries & Views
        # ==========================================
        sdt = SDTree{Tuple{Symbol, Int}, String}()
        sdt[:A, 1] = "Found"

        # Type mismatches should trigger safe ArgumentErrors
        @test_throws ArgumentError sdt[:A, "WrongType"] = "Fail"
        @test_throws ArgumentError sdt[:A, "WrongType"]
        @test_throws ArgumentError delete!(sdt, (:A, "WrongType"))
        @test !haskey(sdt, (:A, "WrongType"))

        # Scalar forwarding on SDTree
        sdt_flat = SDTree{Tuple{Symbol}, Int}()
        sdt_flat[:ScalarKey] = 42
        @test sdt_flat[:ScalarKey] == 42
        @test haskey(sdt_flat, :ScalarKey)
        @test sdt_flat[:ScalarKey] == 42
        delete!(sdt_flat, :ScalarKey)
        prune!(sdt_flat, :ScalarKey)

        # SDBranch View mutations and nested constructors
        sdt_deep = SDTree((:A, :B, :C) => 100)
        br_deep = view(sdt_deep, (:A,))

        @test_throws ArgumentError br_deep[:B, "WrongType"] = 200
        @test_throws ArgumentError br_deep[:B, "WrongType"]
        @test_throws ArgumentError delete!(br_deep, (:B, "WrongType"))
        @test !haskey(br_deep, (:B, "WrongType"))

        br_nested = SDBranch(br_deep, (:B,)) # Hit constructor signature
        @test br_nested[(:C,)] == 100
        br_nested[:C] = 150
        @test sdt_deep[(:A, :B, :C)] == 150
        delete!(br_nested, :C)
        prune!(br_nested, :C)

        # SDLeaf constructor with offset suffix
        sdt_lf = SDTree((:A, :B) => 1)
        br_lf = view(sdt_lf, (:A,))
        lf_obj = SDLeaf(br_lf, (:B,))
        @test lf_obj[()] == 1
        delete!(lf_obj, ())

        # Edge cases for properties
        @test is_leaf_level(lf_obj)
        @test !is_stale(sdt_deep)

        # ==========================================
        # 4. values_view Operations on Views
        # ==========================================
        t_vv = SDTree((1, 2) => "X", (1, 3) => "Y")
        br_vv = view(t_vv, (1,))
        lf_vv = view(t_vv, (1, 2))

        # Re-trigger internal viewid rebuild code blocks
        empty!(t_vv.viewid)
        @test values_view(br_vv) == ["X", "Y"]
        @test values_view(lf_vv) == ["X"]

        # Validate stale view arrays safely drop down to empty elements
        empty!(t_vv)
        @test isempty(values_view(br_vv))
        @test isempty(values_view(lf_vv))

        # ==========================================
        # 5. AbstractTrees Branch-as-Root Leaf Display
        # ==========================================
        t_dis = SDTree((1, 2) => "Display")
        lf_dis = view(t_dis, (1, 2))
        out_dis = sprint(print_tree, StaticDictTrees.BranchAsRoot(lf_dis))
        @test occursin("2 => \"Display\"", out_dis)
    end
end
