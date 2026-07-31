"""
The single source of truth for a manuscript's numbering and registered values.

A number is an entry's position within its `(kind, location)` bucket, derived from `entries`
order. Numbers are never written down. `bucket_order` is likewise derived — the order each bucket
first appears in `entries` — so cross-reference output can be canonically ordered without a
second declaration that could drift out of sync.
"""
struct Registry
    entries::Vector{AbstractEntry}
    values::Vector{ValueSet}
    pending::Vector{String}
    index::Dict{String,AbstractEntry}
    numbers::Dict{String,Int}
    bucket_order::Vector{Tuple{Symbol,Symbol}}
    valindex::Dict{String,ValueSet}
end

# A caption that already carries its own "Table 1:" style prefix would render the number twice.
const _CAPTION_PREFIX = r"^\s*(?:supplementary\s+)?(?:table|figure)s?\s+\d+\s*:"i

"""
    Registry(entries, values = ValueSet[]; pending = String[])

Build a registry, validating it. Throws `ArgumentError` on a duplicate entry key, a duplicate
value set name, a caption that carries its own number prefix, or a `pending` key that names no
entry. `pending` lists entries that have a number but no rendered body yet; the reference check
reports them as `PENDING` rather than as errors.
"""
function Registry(
    entries::AbstractVector{<:AbstractEntry},
    values::AbstractVector{ValueSet}=ValueSet[];
    pending::AbstractVector{<:AbstractString}=String[],
)
    seen = Set{String}()
    for e in entries
        e.key in seen && throw(ArgumentError("duplicate entry key: \"$(e.key)\""))
        push!(seen, e.key)
        occursin(_CAPTION_PREFIX, e.caption) && throw(
            ArgumentError(
                "caption for \"$(e.key)\" starts with its own number prefix; " *
                "store the caption body only — the number comes from the registry",
            ),
        )
    end

    vseen = Set{String}()
    for v in values
        v.name in vseen && throw(ArgumentError("duplicate value set name: \"$(v.name)\""))
        push!(vseen, v.name)
    end

    for k in pending
        k in seen || throw(ArgumentError("pending key is not a registered entry: \"$k\""))
    end

    numbers = Dict{String,Int}()
    counts = Dict{Tuple{Symbol,Symbol},Int}()
    order = Tuple{Symbol,Symbol}[]
    for e in entries
        b = bucket(e)
        b in order || push!(order, b)
        counts[b] = get(counts, b, 0) + 1
        numbers[e.key] = counts[b]
    end

    return Registry(
        collect(AbstractEntry, entries),
        collect(ValueSet, values),
        collect(String, pending),
        Dict{String,AbstractEntry}(e.key => e for e in entries),
        numbers,
        order,
        Dict{String,ValueSet}(v.name => v for v in values),
    )
end

function _entry(reg::Registry, key::AbstractString)
    haskey(reg.index, key) || throw(ArgumentError("unknown manuscript key: \"$key\""))
    return reg.index[key]
end

"Position of `key` within its `(kind, location)` bucket."
number(reg::Registry, key::AbstractString) = reg.numbers[_entry(reg, key).key]
