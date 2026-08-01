# The project-local module that owns the registry. Copy into your project as
# src/manuscript/refs.jl, then `include` it from the .qmd.
#
# Prose then reads:
#   $(ref("pop1"))                    -> "Table 1"
#   $(val("descr", ["n_0"]))          -> 872
module ManuscriptRefs

using Hawkeye

const REM_FOOTER = "DAS28: disease activity score using 28 joints"
const SUPPRESSED_NOTE = "--: less than five events."

const ENTRIES = AbstractEntry[
    MainTable("pop1", "Descriptive statistics at the six months visit.", REM_FOOTER),
    MainTable(
        "prop_rem",
        "Proportions of patients reaching each remission outcome.",
        sanitize_join(REM_FOOTER, SUPPRESSED_NOTE),
    ),
    SuppTable("def_rem", "Definitions and cut-offs of the remission outcomes.", REM_FOOTER),
    MainFigure("fig_descr", "Prescription patterns over time.", "figures/descr.svg"),
    SuppFigure("fig_high", "Proportions in the DAS28 High stratum.", "figures/high.svg"),
]

# Load whatever your analysis wrote. Any AbstractDict works; keys must be String at every depth.
const VALUES = ValueSet[
    ValueSet("descr", Dict("n_0" => 872, "n_6" => 459)),
    ValueSet("props", Dict("Moderate" => Dict("das28_remission" => (e=5, n=10, p="50%")))),
]

# Entries with a number but no rendered body yet. Empty is the goal.
const PENDING = String[]

const REG = Registry(ENTRIES, VALUES; pending=PENDING)

Hawkeye.@bind REG

end
