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

# Bare by default. A comma is the correctness case: grouped keys are comma-joined, so an unquoted
# key containing one would read as two keys.
_fmtkey(k::AbstractString) =
    (isempty(k) || occursin(r"[,\s]", k)) ? repr(String(k)) : String(k)

# Long types wrap badly and are background information; the face already says "this is a type".
function _fmttype(T)
    s = string(T)
    return length(s) > 50 ? string(first(s, 49), '…') : s
end

# Greedy wrap over indivisible tokens. `seps[i]` precedes `tokens[i]`; `seps[1]` is unused.
# Returns the token indices belonging to each line.
function _wraplines(
    tokens::Vector{Pair{String,Union{Nothing,Symbol}}},
    seps::Vector{String},
    avail::Int,
)
    lines = [[1]]
    w = textwidth(first(tokens[1]))
    for i in 2:length(tokens)
        add = textwidth(seps[i]) + textwidth(first(tokens[i]))
        if w + add <= avail
            push!(lines[end], i)
            w += add
        else
            push!(lines, [i])
            w = textwidth(first(tokens[i]))
        end
    end
    return lines
end

_faced(text::AbstractString, ::Nothing) = text
_faced(text::AbstractString, f::Symbol) = styled"{$f:$text}"

function _emit!(out, gutter, connector, contprefix, tokens, seps, width)
    avail = max(width - textwidth(gutter) - textwidth(connector), 1)
    for (j, idxs) in enumerate(_wraplines(tokens, seps, avail))
        prefix = j == 1 ? gutter * connector : contprefix
        pieces = Any[styled"{hawkeye_tree:$prefix}"]
        for (n, i) in enumerate(idxs)
            n > 1 && push!(pieces, seps[i])
            push!(pieces, _faced(first(tokens[i]), last(tokens[i])))
        end
        push!(out, annotatedstring(pieces...))
    end
    return nothing
end

# Group this branch's children by identical shape and print each distinct shape once. Grouping is
# what keeps a divergent dictionary honest: a union of keys per level would read as though every
# branch had every key.
function _walk!(out::Vector{AbstractString}, b::Branch, gutter::AbstractString, width::Int)
    groups = Dict{Shape,Vector{String}}()
    order = Shape[]
    for (k, s) in b.children
        haskey(groups, s) || push!(order, s)
        push!(get!(groups, s, String[]), k)
    end
    for (i, s) in enumerate(order)
        ks = groups[s]
        islast = i == length(order)
        connector = islast ? "└─ " : "├─ "
        # A wrapped line must keep the vertical bar, or the sibling chain breaks wherever a wrap
        # happens to fall. This prefix is exactly as wide as `gutter * connector`.
        contprefix = gutter * (islast ? "   " : "│  ")
        tokens = Pair{String,Union{Nothing,Symbol}}[]
        seps = String[]
        for (j, k) in enumerate(ks)
            text = j < length(ks) ? _fmtkey(k) * "," : _fmtkey(k)
            push!(tokens, text => nothing)
            push!(seps, j == 1 ? "" : " ")
        end
        if s isa Leaf
            push!(tokens, _fmttype(s.type) => :hawkeye_type)
            push!(seps, "  ")
        end
        _emit!(out, gutter, connector, contprefix, tokens, seps, width)
        s isa Branch && _walk!(out, s, contprefix, width)
    end
    return out
end

"""
    structure(vs, io = devnull) -> AnnotatedString

The key hierarchy of a value set drawn as a tree, with the leaf type after each leaf node. Sibling
subtrees sharing a shape are listed on one node; subtrees that differ are drawn separately, so
divergent branches are visible rather than merged.

Everything structural — glyphs, leaf count, leaf types — is dimmed, leaving the keys as the only
default-weight text, since the keys are what a `val` path is written from. `io` supplies the
wrapping width; without it the output is 80 columns wide.
"""
function structure(vs::ValueSet, io::IO=devnull)
    width = displaysize(io)[2]
    n = length(leafpaths(vs.dict))
    unit = n == 1 ? "leaf" : "leaves"
    tail = "· $n $unit"
    out = AbstractString[annotatedstring(
        styled"{hawkeye_name:$(vs.name)}",
        " ",
        styled"{hawkeye_count:$tail}",
    )]
    _walk!(out, shape(vs.dict)::Branch, "", width)
    return annotatedstring(join(out, "\n"), "\n")
end

Base.show(io::IO, ::MIME"text/plain", vs::ValueSet) = print(io, structure(vs, io))
Base.show(io::IO, vs::ValueSet) =
    print(io, "ValueSet(", repr(vs.name), ", ", length(leafpaths(vs.dict)), " leaves)")
