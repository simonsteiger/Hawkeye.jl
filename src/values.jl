"""
A named dictionary of computed values for use in manuscript prose. Read values with [`val`](@ref).

Keys must be `String` at every depth, because a `val` path can only name `String` keys. The
constructor throws an `ArgumentError` otherwise.
"""
struct ValueSet
    name::String
    dict::AbstractDict

    function ValueSet(name::AbstractString, dict::AbstractDict)
        _checkkeys(name, dict, String[])
        return new(String(name), dict)
    end
end

# `path` holds the keys leading to `d` and is reported in the error message.
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

"""
The keys of a nested dictionary and the types of its leaves. Two shapes are equal when their keys
and leaf types match.
"""
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

The [`Shape`](@ref) of `x`. Keys are sorted, so insertion order does not affect equality.
"""
function shape(d::AbstractDict)
    ks = sort!(collect(String, keys(d)))
    return Branch([k => shape(d[k]) for k in ks])
end

shape(x) = Leaf(typeof(x))

"""
    leafpaths(d) -> Vector{Vector{String}}

The key path to every leaf of `d`. A leaf is any value that is not a dictionary.
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

# A key is quoted only when it is empty or contains a comma or whitespace. Grouped keys are
# comma-separated, so an unquoted comma would read as two keys.
_fmtkey(k::AbstractString) =
    (isempty(k) || occursin(r"[,\s]", k)) ? repr(String(k)) : String(k)

# Long type names are truncated to keep the tree readable.
function _fmttype(T)
    s = string(T)
    return length(s) > 50 ? string(first(s, 49), '…') : s
end

# Fill each line with as many whole tokens as fit in `avail` columns. `seps[i]` precedes
# `tokens[i]`; `seps[1]` is unused. Returns the token indices of each line.
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

# Children with the same shape share one node. Children with different shapes get separate nodes,
# so the tree never shows a key under a branch that lacks it.
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
        # Continuation lines keep the vertical bar that connects to the next sibling. The prefix is
        # as wide as `gutter * connector`.
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

Draw the keys of a value set as a tree, with the type after each leaf. Sibling subtrees with the
same shape share one node; subtrees that differ are drawn separately.

Tree lines, the leaf count and leaf types are dimmed, so the keys stand out. `io` supplies the
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
