using Hawkeye
using Test

@testset "Hawkeye.jl" begin
    include("entries.jl")
    include("values.jl")
    include("registry.jl")
    include("render.jl")
    include("bind.jl")
    include("checks_scan.jl")
    include("fixtures.jl")
    include("checks_refs.jl")
end
