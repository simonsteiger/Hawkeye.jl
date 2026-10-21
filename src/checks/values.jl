"""
Value check.

Scans `.qmd` text for `val("set", ["key", ...])` calls. Reports paths that do not resolve, which
would stop a render at the first bad call, and registered leaves that no source reads.

Only calls with a literal name and a literal path can be checked. Other calls are reported as
unparsed.
"""
module Values

using PrettyTables

using ...Hawkeye: Registry, leafpaths
using ..Checks: Source, mask_comments, extract_vec_calls

"The number of leaves in one value set and how many of them are read."
struct ValRow
    name::String
    leaves::Int
    referenced::Int
end

struct Report
    rows::Vector{ValRow}
    unknown::Vector{Tuple{Vector{String},String,Int}} # path, file, line
    unused::Vector{Vector{String}}                    # set name prepended
    unparsed::Vector{Tuple{String,Int}}               # file, line
end

"""
    analyze(reg, sources) -> Report

Check every `val(...)` call in `sources` against the registry's value sets.

A path is referenced only when it names a leaf. A path that ends on a nested dictionary is reported
as unknown, because it would insert the whole dictionary into the prose.
"""
function analyze(reg::Registry, sources::AbstractVector{Source})
    read_paths = Tuple{Vector{String},String,Int}[]
    unparsed = Tuple{String,Int}[]

    for s in sources
        masked = mask_comments(s.text)
        calls, up = extract_vec_calls(masked, "val")
        for c in calls
            push!(read_paths, (c.args, s.path, c.line))
        end
        append!(unparsed, ((s.path, l) for l in up))
    end

    # every registered leaf path, starting with the set name
    all_leaves = Set{Vector{String}}()
    per_set = Dict{String,Vector{Vector{String}}}()
    for v in reg.values
        ls = [[v.name; p] for p in leafpaths(v.dict)]
        per_set[v.name] = ls
        union!(all_leaves, ls)
    end

    unknown = Tuple{Vector{String},String,Int}[]
    referenced = Set{Vector{String}}()
    for (p, f, l) in read_paths
        if p in all_leaves
            push!(referenced, p)
        else
            push!(unknown, (p, f, l))
        end
    end

    rows = [
        ValRow(v.name, length(per_set[v.name]), count(in(referenced), per_set[v.name]))
        for v in reg.values
    ]
    unused = sort!([p for p in all_leaves if !(p in referenced)])

    return Report(rows, unknown, unused, unparsed)
end

has_findings(r::Report) = !isempty(r.unknown) || !isempty(r.unused) || !isempty(r.unparsed)

# Formats a path as the `val` call that reads it.
_fmtcall(p::Vector{String}) =
    "val(" * repr(p[1]) * ", [" * join((repr(k) for k in p[2:end]), ", ") * "])"

function report_string(r::Report)
    io = IOBuffer()

    data = hcat(
        [row.name for row in r.rows],
        [string(row.leaves) for row in r.rows],
        [string(row.referenced) for row in r.rows],
        [string(row.leaves - row.referenced) for row in r.rows],
    )
    pretty_table(
        io,
        data;
        column_labels=["value set", "leaves", "used", "unused"],
        backend=:text,
        alignment=:l,
        display_size=(typemax(Int), typemax(Int)),
    )

    if !isempty(r.unknown)
        println(io, "\nUNKNOWN PATH — does not resolve; these abort quarto render:")
        for (p, f, l) in r.unknown
            println(io, "  $f:$l  $(_fmtcall(p))")
        end
    end
    if !isempty(r.unparsed)
        println(
            io,
            "\nUNPARSED — val( call the scanner could not read; put it on one line:",
        )
        for (f, l) in r.unparsed
            println(io, "  $f:$l")
        end
    end
    if !isempty(r.unused)
        println(io, "\nUNUSED — registered but never read by any source:")
        for p in r.unused
            println(io, "  $(_fmtcall(p))")
        end
    end

    if !has_findings(r)
        total = isempty(r.rows) ? 0 : sum(row.leaves for row in r.rows)
        println(io, "\nAll $total registered values read.")
    end

    return String(take!(io))
end

end # module
