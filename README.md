# StaticDictTrees.jl

---

**StaticDictTrees.jl** provides a data structure that maps fixed-length `Tuple` keys to values, just like a standard `Dict` would. Also, it treats the tuple as a hierarchical path where each element represents a specific step along a branch, thus allowing you to represent tree-like data structures, as well as to isolate specific branches when the provided `Tuple` key is incomplete. Finally, it allows you to access the elements as a single, contiguous vector with no need for nested loops.

> [!WARNING]
> Breaking Changes in v0.2.0
> The `keys(::SDTree, level::Int)` or `branches` methods are no longer supported. Also, the possibility to insert "metadata" using incomplete keys is no longer provided since the same functionality can now be obtained using the `DictTree` and `DictBranch` structures.


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
# 0.510998

# ... or create a view based on an incomplete key (branch)
leptons = view(part_mass, (:Fermion, :Lepton))
println(leptons[:electron])
# 0.510998

# Obtain a view on the internal values vector
println(values_view(leptons))
# [0.510998, 105.658, 1776.86, 0.0, 0.0, 0.0]
```

## Introduction

The structures provided by **StaticDictTrees.jl** are:
- `SDTree`: provides a fast, tree-like hierarchical data structure with an `AbstractDict` interface and `Tuple` as keys. The tree depth is equal to the length of the `Tuple` key and is fixed (hence "static" in the package name);
- `SDBranch`: provides a type-stable view of a specific branch of an `SDTree` object, allowing updates to be seamlessly reflected in the original tree. An `SDBranch` is created by invoking the `view` function on an `SDTree` and providing an incomplete key representing the path to a branch.

In order to remove the limitation of a fixed tree depth, v0.2.0 of the package introduces two new data structures:
- `DictTree`: to manage a collection of static trees (namely `SDTree` objects) and to dynamically dispatch method calls depending on key length;
- `DictBranch`: similar to `SDBranch`, it provides a view on a specific branch of a `DictTree`, allowing you to access / modify its values using an incomplete key prefix.

While slightly slower than their static-depth counterparts (`SDTree` and `SDBranch`) due to the dynamic routing overhead, they allow you to insert and retrieve data at any arbitrary depth. On the other hand, there is no `values_view` defined for `DictTree` and `DictBranch` since their value vectors are scattered among different depths.


### Features

* $O(1)$ complexity for lookups, insertions, updates, and single-item deletions (`delete!`) for `SDTree` and `SDBranch`. Pruning a branch (`prune!`) scales proportionally to the number of items being removed;
* Zero-allocation views on any branch of a static depth tree, with no need to allocate new dictionaries or copy data (`view`);
* Provides a view to access the underlying contiguous (i.e., dense) `Vector` of values (`values_view`);
* Availability of `delete!` and `prune!` methods to delete a single leaf value or an entire branch respectively;
* Availability of `DictTree` and `DictBranch` structures to operate on trees with arbitrary depths;
* Iterate all trees sequentially, i.e., with no nested loops;
* Compatible with `AbstractDict` and `AbstractTrees` interfaces;
* Dedicated `show()` methods allow you to easily display the tree structure in the REPL;
* Docstrings available for all methods.



### Use cases

`StaticDictTrees` provides a suitable data structure in the following cases:

- You need $O(1)$ performance on a fixed depth tree-like data structure, while still being able to quickly access data based on an incomplete key (branch);

- You need to represent your tree data using a dictionary, but you also need to access the values in a vector without additional memory allocation due to (e.g.) a `collect` invocation;

- You need something similar to a multi-dimensional sparse array whose indexing is based on a generic `Tuple`, rather than a tuple of integers;

- You need to implement an in-memory database index based on a composite primary key;

- You need a data structure to represent a generic tree dictionary with arbitrary depths, but you also need $O(1)$ performance on a specific fixed-depth branch.


## Installation

```julia
# Hit `]` in the REPL to enter the Pkg prompt
pkg> add StaticDictTrees
```

## Static dict tree creation

Create an empty tree by specifying the fixed `Tuple` type to be used as keys. Any tuple can be used for the purpose:

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

## Zero-allocation views

A view on a `SDTree` is a lightweight, zero-allocation object holding a direct memory pointer to a specific subset of the parent tree's cache.
```julia
# Take a view on a branch
v = view(part_mass, (:Fermion, :Lepton))

# Updating the view mutates the underlying tree data
v[:electron_neutrino] = NaN

# Check the original tree
part_mass[:Fermion, :Lepton, :electron_neutrino]
# NaN
```

### Stale views and safe fallbacks

`StaticDictTrees` views hold direct memory references to the parent tree.

When the underlying data is removed from the parent tree by means of `delete!`, `prune!` or `empty!` the view safely transitions into a **stale** state, namely a state in which the stale view acts as an empty collection (length 0, empty iterators) and prevents unhandled memory errors. You can manually check this state using the `is_stale()` function:

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
part_mass[:Boson, :Scalar, :Higgs] = 4.0

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

# Check for explicit key existence
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

While `SDTree` guarantees maximum performance by enforcing a fixed depth, real-world data may be heterogeneous. E.g., you might want to store high-level data at depth 1, sub-category details at depth 2, and raw data at depth 3.

Version 0.2.0 of this package introduces the `DictTree` structure which acts as a collection of `SDTree` objects, each with its own fixed depth, and automatically routes method calls to the appropriate tree depending on the length of the `Tuple` key:

### Basic Usage

```julia
using StaticDictTrees

# Create an empty dynamic tree
dt = DictTree()

# Insert data at various depths!
dt[(:Engineering,)] = "Main Tech Hub"               # depth 1
dt[(:Engineering, :Software)] = "Backend Team"      # depth 2
dt[(:Engineering, :Software, :Alice)] = 95000.0     # depth 3
```

### Multi-layer views (`DictBranch`)

Just like `SDTree`, you can obtain a `view` of a `DictTree` to access elements using incomplete keys, and to reflect any modification directly into the parent tree.

```julia
# Take a view on the Engineering department
eng = view(dt, (:Engineering,))

# Access the exact match (the branch's own data) via the empty tuple
println(eng[()])
# Output: "Main Tech Hub"

# Access deeper elements using relative suffix keys
println(eng[(:Software, :Alice)])
# Output: 95000.0
```

### Accessing internal trees and labels

As anticipated, the use of `DictTree` and `DictBranch` involve a dynamic dispatch on the key length, or equivalently on the tree depth. To gain $O(1)$ performance on a specific depth tree you can use the `get_tree` method to retrieve the proper `SDTree` object natively, e.g.:
```julia
dt[:Engineering]               # This requires a dynamic dispatch
fast_tree = get_tree(dt, 1);   # Access the SDTree object with depth=1
fast_tree[:Engineering]        # This is type-stable and O(1)
```

You may even associate a label to a specific depth, and use it retrieve the corresponding `SDTree`:
```julia
dt = DictTree()

# Pre-allocate depth 1 and label it :Department
add_tree!(dt, SDTree{Tuple{Symbol}, String}(); label=:Department)

# Retrieve the type-stable tree by its label
dept_tree = get_tree(dt, :Department)
dept_tree[(:Engineering,)] = "Main Tech Hub"

# You can also check for existence using the label
println(hasdepth(dt, :Department)) # true
```

### Auto-initialization of intermediate depths

In case inserting a deep leaf node requires its parent categories to exist, you can provide an `initializer` function to `add_tree!`. This will be automatically invoked whenever you insert a value at a deeper level to populate the missing intermediate parent trees with default values.

```julia
dt = DictTree()

# Depth 1 Initializer
add_tree!(dt, SDTree{Tuple{Symbol}, String}();
          initializer = x -> "Default Dept: $x")

# Depth 2 Initializer: receives the partial tuple (x is a 2-Tuple)
add_tree!(dt, SDTree{Tuple{Symbol, Symbol}, String}();
          initializer = x -> "Default Team for $(x[1])")

# We insert a leaf at depth 3...
dt[(:Engineering, :Backend, :Alice)] = 95000.0

# ...and the intermediate layers are automatically populated
println(dt[(:Engineering,)])
# Output: "Default Dept: Engineering"

println(dt[(:Engineering, :Backend)])
# Output: "Default Team for Engineering"
```

**Note:** Initializers do not overwrite existing values. They only trigger if the value at the specific depth *does not already exist*.


### Data validation

You can provide a `validator` function when adding a tree layer to enforce custom business rules before values are inserted. The function receives the underlying `tree`, the `key`, and the `value` being inserted. If it returns `false`, the `DictTree` will immediately throw an `ArgumentError` and safely reject the insertion.

```julia
dt = DictTree()

# Example: Ensure budgets are strictly positive and capped at 1,000,000
add_tree!(dt, SDTree{Tuple{Symbol}, Float64}();
          validator = (tree, key, val) -> 0.0 < val <= 1_000_000.0)

dt[(:Marketing,)] = 50000.0   # Succeeds

# dt[(:Engineering,)] = -50.0 # Throws ArgumentError!
```


### Auto-cleaning (Upward garbage collection)

When working with hierarchical data, deleting all leaves of a branch can leave orphaned parent metadata behind. By setting `autoclean = true` when adding a tree layer, `DictTree` will automatically perform "upward garbage collection".

Whenever you `delete!` or `prune!` an element, the shell checks if its parent metadata is now the *only* item remaining in the branch. If it is, the parent is automatically deleted as well!

```julia
dt = DictTree()

add_tree!(dt, SDTree{Tuple{Symbol}, String}();
          label=:Dept,
          initializer = x -> "Auto-Dept: $x",
          autoclean = true) # Enable auto-cleanup!

# Insert a deep leaf (initializers fire downward!)
dt[(:Eng, :Backend, :Alice)] = 95000.0

# Verify there is an entry key at depth 1
println(haskey(dt, (:Eng,))) # true

# Now delete the leaf...
delete!(dt, (:Eng, :Backend, :Alice))

# ...and the upward cascade automatically deletes the (:Eng,) entry
println(haskey(dt, (:Eng,))) # false
```


### Cross-layer pruning

Using `prune!` on a `DictTree` or `DictBranch` will delete the exact key match and recursively delete all associated elements across every deeper layer in the entire structure. If `autoclean = true` is configured for parent layers, pruning deep branches will also trigger upward cleanup of orphaned entries.

```julia
# This will delete the data at (:Engineering, :Software)
# and the leaf data at (:Engineering, :Software, :Alice)
prune!(dt, (:Engineering, :Software))

println(haskey(dt, (:Engineering, :Software)))         # false
println(haskey(dt, (:Engineering, :Software, :Alice))) # false
println(haskey(dt, (:Engineering,)))                   # true (Parent is untouched, unless autoclean triggered)
```


### Value types of internal trees

By default, dynamically created trees use `Any` as their value type to allow for flexible, heterogeneous routing. If you want strict type safety and performance for a specific depth layer, you can manually specify the value type by using `add_tree!`:

```julia
# Allocate depth 1 tree to only accept Symbol keys and String values
dt = DictTree()
add_tree!(dt, SDTree{Tuple{Symbol}, String}())

dt[(:Engineering,)] = "Main Tech Hub"
# dt[(:Logistics,)] = 100.0 # This would now throw a MethodError!
```



## Check $O(1)$ scalability for static dict trees

True $O(1)$ complexity means that elapsed time during operations remains constant regardless of the dataset's size. In the real world, however, it is difficult to empirically verify such a statement due to a number of optimizations occurring at different levels (compiler, operating system, CPU cache, etc.).

The `test/check_performance.jl` script allows you to measure the time required to perform a lookup, an insertion, an update and a delete using `SDTree` and a view on it (`SDBranch`), as well as compare the corresponding times obtained with the standard `Dict`. It also measures the performance for pruning operations (only for `SDTree` and `SDBranch`). The example covers the cases N=1,000 and N=1,000,000 datasets.
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

Single insertions, on the other hand, provide slightly worse performance due to the need to populate internal structures. This additional load may partly be mitigated by invoking `sizehint!`.

Branch pruning (`prune!`) is not supported by `Dict`, hence a direct comparison is not possible. However, the results show that it is able to perform massive batch deletions in just a few microseconds.

Finally, the performance on zero-allocation views (`SDBranch`) is nearly identical to operating directly on the root `SDTree`.



## Disclaimer

This package was developed with the assistance of AI (Gemini), but all code has been manually reviewed and tested for type stability and correctness by the author.
