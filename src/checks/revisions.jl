"""
Validate that quoted manuscript revisions in a reply-to-reviewers letter still exist in the
rendered manuscript text, and that every reviewer comment has a recorded response.

A reply letter is a `.qmd` of fenced divs. A `# Reviewer N` heading sets the reviewer number and
resets the comment counter; each `.comment` div increments it; each `.revision` div is captured
and tagged `R{reviewer}.{comment}`. A `status="..."` attribute on a comment div carries through to
the overview, so the report doubles as a traffic-light view of where each point stands. Statuses
are open strings — the check reports what it finds rather than validating a fixed list.
"""
module Revisions

using PrettyTables

# hyphen/en-dash/em-dash/figure-dash/minus variants -> '-'
const _DASHES = Set{Char}(['‐', '‑', '‒', '–', '—', '―', '−'])
const _DQUOTES = Set{Char}([
    Char(0x201C),
    Char(0x201D),
    Char(0x201E),
    Char(0x201F),
    Char(0x00AB),
    Char(0x00BB),
])
const _SQUOTES = Set{Char}([Char(0x2018), Char(0x2019), Char(0x201A), Char(0x201B)])

"Collapse whitespace to single spaces; straighten curly quotes; unify dashes. Trims ends."
function normalize_text(s::AbstractString)
    buf = IOBuffer()
    for ch in s
        if ch in _DASHES
            print(buf, '-')
        elseif ch in _DQUOTES
            print(buf, '"')
        elseif ch in _SQUOTES
            print(buf, '\'')
        elseif isspace(ch)
            print(buf, ' ')
        else
            print(buf, ch)
        end
    end
    return strip(replace(String(take!(buf)), r" +" => " "))
end

"A single quoted manuscript revision pulled from a reply letter."
struct Revision
    id::String      # "R{reviewer}.{comment}"
    section::String # freeform pointer, "" if none
    status::String  # from the comment div it answers, "" if none
    text::String    # raw joined body; normalized at match time
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

Line-scan a reply `.qmd`, returning the captured revisions and every comment with whether a
revision followed it.
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
                    Revision(
                        "R$reviewer.$comment",
                        section,
                        status,
                        strip(join(body, " ")),
                    ),
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

"Outcome of matching one `Revision` against the manuscript text."
struct Result
    id::String
    status::String
    section::String
    found::Bool
    snippet::String
end

struct Report
    results::Vector{Result}
    orphans::Vector{Comment}
end

"""
    analyze(reply_qmd, manuscript_text) -> Report

Normalize both sides, then test each revision's text as a substring of the manuscript text. Empty
revision text never matches. Comments with no recorded revision are returned as orphans.
"""
function analyze(reply_qmd::AbstractString, manuscript_text::AbstractString)
    revisions, comments = extract(reply_qmd)
    hay = normalize_text(manuscript_text)
    results = map(revisions) do r
        needle = normalize_text(r.text)
        found = !isempty(needle) && occursin(needle, hay)
        Result(r.id, r.status, r.section, found, first(needle, 60))
    end
    return Report(results, [c for c in comments if !c.responded])
end

"Read manuscript plain text from one or more paths; convert `.docx` via pandoc."
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

has_findings(r::Report) = any(!x.found for x in r.results) || !isempty(r.orphans)

function report_string(r::Report)
    io = IOBuffer()

    data = hcat(
        [x.id for x in r.results],
        [isempty(x.status) ? "—" : x.status for x in r.results],
        [isempty(x.section) ? "—" : x.section for x in r.results],
        [x.found ? "ok" : "MISSING" for x in r.results],
    )
    pretty_table(
        io,
        data;
        column_labels=["id", "status", "section", "quote"],
        backend=:text,
        alignment=:l,
        display_size=(typemax(Int), typemax(Int)),
    )

    misses = [x for x in r.results if !x.found]
    if !isempty(misses)
        println(io, "\nMISSING — quote not found in the manuscript:")
        for x in misses
            println(io, "  $(x.id): \"$(x.snippet)…\"")
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
