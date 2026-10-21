"One `.qmd` source. `path` is used only to label findings and error messages."
struct Source
    path::String
    text::String
end

"A parsed call with literal string arguments. `first`/`last` are byte offsets within `line`'s text."
struct Call
    args::Vector{String}
    line::Int
    first::Int
    last::Int
end

"""
    mask_comments(text) -> String

Replace every `<!-- ... -->` comment with as many newlines as it spans, so line numbers stay the
same.
"""
mask_comments(text::AbstractString) =
    replace(text, r"<!--.*?-->"s => m -> "\n"^count(==('\n'), m))

"""
    mask_code_blocks(text) -> String

Blank out fenced code blocks, keeping the line count. Inline code spans are kept, because `ref`
calls are written in `` `{julia} ref("k")` `` spans.
"""
function mask_code_blocks(text::AbstractString)
    out = IOBuffer()
    infence = false
    lines = collect(eachsplit(text, '\n'))
    for (i, line) in enumerate(lines)
        if startswith(lstrip(line), "```")
            infence = !infence
            print(out, "")
        elseif !infence
            print(out, line)
        end
        i < length(lines) && print(out, '\n')
    end
    return String(take!(out))
end

# Matches a complete `f("a", "b")` call. Group 1 is the quoted argument list.
_call_regex(fname::AbstractString) =
    Regex("\\b" * fname * "\\(\\s*(\"[^\"]*\"(?:\\s*,\\s*\"[^\"]*\")*)\\s*\\)")

# Matches any `f(`, including calls that `_call_regex` cannot read.
_open_regex(fname::AbstractString) = Regex("\\b" * fname * "\\(")

# One double-quoted argument inside a captured argument list.
const _QUOTED = r"\"([^\"]*)\""

"""
    extract_calls(masked, fname) -> (calls, unparsed)

Find every `fname("a", ...)` call with literal string arguments in masked `.qmd` text.

`calls` is in source order, including the order of calls on the same line.

`unparsed` lists lines with more `fname(` than readable calls. This happens when a call spans
several lines or has a non-literal argument.
"""
function extract_calls(masked::AbstractString, fname::AbstractString)
    callre = _call_regex(fname)
    openre = _open_regex(fname)
    calls = Call[]
    unparsed = Int[]
    for (i, line) in enumerate(eachsplit(masked, '\n'))
        opened = count(openre, line)
        parsed = 0
        for m in eachmatch(callre, line)
            parsed += 1
            args = [String(q.captures[1]) for q in eachmatch(_QUOTED, m.captures[1])]
            push!(calls, Call(args, i, m.offset, m.offset + ncodeunits(m.match) - 1))
        end
        opened > parsed && push!(unparsed, i)
    end
    return calls, unparsed
end

# Matches a complete `f("name", ["a", "b"])` call. Group 1 is the name and group 2 the contents of
# the brackets, which is `nothing` for an empty vector.
_vec_call_regex(fname::AbstractString) = Regex(
    "\\b" *
    fname *
    "\\(\\s*\"([^\"]*)\"\\s*,\\s*" *
    "\\[\\s*(\"[^\"]*\"(?:\\s*,\\s*\"[^\"]*\")*)?\\s*\\]\\s*\\)",
)

"""
    extract_vec_calls(masked, fname) -> (calls, unparsed)

Find every `fname("name", ["a", ...])` call with a literal name and a literal path vector in
masked `.qmd` text. Each `Call.args` is the name followed by the path elements.

`unparsed` lists lines with more `fname(` than readable calls. This happens when a call spans
several lines or its path is not a literal vector.
"""
function extract_vec_calls(masked::AbstractString, fname::AbstractString)
    callre = _vec_call_regex(fname)
    openre = _open_regex(fname)
    calls = Call[]
    unparsed = Int[]
    for (i, line) in enumerate(eachsplit(masked, '\n'))
        opened = count(openre, line)
        parsed = 0
        for m in eachmatch(callre, line)
            parsed += 1
            path = if m.captures[2] === nothing
                String[]
            else
                [String(q.captures[1]) for q in eachmatch(_QUOTED, m.captures[2])]
            end
            args = [String(m.captures[1]); path]
            push!(calls, Call(args, i, m.offset, m.offset + ncodeunits(m.match) - 1))
        end
        opened > parsed && push!(unparsed, i)
    end
    return calls, unparsed
end

"A table or figure number typed by hand rather than produced by `ref`."
const _LITERAL = r"(?:supplementary\s+)?(?:Table|Figure)s?\s+\d+"

"""
    find_literals(masked) -> Vector{Tuple{Int,String}}

Find hand-typed table and figure numbers, as `(line, text)`.

`ref` calls produce their numbers at render time, so any number in the source text was typed by
hand.
"""
function find_literals(masked::AbstractString)
    hits = Tuple{Int,String}[]
    for (i, line) in enumerate(eachsplit(masked, '\n'))
        for m in eachmatch(_LITERAL, line)
            push!(hits, (i, String(m.match)))
        end
    end
    return hits
end

"""
    find_adjacent(masked, fname) -> Vector{Int}

Lines with two `fname(` calls separated only by punctuation.

Such calls should be merged, because each call groups only its own arguments:
`\$(ref("figA", "tabA")), \$(ref("tabB", "figB"))` renders four separate labels, where one call
would group the two tables and the two figures.

A pair is not reported when the text between the calls contains a letter, a digit or a semicolon.
"""
function find_adjacent(masked::AbstractString, fname::AbstractString)
    callre = _call_regex(fname)
    hits = Int[]
    for (i, line) in enumerate(eachsplit(masked, '\n'))
        ms = collect(eachmatch(callre, line))
        for j in 2:length(ms)
            # `RegexMatch.offset` is a byte index, so the match is measured with `ncodeunits`.
            from = ms[j-1].offset + ncodeunits(ms[j-1].match)
            to = prevind(line, ms[j].offset)
            gap = from > to ? "" : SubString(line, from, to)
            if !occursin(r"[[:alnum:]]", gap) && !occursin(';', gap)
                push!(hits, i)
                break
            end
        end
    end
    return hits
end
