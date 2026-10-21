# A source that cites each entry once, in the order given, so numbers follow that order.
cite_in_order(entries) =
    Source("cited.qmd", join(("\$(ref(\"$(e.key)\"))" for e in entries), "\n"))

const CHECK_ENTRIES = [
    MainTable("pop1", "Descriptives.", "F1"),
    MainTable("prop_rem", "Proportions.", "F2"),
    SuppTable("def_rem", "Definitions.", "F3"),
    SuppTable("pop2", "More.", "F4"),
    MainFigure("fig_descr", "A figure.", "figs/descr.svg"),
    SuppFigure("fig_high", "Supp figure.", "figs/high.svg"),
]

# Shared registry for check tests. Six entries across all four buckets, plus two value sets.
const CHECKREG = Registry(
    CHECK_ENTRIES,
    [
        ValueSet("descr", Dict("n_0" => 872, "n_6" => 459)),
        ValueSet("props", Dict("Moderate" => Dict("das28" => 0.5))),
    ];
    sources=[cite_in_order(CHECK_ENTRIES)],
    pending=["pop2"],
)

src(text) = Hawkeye.Checks.Source("manuscript.qmd", text)
