"""
The table and figure entries and the value sets of one manuscript.

Entries are numbered by their first `ref` citation in the manuscript sources: within each
`(kind, location)` bucket, the first entry cited is number 1, the next new entry cited is number 2,
and so on. Entries that the sources never cite are dropped: they have no number and are listed in
`dropped`, in the order of `entries`.

`entries` holds every entry passed to the constructor, including dropped ones. `index` and
`numbers` hold only the cited entries. `bucket_order` is the order in which buckets are first
cited; `ref` lists buckets in this order.
"""
struct Registry
    entries::Vector{AbstractEntry}
    values::Vector{ValueSet}
    pending::Vector{String}
    index::Dict{String,AbstractEntry}
    numbers::Dict{String,Int}
    bucket_order::Vector{Tuple{Symbol,Symbol}}
    valindex::Dict{String,ValueSet}
    dropped::Vector{String}
end

# Matches a caption that starts with its own number, such as "Table 1:".
const _CAPTION_PREFIX = r"^\s*(?:supplementary\s+)?(?:table|figure)s?\s+\d+\s*:"i

"""
    Registry(entries, values = ValueSet[]; sources, pending = String[])

Build a registry, numbering `entries` by the order of their first citation in `sources`.

`sources` is a vector of [`Source`](@ref), read in the given order. Within each source,
`ref("a", "b")` calls are read in source order and the arguments of one call from left to right;
calls inside `<!-- -->` comments are ignored. Within each `(kind, location)` bucket, an entry's
number is its position among the bucket's entries in that order of first citation. Later citations
do not affect numbering. Entries that are never cited are dropped and get no number; text inside
table footers is not scanned.

Throws `ArgumentError` on a duplicate entry key, a duplicate value set name, a caption that starts
with its own number, a `pending` key that names no entry, a `ref(` call that cannot be read (it
spans several lines or has a non-literal argument), or a `ref` key that names no entry. The last
two name the file and line.

`pending` lists entries whose table or figure does not exist yet. The reference check reports a
referenced pending entry as `PENDING`, which is not a finding. An uncited pending entry is dropped
like any other.

```julia
sources = [Source(p, read(p, String)) for p in ["manuscript.qmd", "supplement.qmd"]]
reg = Registry(ENTRIES, VALUES; sources)
```
"""
function Registry(
    entries::AbstractVector{<:AbstractEntry},
    values::AbstractVector{ValueSet}=ValueSet[];
    sources::AbstractVector{Source},
    pending::AbstractVector{<:AbstractString}=String[],
)
    entry_by_key = Dict{String,AbstractEntry}()
    for e in entries
        haskey(entry_by_key, e.key) &&
            throw(ArgumentError("duplicate entry key: \"$(e.key)\""))
        entry_by_key[e.key] = e
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
        haskey(entry_by_key, k) ||
            throw(ArgumentError("pending key is not a registered entry: \"$k\""))
    end

    numbers = Dict{String,Int}()
    counts = Dict{Tuple{Symbol,Symbol},Int}()
    order = Tuple{Symbol,Symbol}[]
    for key in _cited_keys(sources, entry_by_key)
        haskey(numbers, key) && continue
        b = bucket(entry_by_key[key])
        b in order || push!(order, b)
        counts[b] = get(counts, b, 0) + 1
        numbers[key] = counts[b]
    end

    return Registry(
        collect(AbstractEntry, entries),
        collect(ValueSet, values),
        collect(String, pending),
        Dict{String,AbstractEntry}(k => entry_by_key[k] for k in keys(numbers)),
        numbers,
        order,
        Dict{String,ValueSet}(v.name => v for v in values),
        [e.key for e in entries if !haskey(numbers, e.key)],
    )
end

"""
Every key cited by a `ref` call in `sources`, in citation order and with repeats. Throws
`ArgumentError` naming the file and line of an unreadable `ref(` call or of a key that is not in
`entry_by_key`.
"""
function _cited_keys(sources::AbstractVector{Source}, entry_by_key::AbstractDict)
    cited = String[]
    for s in sources
        calls, unparsed = extract_calls(mask_comments(s.text), "ref")
        isempty(unparsed) || throw(
            ArgumentError(
                "cannot read the ref( call at " *
                join(("$(s.path):$l" for l in unparsed), ", ") *
                "; write each ref( call on one line with literal string arguments",
            ),
        )
        for c in calls, key in c.args
            haskey(entry_by_key, key) || throw(
                ArgumentError(
                    "$(s.path):$(c.line): ref(\"$key\") names no registered entry",
                ),
            )
            push!(cited, key)
        end
    end
    return cited
end

function _entry(reg::Registry, key::AbstractString)
    haskey(reg.index, key) && return reg.index[key]
    key in reg.dropped && throw(
        ArgumentError(
            "\"$key\" is registered but never referenced in the sources, so it has no number",
        ),
    )
    throw(ArgumentError("unknown manuscript key: \"$key\""))
end

"""
Position of `key` within its `(kind, location)` bucket, in the order of first citation in the
registry's sources.
"""
number(reg::Registry, key::AbstractString) = reg.numbers[_entry(reg, key).key]
