"""
Cross-reference check.

Scans `.qmd` text for `ref("key")` calls. For each registry entry it reports whether the entry is
referenced and whether first references appear in ascending numeric order. A registry numbers its
entries by first reference in its own sources, so the order check finds problems only when the
checked sources differ from the registry's. It also reports unknown
keys, `ref(` calls it could not read, hand-typed numbers, adjacent calls that should be merged, and
figure files that do not exist.

Bibliographic citations are checked by [`Hawkeye.Checks.Bib`](@ref).

Run this check before `quarto render`: an unknown key makes `ref` throw, which stops the render at
the first bad call.
"""
module Refs

using PrettyTables

using ...Hawkeye: Registry, AbstractFigure, bucket, number, entry_label
using ..Checks: Source, Call, mask_comments, extract_calls, find_literals, find_adjacent

"""
The result for one registry entry.

`status` is one of `"ok"`, `"UNREFERENCED"`, `"PENDING (no body)"`,
`"OUT OF ORDER (before KEY @FILE:LINE)"`, or
`"UNNUMBERED (not referenced in the registry's sources)"` for an entry the checked sources cite
but the registry dropped. `label` is `"—"` for an entry the registry dropped, since it has no
number. `first` is the file and line of the first reference, or `nothing` when the entry is
unreferenced.
"""
struct RefRow
    key::String
    label::String
    status::String
    first::Union{Tuple{String,Int},Nothing}
end

"""
The result for a set of sources.

`rows` has one row per entry in `reg.entries`, including dropped entries, in registry order. The
other fields list findings that do
not belong to a single entry.
"""
struct Report
    rows::Vector{RefRow}
    unknown::Vector{Tuple{String,String,Int}}      # key, file, line
    unparsed::Vector{Tuple{String,Int}}            # file, line
    literals::Vector{Tuple{String,Int,String}}     # file, line, text
    adjacent::Vector{Tuple{String,Int}}            # file, line
    missing_figures::Vector{Tuple{String,String}}  # key, resolved path
end

"""
    analyze(reg, sources; figdir = ".") -> Report

Check `.qmd` sources against the registry.

Within each `(kind, location)` bucket the first reference to each entry should appear in ascending
order of number, and every entry should be referenced at least once. Later references to the same
entry are ignored for ordering. When a higher-numbered entry is referenced first, its row is marked
out of order and names the lower-numbered entry referenced after it. Checked against the sources
the registry was built from, every first reference is in order and every unreferenced entry is one
the registry dropped.

`figdir` is the directory that figure paths resolve against; pass `nothing` to skip the file
existence check.
"""
function analyze(
    reg::Registry,
    sources::AbstractVector{Source};
    figdir::Union{AbstractString,Nothing}=".",
)
    refs = Tuple{String,String,Int}[] # key, file, line
    unparsed = Tuple{String,Int}[]
    literals = Tuple{String,Int,String}[]
    adjacent = Tuple{String,Int}[]

    for s in sources
        masked = mask_comments(s.text)
        calls, up = extract_calls(masked, "ref")
        for c in calls, a in c.args
            push!(refs, (a, s.path, c.line))
        end
        append!(unparsed, ((s.path, l) for l in up))
        append!(literals, ((s.path, l, t) for (l, t) in find_literals(masked)))
        append!(adjacent, ((s.path, l) for l in find_adjacent(masked, "ref")))
    end

    registered = Set(e.key for e in reg.entries)
    unknown = [(k, f, l) for (k, f, l) in refs if !(k in registered)]

    # first reference per registered key, in source order
    first_at = Dict{String,Tuple{String,Int}}()
    order = String[]
    for (k, f, l) in refs
        (k in registered && !haskey(first_at, k)) || continue
        first_at[k] = (f, l)
        push!(order, k)
    end

    # key => (lower-numbered key first referenced after it, location of that reference)
    violation = Dict{String,Tuple{String,Tuple{String,Int}}}()
    for b in reg.bucket_order
        seq = [k for k in order if haskey(reg.index, k) && bucket(reg.index[k]) == b]
        for i in 2:length(seq)
            if number(reg, seq[i]) < number(reg, seq[i-1])
                violation[seq[i-1]] = (seq[i], first_at[seq[i]])
            end
        end
    end

    rows = map(reg.entries) do e
        key = e.key
        at = get(first_at, key, nothing)
        status = if at === nothing
            "UNREFERENCED"
        elseif key in reg.dropped
            "UNNUMBERED (not referenced in the registry's sources)"
        elseif key in reg.pending
            "PENDING (no body)"
        elseif haskey(violation, key)
            other, (of, ol) = violation[key]
            "OUT OF ORDER (before $other @$of:$ol)"
        else
            "ok"
        end
        label = key in reg.dropped ? "—" : entry_label(reg, key)
        RefRow(key, label, status, at)
    end

    missing_figures = Tuple{String,String}[]
    if figdir !== nothing
        for e in reg.entries
            e isa AbstractFigure || continue
            p = joinpath(figdir, e.path)
            isfile(p) || push!(missing_figures, (e.key, p))
        end
    end

    return Report(rows, unknown, unparsed, literals, adjacent, missing_figures)
end

"""
Whether the report contains findings. Rows with status `"ok"` or `"PENDING (no body)"` are not
findings.
"""
has_findings(r::Report) =
    any(row -> row.status != "ok" && row.status != "PENDING (no body)", r.rows) ||
    !isempty(r.unknown) ||
    !isempty(r.unparsed) ||
    !isempty(r.literals) ||
    !isempty(r.adjacent) ||
    !isempty(r.missing_figures)

_loc(::Nothing) = "—"
_loc(t::Tuple{String,Int}) = "$(t[1]):$(t[2])"

"""
    report_string(report) -> String

Format a report for a terminal: a table with one row per registry entry, then one block per kind
of finding, then a summary line. The table is printed even when there are no findings.
"""
function report_string(r::Report)
    io = IOBuffer()

    data = hcat(
        [row.key for row in r.rows],
        [row.label for row in r.rows],
        [row.status for row in r.rows],
        [_loc(row.first) for row in r.rows],
    )
    # `alignment=:left` is accepted but drops cell padding; use `:l`.
    pretty_table(
        io,
        data;
        column_labels=["key", "number", "status", "first ref"],
        backend=:text,
        alignment=:l,
        display_size=(typemax(Int), typemax(Int)),
    )

    if !isempty(r.unknown)
        println(io, "\nUNKNOWN KEY — not in the registry; these abort quarto render:")
        for (key, f, l) in r.unknown
            println(io, "  $f:$l  ref(\"$key\")")
        end
    end
    if !isempty(r.unparsed)
        println(
            io,
            "\nUNPARSED — ref( call the scanner could not read; put it on one line:",
        )
        for (f, l) in r.unparsed
            println(io, "  $f:$l")
        end
    end
    if !isempty(r.literals)
        println(io, "\nLITERAL — number typed by hand; use ref(\"key\") instead:")
        for (f, l, t) in r.literals
            println(io, "  $f:$l  \"$t\"")
        end
    end
    if !isempty(r.adjacent)
        println(
            io,
            "\nADJACENT — two ref( calls separated only by punctuation; merge them into one " *
            "call so their numbers group:",
        )
        for (f, l) in r.adjacent
            println(io, "  $f:$l")
        end
    end
    if !isempty(r.missing_figures)
        println(io, "\nMISSING FIGURE — registered path does not exist:")
        for (key, p) in r.missing_figures
            println(io, "  $key  $p")
        end
    end

    if has_findings(r)
        println(
            io,
            "\nNumbers follow the order of first reference in the sources. " *
            "Reference with ref(\"key\"); " *
            "never write a number by hand.",
        )
    else
        println(io, "\nAll $(length(r.rows)) entries referenced, in order.")
    end

    return String(take!(io))
end

end # module
