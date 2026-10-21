"""
The table and figure entries and the value sets of one manuscript.

An entry's number is its position among the entries of the same `(kind, location)` bucket, in the
order of `entries`. `bucket_order` is the order in which buckets first appear in `entries`; `ref`
lists buckets in this order.
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

# Matches a caption that starts with its own number, such as "Table 1:".
const _CAPTION_PREFIX = r"^\s*(?:supplementary\s+)?(?:table|figure)s?\s+\d+\s*:"i

"""
    Registry(entries, values = ValueSet[]; pending = String[])

Build a registry. Throws `ArgumentError` on a duplicate entry key, a duplicate value set name, a
caption that starts with its own number, or a `pending` key that names no entry.

`pending` lists entries whose table or figure does not exist yet. The reference check reports a
referenced pending entry as `PENDING`, which is not a finding.
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
