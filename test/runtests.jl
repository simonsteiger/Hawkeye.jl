using Hawkeye
using Test

@testset "Hawkeye.jl" begin
    include("fixtures.jl")
    include("entries.jl")
    include("values.jl")
    include("registry.jl")
    include("render.jl")
    include("bind.jl")
    include("checks_scan.jl")
    include("checks_refs.jl")
    include("checks_values.jl")
    include("checks_bib.jl")
    include("checks_revisions.jl")
end
