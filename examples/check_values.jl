# Check that every val(...) path resolves, and report registered values prose never reads.
#
#     julia --project=. examples/check_values.jl
#
# An unresolvable path aborts quarto render at the first bad call, so catching them statically
# reports all of them at once. The unused list answers the other question: which computed
# statistics never made it into the paper.

using Hawkeye
using Hawkeye.Checks: Source
using Hawkeye.Checks.Values

include("manuscript_refs.jl")
using .ManuscriptRefs: REG

const ROOT = dirname(@__DIR__)
const QMDS = [joinpath(ROOT, "article", "manuscript", "manuscript.qmd")]

sources = [Source(p, read(p, String)) for p in QMDS if isfile(p)]
isempty(sources) && error("no manuscript sources found")

report = Values.analyze(REG, sources)
print(Values.report_string(report))

# Unused values are informational, so gate only on paths that would break a render.
isempty(report.unknown) || exit(1)
