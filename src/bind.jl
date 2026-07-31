"""
    @bind reg

Define registry-free `ref`, `val`, `caption`, `footer`, `entry_label` and `figures_md` in the
calling module, each forwarding to the Hawkeye function with `reg` pre-applied, and export them.

Intended for a small project module that owns the registry:

```julia
module ManuscriptRefs
using Hawkeye
const ENTRIES = [MainTable("pop1", "...", POP_FOOTER)]
const VALUES  = [ValueSet("descr", load("descr.jld2", "descr_dict"))]
const REG = Registry(ENTRIES, VALUES)
Hawkeye.@bind REG
end
```

Manuscript prose then reads `ref("pop1")` and `val("descr", "n_0")`.

Hawkeye deliberately does not export these names. Defining `ref` in a module that has
`using Hawkeye` would otherwise add a method to Hawkeye's own function rather than creating a
local one, and two project modules would overwrite each other's binding. The function objects are
interpolated directly, so the generated code depends on no name being in scope at the call site.
"""
macro bind(reg)
    fref, fval = ref, val
    fcaption, ffooter = caption, footer
    flabel, ffigures = entry_label, figures_md
    return esc(
        quote
            ref(keys::AbstractString...) = $fref($reg, keys...)
            val(name::AbstractString, path::AbstractString...) = $fval($reg, name, path...)
            caption(key::AbstractString) = $fcaption($reg, key)
            footer(key::AbstractString) = $ffooter($reg, key)
            entry_label(key::AbstractString) = $flabel($reg, key)
            figures_md() = $ffigures($reg)
            export ref, val, caption, footer, entry_label, figures_md
            nothing
        end,
    )
end
