# StaticDictTrees.jl

**StaticDictTrees.jl** provides a high-performance, strictly typed, and flattened hierarchical dictionary for Julia. It is designed for multi-level hierarchical data where you need the ergonomics of nested dictionaries without the massive performance penalties of pointer-chasing and type instability.

Under the hood, a `StaticDictTree` acts like an in-memory database index. It flattens your hierarchy into an `NTuple{N, K}` composite key and automatically builds cached secondary indices. This allows for blazingly fast, $O(1)$ lookups of partial branches (prefixes) optimized heavily for **write-seldom, read-often** workflows.

## Why StaticDictTrees?

The standard way to represent hierarchical data in Julia is nesting: `Dict{String, Dict{String, Dict{String, Int}}}`. However, nested dictionaries suffer from:

* **Poor Iteration:** Walking the tree requires complex recursive loops.
* **Memory Overhead:** Every node is a newly allocated hash table.
* **Type Instability:** Hard to maintain strict typing across variable depths.

`StaticDictTrees.jl` solves this by storing all values in a single, strictly typed flat vector, using tuple keys (e.g., `("server", "db", "latency")`), and providing zero-cost `StaticDictBranch` views to interact with sub-trees.

## Design Philosophy: The Fixed Depth Trade-off

You will notice that a `StaticDictTree` requires you to specify a fixed maximum depth, `N`, upfront (e.g., `StaticDictTree{3, String, Int}`). This is not an accident; it is a deliberate architectural trade-off to achieve maximum performance.

If we allowed variable-depth paths natively, we would have to use `Vector{K}` as our keys. Because vectors are dynamically sized, they live on the **heap**. Every single time you performed a dictionary lookup, Julia would have to allocate memory for the array, triggering the Garbage Collector and destroying performance. Alternatively, building a recursive tree (nodes pointing to nodes) would mean chasing pointers through memory with multiple expensive hash lookups per query.

By locking `N` into the type signature:

1. **Keys live on the stack:** Your paths become `NTuple{N, K}`, which are stack-allocated, zero-overhead, and instantly hashed.
2. **One contiguous lookup:** Looking up `dt["a", "b", "c"]` requires exactly one hash lookup, not three.
3. **Perfect Type Stability:** The JIT compiler knows the exact size and type of every branch and root, allowing it to compile your lookups down to hyper-efficient, allocation-free machine code.

*(**Tip for variable-depth data:** If you are modeling something with variable depth, like a file system, simply set `N` to your maximum expected depth and pad shallower paths with empty values like `""` or a dedicated `:empty` symbol!)*

## Installation

*(Note: Once registered, users will install via the standard package manager)*

```julia
using Pkg
Pkg.add("StaticDictTrees")

```

## Quick Start

### 1. Creating a StaticDictTree

Initialize a tree by specifying the depth (`N`), the key type (`K`), and the value type (`V`).

```julia
using StaticDictTrees

# Create a tree with a fixed depth of 3, using String keys and Float64 values
dt = StaticDictTree{3, String, Float64}()

# Insert data using tuple keys
dt["server", "db", "latency"] = 12.5
dt["server", "db", "uptime"] = 99.9
dt["local", "cache", "latency"] = 2.1
```

Because of our custom display methods, printing `dt` in the REPL yields a beautiful, visually indented tree:

```text
StaticDictTree{3, String, Float64} with 3 entries:
  "server"
    "db"
      "latency" => 12.5
      "uptime" => 99.9
  "local"
    "cache"
      "latency" => 2.1
```

### 2. Creating Branches (Views)

You can instantly access a sub-tree by creating a `StaticDictBranch`. Branches are highly optimized, type-stable views that do not allocate new memory for their contents.

```julia
# Create a branch by fixing the first prefix to "server"
server_view = StaticDictBranch(dt, "server")

# Access the remaining dynamic keys normally
println(server_view["db", "latency"]) # Output: 12.5

# Mutating the branch mutates the underlying tree!
server_view["db", "uptime"] = 100.0
```

### 3. Tree Navigation

`StaticDictTrees.jl` provides built-in utilities to navigate up and down your hierarchies.

```julia
# Check the required dynamic key length for the current view
println(key_length(server_view)) # Output: 2

# Climb back up the tree
root = parent(server_view)
```

### 4. Single-Key Fallbacks

For convenience, if you are working with a root tree of depth 1 (`N=1`) or a branch that only requires 1 more key (`M=1`), you can index it directly without wrapping your key in a tuple:

```julia
db_view = StaticDictBranch(dt, "server", "db")

# db_view expects 1 remaining key. We can omit the tuple parentheses!
db_view["latency"] = 15.0 
```

## Advanced Features

* **Iteration:** Iterating over a `StaticDictTree` or a `StaticDictBranch` yields `(key => value)` pairs in exact insertion order. Branch iteration is fully cached, meaning walking a subset of your data avoids redundant hash-lookups.
* **Generics:** `K` can be any type that supports `hash` and `isequal`. Using `isbits` types like `Symbol` or `Int` will yield the maximum possible performance.
* **Standard Base Extensions:** `keys()`, `values()`, `length()`, `isempty()`, and `empty!()` are fully implemented and optimized. Calling `values(branch)` returns a mutated standard `SubArray` view of the parent vector.
