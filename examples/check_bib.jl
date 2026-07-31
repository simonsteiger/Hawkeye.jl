# Check citations against the bibliography.
#
#     julia --project=. examples/check_bib.jl
#
# Reports how often each .bib entry is cited, entries that are never cited, and citations with no
# matching entry (which pandoc renders as "?").

using Hawkeye
using Hawkeye.Checks: Source
using Hawkeye.Checks.Bib

const ROOT = dirname(@__DIR__)
const BIB = joinpath(ROOT, "article", "manuscript", "bibliography.bib")
const QMDS = [joinpath(ROOT, "article", "manuscript", "manuscript.qmd")]

sources = [Source(p, read(p, String)) for p in QMDS if isfile(p)]
report = Bib.analyze(read(BIB, String), sources)
print(Bib.report_string(report))

# A missing key breaks the rendered bibliography; an uncited entry is only untidy.
isempty(report.missing_keys) || exit(1)
