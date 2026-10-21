module Hawkeye

using StyledStrings

include("entries.jl")
include("values.jl")
include("scan.jl")
include("registry.jl")
include("render.jl")
include("bind.jl")
include("checks/Checks.jl")

export AbstractEntry, AbstractTable, AbstractFigure
export MainTable, SuppTable, MainFigure, SuppFigure
export sanitize_join
export ValueSet, structure
export Registry, Source
export Checks

# Registered faces can be restyled from a user's faces.toml.
function __init__()
    StyledStrings.addface!(:hawkeye_name => StyledStrings.Face(weight=:bold))
    StyledStrings.addface!(:hawkeye_count => StyledStrings.Face(foreground=:bright_black))
    StyledStrings.addface!(:hawkeye_tree => StyledStrings.Face(foreground=:bright_black))
    StyledStrings.addface!(:hawkeye_type => StyledStrings.Face(foreground=:bright_black))
    return nothing
end

end
