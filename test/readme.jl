# Run all the `julia` code blocks in README.md, in order, within a single module,
# to make sure the examples do not drift from the actual package behavior.
@testset "README examples" begin
    readme = joinpath(@__DIR__, "..", "README.md")
    blocks = [m.captures[1] for m in eachmatch(r"```julia\n(.*?)```"s, read(readme, String))]
    # skip REPL transcripts and installation instructions
    blocks = filter(b -> !occursin("pkg>", b) && !occursin("julia>", b) && !occursin("Pkg.add", b), blocks)
    @test length(blocks) > 10
    mod = Module(:ReadmeExamples)
    Core.eval(mod, :(using StaticDictTrees))
    for (i, code) in enumerate(blocks)
        ok = try
            redirect_stdout(devnull) do
                Base.include_string(mod, code, "README.md block $i")
            end
            true
        catch e
            @error "README block $i failed" exception=(e, catch_backtrace())
            false
        end
        @test ok
    end
end
