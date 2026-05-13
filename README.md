# StaticDictTrees.jl

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

**StaticDictTrees.jl** provides a high-performance, type-stable, flattened hierarchical dictionary for Julia. It mimics the ergonomics of nested dictionaries without the complexity and type instability of nested `Dict` structures. By flattening hierarchies into `NTuple{N, K}` keys and using cached secondary indices, it enables O(1) lookups optimized for write-seldom, read-often workflows.

## Why StaticDictTrees?

Standard nested dictionaries (e.g., `Dict{K, Dict{K, V}}`) suffer from:

* **Poor Iteration:** Requires complex recursive loops.
* **Memory Overhead:** Every node is a separate hash table allocation.
* **Type Instability:** Hard to maintain strict typing across variable depths.

`StaticDictTrees.jl` stores all values in a single flat vector and provides zero-cost `StaticDictBranch` views for sub-tree interaction.

## Design choice: The Fixed Depth Trade-off

In order to maximize performance, `StaticDictTree` relies on a fixed (*static*) tree depth, e.g., `StaticDictTree{3, Symbol, Int}`.  The reasons for such choices are:

1. **Stack-allocated keys:** Paths are strictly `NTuple{N, K}`, avoiding heap allocations during lookups;
2. **Contiguous Lookups:** Accessing deep values requires exactly one hash lookup. By flattening the path into a single composite key, `StaticDictTree` collapses multiple nested lookups into a single, direct memory access to the value vector;
3. **Type Stability:** The JIT compiler can generate highly optimized, allocation-free machine code because the tree's structure and depth are encoded in the type parameters at compile time.


## Installation

```julia
using Pkg
Pkg.add("StaticDictTrees")
```

## Usage

### Creating a StaticDictTree

Initialize a tree by specifying the tree depth (3), key type (`Symbol`), and value type (`Float64`). `Symbol` is the idiomatic choice for maximum performance.

```julia
using StaticDictTrees

dt = StaticDictTree{3, Symbol, Float64}()
dt[:server, :db, :latency] = 12.5
dt[:server, :db, :uptime] = 99.9
dt[:local, :cache, :latency] = 2.1
```

### Branching and Chaining (Views)

`StaticDictBranch` provides a type-stable view into a sub-tree without memory reallocation. You can also chain branches together—they safely collapse down to the root parent automatically to preserve O(1) performance.

```julia
# Branch from the root
server_view = StaticDictBranch(dt, :server)
println(server_view[:db, :latency]) # 12.5

# Branch from another branch!
db_view = StaticDictBranch(server_view, :db)
db_view[:uptime] = 100.0 # Mutates the underlying root tree!
```

### Tree Navigation & Metadata

Navigate the hierarchy or check the remaining expected depth of any given view.

```julia
println(key_length(server_view)) # Output: 2 (needs 2 more keys to reach a leaf)

# Climb back up the tree hierarchy
root = parent(server_view)
```

### Single-Key Fallbacks

If a tree or branch requires exactly 1 more key to reach a leaf (i.e., `key_length == 1`), you can omit the tuple syntax:

```julia
# db_view expects 1 remaining key
db_view[:uptime] = 101.0
```

### Deletion vs. Pruning

* **`delete!`** removes a specific leaf entry from the tree.
* **`prune!`** removes an entire branch and all of its associated leaves.

```julia
# Delete a specific leaf using a full tuple key
delete!(dt, (:local, :cache, :latency))

# Prune an entire branch from the root
prune!(dt, :server, :db)

# Prune via a branch view
prune!(server_view, :db)
```

### Standard Dictionary Methods

`StaticDictTrees.jl` fully supports Julia's standard dictionary interface.

```julia
dt = StaticDictTree{3, Symbol, Float64}()
dt[:server, :db, :latency] = 12.5
dt[:server, :db, :uptime] = 99.9
dt[:local, :cache, :latency] = 2.1
server_view = StaticDictBranch(dt, :server)

# Iteration yields `key => value` in insertion order.
for (k, v) in server_view
    println(k, " -> ", v)
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
