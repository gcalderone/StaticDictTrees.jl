using Test
using DataStructures, StaticDictTrees

@testset "StaticDictTree and StaticDictBranch Comprehensive Suite" begin

    @testset "1. Basic Operations & Generic Key Types" begin
        # Testing with Strings
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

        # Testing with Symbols
        dt_sym = StaticDictTree{3, Symbol, Float64}()
        dt_sym[:sys, :cpu, :usage] = 45.5
        dt_sym[:sys, :mem, :usage] = 80.0
        
        @test dt_sym[:sys, :cpu, :usage] == 45.5
        @test length(dt_sym) == 2
    end

    @testset "2. Single-Key Fallbacks" begin
        # Root fallback (N=1)
        dt1 = StaticDictTree{1, Symbol, String}()
        dt1[:a] = "Alpha"
        @test dt1[:a] == "Alpha"
        @test dt1[(:a,)] == "Alpha"

        # Branch fallback (M=1)
        dt3 = StaticDictTree{3, Symbol, String}()
        dt3[:a, :b, :c] = "Target"
        
        branch = StaticDictBranch(dt3, :a, :b)
        @test key_length(branch) == 1
        
        # Access via single key instead of 1-tuple
        @test branch[:c] == "Target"
        branch[:d] = "New Target"
        @test dt3[:a, :b, :d] == "New Target"
    end

    @testset "3. StaticDictBranch Creation & Manipulation" begin
        dt = StaticDictTree{3, String, String}()
        dt["A", "B", "C"] = "Data 1"
        dt["A", "B", "D"] = "Data 2"
        dt["A", "X", "Y"] = "Data 3"
        
        # Create a branch by fixing the first prefix
        branch_A = StaticDictBranch(dt, "A")
        
        @test length(branch_A) == 3
        @test collect(keys(branch_A)) == [("B", "C"), ("B", "D"), ("X", "Y")]
        
        # Create a deeper branch by fixing two prefixes
        branch_AB = StaticDictBranch(dt, "A", "B")
        @test length(branch_AB) == 2
        @test collect(values(branch_AB)) == ["Data 1", "Data 2"]
        
        # Mutation through the branch
        branch_AB["E"] = "Data 4"
        @test dt["A", "B", "E"] == "Data 4" # Check root
        
        # Assertion Error for too many keys (F >= N)
        @test_throws AssertionError StaticDictBranch(dt, "A", "B", "C")
    end

    @testset "4. Tree Navigation (parent and key_length)" begin
        dt = StaticDictTree{4, Symbol, Int}()
        dt[:a, :b, :c, :d] = 100
        
        branch_abc = StaticDictBranch(dt, :a, :b, :c) # M = 1
        branch_ab = StaticDictBranch(dt, :a, :b)      # M = 2
        branch_a = StaticDictBranch(dt, :a)           # M = 3
        
        @test key_length(dt) == 4
        @test key_length(branch_a) == 3
        @test key_length(branch_ab) == 2
        @test key_length(branch_abc) == 1
        
        # Climb the tree dynamically!
        p1 = parent(branch_abc)
        @test p1.prefix == (:a, :b)
        @test key_length(p1) == 2
        
        p2 = parent(p1)
        @test p2.prefix == (:a,)
        @test key_length(p2) == 3
        
        p3 = parent(p2)
        @test p3 isa StaticDictTree # We reached the root!
        @test parent(p3) === nothing
    end

    @testset "5. Iteration Order and Caching" begin
        dt = StaticDictTree{2, String, Int}()
        dt["group1", "A"] = 10
        dt["group2", "B"] = 20
        dt["group1", "C"] = 30
        
        # Root iteration
        @test collect(dt) == [
            ("group1", "A") => 10,
            ("group2", "B") => 20,
            ("group1", "C") => 30
        ]
        
        # Branch iteration
        branch = StaticDictBranch(dt, "group1")
        @test collect(branch) == [
            ("A",) => 10,
            ("C",) => 30
        ]
    end

    @testset "6. The empty! Function" begin
        dt = StaticDictTree{3, Symbol, Float64}()
        dt[:a, :b, :c] = 1.0
        dt[:a, :b, :d] = 2.0
        
        branch = StaticDictBranch(dt, :a)
        @test length(dt) == 2
        @test length(branch) == 2
        
        # Empty the root
        empty!(dt)
        
        @test length(dt) == 0
        @test isempty(dt)
        @test length(branch) == 0 # Branch should dynamically reflect the empty root
        
        # Ensure we can insert again without BoundsErrors
        dt[:x, :y, :z] = 9.9
        @test dt[:x, :y, :z] == 9.9
        @test length(dt.branchinds) == 2 # Pre-allocated structural vectors should remain intact
    end

    @testset "7. Display and Show Methods (No Errors)" begin
        dt = StaticDictTree{3, String, Int64}()
        dt["A", "B", "C"] = 1
        
        # We just want to ensure these don't throw an error when formatting
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
