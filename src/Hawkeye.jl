module Hawkeye

include("entries.jl")
include("values.jl")
include("registry.jl")
include("render.jl")

export AbstractEntry, AbstractTable, AbstractFigure
export MainTable, SuppTable, MainFigure, SuppFigure
export sanitize_join
export ValueSet, structure
export Registry

end
