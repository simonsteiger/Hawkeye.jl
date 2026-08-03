# Hawkeye

[![Build Status](https://github.com/simonsteiger/Hawkeye.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/simonsteiger/Hawkeye.jl/actions/workflows/CI.yml?query=branch%3Amain)

Sometimes it's hard to tell what's in and what's out. Let the [machine](https://en.wikipedia.org/wiki/Hawk-Eye) take care of that.

## Main features

The main purpose of this package is to help you organise your tables and figures.
This is done by defining collections of that are vectors of `AbstractEntry`:

```julia
module ManuscriptRefs
using Hawkeye

const ENTRIES = AbstractEntry[
    MainTable("tab1", "All you ever wanted to know about my sample.", "GG: Good Game"),
    SuppTable("stab1", "The table that most people probably won't look at.", "GLHF: Good Luck Have Fun"),
    MainFigure("fig1", "This figure is here to make veryone happy.", "figures/fig1.svg"),
]

const VALUES = ValueSet[
    ValueSet("descriptives", load("output/descriptives.jld2", "descr")),
]

const REG = Registry(ENTRIES, VALUES)
Hawkeye.@bind REG
end
```

The table and figure numbers are automatically taken care of via the ordering in each of the vectors.
There'll be more info in the docs once I have them.

## Entries to markdown

```markdown
Patients were followed for six months ($(ref("tab1"))).
Definitions appear in $(ref("tab_def", "fig1")).
The cohort included $(val("descr", ["t0"])) patients.
```

`ref` groups its arguments by bucket, sorts them, collapses runs of three or more to a range, and
joins them. Argument order does not affect the result. Passing several keys to one call
is what lets them group — two adjacent calls cannot merge, and the reference check reports that
as `ADJACENT`.

## Checks

Hawkeye can do a bunch of checks for you.
Doing these manually is one of the things I like the least about writing manuscripts, but getting them
automated correctly is of course difficult.
You should always double-check!

| Check | Reports |
| --- | --- |
| `Checks.Refs` | unreferenced entries, out-of-order first references, unknown keys, unreadable `ref(` calls, hand-typed numbers, mergeable adjacent calls, missing figure files |
| `Checks.Values` | `val` paths that do not resolve, registered values prose never reads |
| `Checks.Bib` | per-entry citation counts, uncited `.bib` entries, citations with no entry |
| `Checks.Revisions` | reply-letter quotes missing from the rendered manuscript, comment status overview, comments with no recorded response |

Make sure to run the reference check *before* `quarto render`.

## Installation

This package is not registered in the General registry. Add it via url:

```julia
Pkg.add(url="https://github.com/simonsteiger/Hawkeye.jl")
```
