"""
A registered manuscript table or figure.

The four concrete types combine a kind (table or figure) with a location (main or supplementary).
Tables have a `footer`, figures have a `path`. Use [`kind`](@ref) and [`location`](@ref) instead of
checking the concrete type.
"""
abstract type AbstractEntry end
abstract type AbstractTable <: AbstractEntry end
abstract type AbstractFigure <: AbstractEntry end

struct MainTable <: AbstractTable
    key::String
    caption::String # without a "Table 1: " prefix; `Registry` rejects captions that have one
    footer::String  # abbreviations, printed under the table
end

struct SuppTable <: AbstractTable
    key::String
    caption::String
    footer::String
end

struct MainFigure <: AbstractFigure
    key::String
    caption::String
    path::String # image path, relative to the figures document
end

struct SuppFigure <: AbstractFigure
    key::String
    caption::String
    path::String
end

kind(::AbstractTable) = :table
kind(::AbstractFigure) = :figure

location(::Union{MainTable,MainFigure}) = :main
location(::Union{SuppTable,SuppFigure}) = :supp

"The `(kind, location)` pair of an entry. Entries are numbered separately within each bucket."
bucket(e::AbstractEntry) = (kind(e), location(e))

"""
    sanitize_join(parts...) -> String

Join text fragments into sentences. Each part ends with a single period, parts are separated by a
space, and empty parts are dropped. Use it to build a footer from constants that may or may not
end in a period.

Surrounding whitespace is stripped with a warning.

```julia
sanitize_join(REM_FOOTER, SUPPRESSED_COUNT_NOTE, SUPPRESSED_NOTE)
```
"""
function sanitize_join(parts::AbstractString...)
    cleaned = String[]
    for (i, p) in enumerate(parts)
        s = strip(p)
        s == p || @warn(
            "sanitize_join: argument $i has surrounding whitespace; stripped it, " *
            "but the source string is worth cleaning",
            argument = repr(p),
        )
        isempty(s) && continue
        push!(cleaned, rstrip(s, '.') * ".")
    end
    return join(cleaned, " ")
end
