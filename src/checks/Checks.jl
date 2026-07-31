"""
Static checks over Quarto manuscript sources.

Every check exposes the same triple: a pure `analyze(...) -> Report`, plus `has_findings(report)`
and `report_string(report)`. All IO and exit-code handling belongs in the caller's scripts, so a
check can be tested against inline string fixtures with no files on disk.
"""
module Checks

using PrettyTables

using ..Hawkeye:
    Hawkeye,
    Registry,
    AbstractEntry,
    AbstractFigure,
    ValueSet,
    bucket,
    number,
    entry_label,
    leafpaths

include("scan.jl")

end # module
