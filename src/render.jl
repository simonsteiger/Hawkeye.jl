"""
    entry_label(reg, key) -> String

The entry's label and number, such as `"Table 2"` or `"supplementary Table 4"`.
"""
function entry_label(reg::Registry, key::AbstractString)
    e = _entry(reg, key)
    return string(_bucket_label(kind(e), location(e), false), " ", number(reg, key))
end

"Format sorted, unique numbers as strings. Three or more consecutive numbers become `n–m`."
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

Keys are grouped by `(kind, location)` bucket, and buckets appear in the registry's
`bucket_order`, so argument order does not affect the result. Within a bucket, numbers are sorted
and deduplicated, three or more consecutive numbers become a range, and items are joined with
commas and a final " and ". Two buckets are joined with " and " when the first holds a single
number, and with ", and " when it holds several. Three or more buckets are joined with commas and
a final ", and ".

```julia
ref(reg, "prop_trt")                            # "Table 3"
ref(reg, "prop_rem_Moderate", "or_rem_Moderate") # "supplementary Tables 2 and 3"
ref(reg, "prop_trt", "fig_descr")               # "Table 3 and Figure 1"
ref(reg, "prop_rem", "prop_trt", "fig_descr")   # "Tables 2 and 3, and Figure 1"
ref(reg, "prop_trt", "def_rem", "fig_descr")    # "Table 3, supplementary Table 1, and Figure 1"
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
    bucket_numbers = [sort!(unique(groups[b])) for b in order]
    parts = map(order, bucket_numbers) do b, nums
        label = _bucket_label(b[1], b[2], length(nums) > 1)
        # no comma before the final "and"
        return string(label, " ", join(_collapse(nums), ", ", " and "))
    end
    two_buckets_first_single = length(parts) == 2 && length(first(bucket_numbers)) == 1
    final_separator = two_buckets_first_single ? " and " : ", and "
    return join(parts, ", ", final_separator)
end

"""
The caption preceded by its capitalised label and number, as in `"Supplementary Table 4: ..."`.
"""
function caption(reg::Registry, key::AbstractString)
    e = _entry(reg, key)
    prefix = uppercasefirst(_bucket_label(kind(e), location(e), false))
    return "$prefix $(number(reg, key)): $(e.caption)"
end

"The footer of a table, or an empty string for a figure."
footer(reg::Registry, key::AbstractString) = _footer(_entry(reg, key))
_footer(e::AbstractTable) = e.footer
_footer(::AbstractFigure) = ""

# `ValueSet` guarantees `String` keys, so `k` is looked up without conversion.
function _child(d::AbstractDict, k::AbstractString)
    haskey(d, k) && return (d[k], true)
    return (nothing, false)
end

_keylist(d::AbstractDict) = join(sort!([repr(String(k)) for k in keys(d)]), ", ")

_fmtcall(name, path) = "val(" * repr(name) * ", [" * join(map(repr, path), ", ") * "])"

"""
    val(reg, name, path)

Read a registered value. `name` selects a value set and `path` lists the keys to follow inside it.

```julia
val(reg, "descr", ["n_0"])
val(reg, "props", ["Moderate", "decomposition", "das28_remission"])
```

Throws `ArgumentError` naming the level that failed and the valid keys at that level.
"""
function val(reg::Registry, name::AbstractString, path::AbstractVector{<:AbstractString})
    haskey(reg.valindex, name) || throw(
        ArgumentError(
            "unknown value set: \"$name\"; registered: " *
            join(sort!([repr(k) for k in keys(reg.valindex)]), ", "),
        ),
    )
    cur = reg.valindex[name].dict
    for (i, k) in enumerate(path)
        cur isa AbstractDict || throw(
            ArgumentError(
                "$(_fmtcall(name, path)): " *
                "\"$(path[i-1])\" is a leaf of type $(typeof(cur)); cannot descend to \"$k\"",
            ),
        )
        child, ok = _child(cur, k)
        ok || throw(
            ArgumentError(
                "$(_fmtcall(name, path)): " *
                "no key \"$k\" at level $i; valid keys there: $(_keylist(cur))",
            ),
        )
        cur = child
    end
    return cur
end
