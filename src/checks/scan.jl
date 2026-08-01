"One `.qmd` source under check. `path` is used only to label findings."
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

Blank out every `<!-- ... -->` comment, replacing each with as many newlines as it spanned.

Line numbers downstream stay correct, which every finding depends on. Masking applies to call
extraction as well as literal detection: commented text never reaches rendered output, so a
number inside a comment misleads nobody and a commented-out `ref("x")` must not count as a
reference to `x`.
"""
mask_comments(text::AbstractString) =
    replace(text, r"<!--.*?-->"s => m -> "\n"^count(==('\n'), m))

"""
    mask_code_blocks(text) -> String

Blank out fenced code blocks, preserving line count.

Used by the bibliography check only. A `.qmd` code block is full of Julia macros — `@model`,
`@__DIR__` — that a citation scanner would otherwise read as `@key` citations. Inline code spans
are deliberately left intact, because `ref` calls legitimately live in `` `{julia} ref("k")` ``
spans.
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

# A full `f("a", "b")` call. Capture group 1 is the comma-separated quoted argument list.
_call_regex(fname::AbstractString) =
    Regex("\\b" * fname * "\\(\\s*(\"[^\"]*\"(?:\\s*,\\s*\"[^\"]*\")*)\\s*\\)")

# Any `f(` opening, parsed or not. Counted against the full regex to catch calls it misses.
_open_regex(fname::AbstractString) = Regex("\\b" * fname * "\\(")

# One double-quoted argument inside a captured argument list.
const _QUOTED = r"\"([^\"]*)\""

"""
    extract_calls(masked, fname) -> (calls, unparsed)

Pull every `fname("a", ...)` call with literal string arguments out of masked `.qmd` text.

`calls` is in source order, preserving order within a line — which matters, since two calls can
share a line and their interleaving decides the reference order verdict.

`unparsed` lists lines where a bare `fname(` outnumbers the calls the regex could read. A call
split across lines, or written with a non-literal argument, lands here instead of silently
vanishing and reading as an unreferenced entry.
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

# A full `f("name", ["a", "b"])` call. Group 1 is the name, group 2 the bracketed argument list,
# which is `nothing` for an empty vector.
_vec_call_regex(fname::AbstractString) = Regex(
    "\\b" *
    fname *
    "\\(\\s*\"([^\"]*)\"\\s*,\\s*" *
    "\\[\\s*(\"[^\"]*\"(?:\\s*,\\s*\"[^\"]*\")*)?\\s*\\]\\s*\\)",
)

"""
    extract_vec_calls(masked, fname) -> (calls, unparsed)

Pull every `fname("name", ["a", ...])` call with a literal name and a literal path vector out of
masked `.qmd` text. Each `Call.args` is the name followed by the path elements.

`unparsed` lists lines where a bare `fname(` outnumbers the calls the regex could read. A call
split across lines, or one whose path comes from a helper function, lands here. A helper's path
cannot be resolved without evaluating it — the aliasing problem this check exists to prevent — so
such calls are reported rather than silently dropped, which would read as unused leaves.
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

A number written directly in prose bypasses the registry and goes stale the moment entries are
reordered. Since `ref` interpolates its result, source text never contains a registry-produced
number — every hit is hand-typed.
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

Lines carrying two `fname(` calls separated only by punctuation.

Such calls should be merged: each call groups only its own arguments, so
`\$(ref("figA", "tabA")), \$(ref("tabB", "figB"))` renders four separate labels instead of
grouping the two tables and the two figures. Merged into one call it renders correctly.

The gap between two calls disqualifies the pair when it contains any alphanumeric character
(real prose separates them, so they are deliberately distinct) or a semicolon (a deliberate
clause break).
"""
function find_adjacent(masked::AbstractString, fname::AbstractString)
    callre = _call_regex(fname)
    hits = Int[]
    for (i, line) in enumerate(eachsplit(masked, '\n'))
        ms = collect(eachmatch(callre, line))
        for j in 2:length(ms)
            # byte arithmetic: RegexMatch.offset is a byte index, so ncodeunits, not length
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
