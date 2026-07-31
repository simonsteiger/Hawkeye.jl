# Check manuscript cross-references before rendering.
#
#     julia --project=. examples/check_refs.jl
#
# Prints one row per registry entry, then any findings. Exits 1 when anything is outstanding, so
# it can gate a render or a CI job. Loads no study data, so it runs in about a second.
#
# Run this *before* quarto render: an unknown key makes ref throw, which kills the render at the
# first bad call, and no in-document check would ever get to report the rest.

using Hawkeye
using Hawkeye.Checks: Source
using Hawkeye.Checks.Refs

include("manuscript_refs.jl")
using .ManuscriptRefs: REG

const ROOT = dirname(@__DIR__)
const QMDS = [
    joinpath(ROOT, "article", "manuscript", "manuscript.qmd"),
    joinpath(ROOT, "article", "manuscript", "supplementary.qmd"),
]

sources = [Source(p, read(p, String)) for p in QMDS if isfile(p)]
isempty(sources) && error("no manuscript sources found")

report = Refs.analyze(REG, sources; figdir=joinpath(ROOT, "article", "manuscript"))
print(Refs.report_string(report))

Refs.has_findings(report) && exit(1)
