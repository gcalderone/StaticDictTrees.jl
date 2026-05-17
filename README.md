# StaticDictTrees.jl

**StaticDictTrees.jl** maps fixed-length `Tuple` keys to values, just like a standard `Dict` would.  Also, it allows you to obtain tree-like views on a branch identified by an incomplete key.

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

# ... or create a view based on an incomplete key (branch)
leptons = view(part_mass, (:Fermion, :Lepton))
println(leptons[:electron])
```

## Use cases

`StaticDictTrees` provides a suitable data structure in the following cases:

- You need something similar to a multi-dimentional sparse array whose indexing is based on a generic `Tuple`, rather than a tuple of integers;

- You need a `Dict` with `Tuple` keys, but you also need to quickly access data based on an incomplete key (branch);

- You need to implement an in-memory database index based on a composite primary key;

- You need to represent a tree with fixed depth, and to walk it sequentially

## Features

* **Tuple keys:** Supports any generic `Tuple` as key;
* **O(1) complexity:** Lookups, insertions and updates have $O(1)$ complexity (deletion and pruning scale as $O(N)$ );
* **Cache-friendly:** All values are stored contiguously in a single flat `Vector`;
* **Zero-allocation views:** Instantly step into sub-branches without allocating new dictionaries or copying data;
* **100% compatible with Julia ecosystem:** Fully implements the `AbstractDict` and `AbstractTrees.jl` interfaces;
* **Type Stable:** Natively supports heterogeneous tuple keys (e.g., `Tuple{Int, Symbol, String}`) without type instability.

### Limitations

The dictionary tree provided by `StaticDictTree` has a constant (*static*, hence the name) depth, i.e., all leaves have exactly the same distance from the root equal to the length of the `Tuple` used as key.

If you need a variable depth tree consider using a [`Trie`](https://juliacollections.github.io/DataStructures.jl/stable/trie/) structure.


## Installation

```julia
# Hit `]` in the REPL to enter the Pkg prompt
pkg> add StaticDictTrees
```

## Static Dict Tree creation

Create an empty tree by specifying the fixed `Tuple` type to be used as keys.  Any tuple can be used for the purpose:

```julia
using StaticDictTrees

# Create an empty tree using `Tuple{Int, Symbol, String}` as key
dt = SDTree{Tuple{Int, Symbol, String}, Float64}()
```

Insert data using standard `Dict` syntax:
```julia
dt[1, :server, "latency"] = 12.5
dt[1, :server, "uptime"]  = 99.9
dt[2, :local,  "cache"]   = 2.1
```


## Zero-Allocation Views

A view on a `SDTree` is a lightweight, zero-allocation object holding a direct memory pointer to a specific subset of the parent tree's cache.
```julia
# Take a view on a branch
v = view(part_mass, (:Fermion, :Lepton))

# Updating the view mutates the underlying tree data
v[:electron_neutrino] = NaN

part_mass[:Fermion, :Lepton, :electron_neutrino]
# NaN
```


## `AbstractDict` and `AbstractTrees` integration

All data structures defined in `StaticDictTrees` inherit from `AbstractDict` and implement all the relevant functionalities, i.e.:
```julia
# Iterate over all leaves in the same order they were inserted
for (key, val) in part_mass
    println("Path: $key, Value: $val")
end

# Convert to a standard dictionary
Dict(part_mass)

# Get all keys
keys(part_mass)

# Get all values
values(part_mass)

# Print number of entries
length(part_mass)
```

Also, `StaticDictTrees.jl` implements the `AbstractTrees.jl` interface to exploit all its functionalities. E.g. the automatic display looks as follows:
```julia
julia> part_mass
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



## Tree navigation and utilities

`StaticDictTrees` provides several utility functions to navigate the hierarchical structure, inspect paths, and remove specific elements.

Using the `part_mass` tree from our first example, here is how you can use `depth`, `is_leaf_level`, `keys`, `parent`, and the standard `delete!` function:

```julia
# Get the fixed depth of the tree (the length of the tuple keys)
println(depth(part_mass))
# Output: 3

# Check if a structure points to a final value, namely if it can be indexed by a scalar value
println(is_leaf_level(part_mass)) # false
println(is_leaf_level(view(part_mass, (:Fermion)))) # false
println(is_leaf_level(view(part_mass, (:Fermion, :Quark)))) # true
println(view(part_mass, (:Fermion, :Quark))[:up]) # the view is at leaf level, hence we can use a scalar value as key

# Retrieve unique prefixes down to a specific depth
# Level 1 returns the root categories
collect(keys(part_mass, 1))
# Output: [(:Fermion,), (:Boson,)]

# Level 2 returns the sub-categories
collect(keys(part_mass, 2))
# Output: [(:Fermion, :Quark), (:Fermion, :Lepton), (:Boson, :Gauge), (:Boson, :Scalar)]

# For a branch, the level is relative to the branch's root
fermions = view(part_mass, (:Fermion,))
collect(keys(fermions, 1))
# Output: [(:Quark,), (:Lepton,)]

# Navigate upward from a specific view
quarks = view(part_mass, (:Fermion, :Quark))
fermions = parent(quarks)

# Remove a specific leaf entry
# (Note: to remove an entire branch at once, use `prune!` instead)
delete!(part_mass, (:Boson, :Scalar, :higgs))

# Remove an entire branch from the tree efficiently
prune!(part_mass, (:Boson,))

# Remove a branch from within a view
prune!(view(part_mass, (:Fermion,)), (:Quark,))

# All operations on a branch are reflected into the parent tree, i.e. the part_mass now contains only "Fermions":
keys(part_mass, 1)
# Output: :Fermion
```

## Check $O(1)$ scalability

True $O(1)$ complexity means that elapsed time during operations remains constant regardless of the dataset's size.  In the real world, however, it is difficult to empirically verify such statement due to a number of optimizations occurring at different levels (compiler, operating system, CPU cache, etc.)

The `test/check_performance.jl` script allows you to measure the time required to perform a lookup, an insertion and an update using `SDTree`, and compare the corresponding times obtained with the standard `Dict`.  The example covers the cases N=1,000 and N=1,000,000 datasets.
```
julia> include("test/check_performance.jl")
--- Generate small (N=1,000) and large (N=1,000,000) datasets ---

--- Test lookups ---
Dict       (N=    1000), Avg. time:   60.1 ns, Allocated: 0 MB
Dict       (N= 1000000), Avg. time:  115.6 ns, Allocated: 0 MB
SDTree     (N=    1000), Avg. time:   81.0 ns, Allocated: 0 MB
SDTree     (N= 1000000), Avg. time:  118.4 ns, Allocated: 0 MB

--- Test insertion ---
Dict       (N=    1000), Avg. time:   58.9 ns, Allocated: 0 MB
Dict       (N= 1000000), Avg. time:  254.3 ns, Allocated: 132 MB
SDTree     (N=    1000), Avg. time:  289.8 ns, Allocated: 1 MB
SDTree     (N= 1000000), Avg. time: 1855.3 ns, Allocated: 705 MB

--- Test update ---
Dict       (N=    1000), Avg. time:   72.2 ns, Allocated: 0 MB
Dict       (N= 1000000), Avg. time:  160.5 ns, Allocated: 0 MB
SDTree     (N=    1000), Avg. time:  105.6 ns, Allocated: 0 MB
SDTree     (N= 1000000), Avg. time:  215.4 ns, Allocated: 0 MB
```

As expected, both lookup and update operations do not require any allocation, and the averaged elapsed times scale approximately like `Dict` ones.  For insertions the performance for `SDTree` scale slightly worse than `Dict` due to the amount of internal structures to be updated to keep track of all newly inserted keys.



## Disclaimer

This package was developed with the assistance of AI (Gemini), but all code has been manually reviewed and tested for type stability and correctness by the author.
