"""
A named dictionary of computed values registered for use in manuscript prose.

Values are read through [`val`](@ref) rather than by indexing, which is what makes both halves of
the value check possible: an unresolvable path is caught statically instead of aborting a render,
and a registered leaf that prose never reads can be reported as unused.

Keys must be `String` at every depth. A dictionary keyed otherwise is unreachable — no `val` path
can name its leaves — so it is rejected here, where the registry is built, rather than at the read
that would have failed much later.
"""
struct ValueSet
    name::String
    dict::AbstractDict

    function ValueSet(name::AbstractString, dict::AbstractDict)
        _checkkeys(name, dict, String[])
        return new(String(name), dict)
    end
end

# Depth-first, reporting the path of already-valid keys leading to the offending dictionary.
function _checkkeys(name::AbstractString, d::AbstractDict, path::Vector{String})
    for (k, v) in d
        k isa String || throw(
            ArgumentError(
                "ValueSet(\"$name\"): at [$(join((repr(p) for p in path), ", "))], " *
                "key $(repr(k)) has type $(typeof(k)); value keys must be String",
            ),
        )
        v isa AbstractDict && _checkkeys(name, v, [path; k])
    end
    return nothing
end

"The recursive key/type skeleton of a registered value. Compared structurally to group branches."
abstract type Shape end

struct Leaf <: Shape
    type::Type
end

struct Branch <: Shape
    children::Vector{Pair{String,Shape}} # sorted by key
end

Base.:(==)(a::Leaf, b::Leaf) = a.type == b.type
Base.:(==)(a::Branch, b::Branch) = a.children == b.children
Base.:(==)(::Shape, ::Shape) = false
Base.hash(l::Leaf, h::UInt) = hash(l.type, hash(:Leaf, h))
Base.hash(b::Branch, h::UInt) = hash(b.children, hash(:Branch, h))

"""
    shape(x) -> Shape

The key/type skeleton of `x`. Keys are sorted, so two dictionaries with the same contents in
different insertion order compare equal.
"""
function shape(d::AbstractDict)
    ks = sort!(collect(String, keys(d)))
    return Branch([k => shape(d[k]) for k in ks])
end

shape(x) = Leaf(typeof(x))

"""
    leafpaths(d) -> Vector{Vector{String}}

Every root-to-leaf key path in `d`, where a leaf is any value that is not itself a dictionary.
Used by the value check to enumerate what prose could read.
"""
function leafpaths(d::AbstractDict, prefix::Vector{String}=String[])
    out = Vector{String}[]
    for (k, v) in d
        p = [prefix; string(k)]
        if v isa AbstractDict
            append!(out, leafpaths(v, p))
        else
            push!(out, p)
        end
    end
    return out
end

_fmtkeys(ks) = join(("\"$k\"" for k in ks), ", ")

# Bare by default. A comma is the correctness case: grouped keys are comma-joined, so an unquoted
# key containing one would read as two keys.
_fmtkey(k::AbstractString) =
    (isempty(k) || occursin(r"[,\s]", k)) ? repr(String(k)) : String(k)

# Long types wrap badly and are background information; the face already says "this is a type".
function _fmttype(T)
    s = string(T)
    return length(s) > 50 ? string(first(s, 49), '…') : s
end

# Group this branch's children by identical shape, print each distinct shape once. Grouping is
# what keeps a divergent dictionary honest: a union of keys per level would read as though every
# branch had every key.
function _print_shape(io::IO, b::Branch, indent::Int)
    groups = Dict{Shape,Vector{String}}()
    order = Shape[]
    for (k, s) in b.children
        haskey(groups, s) || push!(order, s)
        push!(get!(groups, s, String[]), k)
    end
    pad = "  "^indent
    for s in order
        ks = groups[s]
        if s isa Leaf
            println(io, pad, _fmtkeys(ks), " :: ", s.type)
        else
            println(io, pad, _fmtkeys(ks))
            _print_shape(io, s::Branch, indent + 1)
        end
    end
    return nothing
end

"""
    structure(vs) -> String

The key hierarchy of a value set, one line per level, with the leaf type appended to any line
whose keys are leaves. Sibling subtrees sharing a shape are listed together; subtrees that differ
are printed separately, so divergent branches are visible rather than merged.
"""
function structure(vs::ValueSet)
    io = IOBuffer()
    println(io, vs.name, ": ", length(leafpaths(vs.dict)), " leaves")
    _print_shape(io, shape(vs.dict)::Branch, 1)
    return String(take!(io))
end

Base.show(io::IO, ::MIME"text/plain", vs::ValueSet) = print(io, structure(vs))
Base.show(io::IO, vs::ValueSet) =
    print(io, "ValueSet(", repr(vs.name), ", ", length(leafpaths(vs.dict)), " leaves)")
