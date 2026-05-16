# StaticDictTrees.jl

**StaticDictTrees.jl** provides a high-performance, flattened hierarchical dictionary for Julia. It maps fixed-depth `Tuple` keys to values, combining the ergonomics of a nested tree with the extreme performance and cache-locality of flat arrays.

If you need a multidimensional, hierarchical key-value store but cannot afford the memory overhead, pointer-chasing, or type instability of deeply nested standard `Dict`s, this package is for you.

## Why StaticDictTrees?

* **O(1) Everything:** Lookups and insertions are O(1) by hashing the full tuple path.
* **Cache-Friendly:** All values are stored contiguously in a single flat `Vector`.
* **Zero-Allocation Views:** Instantly step into sub-branches without allocating new dictionaries or copying data.
* **100% Julian:** Fully subtypes `AbstractDict` and integrates seamlessly with `AbstractTrees.jl`.
* **Type Stable:** Natively supports heterogeneous tuple keys (e.g., `Tuple{Int, Symbol, String}`) without type instability.

## Installation

```julia
# Hit `]` in the REPL to enter the Pkg prompt
pkg> add StaticDictTrees
```

## Quick Start

Create a tree by specifying the fixed `Tuple` type for your keys, and the type for your values.

```julia
using StaticDictTrees

# Create a tree with a depth of 3
dt = SDTree{Tuple{Int, Symbol, String}, Float64}()

# Insert data using standard dictionary syntax
dt[1, :server, "latency"] = 12.5
dt[1, :server, "uptime"]  = 99.9
dt[2, :local,  "cache"]   = 2.1
```

Because `StaticDictTrees.jl` integrates with `AbstractTrees.jl`, typing `dt` in the REPL instantly visualizes your data:

```julia
julia> dt
SDTree{Tuple{Int64, Symbol, String}, Float64} with 3 entries:
SDTree (Root)
├─ 1
│  └─ :server
│     ├─ "latency" => 12.5
│     └─ "uptime" => 99.9
└─ 2
   └─ :local
      └─ "cache" => 2.1
```

## Zero-Allocation Views

Instead of copying data to look at a specific sub-branch, use the `view` function. This creates a lightweight, zero-allocation `SDBranch` (or `SDLeaf`) that holds a direct memory pointer to the parent tree's internal caches.

```julia
# Take a view of everything under `(1, :server)`
server_view = view(dt, (1, :server))

# Mutating the view mutates the underlying flat array
server_view["latency"] = 8.0 

julia> dt[1, :server, "latency"]
8.0
```

Views automatically route to the correct type based on the path length:
* Partial path -> `SDBranch`
* Full path -> `SDLeaf`

## Pruning and Deletion

Because values are stored in a dense, flat array, deleting individual leaves forces subsequent elements to shift in memory. `StaticDictTrees` provides a powerful `prune!` function to efficiently remove entire branches at once.

```julia
# Removes the entire `(1, :server)` branch and all its associated leaves safely
prune!(dt, (1, :server)) 

# You can also use prune! on a full key (it falls back to standard delete!)
prune!(dt, (2, :local, "cache")) 
```

## Ecosystem Compatibility

Because `AbstractSDTree <: AbstractDict`, it works perfectly with Julia's standard library. 

```julia
# Iterate over all leaves
for (key, val) in dt
    println("Path: $key, Value: $val")
end

# Convert to a standard dictionary
Dict(dt)

# Get all values as a flat iterator
values(dt)
```

## Under the Hood

Standard nested dictionaries (e.g., `Dict{Int, Dict{Symbol, Float64}}`) suffer from heavy memory fragmentation and pointer-chasing. 

`SDTree` solves this using **Data-Oriented Design**:
1. `keys`: A single `Vector{KT}`.
2. `values`: A single `Vector{VT}`.
3. `lookup`: A single flat `Dict{KT, Int}` mapping the full tuple to the array index.
4. `branch_lookup`: A tuple of highly optimized dictionaries that track the hierarchical relationships (prefixes to suffixes) purely using integer indices, enabling instant tree-traversal and visualization without duplicating your actual data.
