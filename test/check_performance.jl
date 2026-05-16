using StaticDictTrees, BenchmarkTools

# Helper function to build a tree of size N
function build_tree(N)
    dt = SDTree{Tuple{Int, Symbol, String}, Float64}()
    for i in 1:N
        dt[mod(i, 100), Symbol(:l, rand(Int)), string(rand())] = rand()
    end
    return dt
end

println("--- Generate small (N=1,000) and large (N=1,000,000) datasets ---")
const dt_small = build_tree(1_000);
const dt_large = build_tree(1_000_000);
# Also generate standard Dicts to compare performance
const dict_small = Dict(dt_small);
const dict_large = Dict(dt_large);

const keys_small = collect(keys(dt_small));
const keys_large = collect(keys(dt_large));

println("\n--- Test retrieval ---")
print("N = 1,000           : ")
@btime $dt_small[k]                  evals=1 setup = (k = rand($keys_small))

print("N = 1,000 (Dict)    : ")
@btime $dict_small[k]                evals=1 setup = (k = rand($keys_small))

print("N = 1,000,000       : ")
@btime $dt_large[k]                  evals=1 setup = (k = rand($keys_large))

print("N = 1,000,000 (Dict): ")
@btime $dict_large[k]                evals=1 setup = (k = rand($keys_large))


println("\n--- Test insertion ---")
print("N = 1,000           : ")
@btime $dt_small[newk] = rand()      evals=1 setup = (k = rand($keys_small); newk = (-k[1], k[2:end]...))

print("N = 1,000 (Dict)    : ")
@btime $dict_small[newk] = rand()    evals=1 setup = (k = rand($keys_small); newk = (-k[1], k[2:end]...))

print("N = 1,000,000       : ")
@btime $dt_large[newk] = rand()      evals=1 setup = (k = rand($keys_large); newk = (-k[1], k[2:end]...))

print("N = 1,000,000 (Dict): ")
@btime $dict_large[newk] = rand()    evals=1 setup = (k = rand($keys_large); newk = (-k[1], k[2:end]...))


println("\n--- Test overwrite ---")
print("N = 1,000           : ")
@btime $dt_small[k] = rand()         evals=1 setup = (k = rand($keys_small))

print("N = 1,000 (Dict)    : ")
@btime $dict_small[k] = rand()       evals=1 setup = (k = rand($keys_small))

print("N = 1,000,000       : ")
@btime $dt_large[k] = rand()         evals=1 setup = (k = rand($keys_large))

print("N = 1,000,000 (Dict): ")
@btime $dict_large[k] = rand()       evals=1 setup = (k = rand($keys_large))


println("\n--- Test view generation ---")
print("N = 1,000    : ")
@btime begin
    v = view($dt_small, (1,))
end
@info "View length: $(length(view(dt_small, (1,))))"

print("N = 1,000,000: ")
@btime begin
    v = view($dt_large, (1,))
end
@info "View length: $(length(view(dt_large, (1,))))"
