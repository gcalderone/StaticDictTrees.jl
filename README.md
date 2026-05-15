# StaticDictTrees.jl

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

**StaticDictTrees.jl** provides a high-performance, type-stable, flattened hierarchical dictionary for Julia. It mimics the ergonomics of nested dictionaries without the complexity and type instability of nested `Dict` structures. By flattening hierarchies into `Tuple` keys and using cached secondary indices, it enables **O(1)** lookups optimized for write-seldom, read-often workflows.

Crucially, `StaticDictTrees` provides native, allocation-free support for **heterogeneous tuple keys** (e.g., `Tuple{Int, Symbol, String}`), allowing you to mix data types in your hierarchical paths while maintaining strict type stability.

## Why StaticDictTrees?

Standard nested dictionaries (e.g., `Dict{K, Dict{K, V}}`) suffer from:
* **Poor Iteration:** Requires complex recursive loops.
* **Memory Overhead:** Every node is a separate hash table allocation.
* **Type Instability:** Hard to maintain strict typing across variable depths, especially with mixed key types.

`StaticDictTrees.jl` stores all values in a single flat vector and provides zero-cost `StaticDictBranch` views for sub-tree exploration.

### Comparison with `DataStructures.Trie`

While `Trie` (from `DataStructures.jl`) is an excellent data structure, it serves a different core purpose. `StaticDictTrees` offers several distinct architectural advantages for fixed-depth data:

1. **Heterogeneous Keys:** A `Trie{K, V}` requires a homogeneous sequence of keys (e.g., an array of `Char` for strings, or a sequence of strictly `Symbol`s). `StaticDictTree` fully supports mixed types in the path (e.g., `(1, :server, "latency")`).
2. **O(1) Lookups:** Looking up a deep value in a `Trie` is an **O(L)** operation, requiring `L` separate hash lookups and pointer jumps down the node tree. `StaticDictTree` resolves the entire path in exactly **one** hash lookup (O(1)).
3. **Contiguous Memory:** `Trie` nodes are scattered across the heap. `StaticDictTree` stores all values contiguously in a single `Vector`, maximizing cache locality.
4. **Trade-off:** To achieve this performance, `StaticDictTree` requires a **fixed tree depth** determined by the `Tuple` type, whereas a `Trie` gracefully handles highly variable-length sequences.

## Installation

```julia
using Pkg
Pkg.add("StaticDictTrees")
```

## Usage

### Creating a Tree with Heterogeneous Keys

Initialize a tree by specifying a strictly typed `Tuple` for the keys and a type for the values. 

```julia
using StaticDictTrees

# Tree with depth 3, mixing Int, Symbol, and String keys!
dt = StaticDictTree((1, :server, "latency") => 12.5,
                    (1, :server, "uptime")  => 99.9,
                    (2, :local, "cache")    => 2.1)
```

### Branching and Chaining (Views)

`StaticDictBranch` provides a type-stable view into a sub-tree without memory reallocation. You must provide the prefix as a `Tuple`. You can also chain branches together—they safely collapse down to the root parent automatically.

```julia
# Branch from the root
server_view = StaticDictBranch(dt, (1, :server))
println(server_view[("latency",)]) # 12.5

# Branch from another branch
root_view = StaticDictBranch(dt, (1,))
db_view = StaticDictBranch(root_view, (:server,))

db_view["uptime"] = 100.0 # Mutates the underlying root tree!
```

### Deletion vs. Pruning

* **`delete!`** removes a specific leaf entry from the tree.
* **`prune!`** removes an entire branch and all of its associated leaves, intelligently shifting internal indices.

```julia
# Delete a specific leaf using a full tuple key
delete!(dt, (2, :local, "cache"))

# Prune an entire branch from the root
prune!(dt, (1, :server))

# Prune via a branch view
prune!(root_view, (:server,))
```


### Standard Dictionary Methods

`StaticDictTrees.jl` fully supports Julia's standard dictionary interface.

```julia
dt = StaticDictTree{Tuple{Int, Symbol, String}, Float64}()
dt[(1, :server, "latency")] = 12.5
dt[(1, :server, "uptime")] = 99.9

server_view = StaticDictBranch(dt, (1, :server))

# Iteration yields `key => value` in insertion order.
for (k, v) in server_view
    println(k, " -> ", v) # k is ("latency",), etc.
end

# Extract components
k = keys(dt)
v = values(server_view) # Returns a fast SubArray view of the root vector!

# Emptying
empty!(server_view) # Empties just the branch
empty!(dt)          # Empties the entire tree
```

## Disclaimer

This package was developed with the assistance of AI (Gemini), but all code has been manually reviewed and tested for type stability and correctness by the author.
