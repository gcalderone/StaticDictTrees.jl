using Test
using DataStructures, StaticDictTrees

@testset "StaticDictTree Comprehensive Suite" begin

    @testset "1. Basic Tree Operations" begin
        dt_str = StaticDictTree{2, String, Int}()
        @test isempty(dt_str)
        @test key_length(dt_str) == 2
        @test parent(dt_str) === nothing

        dt_str["user", "age"] = 30
        dt_str["user", "id"] = 101

        @test length(dt_str) == 2
        @test dt_str["user", "age"] == 30
        @test collect(keys(dt_str)) == [("user", "age"), ("user", "id")]
        @test collect(values(dt_str)) == [30, 101]
    end

    @testset "2. Single-Key Fallbacks (TRD=1 and BRD=1)" begin
        # Root fallback
        dt1 = StaticDictTree{1, Symbol, String}()
        dt1[:a] = "Alpha"
        @test dt1[:a] == "Alpha"
        @test dt1[(:a,)] == "Alpha"

        # Branch fallback
        dt3 = StaticDictTree{3, Symbol, String}()
        dt3[:a, :b, :c] = "Target"
        branch = StaticDictBranch(dt3, :a, :b)

        @test key_length(branch) == 1
        @test branch[:c] == "Target"

        branch[:d] = "New Target"
        @test dt3[:a, :b, :d] == "New Target"
    end

    @testset "3. Branch Creation & Chaining" begin
        dt = StaticDictTree{3, String, String}()
        dt["A", "B", "C"] = "Data 1"
        dt["A", "B", "D"] = "Data 2"
        dt["A", "X", "Y"] = "Data 3"

        branch_A = StaticDictBranch(dt, "A")
        @test length(branch_A) == 3

        # Branch from Branch chaining
        branch_AB = StaticDictBranch(branch_A, "B")
        @test length(branch_AB) == 2
        @test collect(values(branch_AB)) == ["Data 1", "Data 2"]

        # Ensure it flattened correctly to the root parent
        @test branch_AB.parent === dt
        @test branch_AB.prefix == ("A", "B")

        # Over-branching assertion
        @test_throws AssertionError StaticDictBranch(branch_AB, "C")
    end

    @testset "4. Tree Navigation (parent and key_length)" begin
        dt = StaticDictTree{4, Symbol, Int}()
        dt[:a, :b, :c, :d] = 100

        b1 = StaticDictBranch(dt, :a)
        b2 = StaticDictBranch(b1, :b)
        b3 = StaticDictBranch(b2, :c)

        @test key_length(dt) == 4
        @test key_length(b1) == 3
        @test key_length(b2) == 2
        @test key_length(b3) == 1

        p1 = parent(b3)
        @test p1.prefix == (:a, :b)

        p2 = parent(p1)
        @test p2.prefix == (:a,)

        p3 = parent(p2)
        @test p3 isa StaticDictTree
        @test parent(p3) === nothing
    end

    @testset "5. Iteration Order and Caching" begin
        dt = StaticDictTree{2, String, Int}()
        dt["g1", "A"] = 10
        dt["g2", "B"] = 20
        dt["g1", "C"] = 30

        @test collect(dt) == [
            ("g1", "A") => 10,
            ("g2", "B") => 20,
            ("g1", "C") => 30
        ]

        branch = StaticDictBranch(dt, "g1")
        @test collect(branch) == [
            ("A",) => 10,
            ("C",) => 30
        ]
    end

    @testset "6. Deletion & Pruning" begin
        dt = StaticDictTree{3, String, Int}()
        dt["server", "db", "latency"] = 10
        dt["server", "db", "uptime"] = 100
        dt["server", "api", "calls"] = 500
        dt["local", "cache", "size"] = 1024

        branch = StaticDictBranch(dt, "server", "db")

        # Specific Leaf Deletion
        delete!(branch, "latency")
        @test length(dt) == 3
        @test !haskey(dt, ("server", "db", "latency"))

        # Index shifting verification
        @test dt["local", "cache", "size"] == 1024

        # Pruning via Root
        prune!(dt, "local")
        @test length(dt) == 2
        @test !haskey(dt.branchinds[2], ("local",))

        # Pruning via Branch
        server_branch = StaticDictBranch(dt, "server")
        prune!(server_branch, "api")
        @test length(dt) == 1
        @test dt["server", "db", "uptime"] == 100
    end

    @testset "7. The empty! Function" begin
        dt = StaticDictTree{3, Symbol, Float64}()
        dt[:a, :b, :c] = 1.0
        dt[:a, :x, :y] = 2.0

        branch = StaticDictBranch(dt, :a, :b)
        empty!(branch)

        @test length(dt) == 1
        @test dt[:a, :x, :y] == 2.0

        empty!(dt)
        @test isempty(dt)
        @test length(dt.values) == 0
    end

    @testset "8. Display and Show Methods (No Errors)" begin
        dt = StaticDictTree{3, String, Int64}()
        dt["A", "B", "C"] = 1

        buf = IOBuffer()
        show(buf, dt)
        @test occursin("StaticDictTree{3, String, Int64}", String(take!(buf)))

        show(buf, MIME("text/plain"), dt)
        @test occursin("=> 1", String(take!(buf)))

        branch = StaticDictBranch(dt, "A")
        show(buf, MIME("text/plain"), branch)
        @test occursin("StaticDictBranch{3, 2, String, Int64}", String(take!(buf)))
    end
end
