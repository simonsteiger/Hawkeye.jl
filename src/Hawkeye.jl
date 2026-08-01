module Hawkeye

using StyledStrings

include("entries.jl")
include("values.jl")
include("registry.jl")
include("render.jl")
include("bind.jl")
include("checks/Checks.jl")

export AbstractEntry, AbstractTable, AbstractFigure
export MainTable, SuppTable, MainFigure, SuppFigure
export sanitize_join
export ValueSet, structure
export Registry
export Checks

# Faces are registered rather than hardcoded so a user's faces.toml can restyle the tree.
# A repeat addface! for an existing face neither errors nor overwrites, so no guard is needed
# against precompilation or a reload.
function __init__()
    StyledStrings.addface!(:hawkeye_name => StyledStrings.Face(weight=:bold))
    StyledStrings.addface!(:hawkeye_count => StyledStrings.Face(foreground=:bright_black))
    StyledStrings.addface!(:hawkeye_tree => StyledStrings.Face(foreground=:bright_black))
    StyledStrings.addface!(:hawkeye_type => StyledStrings.Face(foreground=:bright_black))
    return nothing
end

end
