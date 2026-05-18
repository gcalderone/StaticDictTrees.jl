using StaticDictTrees, Random, Printf

# Build a tree of size N
function build_tree(N)
    dt = SDTree{Tuple{Int, Symbol, String}, Float64}()
    for i in 1:N
        dt[mod(i, 100), Symbol(:l, rand(Int)), string(rand())] = rand()
    end
    return dt
end

shuffled_keys(dict) = collect(keys(dict))[randperm(length(dict))]

# ------------------------------------------------------------------------------
println("--- Generate small (N=1,000) and large (N=1,000,000) datasets ---")
sdtr_warmup = build_tree(10);
sdtr_small = build_tree(1_000);
sdtr_large = build_tree(1_000_000);

# Also generate corresponding Dict objects for comparison
dict_warmup = Dict(sdtr_warmup);
dict_small = Dict(sdtr_small);
dict_large = Dict(sdtr_large);


# ------------------------------------------------------------------------------
println("\n--- Test lookups ---")
function test_lookup(label, dict; warmup=false)
    k = shuffled_keys(dict)
    GC.gc(true)
    GC.enable(false)
    count = 0.
    stats = @timed begin
        for k in k
            count += dict[k]
        end
    end
    GC.enable(true)
    warmup  ||  @printf "%-10s (N=%8d), Avg. time: %10.3f μs, Allocated: %4d MB\n" label length(dict) (stats.time / length(k) * 1e6) stats.bytes / (1024^2)
end

test_lookup("Warmup", sdtr_warmup, warmup=true)
test_lookup("Warmup", dict_warmup, warmup=true)
test_lookup("Dict"  , dict_small)
test_lookup("Dict"  , dict_large)
test_lookup("SDTree", sdtr_small)
test_lookup("SDTree", sdtr_large)


# ------------------------------------------------------------------------------
println("\n--- Test update ---")
function test_update(label, dict; warmup=false)
    k = shuffled_keys(dict)

    GC.gc(true)
    GC.enable(false)
    stats = @timed begin
        for k in k
            dict[k] = 1.
        end
    end
    GC.enable(true)
    warmup  ||  @printf "%-10s (N=%8d), Avg. time: %10.3f μs, Allocated: %4d MB\n" label length(dict) (stats.time / length(k) * 1e6) stats.bytes / (1024^2)
end

test_update("Warmup", sdtr_warmup, warmup=true)
test_update("Warmup", dict_warmup, warmup=true)
test_update("Dict"  , dict_small)
test_update("Dict"  , dict_large)
test_update("SDTree", sdtr_small)
test_update("SDTree", sdtr_large)


# ------------------------------------------------------------------------------
println("\n--- Test insertion ---")
function test_insertion(label, dict; warmup=false)
    k = shuffled_keys(dict)
    for i in 1:length(k) # generate new keys
        k[i] = (-k[i][1], (k[i][2:end])...)
    end
    tmp = deepcopy(dict)
    GC.gc(true)
    GC.enable(false)
    stats = @timed begin
        for k in k
            tmp[k] = 0.
        end
    end
    GC.enable(true)
    warmup  ||  @printf "%-10s (N=%8d), Avg. time: %10.3f μs, Allocated: %4d MB\n" label length(dict) (stats.time / length(k) * 1e6) stats.bytes / (1024^2)
end

test_insertion("Warmup", sdtr_warmup, warmup=true)
test_insertion("Warmup", dict_warmup, warmup=true)
test_insertion("Dict"  , dict_small)
test_insertion("Dict"  , dict_large)
test_insertion("SDTree", sdtr_small)
test_insertion("SDTree", sdtr_large)


# ------------------------------------------------------------------------------
println("\n--- Test delete ---")
function test_delete(label, dict; warmup=false)
    N = 100
    k = shuffled_keys(dict)
    k = k[1:min(N, length(k))]  # consider only N entries to delete
    tmp = deepcopy(dict)
    GC.gc(true)
    GC.enable(false)
    stats = @timed begin
        for k in k
            delete!(tmp, k)
        end
    end
    GC.enable(true)
    warmup  ||  @printf "%-10s (N=%8d, deleted %5d entries), Avg. time: %10.3f μs, Allocated: %4d MB\n" label length(dict) N (stats.time / N * 1e6) stats.bytes / (1024^2)
end

test_delete("Warmup", sdtr_warmup, warmup=true)
test_delete("Warmup", dict_warmup, warmup=true)
test_delete("Dict"  , dict_small )
test_delete("Dict"  , dict_large )
test_delete("SDTree", sdtr_small )
test_delete("SDTree", sdtr_large )


# ------------------------------------------------------------------------------
println("\n--- Test prune ---")
function test_prune(label, dict; warmup=false)
    tmp = deepcopy(dict)
    Nbefore = length(tmp)
    GC.gc(true)
    GC.enable(false)
    stats = @timed begin
        prune!(tmp, (1,))
    end
    GC.enable(true)
    Nafter = length(tmp)
    N = Nbefore - Nafter
    warmup  ||  @printf "%-10s (N=%8d, deleted %5d entries), Avg. time: %10.3f μs, Allocated: %4d MB\n" label length(dict) N (stats.time / N * 1e6) stats.bytes / (1024^2)
end

test_prune("Warmup", sdtr_warmup, warmup=true)
test_prune("SDTree", sdtr_small)
test_prune("SDTree", sdtr_large)
println("(pruning is not supported by Dict ...)")


# Final check
d = Dict(sdtr_large);
for (k, v) in sdtr_large
    @assert sdtr_large[k] == d[k]
end

prune!(sdtr_large, (8,))
for (k, v) in sdtr_large
    @assert sdtr_large[k] == d[k]
end
