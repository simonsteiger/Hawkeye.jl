module Hawkeye

include("entries.jl")
include("values.jl")

export AbstractEntry, AbstractTable, AbstractFigure
export MainTable, SuppTable, MainFigure, SuppFigure
export sanitize_join
export ValueSet, structure

end
