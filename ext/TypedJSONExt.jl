module TypedJSONExt

using StaticDictTrees, DataStructures

using TypedJSON
import TypedJSON: lower, reconstruct

TypedJSON.lower(sdt::SDTree) = TypedJSON.JSONDict(Symbol("StaticDictTrees.SDTree"), lower(OrderedDict(sdt)).dict)

TypedJSON.reconstruct(::Val{Symbol("StaticDictTrees.SDTree")}, dict) = SDTree(OrderedDict(Pair.(dict[:keys], dict[:vals])))

TypedJSON.reconstruct(::Val{Symbol("StaticDictTrees.TreeLayer")}, dict) = StaticDictTrees.TreeLayer(values(dict)...)

TypedJSON.reconstruct(::Val{Symbol("StaticDictTrees.DictTree")}, dict) = StaticDictTrees.DictTree(values(dict)...)

end
