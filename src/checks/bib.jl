"""
Bibliography check.

Cross-references `[@key]` citations in `.qmd` sources against the entries of a `.bib` file, and
reports how often each entry is cited. The reference check deliberately ignores citations; this
check covers them, and is separate because it validates a different registry.

Pandoc has four citation spellings and all are recognised: `[@key]`, `[@a; @b]`, `@a [p. 33]`,
and the suppressed-author form `[-@a]`. Fenced code blocks are masked first — a `.qmd` is full of
Julia macros such as `@model` and `@__DIR__` that would otherwise read as citations.
"""
module Bib

using PrettyTables

using ..Checks: Source, mask_comments, mask_code_blocks

"One bibliography entry's usage."
struct BibRow
    key::String
    count::Int
    first::Union{Tuple{String,Int},Nothing}
end

struct Report
    rows::Vector{BibRow}
    uncited::Vector{String}
    missing_keys::Vector{Tuple{String,String,Int}} # key, file, line
end

# `@type{key,` — the key runs to the first comma or whitespace.
const _BIB_ENTRY = r"@\w+\s*\{\s*([^,\s\}]+)\s*,"

"""
    bib_keys(bibtext) -> Vector{String}

Entry keys declared in `.bib` text, in file order.
"""
bib_keys(bibtext::AbstractString) =
    [String(m.captures[1]) for m in eachmatch(_BIB_ENTRY, bibtext)]

# A citation key: optional suppressed-author dash, then the pandoc-legal key character set. The
# lookbehind keeps email addresses and `x@y` expressions from matching. The key must end on an
# alphanumeric/underscore character — pandoc treats a trailing `.` (or other internal punctuation)
# as sentence punctuation, not part of the key, so it must not be swallowed here either.
const _CITE = r"(?<![A-Za-z0-9_])-?@([A-Za-z](?:[A-Za-z0-9_:.#$%&+?<>~/-]*[A-Za-z0-9_])?)"

"""
    citations(masked) -> Vector{Tuple{String,Int}}

Every citation key in masked text, as `(key, line)`, in source order.
"""
function citations(masked::AbstractString)
    hits = Tuple{String,Int}[]
    for (i, line) in enumerate(eachsplit(masked, '\n'))
        for m in eachmatch(_CITE, line)
            push!(hits, (String(m.captures[1]), i))
        end
    end
    return hits
end

"""
    analyze(bibtext, sources) -> Report

Check citations in `sources` against the entries declared in `bibtext`.

Takes the `.bib` text rather than a path, so the check stays pure and testable without files.
`missing_keys` is deduplicated by key, keeping the first occurrence's file and line — repeat
citations of the same undefined key produce one report line, not one per occurrence.
"""
function analyze(bibtext::AbstractString, sources::AbstractVector{Source})
    keys_in_bib = bib_keys(bibtext)
    known = Set(keys_in_bib)

    cites = Tuple{String,String,Int}[] # key, file, line
    for s in sources
        masked = mask_code_blocks(mask_comments(s.text))
        append!(cites, ((k, s.path, l) for (k, l) in citations(masked)))
    end

    counts = Dict{String,Int}()
    first_at = Dict{String,Tuple{String,Int}}()
    missing_keys = Tuple{String,String,Int}[]
    missing_seen = Set{String}()
    for (k, f, l) in cites
        if k in known
            counts[k] = get(counts, k, 0) + 1
            haskey(first_at, k) || (first_at[k] = (f, l))
        elseif k ∉ missing_seen
            push!(missing_keys, (k, f, l))
            push!(missing_seen, k)
        end
    end

    rows = [BibRow(k, get(counts, k, 0), get(first_at, k, nothing)) for k in keys_in_bib]
    uncited = [k for k in keys_in_bib if get(counts, k, 0) == 0]

    return Report(rows, uncited, missing_keys)
end

has_findings(r::Report) = !isempty(r.uncited) || !isempty(r.missing_keys)

_loc(::Nothing) = "—"
_loc(t::Tuple{String,Int}) = "$(t[1]):$(t[2])"

function report_string(r::Report)
    io = IOBuffer()

    data = hcat(
        [row.key for row in r.rows],
        [string(row.count) for row in r.rows],
        [_loc(row.first) for row in r.rows],
    )
    pretty_table(
        io,
        data;
        column_labels=["key", "cited", "first use"],
        backend=:text,
        alignment=:l,
        display_size=(typemax(Int), typemax(Int)),
    )

    if !isempty(r.missing_keys)
        println(
            io,
            "\nMISSING — cited but absent from the .bib; pandoc renders these as ?:",
        )
        for (k, f, l) in r.missing_keys
            println(io, "  $f:$l  [@$k]")
        end
    end
    if !isempty(r.uncited)
        println(io, "\nUNCITED — present in the .bib, never cited:")
        for k in r.uncited
            println(io, "  $k")
        end
    end

    if !has_findings(r)
        println(io, "\nAll $(length(r.rows)) bibliography entries cited.")
    end

    return String(take!(io))
end

end # module
