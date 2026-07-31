"""
    entry_label(reg, key) -> String

The entry's bucket label and number: `"Table 2"`, `"supplementary Table 4"`. Singular label, no
trailing colon — [`caption`](@ref) builds the sentence-initial form separately.
"""
function entry_label(reg::Registry, key::AbstractString)
    e = _entry(reg, key)
    return string(_bucket_label(kind(e), location(e), false), " ", number(reg, key))
end

"Sorted, unique numbers -> display items. Contiguous runs of 3+ collapse to `n–m`."
function _collapse(nums::Vector{Int})
    items = String[]
    i = firstindex(nums)
    while i <= lastindex(nums)
        j = i
        while j < lastindex(nums) && nums[j+1] == nums[j] + 1
            j += 1
        end
        if j - i + 1 >= 3
            push!(items, "$(nums[i])–$(nums[j])")
        else
            append!(items, string.(nums[i:j]))
        end
        i = j + 1
    end
    return items
end

function _bucket_label(kind::Symbol, location::Symbol, plural::Bool)
    stem = kind === :table ? "Table" : "Figure"
    word = plural ? stem * "s" : stem
    return location === :supp ? "supplementary $word" : word
end

"""
    ref(reg, keys...)

Render one or more entry keys as an English cross-reference.

Keys are bucketed by `(kind, location)`. Buckets are emitted in the registry's canonical
`bucket_order`, so argument order does not affect the result. Within a bucket, numbers are sorted
and deduplicated, contiguous runs of three or more collapse to a range, and items are joined
BMJ-style. Buckets sharing a `kind` are then joined BMJ-style; buckets of mixed `kind` are joined
with commas.

```julia
ref(reg, "prop_trt")                            # "Table 3"
ref(reg, "prop_rem_Moderate", "or_rem_Moderate") # "supplementary Tables 2 and 3"
```
"""
function ref(reg::Registry, keys::AbstractString...)
    isempty(keys) && throw(ArgumentError("ref requires at least one key"))
    entries = [_entry(reg, key) for key in keys] # throws on any unknown key first
    groups = Dict{Tuple{Symbol,Symbol},Vector{Int}}()
    for e in entries
        push!(get!(groups, bucket(e), Int[]), number(reg, e.key))
    end
    order = [b for b in reg.bucket_order if haskey(groups, b)]
    parts = map(order) do b
        nums = sort!(unique(groups[b]))
        label = _bucket_label(b[1], b[2], length(nums) > 1)
        # BMJ style, no Oxford comma: join's third argument is the final separator
        return string(label, " ", join(_collapse(nums), ", ", " and "))
    end
    all_same_kind = length(Set(b[1] for b in order)) == 1
    return all_same_kind ? join(parts, ", ", " and ") : join(parts, ", ")
end
