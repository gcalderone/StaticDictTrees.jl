# StaticDictTrees.jl

---

**StaticDictTrees.jl** provides a data structure to map fixed-length `Tuple` keys to values, just like a standard `Dict` would. Also, it allows you to obtain tree-like views on a branch identified by an incomplete key.  Finally, it allows to access the vector containing all values inserted.2

> [!WARNING]
> Breaking Changes in v0.2.0
> The `keys(::SDTree, level::Int)` or `branches` methods are no longer supported.  Also, the possibility to inserte "metadata" using incomplete keys is no longer provided since the same functionality can now be otained using the `DictTree` and `DictBranch` structures.


## Quick start
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

## Obtain a view on the internal values vector
julia> println(values_view(leptons))
[0.510998, 105.658, 1776.86, 0.0, 0.0, 0.0]
```

## Introduction

The structures provided by **StaticDictTrees.jl** are:
- `SDTree`: provide a fast a tree-like hierarchical data structure with `AbstractDict` interface and `Tuple` as keys.  The tree depth is equal to the length of the `Tuple` key and is fixed (hence "static" in the package name;
- `SDBranch`: provide same performance on a type-stable view of a specific branch of a `SDTree` object, allowing updates to be seamlessly reflected in the original tree.  A `SDBranch` is created by invoking the `view` function on an `SDTree`, and providing an incomplete key representing the path to a branch.

In order to remove the limitation of the fixed tree depth, the v0.2.0 of the package introduces two new data structures:
- `DictTree`: to manage a collection of static trees i.e. (`SDTree` objects) and to dynamically dispatch method calls depending on key length;
- `DictBranch`: similar to `SDBranch`, it provides a view on a specific branch of a `DictTree`, allowing to access / modify its values using incomplete keys.

While slightly slower than the static-depth counterparts (`SDTree` and `SDBranch`) due to the dynamic routing overhead, they allows you to insert and retrieve data at any arbitrary depth.  On the other hand, there is no `values_view` defined for `SDTree` and `SDBranch` since their value vectors are scattered among different depths.


### Features

* O(1) complexity for lookups, insertions, updates and single-item deletions (`delete!`) for `SDTree` and `SDBranch`.  Pruning a branch (`prune!`) scales proportionally to the number of items being removed;
* Zero-allocation view on any branch of a static depth tree, with no need to allocate new dictionaries or copying data (`view`);
* Provide a view to access the underlying contiguous (i.e. dense) `Vector` of values (`values_view`).
* Availability of `delete!`  and `prune!` methods to delete a single leaf value or an entire branch respectively;
* Availability of `DictTree` and `DictBranch` structure to operate on trees with arbitrary depths;
* Iterate all trees sequentially, i.e. with no nested loops;
* Compatible with `AbstractDict` and `AbstractTrees` interfaces;
* Dedicated `show()` methods allows to easily display tree structure in the REPL;
* Docstrings available for all methods.



### Use cases

`StaticDictTrees` provides a suitable data structure in the following cases:

- You need $O(1)$ performance on a fixed depth tree-like data structure, while still being able to quickly access data based on an incomplete key (branch);

- You need to represent your tree data using a dictionary, but you also need to access the values without memory allocation (i.e. using a view on a vector); 

- You need something similar to a multi-dimensional sparse array whose indexing is based on a generic `Tuple`, rather than a tuple of integers;

- You need to implement an in-memory database index based on a composite primary key;

- You need a data structure to represent generic tree dictionary with arbitrary depths, but you also need $O(1)$ performance on a specific branch.


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

# Insert data using standard `Dict` syntax:
dt[1, :server, "latency"] = 12.5
dt[1, :server, "uptime"]  = 99.9
dt[2, :local,  "cache"]   = 2.1
```

If you plan to insert a large number of entries, you can improve performance and reduce memory allocations by pre-allocating the internal memory using `sizehint!`:
```julia
sizehint!(dt, 1_000_000)
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

All `StaticDictTrees` data structures inherit from `AbstractDict` and implement all the relevant functionalities, i.e.:
```julia
# Iterate over all leaves in the same order they were inserted
for (key, val) in part_mass
    println("Path: $key, Value: $val")
end

# Convert to a standard dictionary
Dict(part_mass)

# Get all leaf keys
keys(part_mass)

# Get all leaf values (returns a lazy iterator, just like a standard Dict)
values(part_mass)

# Get all leaf values as a zero-allocation `SubArray` view preserving insertion order
values_view(part_mass)

# Print number of explicitly assigned leaf entries
length(part_mass)
```

Also, `StaticDictTrees.jl` implements the `AbstractTrees.jl` interface to exploit all its functionalities. E.g. the automatic display looks as follows:
```julia
julia> part_mass
SDTree{Tuple{Symbol, Symbol, Symbol}, Float64} with 17 entries:
(root)
├─ :Boson
│  ├─ :Gauge
│  │  ├─ :W => 80377.0
│  │  ├─ :Z => 91187.6
│  │  ├─ :gluon => 0.0
│  │  └─ :photon => 0.0
│  └─ :Scalar
│     └─ :Higgs => 4.0
└─ :Fermion
   ├─ :Lepton
   │  ├─ :electron => 0.510998
   │  ├─ :electron_neutrino => 0.0
   │  ├─ :muon => 105.658
   │  ├─ :muon_neutrino => 0.0
   │  ├─ :tau => 1776.86
   │  └─ :tau_neutrino => 0.0
   └─ :Quark
      ├─ :bottom => 4180.0
      ├─ :charm => 1270.0
      ├─ :down => 4.7
      ├─ :strange => 96.0
      ├─ :top => 172760.0
      └─ :up => 2.2
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
println(is_leaf_level(view(part_mass, (:Fermion,)))) # false
println(is_leaf_level(view(part_mass, (:Fermion, :Quark)))) # true
println(view(part_mass, (:Fermion, :Quark))[:up]) # the view is at leaf level, hence we can use a scalar value as key

# Check for key existence
haskey(part_mass, (:Fermion, :Lepton, :electron)) # true

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
```


## Variable depth trees with `DictTree` and `DictBranch`

While `SDTree` guarantees maximum performance by enforcing a fixed depth, real-world data is often heterogeneous. E.g., you might want to store high-level metadata at depth 1, sub-category details at depth 2, and raw data at depth 3.

Version 0.2.0 of this packae introduces the `DictTree` structure which acts as a dynamic manager of a collection of optimized `SDTree`s, each with its own fixed depth, and automatically routes method calls to the appropriate tree depending on the length of the `Tuple` key:

### Basic Usage

```julia
using StaticDictTrees

# Create an empty dynamic tree
dt = DictTree()

# Insert data at various depths!
dt[(:Engineering,)] = "Main Tech Hub"               # Depth 1
dt[(:Engineering, :Software)] = "Backend Team"      # Depth 2
dt[(:Engineering, :Software, :Alice)] = 95000.0     # Depth 3
```

### Multi-Layer Views (`DictBranch`)

Just like `SDTree`, you can obtain a `view` of a `DictTree` to access elements using incomplete keys, and to reflect any modification directly into the parent tree.

```julia
# Take a view on the Engineering department
eng = view(dt, (:Engineering,))

# Access the exact match (the branch's own metadata) via the empty tuple
println(eng[()])
# Output: "Main Tech Hub"

# Access deeper elements using relative suffix keys
println(eng[(:Software, :Alice)])
# Output: 95000.0
```

### Accessing internal trees

As anticipated, the use of `DictTree` and `DictBranch` involve a dynamic dispatch on the key length, or equivalently on the tree depth. To gain $O(1)$ performance on a specific depth you can use the `get_tree` method to retrieve the proper `SDTree` object, e.g.:
```julia
dt[:Engineering]               # This requires a dynamic dispatch
fast_tree = get_tree(dt, 1)l;  # access the SDTree object with depth=1
fast_tree[:Engineering]        # This is type stable
```

To check if a specific depth tree is present in `DictTree` you may use the `hasdepth` function.


### Cross-Layer Pruning

Because a `DictTree` handles multiple depths simultaneously, pruning is highly cascading. Using `prune!` on a `DictTree` or `DictBranch` will delete the exact key match *and* recursively delete all associated elements across every deeper layer in the entire structure.

```julia
# This will delete the ata at (:Engineering, :Software)
# and the leaf data at (:Engineering, :Software, :Alice)
prune!(dt, (:Engineering, :Software))

println(haskey(dt, (:Engineering, :Software)))         # false
println(haskey(dt, (:Engineering, :Software, :Alice))) # false
println(haskey(dt, (:Engineering,)))                   # true (Parent is untouched)
```


### Value types of internal trees

By default, dynamically created trees use `Any` as their value type to allow for flexible, heterogeneous routing. If you want strict type safety and performance for a specific depth layer, you can manually pre-allocate it using `add_tree!`:

```julia
# Strictly lock depth 1 to only accept Integer keys and String values
dt = DictTree()
add_tree!(dt, Tuple{Symbol}, String)

dt[(:Engineering,)] = "Main Tech Hub"
# dt[(:Logistics,)] = 100.0 # This would now throw a MethodError!
```



## Check $O(1)$ scalability

True $O(1)$ complexity means that elapsed time during operations remains constant regardless of the dataset's size.  In the real world, however, it is difficult to empirically verify such statement due to a number of optimizations occurring at different levels (compiler, operating system, CPU cache, etc.)

The `test/check_performance.jl` script allows you to measure the time required to perform a lookup, an insertion, an update and a delete using `SDTree` and a view on it (`SDBranch`), as well as compare the corresponding times obtained with the standard `Dict`.  It also measures the performance for pruning operations (only for `SDTree` and `SDBranch`).  The example covers the cases N=1,000 and N=1,000,000 datasets.
```
julia> include("test/check_performance.jl")
--- Generate small (N=1,000) and large (N=1,000,000) datasets, and corresponding views containing half the entries ---

--- Test lookups ---
Dict       (N=    1000), Avg. time:      0.090 μs, Allocated:    0 MB
Dict       (N= 1000000), Avg. time:      0.133 μs, Allocated:    0 MB
SDTree     (N=    1000), Avg. time:      0.127 μs, Allocated:    0 MB
SDTree     (N= 1000000), Avg. time:      0.209 μs, Allocated:    0 MB
SDBranch   (N=     500), Avg. time:      0.077 μs, Allocated:    0 MB
SDBranch   (N=  500000), Avg. time:      0.180 μs, Allocated:    0 MB

--- Test update ---
Dict       (N=    1000), Avg. time:      0.093 μs, Allocated:    0 MB
Dict       (N= 1000000), Avg. time:      0.152 μs, Allocated:    0 MB
SDTree     (N=    1000), Avg. time:      0.205 μs, Allocated:    0 MB
SDTree     (N= 1000000), Avg. time:      0.366 μs, Allocated:    0 MB
SDBranch   (N=     500), Avg. time:      0.285 μs, Allocated:    0 MB
SDBranch   (N=  500000), Avg. time:      0.390 μs, Allocated:    0 MB

--- Test insertion ---
Dict       (N=    1000), Avg. time:      0.047 μs, Allocated:    0 MB
Dict       (N= 1000000), Avg. time:      0.260 μs, Allocated:  164 MB
SDTree     (N=    1000), Avg. time:      0.653 μs, Allocated:    0 MB
SDTree     (N= 1000000), Avg. time:      1.751 μs, Allocated:  393 MB
SDBranch   (N=     500), Avg. time:      0.820 μs, Allocated:    0 MB
SDBranch   (N=  500000), Avg. time:      1.657 μs, Allocated:  149 MB

--- Test delete ---
Dict       (N=    1000, deleted    100 entries), Avg. time:      0.272 μs, Allocated:    0 MB
Dict       (N= 1000000, deleted    100 entries), Avg. time:      0.437 μs, Allocated:    0 MB
SDTree     (N=    1000, deleted    100 entries), Avg. time:      2.169 μs, Allocated:    0 MB
SDTree     (N= 1000000, deleted    100 entries), Avg. time:      3.555 μs, Allocated:    0 MB
SDBranch   (N=     500, deleted    100 entries), Avg. time:      1.914 μs, Allocated:    0 MB
SDBranch   (N=  500000, deleted    100 entries), Avg. time:      3.485 μs, Allocated:    0 MB

--- Test prune ---
SDTree     (N=    1000, deleted    500 entries), Avg. time:      1.010 μs, Allocated:    0 MB
SDTree     (N= 1000000, deleted 500000 entries), Avg. time:      2.102 μs, Allocated:   11 MB
SDBranch   (N=     500, deleted    500 entries), Avg. time:      0.962 μs, Allocated:    0 MB
SDBranch   (N=  500000, deleted 500000 entries), Avg. time:      2.154 μs, Allocated:    8 MB
(pruning is not supported by Dict ...)
```
Note: all the above timings are calculated per *single operation*, while the allocated memory is reported as total allocations.


As expected, the average elapsed times for lookups, updates, and deletions on an `SDTree` scale similarly to a standard `Dict`, and show similar performance. Furthermore, these operations require exactly zero memory allocations.

Single insertions, on the other hand, provide slightly worse performance due to the population of internal structures. This additional load may partly be mitigated by invoking `sizehint!`.

Branch pruning (`prune!`) is not supported by `Dict`, hence a direct comparison is not possible. However, the results shows that it is able to perform massive batch deletions in just a few microseconds.

Finally, the performance on zero-allocation views (`SDBranch`) is nearly identical to operating directly on the root `SDTree`.



## Disclaimer

This package was developed with the assistance of AI (Gemini), but all code has been manually reviewed and tested for type stability and correctness by the author.
