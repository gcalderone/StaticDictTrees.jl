# StaticDictTrees.jl

**StaticDictTrees.jl** provides `SDTree`, a dictionary whose keys are fixed-length `Tuple`s, interpreted as paths in a tree.  Besides the usual `AbstractDict` interface, it allows you to:

- take lightweight **views on branches**, i.e. on all the entries sharing a key prefix, and use them as dictionaries keyed by the remaining part of the key;
- access the values of the whole tree, or of any branch, as an `AbstractVector` (`values_view`), with no need for nested loops or `collect`;
- run **lifecycle hooks** on insertion, update and deletion;
- delete entire branches at once (`prune!`).

The package also provides `DictTree`, a dictionary accepting tuple keys of *any* length, internally organized as a collection of `SDTree`s (one per key length).

## Installation

```julia
# Hit `]` in the REPL to enter the Pkg prompt
pkg> add StaticDictTrees
```

## Quick start

```julia
using StaticDictTrees

# Mass of elementary particles (MeV), keyed by (family, group, name)
part_mass = SDTree((:Fermion, :Quark,  :up)                => 2.2,
                   (:Fermion, :Quark,  :down)              => 4.7,
                   (:Fermion, :Quark,  :strange)           => 96.0,
                   (:Fermion, :Quark,  :charm)             => 1270.0,
                   (:Fermion, :Quark,  :bottom)            => 4180.0,
                   (:Fermion, :Quark,  :top)               => 172760.0,
                   (:Fermion, :Lepton, :electron)          => 0.510998,
                   (:Fermion, :Lepton, :muon)              => 105.658,
                   (:Fermion, :Lepton, :tau)               => 1776.86,
                   (:Fermion, :Lepton, :electron_neutrino) => 0.0, # exact values are unknown
                   (:Fermion, :Lepton, :muon_neutrino)     => 0.0,
                   (:Fermion, :Lepton, :tau_neutrino)      => 0.0,
                   (:Boson,   :Gauge,  :photon)            => 0.0,
                   (:Boson,   :Gauge,  :gluon)             => 0.0,
                   (:Boson,   :Gauge,  :W)                 => 80377.0,
                   (:Boson,   :Gauge,  :Z)                 => 91187.6,
                   (:Boson,   :Scalar, :higgs)             => 125100.0)

# Access using the entire key
println(part_mass[:Fermion, :Lepton, :electron])
# 0.510998

# ... or create a view on a branch, using an incomplete key (prefix)
leptons = view(part_mass, (:Fermion, :Lepton))
println(leptons[:electron])
# 0.510998

# Obtain all the values in a branch as a vector view, in insertion order
println(values_view(leptons))
# [0.510998, 105.658, 1776.86, 0.0, 0.0, 0.0]
```

The REPL displays the tree structure (children are sorted for display; iteration follows insertion order):
```
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
│     └─ :higgs => 125100.0
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

## Data structures

| Type | Description |
|------|-------------|
| `SDTree{KT, VT}` | Dictionary with keys of the fixed tuple type `KT` and values of type `VT`. The tree depth is the length of `KT`, and is fixed (hence "static"). |
| `SDBranch` | View on the entries of an `SDTree` sharing a given prefix, created with `view(tree, prefix)`. It is an `AbstractDict` keyed by the remaining part of the key (suffix). |
| `SDLeaf` | View on a single entry, created with `view(tree, full_key)`. It behaves as a dictionary with a single key: `()`. |
| `DictTree` | Dictionary accepting tuple keys of any length. Each key length is handled by a separate `SDTree` (a *layer*). |
| `DictBranch` | View on the entries of a `DictTree` sharing a given prefix, across all layers. |

## When to use it

`StaticDictTrees` is suitable when:
- your data is naturally indexed by a composite key (e.g. `(detector, channel, run)`), and you often need to work on all the entries sharing a prefix (e.g. all channels of a detector);
- you need something similar to a multi-dimensional sparse array, indexed by arbitrary values rather than integers;
- you need to process the values of a branch as a vector (e.g. `sum(values_view(branch))`);
- you need lifecycle hooks (validation, accumulation, logging) on a dictionary;
- you need a tree with heterogeneous depths (`DictTree`), with automatic creation and cleanup of intermediate nodes.

Alternatives you may want to consider:
- a plain `Dict` with tuple keys is faster and uses much less memory, but branch access requires a full scan;
- nested `Dict`s (`Dict{Symbol, Dict{Symbol, ...}}`) provide cheap branch access, but no flat iteration, no flat value vector, and require manual creation/cleanup of the intermediate levels;
- a `DataFrame` with `groupby` is better suited for columnar data, analytical queries and very large datasets;
- [Dictionaries.jl](https://github.com/andyferris/Dictionaries.jl) provides insertion-ordered dictionaries with efficient vector-like value access, but no prefix views.

## Creating a tree

Create an empty tree by specifying the key and value types.  Any tuple type can be used as key:

```julia
using StaticDictTrees

tree = SDTree{Tuple{Int, Symbol, String}, Float64}()

# Insert data using the standard `Dict` syntax (the brackets of the key tuple can be omitted)
tree[1, :server, "latency"] = 12.5
tree[1, :server, "uptime"]  = 99.9
tree[2, :local,  "cache"]   = 2.1
tree[(2, :local, "hits")]   = 1e4
```

A tree can also be created from an existing dictionary, from a list of pairs (as in the quick start), or from two vectors of keys and values:

```julia
copy_of_tree = SDTree(tree)
tree2 = SDTree([(1, :a), (2, :b)], [10, 20])
```

Keys must have exactly the declared type: unlike `Dict`, no conversion is performed, and keys of a different type (e.g. an `Int32` where an `Int` is expected) raise an `ArgumentError` with `getindex`, `setindex!` and `delete!`, while `haskey` and `get` simply report the key as missing.  Values are converted to the value type as usual.

If you plan to insert a large number of entries, you can reduce reallocations with `sizehint!`:
```julia
sizehint!(tree, 1_000_000)
```

## Views

`view(tree, prefix)` returns an `SDBranch` on the entries whose key starts with `prefix`.  Branches are dictionaries themselves, and any modification is reflected in the parent tree:

```julia
leptons = view(part_mass, (:Fermion, :Lepton))
println(length(leptons))
# 6

# Keys of a branch are the remaining part of the full key (the brackets can be omitted for 1-tuples)
println(leptons[(:muon,)] == leptons[:muon] == part_mass[:Fermion, :Lepton, :muon])
# true

# Updating the view mutates the underlying tree
leptons[:electron_neutrino] = 1e-6
println(part_mass[:Fermion, :Lepton, :electron_neutrino])
# 1.0e-6

# Views can be nested
fermions = view(part_mass, (:Fermion,))
quarks   = view(fermions, (:Quark,))
println(quarks[:top])
# 172760.0

# A complete key returns an `SDLeaf`, a view on a single entry, accessed with the empty tuple
top = view(part_mass, (:Fermion, :Quark, :top))
println(top[()])
# 172760.0
```

A branch view also accepts the full keys of the root tree; note that such keys are *not* restricted to the branch prefix: `quarks[(:Boson, :Gauge, :W)]` returns the mass of the W boson.

Creating a view on a non-existing path raises a `KeyError`.  To check whether a path exists, use `haspath()`:
```julia
println(haspath(part_mass, (:Fermion, :Lepton)))
# true
println(haspath(part_mass, (:Fermion, :Gluon)))
# false
```

### Values as vectors (`values_view`)

All the values of an `SDTree` are stored in a single `Vector`.  `values_view` returns a `SubArray` on that vector, containing the values of the tree or branch in insertion order:

```julia
quark_masses = values_view(view(part_mass, (:Fermion, :Quark)))
println(sum(quark_masses))
# 178312.9

# The view is writable
quark_masses .*= 1e-3   # convert to GeV
println(part_mass[:Fermion, :Quark, :top])
# 172.76
```

Note that:
- the returned `SubArray` accesses the underlying dense `Vector` through a vector of positions, hence it is not itself a contiguous block (e.g. it can't be passed to functions requiring a `StridedArray`);
- insertions and updates are reflected in a previously obtained `values_view`. A deletion, however, invalidates it (it becomes empty): call `values_view` again to obtain an updated one. After deletions, the first `values_view` call rebuilds the list of positions, which costs O(n) in the size of the tree or branch.

### Stale views

A view holds a direct reference to the internal structures of its parent tree.  When the data it refers to is removed, the view becomes **stale**: it behaves as an empty collection (`length` is 0, iteration yields nothing, `values_view` is empty), and `is_stale()` returns `true`:

```julia
pm = SDTree(part_mass)   # a copy, to keep `part_mass` unchanged
v = view(pm, (:Boson, :Scalar))
println(is_stale(v))
# false

prune!(pm, (:Boson, :Scalar))
println(is_stale(v), "  ", length(v))
# true  0

# Re-inserting data does NOT revive a stale branch view: create a new one instead
pm[:Boson, :Scalar, :higgs] = 125100.0
println(is_stale(v), "  ", is_stale(view(pm, (:Boson, :Scalar))))
# true  false
```

Precisely:
- an `SDBranch` becomes stale when all the entries of its branch are removed (deleting only some of them keeps it valid), and stays stale afterwards;
- an `SDLeaf` is stale as long as its key is missing, i.e. it becomes valid again if the key is re-inserted;
- mutating operations on a stale view (`setindex!`, `delete!`, `prune!`) are still forwarded to the root tree using the view prefix, although a stale branch view does not see their results.

## Lifecycle hooks

`SDTree` can invoke user-defined functions when entries are inserted, updated or deleted.  They are configured with keyword arguments in the constructor:
* `on_insert`: invoked when a *new* key is added. Signature: `f(key, new_value) -> value_to_store`;
* `on_update`: invoked when an *existing* key is assigned a new value. Signature: `f(key, old_value, new_value) -> value_to_store`;
* `on_delete`: invoked right *before* an entry is removed. Signature: `f(key, value_about_to_be_deleted)`.

**Example: a self-validating accumulator**
```julia
# Track the energy deposited in the sensors of a particle detector
sensor_log = SDTree{Tuple{Symbol, Int}, Float64}(
    # 1. Reject physically invalid measurements on insertion
    on_insert = (k, v) -> v >= 0.0 ? v : throw(ArgumentError("Energy cannot be negative!")),

    # 2. Add incoming signals to the existing total (accumulator pattern)
    on_update = (k, old_v, new_v) -> old_v + new_v,

    # 3. Log a message when a sensor is removed
    on_delete = (k, v) -> println("Sensor $k removed. Final accumulated energy: $v MeV")
)

# sensor_log[:Calorimeter, 1] = -1.0   # would throw an ArgumentError, leaving the tree unchanged

sensor_log[:Calorimeter, 1] = 500.0  # calls on_insert
sensor_log[:Calorimeter, 1] = 120.0  # calls on_update

println(sensor_log[:Calorimeter, 1])
# 620.0

delete!(sensor_log, (:Calorimeter, 1)) # calls on_delete
# Sensor (:Calorimeter, 1) removed. Final accumulated energy: 620.0 MeV
```

Note that:
- the value stored may differ from the assigned one: as for any Julia assignment, `tree[k] = v` returns `v`, not the stored value. Generic functions relying on `setindex!` (`merge!`, `get!`, the constructors, ...) go through the hooks as well;
- if `on_insert` or `on_update` throw an exception (or return a value which can not be converted to the value type), the tree is left unchanged. If `on_delete` throws, the entry is not removed;
- `on_delete` is invoked by `delete!`, `pop!`, `prune!` and `empty!` on a branch or leaf view, but **not** by `empty!(::SDTree)`, which resets the whole tree in one go;
- hooks are not preserved by functions which create a new dictionary: e.g. `copy(tree)` and `merge(tree, ...)` return a plain `Dict` (generic `AbstractDict` behavior), and `SDTree(tree)` returns a tree without hooks.

## `AbstractDict` and `AbstractTrees` integration

All data structures are subtypes of `AbstractDict`, and support the usual dictionary functions:
```julia
# Iterate over all entries in insertion order
for (key, val) in part_mass
    println("Path: $key, Value: $val")
end

length(part_mass)                       # number of entries
keys(part_mass)                         # iterator over the keys
values(part_mass)                       # iterator over the values
haskey(part_mass, (:Boson, :Gauge, :W)) # true
get(part_mass, (:Boson, :Gauge, :X), NaN)
Dict(part_mass)                         # convert to a standard dictionary
filter(p -> p.second > 1000, part_mass) # returns a Dict
```

The `AbstractTrees.jl` interface is also implemented, e.g. `AbstractTrees.children(part_mass)` returns the views on the first-level branches, and `print_tree` is used to display trees in the REPL.

## Tree navigation and utilities

```julia
pm = SDTree(part_mass)

println(depth(pm))
# 3

# Is a structure one level above the leaves, i.e. can it be indexed by a scalar?
println(is_leaf_level(pm))                               # false
println(is_leaf_level(view(pm, (:Fermion,))))            # false
println(is_leaf_level(view(pm, (:Fermion, :Quark))))     # true

# Navigate upward
quarks = view(pm, (:Fermion, :Quark))
fermions = parent(quarks)                # an SDBranch with prefix (:Fermion,)
println(root(quarks) === pm)             # true

# Remove a single entry
delete!(pm, (:Boson, :Scalar, :higgs))
println(pop!(pm, (:Boson, :Gauge, :W)))  # remove and return
# 80377.0

# Remove an entire branch
prune!(pm, (:Boson,))

# Remove a branch from within a view
prune!(view(pm, (:Fermion,)), (:Quark,))

println(length(pm))   # only the leptons are left
# 6
```

## Variable depth trees with `DictTree` and `DictBranch`

`SDTree` requires all keys to have the same length.  Real-world data may be heterogeneous: e.g. you may want to store department data at depth 1, team data at depth 2 and employee data at depth 3.  A `DictTree` accepts keys of any length, and routes each operation to an internal `SDTree` (a *layer*) according to the key length:

```julia
using StaticDictTrees

dt = DictTree()
dt[(:Engineering,)]                   = "Main Tech Hub"  # depth 1
dt[(:Engineering, :Software)]         = "Backend Team"   # depth 2
dt[(:Engineering, :Software, :Alice)] = 95000.0          # depth 3
dt[(:Engineering, :Software, :Bob)]   = 90000.0          # depth 3

println(length(dt))
# 4
```

Iteration visits the layers in order of increasing depth, and each layer in insertion order.

Since the key type of a `DictTree` is not fixed, every operation involves a dynamic dispatch, hence it is slower than the corresponding operation on an `SDTree`.  Layers created automatically use `Any` as key element and value types: for type-stable access, create the layers explicitly with `add_layer!` (see below).  Also, `values_view` is not available, since values are scattered among layers.

### Multi-layer views (`DictBranch`)

A `view` on a `DictTree` spans all layers. Unlike `SDTree` views, it can be created on any prefix (even a non-existing one) and it is always up to date:

```julia
eng = view(dt, (:Engineering,))

# The entry exactly matching the prefix is accessed with the empty tuple
println(eng[()])
# Main Tech Hub

# Deeper entries are accessed with the remaining part of the key
println(eng[(:Software, :Alice)])
# 95000.0

println(length(eng))
# 4
```

### Accessing the internal trees and labels

Use `get_layer` to retrieve the `SDTree` handling a specific depth, and access it directly, avoiding the routing overhead:
```julia
employees = get_layer(dt, 3)             # the SDTree with depth 3
println(employees[:Engineering, :Software, :Alice])
# 95000.0
```

A layer can also be created explicitly, with a specific key and value type (layers created automatically use `Any` for both), and optionally a label:
```julia
dt = DictTree()
add_layer!(dt, SDTree{Tuple{Symbol}, String}(); label=:Department)

dept = get_layer(dt, :Department)
dept[:Engineering] = "Main Tech Hub"
println(dt[(:Engineering,)])
# Main Tech Hub

println(haslayer(dt, :Department))
# true
println(getlabels(dt))
# Dict(:Department => 1)

# The layer only accepts its own key and value types
# dt[(:Logistics,)] = 100.0   # would throw a MethodError (100.0 is not a String)
```

A layer can be an `SDTree` with its own lifecycle hooks.

### Topology hooks: automatic creation of parent nodes (`on_new_branch`)

The `on_new_branch` keyword of `add_layer!` provides a function returning a default value for the nodes of that layer.  It is invoked whenever an entry is inserted at a deeper level, and the corresponding node in this layer does not exist yet (existing values are never overwritten).  The function receives the node key: a scalar for depth 1, a tuple otherwise (`()` for depth 0).

```julia
dt = DictTree()
add_layer!(dt, SDTree{Tuple{Symbol}, String}();
           on_new_branch = x -> "Default Dept: $x")          # x is a Symbol
add_layer!(dt, SDTree{Tuple{Symbol, Symbol}, String}();
           on_new_branch = x -> "Default Team for $(x[1])")  # x is a 2-tuple

dt[(:Engineering, :Backend, :Alice)] = 95000.0

println(dt[(:Engineering,)])
# Default Dept: Engineering
println(dt[(:Engineering, :Backend)])
# Default Team for Engineering
```

### Topology hooks: automatic cleanup of parent nodes (`clean_on_empty_branch`)

When `clean_on_empty_branch = true` is set for a layer, a node in that layer is automatically deleted when an actual deletion (`delete!` or `prune!`) leaves it with no descendants in any deeper layer:

```julia
dt = DictTree()
add_layer!(dt, SDTree{Tuple{Symbol}, String}();
           on_new_branch = x -> "Auto-Dept: $x",
           clean_on_empty_branch = true)

dt[(:Eng, :Backend, :Alice)] = 95000.0
println(haskey(dt, (:Eng,)))
# true

delete!(dt, (:Eng, :Backend, :Alice))
println(haskey(dt, (:Eng,)))
# false
```

The cleanup proceeds upward through all layers having the flag enabled, and stops at the first node which still has descendants.  Deleting or pruning a non-existing key has no effect.

### Cross-layer pruning

`prune!` on a `DictTree` or `DictBranch` deletes the entry exactly matching the prefix, as well as all the entries below it, in every layer.  An empty prefix `()` removes everything.

```julia
dt = DictTree()
dt[(:Engineering,)]                   = "Main Tech Hub"
dt[(:Engineering, :Software)]         = "Backend Team"
dt[(:Engineering, :Software, :Alice)] = 95000.0
dt[(:Engineering, :Hardware)]         = "Hardware Team"

prune!(dt, (:Engineering, :Software))

println(haskey(dt, (:Engineering, :Software)))         # false
println(haskey(dt, (:Engineering, :Software, :Alice))) # false
println(haskey(dt, (:Engineering, :Hardware)))         # true
println(haskey(dt, (:Engineering,)))                   # true (no clean_on_empty_branch here)
```

## Performance

| Operation | `SDTree` / `SDBranch` |
|-----------|-----------------------|
| lookup, update | O(1), no allocations |
| insertion | O(1) amortized, O(depth) internal updates |
| `delete!` | O(1) amortized, O(depth) internal updates |
| `prune!` | O(number of removed entries) |
| `view` | O(1) |
| `values_view` | O(1), or O(size of the branch) after deletions |

The `test/check_performance.jl` script measures the average time of a lookup, update, insertion and deletion on an `SDTree`, on a view on half its entries (`SDBranch`), and on a `Dict` with the same content, using `Tuple{Bool, Int, Symbol, String}` keys.  Typical results:

```
julia> include("test/check_performance.jl")
--- Test lookups ---
Dict       (N=    1000), Avg. time:      0.085 μs, Allocated:    0 MB
Dict       (N= 1000000), Avg. time:      0.137 μs, Allocated:    0 MB
SDTree     (N=    1000), Avg. time:      0.143 μs, Allocated:    0 MB
SDTree     (N= 1000000), Avg. time:      0.202 μs, Allocated:    0 MB
SDBranch   (N=     500), Avg. time:      0.068 μs, Allocated:    0 MB
SDBranch   (N=  500000), Avg. time:      0.198 μs, Allocated:    0 MB

--- Test update ---
Dict       (N=    1000), Avg. time:      0.123 μs, Allocated:    0 MB
Dict       (N= 1000000), Avg. time:      0.167 μs, Allocated:    0 MB
SDTree     (N=    1000), Avg. time:      0.152 μs, Allocated:    0 MB
SDTree     (N= 1000000), Avg. time:      0.230 μs, Allocated:    0 MB
SDBranch   (N=     500), Avg. time:      0.214 μs, Allocated:    0 MB
SDBranch   (N=  500000), Avg. time:      0.255 μs, Allocated:    0 MB

--- Test insertion ---
Dict       (N=    1000), Avg. time:      0.053 μs, Allocated:    0 MB
Dict       (N= 1000000), Avg. time:      0.244 μs, Allocated:  164 MB
SDTree     (N=    1000), Avg. time:      0.707 μs, Allocated:    0 MB
SDTree     (N= 1000000), Avg. time:      2.201 μs, Allocated:  530 MB
SDBranch   (N=     500), Avg. time:      0.755 μs, Allocated:    0 MB
SDBranch   (N=  500000), Avg. time:      2.120 μs, Allocated:  218 MB

--- Test delete ---
Dict       (N=    1000, deleted    100 entries), Avg. time:      0.251 μs, Allocated:    0 MB
Dict       (N= 1000000, deleted    100 entries), Avg. time:      0.371 μs, Allocated:    0 MB
SDTree     (N=    1000, deleted    100 entries), Avg. time:      2.234 μs, Allocated:    0 MB
SDTree     (N= 1000000, deleted    100 entries), Avg. time:      4.080 μs, Allocated:    0 MB
SDBranch   (N=     500, deleted    100 entries), Avg. time:      1.954 μs, Allocated:    0 MB
SDBranch   (N=  500000, deleted    100 entries), Avg. time:      4.098 μs, Allocated:    0 MB

--- Test prune ---
SDTree     (N=    1000, deleted    500 entries), Avg. time:      1.016 μs, Allocated:    0 MB
SDTree     (N= 1000000, deleted 500000 entries), Avg. time:      2.757 μs, Allocated:   11 MB
SDBranch   (N=     500, deleted    500 entries), Avg. time:      1.030 μs, Allocated:    0 MB
SDBranch   (N=  500000, deleted 500000 entries), Avg. time:      2.817 μs, Allocated:    8 MB
```
All times are averages *per single entry*: e.g. the prune of 500,000 entries above took about 1.4 s in total.  Allocated memory is the total for the whole test.

In summary:
- lookups and updates show performance comparable to a `Dict` (within a factor of 2), and require no allocations;
- insertions and deletions are roughly **10 times slower** than with a `Dict`, since several internal structures (one per depth level) must be updated;
- `prune!` removes an entire branch in a single call, at a cost of a few microseconds per removed entry (no more than calling `delete!` on each entry, and with no need to find them first);
- operating on a view (`SDBranch`) is as fast as operating on the root tree.

### Memory usage

Each entry is registered in one internal dictionary per depth level, and each distinct prefix has its own internal dictionary.  Hence an `SDTree` uses several times the memory of a `Dict` with the same content: in the benchmark above, where almost every entry has its own depth-3 prefix, about 3x the allocations during insertion, and ~7x the final memory footprint (`Base.summarysize`).  The overhead is smaller when many entries share the same prefixes.

## Limitations

- The data structures are **not thread-safe**: concurrent modifications (or modifications concurrent with reads) require external locking.
- Keys are not converted to the key type (see [Creating a tree](#creating-a-tree)).
- The storage order of values is changed by deletions (the last value is moved into the vacant slot).  Iteration and `values_view` always follow insertion order.
- Functions creating new dictionaries (`copy`, `merge`, `filter`, `empty`) return a `Dict`.

## Version history

- **Unreleased**:
  - `view(tree, key)` on a non-existing complete key now throws a `KeyError` (previously it returned a stale `SDLeaf`);
  - new `get` and `pop!` methods for all data structures;
  - `prune!(tree, ())` removes all entries (previously it threw a `BoundsError`);
  - a failed insertion (hook exception, or value not convertible) no longer corrupts the tree;
  - a previously obtained `values_view` on a branch no longer exposes values of other entries after the branch is emptied;
  - `clean_on_empty_branch` is no longer triggered by deleting or pruning non-existing keys;
  - trees with non-comparable keys (e.g. `Symbol` and `Int` in an `Any` layer) can be displayed.
- **v0.2.0** (breaking): the `keys(::SDTree, level::Int)` and `branches` methods have been removed. Inserting "metadata" with incomplete keys in an `SDTree` is no longer supported: use a `DictTree` instead.

## Disclaimer

This package was developed with the assistance of AI (Gemini), but all code has been manually reviewed and tested for type stability and correctness by the author.
