using Test
using StaticDictTrees

# Custom struct for testing the provider enforcement
struct CustomID
    id::Int
end

@testset "SDTree Comprehensive Suite" begin

    @testset "1. Basic Operations & Heterogeneous Tuples" begin
        dt = SDTree{Tuple{Int, Symbol, String}, Float64}()

        @test isempty(dt)
        @test parent(dt) === nothing

        dt[1, :server, "latency"] = 12.5
        dt[1, :server, "uptime"] = 99.9
        dt[2, :local, "cache"] = 2.1

        @test length(dt) == 3
        @test dt[1, :server, "latency"] == 12.5
        @test haskey(dt, (1, :server, "uptime"))
        @test !haskey(dt, (1, :server, "missing"))

        @test collect(keys(dt)) == [(1, :server, "latency"), (1, :server, "uptime"), (2, :local, "cache")]
        @test collect(values(dt)) == [12.5, 99.9, 2.1]
    end

    @testset "2. Use a Custom structure" begin
        dt = SDTree{Tuple{CustomID, String}, Int}()

        key1 = (CustomID(101), "name")
        key2 = (CustomID(102), "age")

        dt[key1...] = 1
        dt[key2...] = 2

        @test length(dt) == 2
        @test dt[key1...] == 1

        branch = SDBranch(dt, (CustomID(101),))
        @test branch["name"] == 1
    end

    @testset "3. Branch Creation, Fallbacks & Chaining" begin
        dt = SDTree{Tuple{String, String, String}, String}()
        dt["A", "B", "C"] = "Data 1"
        dt["A", "B", "D"] = "Data 2"
        dt["A", "X", "Y"] = "Data 3"

        # Testing the non-tuple fallback in the branch constructor
        branch_A = SDBranch(dt, ("A",))
        @test length(branch_A) == 3
        @test haskey(branch_A, ("B", "C"))

        # Branch from Branch chaining
        branch_AB = SDBranch(branch_A, ("B",))
        @test length(branch_AB) == 2
        @test collect(values(branch_AB)) == ["Data 1", "Data 2"]

        # Ensure it flattened correctly to the root parent
        @test branch_AB.parent === dt
        @test branch_AB.prefix == ("A", "B")

        # Test Single-Key Fallbacks
        @test branch_AB["C"] == "Data 1"
        branch_AB["E"] = "Data 4"
        @test dt["A", "B", "E"] == "Data 4"

        # Over-branching assertion
        @test_throws AssertionError SDBranch(branch_AB, ("C",))
    end

    @testset "4. Iteration Order and Caching" begin
        dt = SDTree{Tuple{String, String}, Int}()
        dt["g1", "A"] = 10
        dt["g2", "B"] = 20
        dt["g1", "C"] = 30

        @test collect(dt) == [
            ("g1", "A") => 10,
            ("g2", "B") => 20,
            ("g1", "C") => 30
        ]

        branch = SDBranch(dt, ("g1",))
        @test collect(branch) == [
            ("A",) => 10,
            ("C",) => 30
        ]
    end

    @testset "5. Deletion (Leaf Specific)" begin
        dt = SDTree{Tuple{String, String, String}, Int}()
        dt["server", "db", "latency"] = 10
        dt["server", "db", "uptime"] = 100
        dt["server", "api", "calls"] = 500
        dt["local", "cache", "size"] = 1024

        branch = SDBranch(dt, ("server", "db"))

        # Specific Leaf Deletion via Branch
        delete!(branch, ("latency",))
        @test length(dt) == 3
        @test !haskey(dt, ("server", "db", "latency"))

        # Index shifting verification: "size" should still resolve to 1024
        @test dt["local", "cache", "size"] == 1024

        # Specific Leaf Deletion via Root
        delete!(dt, ("server", "api", "calls"))
        @test length(dt) == 2
        @test !haskey(dt, ("server", "api", "calls"))
    end

    @testset "6. Pruning (Branch Deletion)" begin
        dt = SDTree{Tuple{String, String, String}, Int}()
        dt["server", "db", "latency"] = 10
        dt["server", "db", "uptime"] = 100
        dt["server", "api", "calls"] = 500
        dt["local", "cache", "size"] = 1024

        # Pruning via Root with Varargs
        prune!(dt, ("local",))
        @test length(dt) == 3

        # Pruning via Branch
        server_branch = SDBranch(dt, ("server",))
        prune!(server_branch, ("api",))
        @test length(dt) == 2

        # Verify the rest of the tree is intact
        @test dt["server", "db", "latency"] == 10
        @test dt["server", "db", "uptime"] == 100
    end

    @testset "7. The empty! Function" begin
        dt = SDTree{Tuple{Symbol, Symbol, Symbol}, Float64}()
        dt[:a, :b, :c] = 1.0
        dt[:a, :x, :y] = 2.0
        dt[:z, :z, :z] = 3.0

        branch = SDBranch(dt, (:a,))

        # Empty branch
        empty!(branch)
        @test length(dt) == 1
        @test dt[:z, :z, :z] == 3.0
        @test isempty(branch)

        # Empty tree
        empty!(dt)
        @test isempty(dt)
        @test length(dt.values) == 0
    end

    @testset "8. Display and Show Methods" begin
        dt = SDTree{Tuple{String, String, String}, Int64}()
        dt["A", "B", "C"] = 1

        buf = IOBuffer()
        show(buf, dt)
        @test occursin("SDTree", String(take!(buf)))

        show(buf, MIME("text/plain"), dt)
        text_out = String(take!(buf))
        @test occursin("=> 1", text_out)
        @test occursin("A", text_out)

        branch = SDBranch(dt, ("A",))
        show(buf, MIME("text/plain"), branch)
        @test occursin("SDBranch", String(take!(buf)))
    end
end
