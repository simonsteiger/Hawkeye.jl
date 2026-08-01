using Hawkeye
using StyledStrings
using Test

@testset "shape" begin
    @test Hawkeye.shape(3) == Hawkeye.Leaf(Int)
    @test Hawkeye.shape("s") == Hawkeye.Leaf(String)

    # keys are stringified and sorted, so shape is order-independent
    a = Hawkeye.shape(Dict("b" => 1, "a" => 2))
    b = Hawkeye.shape(Dict("a" => 5, "b" => 6))
    @test a == b
    @test hash(a) == hash(b)

    # differing leaf types make differing shapes
    @test Hawkeye.shape(Dict("a" => 1)) != Hawkeye.shape(Dict("a" => 1.0))
    # differing key sets make differing shapes
    @test Hawkeye.shape(Dict("a" => 1)) != Hawkeye.shape(Dict("b" => 1))
end

@testset "leafpaths" begin
    d = Dict("x" => Dict("p" => 1, "q" => 2), "y" => 3)
    @test sort(Hawkeye.leafpaths(d)) == [["x", "p"], ["x", "q"], ["y"]]
    # an empty dict contributes no leaves
    @test Hawkeye.leafpaths(Dict("x" => Dict{String,Any}())) == Vector{String}[]
end

@testset "structure" begin
    # homogeneous: both branches share a shape, so keys collapse onto one line
    homo = ValueSet(
        "props",
        Dict("High" => Dict("a" => 1, "b" => 2), "Moderate" => Dict("a" => 3, "b" => 4)),
    )
    s = structure(homo)
    @test occursin("props: 4 leaves", s)
    @test occursin("\"High\", \"Moderate\"", s)
    @test occursin("\"a\", \"b\" :: Int64", s)
    # one grouped line per level, not one per branch
    @test count(l -> occursin("\"a\", \"b\"", l), split(s, '\n')) == 1

    # divergent: branches differ, so each shape prints separately
    hetero = ValueSet(
        "mixed",
        Dict("das28" => Dict("a" => 1), "decomposition" => Dict("c" => 1.0)),
    )
    h = structure(hetero)
    @test occursin("\"das28\"", h)
    @test occursin("\"decomposition\"", h)
    @test occursin("\"a\" :: Int64", h)
    @test occursin("\"c\" :: Float64", h)
    # the two branches are NOT merged onto one line
    @test !occursin("\"das28\", \"decomposition\"", h)

    # leaf types are reported, which is the point of the whole function
    nt = ValueSet("v", Dict("k" => (e=1, n=2, p="3%")))
    @test occursin("::", structure(nt))
    @test occursin("NamedTuple", structure(nt))
end

@testset "ValueSet show" begin
    vs = ValueSet("v", Dict("a" => 1))
    @test sprint(show, MIME"text/plain"(), vs) == structure(vs)
    # the raw dict remains reachable with its ordinary display
    @test vs.dict == Dict("a" => 1)
    @test occursin("Dict", sprint(show, MIME"text/plain"(), vs.dict))
end

@testset "faces" begin
    faces = StyledStrings.FACES.current[]
    @test haskey(faces, :hawkeye_name)
    @test haskey(faces, :hawkeye_count)
    @test haskey(faces, :hawkeye_tree)
    @test haskey(faces, :hawkeye_type)
    @test faces[:hawkeye_type].foreground == StyledStrings.SimpleColor(:bright_black)
end
