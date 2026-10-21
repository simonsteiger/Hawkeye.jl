"""
Reply-letter check.

Checks that the manuscript passages quoted in a reply-to-reviewers letter appear in the rendered
manuscript text, and that every reviewer comment has a revision.

A reply letter is a `.qmd` of fenced divs. A `# Reviewer N` heading sets the reviewer number and
restarts comment numbering. Each `.comment` div is one comment, and each `.revision` div gets the
id `R{reviewer}.{comment}` of the comment before it. A `status="..."` attribute on a comment div is
shown in the report; any string is accepted.

Each line of a `.revision` div is matched separately and may appear anywhere in the manuscript.
Quote marks and inline markup are ignored on both sides. `[...]` in a quote stands for an omitted
citation. A citation, footnote or link that is not replaced by `[...]` must appear in the quote as
it does in the manuscript, or the line is reported missing.
"""
module Revisions

using PrettyTables

# hyphen/en-dash/em-dash/figure-dash/minus variants -> '-'
const _DASHES = Set{Char}(['‐', '‑', '‒', '–', '—', '―', '−'])
const _DQUOTES = Set{Char}([
    '"',
    Char(0x201C),
    Char(0x201D),
    Char(0x201E),
    Char(0x201F),
    Char(0x00AB),
    Char(0x00BB),
])
const _SQUOTES = Set{Char}([Char(0x2018), Char(0x2019), Char(0x201A), Char(0x201B)])

# emphasis, inline code, hard line break, math delimiters, super/subscript
const _MARKUP = Set{Char}(['*', '_', '`', '\\', '$', '^', '~'])

"""
Collapse whitespace to single spaces, replace dash variants with `-` and curly apostrophes with
`'`, delete double quotes and inline markup characters, and trim the ends. Applied to both the
quoted revision and the manuscript, so that quoting and emphasis do not affect matching.
"""
function normalize_text(s::AbstractString)
    buf = IOBuffer()
    for ch in s
        if ch in _DASHES
            print(buf, '-')
        elseif ch in _SQUOTES
            print(buf, '\'')
        elseif ch in _DQUOTES || ch in _MARKUP
            continue
        elseif isspace(ch)
            print(buf, ' ')
        else
            print(buf, ch)
        end
    end
    return strip(replace(String(take!(buf)), r" +" => " "))
end

# blockquote, bullet, or ordered-list marker at the start of a line
const _BLOCK_MARKER = r"^(?:>+\s*|[-+*]\s+|\d+\.\s+)"

"""
    line_needles(line) -> Vector{String}

The normalised fragments of one revision line that must each appear in the manuscript. A leading
block marker is dropped, the line is split at `[...]`, and fragments without a letter or digit are
discarded.
"""
function line_needles(line::AbstractString)
    body = normalize_text(replace(strip(line), _BLOCK_MARKER => ""))
    needles = String[]
    for frag in eachsplit(body, "[...]")
        f = strip(frag)
        any(c -> isletter(c) || isdigit(c), f) && push!(needles, String(f))
    end
    return needles
end

"A single quoted manuscript revision pulled from a reply letter."
struct Revision
    id::String              # "R{reviewer}.{comment}"
    section::String         # freeform pointer, "" if none
    status::String          # from the comment div it answers, "" if none
    lines::Vector{String}   # div body lines, unprocessed
end

"A reviewer comment and whether a revision was recorded for it."
struct Comment
    id::String
    status::String
    responded::Bool
end

const _FENCE_OPEN = r"^:{3,}\s*\{([^}]*)\}\s*$"
const _FENCE_CLOSE = r"^:{3,}\s*$"
const _REVIEWER = r"^#\s+Reviewer\s+(\d+)"

_has_class(attr::AbstractString, name::AbstractString) =
    occursin(Regex("(?:^|\\s)\\.\\Q$name\\E(?:\\s|\$)"), attr)

function _attr(attr::AbstractString, name::AbstractString)
    m = match(Regex("$name\\s*=\\s*\"([^\"]*)\""), attr)
    return m === nothing ? "" : String(m.captures[1])
end

"""
    extract(qmd) -> (revisions, comments)

Parse a reply `.qmd` into its revisions and comments. Each comment records whether a revision
follows it.
"""
function extract(qmd::AbstractString)
    revisions = Revision[]
    comments = Comment[]
    reviewer = 0
    comment = 0
    status = ""
    inrev = false
    section = ""
    body = String[]

    for line in eachsplit(qmd, '\n')
        if inrev
            if occursin(_FENCE_CLOSE, line)
                push!(
                    revisions,
                    Revision("R$reviewer.$comment", section, status, copy(body)),
                )
                if !isempty(comments) && comments[end].id == "R$reviewer.$comment"
                    comments[end] = Comment(comments[end].id, comments[end].status, true)
                end
                inrev = false
                empty!(body)
            else
                push!(body, String(line))
            end
            continue
        end

        mr = match(_REVIEWER, line)
        if mr !== nothing
            reviewer = parse(Int, mr.captures[1])
            comment = 0
            continue
        end

        fo = match(_FENCE_OPEN, line)
        if fo !== nothing
            attr = fo.captures[1]
            if _has_class(attr, "comment")
                comment += 1
                status = _attr(attr, "status")
                push!(comments, Comment("R$reviewer.$comment", status, false))
            elseif _has_class(attr, "revision")
                inrev = true
                section = _attr(attr, "section")
                empty!(body)
            end
        end
    end
    return revisions, comments
end

"A revision line absent from the manuscript."
struct Miss
    line::Int       # index among the revision's content-bearing lines
    snippet::String
end

"Outcome of matching one `Revision` against the manuscript text."
struct Result
    id::String
    status::String
    section::String
    nlines::Int     # content-bearing lines in the revision div
    misses::Vector{Miss}
end

"""
    found(r::Result) -> Bool

Whether every content-bearing line of the revision appears in the manuscript. A revision div
without such a line is never found.
"""
found(r::Result) = r.nlines > 0 && isempty(r.misses)

struct Report
    results::Vector{Result}
    orphans::Vector{Comment}
end

"First 60 characters of a raw revision line, ellipsised when cut."
function _snippet(line::AbstractString)
    s = strip(line)
    return length(s) <= 60 ? String(s) : first(s, 60) * "…"
end

"""
    analyze(reply_qmd, manuscript_text) -> Report

Normalise both texts, then test each revision line as a substring of the manuscript text. Lines
with no content are skipped; a revision with no content-bearing line is reported as a miss.
Comments without a revision are returned in `orphans`.
"""
function analyze(reply_qmd::AbstractString, manuscript_text::AbstractString)
    revisions, comments = extract(reply_qmd)
    hay = normalize_text(manuscript_text)
    results = map(revisions) do r
        content = [
            (l, ns) for (l, ns) in ((l, line_needles(l)) for l in r.lines) if !isempty(ns)
        ]
        misses = [
            Miss(i, _snippet(l)) for
            (i, (l, ns)) in enumerate(content) if !all(n -> occursin(n, hay), ns)
        ]
        Result(r.id, r.status, r.section, length(content), misses)
    end
    return Report(results, [c for c in comments if !c.responded])
end

"Read and join the text of the files at `paths`. `.docx` files are converted with pandoc."
function manuscript_plaintext(paths::AbstractVector{<:AbstractString})
    texts = String[]
    for p in paths
        if endswith(lowercase(p), ".docx")
            push!(texts, read(`pandoc $p -t plain --wrap=none`, String))
        else
            push!(texts, read(p, String))
        end
    end
    return join(texts, "\n")
end

has_findings(r::Report) = any(!found(x) for x in r.results) || !isempty(r.orphans)

"How much of a revision is missing, for the overview table."
_quote_cell(x::Result) =
    x.nlines == 0 ? "empty" :
    isempty(x.misses) ? "ok" : "MISSING $(length(x.misses))/$(x.nlines)"

function report_string(r::Report)
    io = IOBuffer()

    data = hcat(
        [x.id for x in r.results],
        [isempty(x.status) ? "—" : x.status for x in r.results],
        [isempty(x.section) ? "—" : x.section for x in r.results],
        [_quote_cell(x) for x in r.results],
    )
    pretty_table(
        io,
        data;
        column_labels=["id", "status", "section", "quote"],
        backend=:text,
        alignment=:l,
        display_size=(typemax(Int), typemax(Int)),
    )

    misses = [x for x in r.results if !found(x)]
    if !isempty(misses)
        println(io, "\nMISSING — quote not found in the manuscript:")
        for x in misses
            if x.nlines == 0
                println(io, "  $(x.id): (empty revision div)")
            else
                for m in x.misses
                    println(io, "  $(x.id) (line $(m.line) of $(x.nlines)): $(m.snippet)")
                end
            end
        end
        println(io, "\nPaste the exact sentence from the rendered manuscript.")
    end
    if !isempty(r.orphans)
        println(io, "\nORPHAN — reviewer comment with no recorded revision:")
        for c in r.orphans
            println(io, "  $(c.id)$(isempty(c.status) ? "" : " [$(c.status)]")")
        end
    end

    if !has_findings(r)
        println(io, "\nAll $(length(r.results)) revisions verified.")
    end

    return String(take!(io))
end

end # module
