"""
A registered manuscript table or figure.

The concrete type carries both axes of the registry — `kind` (table vs figure) and `location`
(main vs supplementary) — so an entry announces its bucket in its first token. Fields differ by
kind: tables carry a `footer`, figures carry a `path`. Query the axes with [`kind`](@ref) and
[`location`](@ref) rather than matching on the type, so bucket logic stays generic.
"""
abstract type AbstractEntry end
abstract type AbstractTable <: AbstractEntry end
abstract type AbstractFigure <: AbstractEntry end

struct MainTable <: AbstractTable
    key::String
    caption::String # body only, no "Table 1: " prefix; Registry rejects one that has it
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

"The `(kind, location)` pair an entry is numbered and cross-referenced within."
bucket(e::AbstractEntry) = (kind(e), location(e))

"""
    sanitize_join(parts...) -> String

Join text fragments into one run of complete sentences: each part is terminated with a single
period, parts are separated by a space, and empty parts are dropped.

Footers are assembled from constants that do not agree on whether they end in a period, so a
plain `join` yields either a missing or a doubled sentence break. This normalises that without
the caller tracking which constant ends how.

Surrounding whitespace is stripped and warned about. Stripping keeps the output correct either
way; the warning exists so the source string gets cleaned rather than silently patched on every
call.

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
