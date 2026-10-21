"""
Static checks over Quarto manuscript sources.

Each check provides `analyze(...) -> Report`, `has_findings(report)` and `report_string(report)`.
`analyze` takes source text rather than file paths. Reading files and setting exit codes is left to
the caller.
"""
module Checks

using PrettyTables

using ..Hawkeye:
    Source,
    Call,
    mask_comments,
    mask_code_blocks,
    extract_calls,
    extract_vec_calls,
    find_literals,
    find_adjacent

include("refs.jl")
include("values.jl")
include("bib.jl")
include("revisions.jl")

end # module
