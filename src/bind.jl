"""
    @bind reg

Define `ref`, `val`, `caption`, `footer` and `entry_label` in the calling module and export them.
Each forwards to the Hawkeye function of the same name with `reg` as its first argument.

Use it in the project module that defines the registry:

```julia
module ManuscriptRefs
using Hawkeye
const ENTRIES = [MainTable("pop1", "...", POP_FOOTER)]
const VALUES  = [ValueSet("descr", load("descr.jld2", "descr_dict"))]
const REG = Registry(ENTRIES, VALUES)
Hawkeye.@bind REG
end
```

Manuscript prose then reads `ref("pop1")` and `val("descr", ["n_0"])`.

Hawkeye does not export these five names, so two project modules can each bind their own registry.
"""
macro bind(reg)
    fref, fval = ref, val
    fcaption, ffooter = caption, footer
    flabel = entry_label
    return esc(
        quote
            ref(keys::AbstractString...) = $fref($reg, keys...)
            val(name::AbstractString, path::AbstractVector{<:AbstractString}) =
                $fval($reg, name, path)
            caption(key::AbstractString) = $fcaption($reg, key)
            footer(key::AbstractString) = $ffooter($reg, key)
            entry_label(key::AbstractString) = $flabel($reg, key)
            export ref, val, caption, footer, entry_label
            nothing
        end,
    )
end
