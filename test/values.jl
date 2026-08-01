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

# Rendering is tested through `structure` at a fixed width, so assertions are exact strings
# rather than `occursin` — glyph placement is the thing under test.
render(vs; width=80) =
    String(structure(vs, IOContext(devnull, :displaysize => (24, width))))

@testset "structure header" begin
    @test render(ValueSet("v", Dict("a" => 1))) == "v · 1 leaf\n└─ a  Int64\n"
    # the noun agrees with the count
    @test startswith(render(ValueSet("v", Dict("a" => 1, "b" => 2))), "v · 2 leaves\n")
    # an empty set renders the header alone
    @test render(ValueSet("v", Dict{String,Any}())) == "v · 0 leaves\n"
end

@testset "structure grouping and glyphs" begin
    # homogeneous: both branches share a shape, so their keys collapse onto one node
    homo = ValueSet(
        "props",
        Dict("High" => Dict("a" => 1, "b" => 2), "Moderate" => Dict("a" => 3, "b" => 4)),
    )
    @test render(homo) == """
        props · 4 leaves
        └─ High, Moderate
           └─ a, b  Int64
        """

    # divergent: branches differ, so each shape prints as its own node and they are not merged
    hetero = ValueSet(
        "mixed",
        Dict("das28" => Dict("a" => 1), "decomposition" => Dict("c" => 1.0)),
    )
    h = render(hetero)
    @test h == """
        mixed · 2 leaves
        ├─ das28
        │  └─ a  Int64
        └─ decomposition
           └─ c  Float64
        """
    @test !occursin("das28, decomposition", h)

    # a non-last node's subtree keeps the ancestor's vertical bar
    mixed = ValueSet("m", Dict("A" => Dict("x" => 1), "z" => 2.0))
    @test render(mixed) == """
        m · 2 leaves
        ├─ A
        │  └─ x  Int64
        └─ z  Float64
        """
end

@testset "structure wrapping" begin
    keys5 = [
        "das28_remission",
        "sdai_remission",
        "cdai_remission",
        "boolean_remission",
        "das28crp_remission",
    ]
    vs = ValueSet("descr", Dict("High" => Dict(k => 1 for k in keys5), "z" => 2.0))
    @test render(vs) == """
        descr · 6 leaves
        ├─ High
        │  └─ boolean_remission, cdai_remission, das28_remission, das28crp_remission,
        │     sdai_remission  Int64
        └─ z  Float64
        """

    # a single key wider than the line overflows rather than being truncated
    wide = ValueSet("wide", Dict("x"^70 => 1))
    @test render(wide) == "wide · 1 leaf\n└─ " * "x"^70 * "  Int64\n"

    # the type is the last wrap token, so it moves to a continuation line rather than overflowing.
    # The key must be long enough to push a 50-column type past the line: 3 + 30 + 2 + 50 = 85.
    nt = ValueSet(
        "v",
        Dict("das28_remission_by_treatment_x" => (aaaa=1, bbbb=2, cccc="3", dddd=4.0)),
    )
    @test render(nt) == """
        v · 1 leaf
        └─ das28_remission_by_treatment_x
           @NamedTuple{aaaa::Int64, bbbb::Int64, cccc::Strin…
        """

    # a type short enough to fit stays on the key's line
    short = ValueSet("v", Dict("k" => (aaaa=1, bbbb=2, cccc="3", dddd=4.0)))
    @test render(short) ==
          "v · 1 leaf\n└─ k  @NamedTuple{aaaa::Int64, bbbb::Int64, cccc::Strin…\n"
end

@testset "structure quoting" begin
    vs = ValueSet("q", Dict("a,b" => 1, "has space" => 2, "" => 3, "plain-key" => 4))
    r = render(vs)
    @test occursin("\"a,b\"", r)
    @test occursin("\"has space\"", r)
    @test occursin("\"\"", r)
    @test occursin("plain-key", r)
    @test !occursin("\"plain-key\"", r)
end

@testset "structure faces" begin
    vs = ValueSet("v", Dict("a" => 1))
    colored = sprint(show, MIME"text/plain"(), vs; context=:color => true)
    # the tree glyphs and the leaf type are dimmed; bright_black is ANSI 90
    @test occursin("\e[90m", colored)
    # the set name is bold
    @test occursin("\e[1m", colored)
    # without color the output is plain text
    plain = sprint(show, MIME"text/plain"(), vs)
    @test !occursin("\e[", plain)
    @test occursin("└─ a", plain)
end

@testset "ValueSet show" begin
    vs = ValueSet("v", Dict("a" => 1))
    @test sprint(show, MIME"text/plain"(), vs) == String(structure(vs))
    # the one-line form is unchanged
    @test sprint(show, vs) == "ValueSet(\"v\", 1 leaves)"
    # the raw dict remains reachable with its ordinary display
    @test vs.dict == Dict("a" => 1)
    @test occursin("Dict", sprint(show, MIME"text/plain"(), vs.dict))
end

@testset "ValueSet key validation" begin
    # a valid nested dictionary is accepted unchanged
    ok = ValueSet("v", Dict("a" => Dict("b" => 1)))
    @test ok.dict == Dict("a" => Dict("b" => 1))

    # a Symbol key at the root is rejected
    @test_throws ArgumentError ValueSet("v", Dict(:a => 1))

    # a Symbol key nested one level down is rejected
    @test_throws ArgumentError ValueSet("v", Dict("High" => Dict(:das28 => 1)))

    # a non-Symbol, non-String key is rejected too
    @test_throws ArgumentError ValueSet("v", Dict(2024 => 1))

    # the message names the set, the path to the containing dict, and the offending key
    err = try
        ValueSet("descr", Dict("High" => Dict(:das28 => 1)))
    catch e
        sprint(showerror, e)
    end
    @test occursin("descr", err)
    @test occursin("[\"High\"]", err)
    @test occursin(":das28", err)
    @test occursin("Symbol", err)

    # a root-level offender reports an empty path
    err2 = try
        ValueSet("descr", Dict(:a => 1))
    catch e
        sprint(showerror, e)
    end
    @test occursin("at []", err2)
end

@testset "key formatting" begin
    # ordinary keys print bare — quotes are noise in a tree
    @test Hawkeye._fmtkey("n_0") == "n_0"
    # hyphens are the common awkward case and stay bare
    @test Hawkeye._fmtkey("moderate-objective") == "moderate-objective"
    # a comma would read as a key separator on a grouped line
    @test Hawkeye._fmtkey("a,b") == "\"a,b\""
    @test Hawkeye._fmtkey("has space") == "\"has space\""
    @test Hawkeye._fmtkey("tab\there") == "\"tab\\there\""
    # an empty key is invisible unless quoted
    @test Hawkeye._fmtkey("") == "\"\""
end

@testset "type truncation" begin
    @test Hawkeye._fmttype(Int64) == "Int64"
    # a 50-column type is left alone; 51 truncates to exactly 50
    exactly50 = "T" * "x"^49
    @test length(Hawkeye._fmttype(exactly50)) == 50
    @test Hawkeye._fmttype(exactly50) == exactly50
    over = "T" * "x"^50
    @test length(Hawkeye._fmttype(over)) == 50
    @test endswith(Hawkeye._fmttype(over), "…")
    @test textwidth(Hawkeye._fmttype(over)) == 50
    # a real long type
    long =
        Hawkeye._fmttype(@NamedTuple{aaaa::Int64, bbbb::Int64, cccc::String, dddd::Float64})
    @test length(long) == 50
end

@testset "faces" begin
    faces = StyledStrings.FACES.current[]
    @test haskey(faces, :hawkeye_name)
    @test haskey(faces, :hawkeye_count)
    @test haskey(faces, :hawkeye_tree)
    @test haskey(faces, :hawkeye_type)
    @test faces[:hawkeye_type].foreground == StyledStrings.SimpleColor(:bright_black)
end
