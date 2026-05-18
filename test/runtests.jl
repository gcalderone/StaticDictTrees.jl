using Test
using StaticDictTrees
using AbstractTrees

@testset "StaticDictTrees.jl" begin

    @testset "Constructors and Basic Dict API" begin
        # Empty initialization
        dt = SDTree{Tuple{Int, Symbol, String}, Float64}()
        @test isempty(dt)
        @test length(dt) == 0

        # Insertion and getindex
        dt[1, :server, "latency"] = 12.5
        dt[(1, :server, "uptime")] = 99.9
        dt[2, :local, "cache"] = 2.1

        @test length(dt) == 3
        @test haskey(dt, (1, :server, "latency"))
        @test !haskey(dt, (3, :unknown, "test"))
        @test dt[1, :server, "latency"] == 12.5

        # Pair/Dict constructors
        dt2 = SDTree((1, :a) => 10, (2, :b) => 20)
        @test length(dt2) == 2
        @test dt2[1, :a] == 10

        dt3 = SDTree(Dict((1, :a) => 10, (2, :b) => 20))
        @test length(dt3) == 2
        @test dt3[2, :b] == 20

        # empty!
        empty!(dt2)
        @test length(dt2) == 0
        @test isempty(dt2.keys) && isempty(dt2.values)
    end

    @testset "Tree Properties (depth, is_leaf_level, parent)" begin
        dt = SDTree{Tuple{Int, Symbol, String}, Float64}()
        dt[1, :server, "latency"] = 12.5

        br1 = SDBranch(dt, (1,))
        br2 = SDBranch(dt, (1, :server))
        lf  = SDLeaf(dt, (1, :server, "latency"))

        # Depth
        @test depth(dt)  == 3
        @test depth(br1) == 1
        @test depth(br2) == 2
        @test depth(lf)  == 3

        # is_leaf_level
        @test !is_leaf_level(dt)
        @test !is_leaf_level(br1)
        @test is_leaf_level(br2)
        @test is_leaf_level(lf)

        # parent traversal
        @test parent(dt) === nothing
        @test parent(br1) === dt
        @test parent(br2).prefix == (1,)
        @test parent(lf).prefix == (1, :server)

        # Depth-1 edge case (Tree directly holds leaves)
        dt_flat = SDTree{Tuple{Int}, Float64}()
        @test is_leaf_level(dt_flat)
        @test parent(SDLeaf(dt_flat, (1,))) === dt_flat
    end

    @testset "View Interface" begin
        dt = SDTree{Tuple{Int, Symbol, String}, Float64}()
        dt[1, :server, "latency"] = 12.5

        # view from Tree
        v1 = view(dt, 1) # Auto-tuple fallback
        @test v1 isa SDBranch
        @test depth(v1) == 1

        # view from Branch
        v2 = view(v1, :server)
        @test v2 isa SDBranch
        @test depth(v2) == 2

        # View to Leaf
        lf1 = view(v2, "latency")
        @test lf1 isa SDLeaf
        @test lf1.key == (1, :server, "latency")

        lf2 = view(dt, (1, :server, "latency"))
        @test lf2 isa SDLeaf

        # View bounds checking
        @test_throws ArgumentError view(dt, (1, :server, "latency", "extra"))
        @test_throws ArgumentError view(v1, (:server, "latency", "extra"))

        # Mutation via views updates the underlying flat array
        v2["latency"] = 99.0
        @test dt[1, :server, "latency"] == 99.0

        lf2[(1, :server, "latency")] = 42.0
        @test dt[1, :server, "latency"] == 42.0
    end

    @testset "Iteration and Collection" begin
        dt = SDTree((1, :a) => 10, (1, :b) => 20, (2, :c) => 30)

        # Tree iteration
        @test length(collect(dt)) == 3
        @test ((1, :a) => 10) in collect(dt)

        # Branch iteration
        br = view(dt, 1)
        @test length(collect(br)) == 2
        @test ((:a,) => 10) in collect(br)

        # Leaf iteration
        lf = view(dt, (2, :c))
        @test length(collect(lf)) == 1
        @test collect(lf)[1] == ((2, :c) => 30)
    end

    @testset "keys by level: SDTree and SDBranch" begin
        # Setup a smaller, representative version of the Standard Model tree
        dt = SDTree(
            (:Fermion, :Quark, :up)       => 2.2,
            (:Fermion, :Quark, :down)     => 4.7,
            (:Fermion, :Lepton, :electron)=> 0.51,
            (:Boson, :Gauge, :photon)     => 0.0,
            (:Boson, :Scalar, :higgs)     => 125100.0
        )

        @testset "Root SDTree (Depth = 3)" begin
            # Level 1: Base Categories
            lvl1 = keys(dt, 1)
            @test Set(lvl1) == Set([(:Fermion,), (:Boson,)])

            # Level 2: Sub-categories
            lvl2 = keys(dt, 2)
            @test Set(lvl2) == Set([
                (:Fermion, :Quark),
                (:Fermion, :Lepton),
                (:Boson, :Gauge),
                (:Boson, :Scalar)
            ])

            # Level 3: Full Leaves
            lvl3 = keys(dt, 3)
            @test length(lvl3) == 5
            @test (:Fermion, :Quark, :up) in lvl3

            # Out of Bounds
            @test_throws ArgumentError keys(dt, 0)
            @test_throws ArgumentError keys(dt, 4)
        end

        @testset "Mid-level SDBranch (Depth = 2 remaining)" begin
            fermions = view(dt, (:Fermion,))

            # Level 1: Sub-categories relative to :Fermion
            lvl1 = keys(fermions, 1)
            @test Set(lvl1) == Set([(:Quark,), (:Lepton,)])

            # Level 2: Full valid suffixes for :Fermion
            lvl2 = keys(fermions, 2)
            @test Set(lvl2) == Set([
                (:Quark, :up),
                (:Quark, :down),
                (:Lepton, :electron)
            ])

            # Out of Bounds
            @test_throws ArgumentError keys(fermions, 0)
            @test_throws ArgumentError keys(fermions, 3)
        end

        @testset "Deep SDBranch (Depth = 1 remaining)" begin
            quarks = view(dt, (:Fermion, :Quark))

            # Level 1: Full valid suffixes for :Quark
            lvl1 = keys(quarks, 1)
            @test Set(lvl1) == Set([(:up,), (:down,)])

            # Out of Bounds (Branch only has 1 level left!)
            @test_throws ArgumentError keys(quarks, 0)
            @test_throws ArgumentError keys(quarks, 2)
        end
    end

    @testset "Deletion and Pruning" begin
        dt = SDTree{Tuple{Int, Symbol}, Float64}()
        dt[1, :a] = 10.0
        dt[1, :b] = 20.0
        dt[2, :c] = 30.0

        # delete!
        delete!(dt, (1, :a))
        @test length(dt) == 2
        @test !haskey(dt, (1, :a))
        @test dt[1, :b] == 20.0 # Ensure indices shifted correctly!

        # prune!
        dt[3, :x] = 100.0
        dt[3, :y] = 200.0

        prune!(dt, (3,))
        @test length(dt) == 2
        @test !haskey(dt, (3, :x))
        @test !haskey(dt, (3, :y))

        # Prune via branch
        dt[4, :m] = 40.0
        dt[4, :n] = 50.0
        br = view(dt, 4)
        @test is_leaf_level(br)
        prune!(br, (:m,)) # Prunes at the leaf level
        @test !haskey(dt, (4, :m))
        @test haskey(dt, (4, :n))
    end

    @testset "Stale Views" begin
        # Setup a fresh tree
        dt = SDTree((:A, :B, :C) => 1.0,
                    (:A, :B, :D) => 2.0,
                    (:X, :Y, :Z) => 3.0)

        # Take views
        branch_v = view(dt, (:A, :B))
        leaf_v   = view(dt, (:A, :B, :C))

        # Initial State
        @test !is_stale(branch_v)
        @test !is_stale(leaf_v)
        @test length(branch_v) == 2
        @test length(leaf_v) == 1

        # Pruning an unrelated branch shouldn't affect our views
        prune!(dt, (:X,))
        @test !is_stale(branch_v)
        @test !is_stale(leaf_v)

        # Prune the parent branch of our views
        prune!(dt, (:A,))

        # They should now instantly report as stale
        @test is_stale(branch_v)
        @test is_stale(leaf_v)

        # Check safe fallback behaviors for the stale SDBranch
        @test length(branch_v) == 0
        @test isempty(collect(keys(branch_v)))
        @test isempty(collect(values(branch_v)))
        @test !haskey(branch_v, (:C,))
        @test collect(branch_v) == [] # Iteration yields nothing

        # Check safe fallback behaviors for the stale SDLeaf
        @test length(leaf_v) == 0
        @test isempty(collect(keys(leaf_v)))
        @test isempty(collect(values(leaf_v)))
        @test !haskey(leaf_v, (:A, :B, :C))
        @test collect(leaf_v) == [] # Iteration yields nothing

        # Test that `empty!` on the parent tree also makes views stale
        dt2 = SDTree((:Fermion, :Quark) => 2.2)
        v2 = view(dt2, (:Fermion,))

        @test !is_stale(v2)
        empty!(dt2)
        @test is_stale(v2)
        @test length(v2) == 0
    end

    @testset "AbstractTrees Integration" begin
        dt = SDTree{Tuple{Int, Symbol}, Float64}()
        dt[1, :a] = 10.0
        dt[1, :b] = 20.0

        # Children API
        c_root = children(dt)
        @test length(c_root) == 1
        @test c_root[1] isa SDBranch

        c_branch = children(c_root[1])
        @test length(c_branch) == 2
        @test c_branch[1] isa SDLeaf

        @test isempty(children(c_branch[1])) # Leaves have no children by default

        # Print formatting (Capture REPL output)
        out_str = sprint(print_tree, dt)

        @test occursin("SDTree (Root)", out_str)
        @test occursin("1", out_str)
        @test occursin(":a => 10.0", out_str)
        @test occursin(":b => 20.0", out_str)

        # Collection expansion fallback
        dt_nested = SDTree{Tuple{Int}, Vector{Int}}()
        dt_nested[1] = [99, 100]

        out_nested = sprint(print_tree, dt_nested)
        @test occursin("1 =>", out_nested) # Should not double print the vector
        @test occursin("99", out_nested)
    end

end
