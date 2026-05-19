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

- You need something similar to a multi-dimensional sparse array whose indexing is based on a generic `Tuple`, rather than a tuple of integers;

- You need a `Dict` with `Tuple` keys, but you also need to quickly access data based on an incomplete key (branch);

- You need to implement an in-memory database index based on a composite primary key;

- You need to represent a tree with fixed depth, and to walk it sequentially.

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

Also note that the key type must be a `Tuple`.  If all you need is simply a dictionary using `Symbol` or `Int` as key you may consider using an [`OrderedDict`](https://juliacollections.github.io/DataStructures.jl/stable/ordered_containers/) which would provide the same functionalities.

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

### Stale Views and Safe Fallbacks

`StaticDictTrees` views hold direct memory references to the parent tree.

When the underlying data is removed from the parent tree by meant of `delete!`, `prune!` or `empty!` the view safely transitions into a **stale** state, namely a state in which the stale view acts as an empty collection (length 0, empty iterators) and prevents unhandled memory errors. You can manually check this state using the `is_stale()` function:

```julia
# Create a view
v = view(part_mass, (:Boson, :Scalar))

# Destroy the data from the parent tree
prune!(part_mass, (:Boson, :Scalar))

# The view is now safely stale
println(is_stale(v))
# true

println(length(v))
# 0

# Restore the deleted entry
part_mass[:Boson, :Scalar, :Higgs] = 4.

# The view is still stale
println(is_stale(v))
# true
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

# Access to root SDTree structure
part_mass === root(quarks)

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

The `test/check_performance.jl` script allows you to measure the time required to perform a lookup, an insertion, an update and a delete using `SDTree` and a view on it (`SDBranch`), as well as compare the corresponding times obtained with the standard `Dict`.  It also measures the performance for pruning operations (only for `SDTree` and `SDBranch`).  The example covers the cases N=1,000 and N=1,000,000 datasets.
```
julia> include("test/check_performance.jl")
--- Generate small (N=1,000) and large (N=1,000,000) datasets, and corresponding views containing half the entries ---

--- Test lookups ---
Dict       (N=    1000), Avg. time:      0.093 μs, Allocated:    0 MB
Dict       (N= 1000000), Avg. time:      0.137 μs, Allocated:    0 MB
SDTree     (N=    1000), Avg. time:      0.097 μs, Allocated:    0 MB
SDTree     (N= 1000000), Avg. time:      0.138 μs, Allocated:    0 MB
SDBranch   (N=     500), Avg. time:      0.105 μs, Allocated:    0 MB
SDBranch   (N=  500000), Avg. time:      0.181 μs, Allocated:    0 MB

--- Test update ---
Dict       (N=    1000), Avg. time:      0.088 μs, Allocated:    0 MB
Dict       (N= 1000000), Avg. time:      0.191 μs, Allocated:    0 MB
SDTree     (N=    1000), Avg. time:      0.193 μs, Allocated:    0 MB
SDTree     (N= 1000000), Avg. time:      0.263 μs, Allocated:    0 MB
SDBranch   (N=     500), Avg. time:      0.183 μs, Allocated:    0 MB
SDBranch   (N=  500000), Avg. time:      0.255 μs, Allocated:    0 MB

--- Test insertion ---
Dict       (N=    1000), Avg. time:      0.053 μs, Allocated:    0 MB
Dict       (N= 1000000), Avg. time:      0.244 μs, Allocated:  164 MB
SDTree     (N=    1000), Avg. time:      0.593 μs, Allocated:    0 MB
SDTree     (N= 1000000), Avg. time:      1.566 μs, Allocated:  557 MB
SDBranch   (N=     500), Avg. time:      1.154 μs, Allocated:    0 MB
SDBranch   (N=  500000), Avg. time:      2.111 μs, Allocated:  313 MB

--- Test delete ---
Dict       (N=    1000, deleted    100 entries), Avg. time:      0.230 μs, Allocated:    0 MB
Dict       (N= 1000000, deleted    100 entries), Avg. time:      0.329 μs, Allocated:    0 MB
SDTree     (N=    1000, deleted    100 entries), Avg. time:     81.270 μs, Allocated:    4 MB
SDTree     (N= 1000000, deleted    100 entries), Avg. time: 351446.733 μs, Allocated: 3470 MB
SDBranch   (N=     500, deleted    100 entries), Avg. time:     79.777 μs, Allocated:    3 MB
SDBranch   (N=  500000, deleted    100 entries), Avg. time: 355157.578 μs, Allocated: 3470 MB

--- Test prune ---
SDTree     (N=    1000, deleted    500 entries), Avg. time:      0.834 μs, Allocated:    0 MB
SDTree     (N= 1000000, deleted 500000 entries), Avg. time:      1.953 μs, Allocated:   19 MB
SDBranch   (N=     500, deleted    500 entries), Avg. time:      0.940 μs, Allocated:    0 MB
SDBranch   (N=  500000, deleted 500000 entries), Avg. time:      2.049 μs, Allocated:   19 MB
(pruning is not supported by Dict ...)
```

As expected, the average elapsed times for lookups, updates, and insertions on an `SDTree` scale similarly to a standard `Dict`. Furthermore, lookups and updates require strictly zero memory allocations.

Single-item deletion, on the other hand, scales much worse than `Dict` and requires allocating memory for the temporary data used to update internal references. However, pruning is significantly more efficient, as it allows you to eliminate many entries at once and subsequently batch-update the internal references.

Additionally, the performance of zero-allocation views (`SDBranch`) is nearly identical to operating directly on the root `SDTree`.

Ultimately, these results show that the distinctive feature provided by `SDTree` and `SDBranch` —namely, the ability to isolate and operate on sub-branches of a tree— comes at the cost of poor performance when deleting individual entries.  While the `Dict` structure, albeit unable to isolate a branch, provides excellent performance also when deleting entries.

## Disclaimer

This package was developed with the assistance of AI (Gemini), but all code has been manually reviewed and tested for type stability and correctness by the author.
