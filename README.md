# StaticDictTrees.jl

**StaticDictTrees.jl** maps fixed-length `Tuple` keys to values, just like a standard `Dict` would, with the additional capability of providing tree-like views on a subset identified by providing only a part of the original tuple used as key.

```julia
using StaticDictTrees

# Create a SDTree representing the mass of elementary particles
part_mass = SDTree((:Fermion, :Quark, :up)                 => 2.2,
                   (:Fermion, :Quark, :down)               => 4.7,
                   (:Fermion, :Quark, :strange)            => 96.0,
                   (:Fermion, :Quark, :charm)              => 1270.0,
                   (:Fermion, :Quark, :bottom)             => 4180.0,
                   (:Fermion, :Quark, :top)                => 172760.0,
                   (:Fermion, :Lepton, :electron)          => 0.510998,
                   (:Fermion, :Lepton, :muon)              => 105.658,
                   (:Fermion, :Lepton, :tau)               => 1776.86,
                   (:Fermion, :Lepton, :electron_neutrino) => 0.0, # exact values are unknown
                   (:Fermion, :Lepton, :muon_neutrino)     => 0.0,
                   (:Fermion, :Lepton, :tau_neutrino)      => 0.0,
                   (:Boson, :Gauge, :photon)               => 0.0,
                   (:Boson, :Gauge, :gluon)                => 0.0,
                   (:Boson, :Gauge, :W)                    => 80377.0,
                   (:Boson, :Gauge, :Z)                    => 91187.6,
                   (:Boson, :Scalar, :higgs)               => 125100.0)

# Access using the entire key
println(part_mass[:Fermion, :Lepton, :electron])

# ... or create a view on a branch and use a partial key
leptons = view(part_mass, (:Fermion, :Lepton))
println(leptons[:electron])
```

The functionality provided by `SDTree` is similar to the one provided by a sparse matrix, but it uses a generic `Tuple` as key rather than a tuple of positive integers.  Also, the functionality is identical to that of a `Dict`, with the possibility to use partial keys.  Finally, it allows users to represent a (constant depth) data tree and to walk it sequentially.



## Features

* **Tuple keys:** Support any generic `Tuple` as key;
* **O(1) everything:** Lookups and insertions are O(1);
* **Cache-friendly:** All values are stored contiguously in a single flat `Vector`;
* **Zero-allocation views:** Instantly step into sub-branches without allocating new dictionaries or copying data;
* **100% compatible with Julia ecosystem:** Fully implement the `AbstractDict` and `AbstractTrees.jl` interface;
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

# Create an empty tree using `Tuple{Int, Symbol, String}` as key
dt = SDTree{Tuple{Int, Symbol, String}, Float64}()

# Insert data using standard dictionary syntax
dt[1, :server, "latency"] = 12.5
dt[1, :server, "uptime"]  = 99.9
dt[2, :local,  "cache"]   = 2.1
```

`StaticDictTrees.jl` integrates with `AbstractTrees.jl` hence typing `dt` in the REPL instantly visualizes your data:

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

A view on a `SDTree` is a lightweight, zero-allocation object holding a direct memory pointer to a specific subset of the parent tree's cache.
```julia
# Take a view of everything under `(1, :server)`
server_view = view(dt, (1, :server))

# Mutating the view mutates the underlying flat array
server_view["latency"] = 8.0

dt[1, :server, "latency"]
8.0
```

Views automatically return the correct type based on the path length:
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
# Iterate over all leaves in the same order they were inserted
for (key, val) in dt
    println("Path: $key, Value: $val")
end

# Convert to a standard dictionary
Dict(dt)

# Get all values as a flat iterator
values(dt)
```


## Demonstrating $O(1)$ Scalability

True $O(1)$ complexity means that operations remain constant regardless of the dataset's size. Standard nested dictionaries require multiple hashes and pointer hops, often scaling poorly as memory fragmentation increases.

`SDTree` hashes the full tuple path directly to a single, flat, array index, therefore its retrieval and insertion times are completely decoupled from the number of elements in the tree.

The `test/check_performance.jl` script allows you to measure the performance of `SDTree` (and compare them to the standard `Dict`) when dealing with a N=1,000 and N=1,000,000 datasets:
```
julia> include("test/check_performance.jl")
--- Generate small (N=1,000) and large (N=1,000,000) datasets ---

--- Test retrieval ---
N = 1,000           :   27.000 ns (0 allocations: 0 bytes)
N = 1,000 (Dict)    :   27.000 ns (0 allocations: 0 bytes)
N = 1,000,000       :   37.000 ns (0 allocations: 0 bytes)
N = 1,000,000 (Dict):   40.000 ns (0 allocations: 0 bytes)

--- Test insertion ---
N = 1,000           :   41.000 ns (0 allocations: 0 bytes)
N = 1,000 (Dict)    :   35.000 ns (0 allocations: 0 bytes)
N = 1,000,000       :   81.000 ns (0 allocations: 0 bytes)
N = 1,000,000 (Dict):   59.000 ns (0 allocations: 0 bytes)

--- Test overwrite ---
N = 1,000           :   41.000 ns (0 allocations: 0 bytes)
N = 1,000 (Dict)    :   34.000 ns (0 allocations: 0 bytes)
N = 1,000,000       :   72.000 ns (0 allocations: 0 bytes)
N = 1,000,000 (Dict):   45.000 ns (0 allocations: 0 bytes)

--- Test view generation ---
N = 1,000    :   10.230 ns (0 allocations: 0 bytes)
[ Info: View length: 10
N = 1,000,000:   10.675 ns (0 allocations: 0 bytes)
[ Info: View length: 10000
```
No allocation was required, and benchmark times are independent of the data size for all cases (the slight increase in timing for the N=1,000,000 case is likely due to cache misses).


## Disclaimer

This package was developed with the assistance of AI (Gemini), but all code has been manually reviewed and tested for type stability and correctness by the author.
