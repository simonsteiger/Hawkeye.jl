# Hawkeye

[![Build Status](https://github.com/simonsteiger/Hawkeye.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/simonsteiger/Hawkeye.jl/actions/workflows/CI.yml?query=branch%3Amain)

Numbering and validation for Quarto research manuscripts written in Julia.

Table and figure numbers are derived from a registry, never typed. Computed statistics are read
through a checkable accessor, never indexed. Four static checks then report what is wrong before
`quarto render` does.

## The registry

Declare entries and values once, in a small project module, and bind them:

```julia
module ManuscriptRefs
using Hawkeye

const ENTRIES = AbstractEntry[
    MainTable("pop1", "Descriptive statistics at six months.", "DAS28: disease activity score"),
    SuppTable("def_rem", "Definitions of the remission outcomes.", "DAS28: disease activity score"),
    MainFigure("fig_descr", "Prescription patterns over time.", "figures/descr.svg"),
]

const VALUES = ValueSet[
    ValueSet("descr", load("output/descr_dict.jld2", "descr_dict")),
]

const REG = Registry(ENTRIES, VALUES)
Hawkeye.@bind REG
end
```

An entry's number is its position within its `(kind, location)` bucket, taken from declaration
order. Reorder `ENTRIES` and every number follows.

## In prose

```markdown
Patients were followed for six months ($(ref("pop1"))).
Definitions appear in $(ref("def_rem", "fig_descr")).
The cohort included $(val("descr", ["n_0"])) patients.
```

`ref` groups its arguments by bucket, sorts them, collapses runs of three or more to a range, and
joins them BMJ-style. Argument order does not affect the result. Passing several keys to one call
is what lets them group — two adjacent calls cannot merge, and the reference check reports that
as `ADJACENT`.

## Inspecting a value set

Deeply nested result dictionaries are opaque when writing prose. `structure` draws the key
hierarchy as a tree, grouping sibling subtrees that share a shape:

```julia
julia> ManuscriptRefs.REG.values[1]
descr · 4 leaves
└─ High, Moderate
   └─ das28_remission, sdai_remission
      @NamedTuple{e::Int64, n::Int64, p::String}
```

Glyphs, the leaf count and the leaf types are dimmed, leaving the keys — which is what a `val`
path is written from — as the only foreground text. The four faces are `hawkeye_name`,
`hawkeye_count`, `hawkeye_tree` and `hawkeye_type`, restylable from a `faces.toml`.

Value dictionary keys must be `String` at every depth; a `ValueSet` built from a dictionary keyed
otherwise throws, naming the offending key and the path to it.

`vs.dict` returns the raw dictionary with its ordinary display.

## Checks

Each check is a pure `analyze` returning a report, plus `has_findings` and `report_string`. IO and
exit codes live in your scripts — see `examples/`.

| Check | Reports |
| --- | --- |
| `Checks.Refs` | unreferenced entries, out-of-order first references, unknown keys, unreadable `ref(` calls, hand-typed numbers, mergeable adjacent calls, missing figure files |
| `Checks.Values` | `val` paths that do not resolve, registered values prose never reads |
| `Checks.Bib` | per-entry citation counts, uncited `.bib` entries, citations with no entry |
| `Checks.Revisions` | reply-letter quotes missing from the rendered manuscript, comment status overview, comments with no recorded response |

Run the reference check *before* `quarto render`: an unknown key makes `ref` throw, killing the
render at the first bad call, so nothing in the document would ever report the rest.

## Installation

```julia
pkg> add https://github.com/simonsteiger/Hawkeye.jl
```
