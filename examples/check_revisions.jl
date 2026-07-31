# Validate that quoted revisions in the reply letter still exist in the rendered manuscript, and
# that every reviewer comment has a recorded response.
#
#     julia --project=. examples/check_revisions.jl
#     julia --project=. examples/check_revisions.jl --strict
#
# Requires the manuscript docx to be rendered first.

using Hawkeye
using Hawkeye.Checks.Revisions

const ROOT = dirname(@__DIR__)
const REPLY = joinpath(ROOT, "article", "reply", "reply.qmd")
const DOCX = [
    joinpath(ROOT, "article", "manuscript", "manuscript.docx"),
    joinpath(ROOT, "article", "manuscript", "supplementary.docx"),
]

existing = filter(isfile, DOCX)
isempty(existing) && error("no rendered manuscript docx found; render the manuscript first")

report = Revisions.analyze(read(REPLY, String), Revisions.manuscript_plaintext(existing))
print(Revisions.report_string(report))

"--strict" in ARGS && Revisions.has_findings(report) && exit(1)
