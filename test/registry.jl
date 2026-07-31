using Hawkeye
using Test

@testset "Registry numbering" begin
    reg = Registry([
        MainTable("t1", "a", ""),
        MainTable("t2", "b", ""),
        SuppTable("s1", "c", ""),
        MainFigure("f1", "d", "f1.svg"),
        SuppFigure("g1", "e", "g1.svg"),
        SuppTable("s2", "f", ""),
    ])
    # numbers count within a bucket, not across the registry
    @test Hawkeye.number(reg, "t1") == 1
    @test Hawkeye.number(reg, "t2") == 2
    @test Hawkeye.number(reg, "s1") == 1
    @test Hawkeye.number(reg, "s2") == 2
    @test Hawkeye.number(reg, "f1") == 1
    @test Hawkeye.number(reg, "g1") == 1

    # bucket order follows first appearance in `entries`
    @test reg.bucket_order ==
          [(:table, :main), (:table, :supp), (:figure, :main), (:figure, :supp)]

    @test_throws ArgumentError Hawkeye._entry(reg, "nope")
end

@testset "Registry validation" begin
    # duplicate entry key: today this silently misnumbers every later entry in the bucket
    @test_throws ArgumentError Registry([MainTable("k", "a", ""), SuppTable("k", "b", "")])

    # caption carrying its own number prefix would render the number twice
    @test_throws ArgumentError Registry([MainTable("k", "Table 1: a", "")])
    @test_throws ArgumentError Registry([
        SuppFigure("k", "supplementary Figure 2: a", "x.svg"),
    ])
    # a caption that merely mentions a number mid-sentence is fine
    @test Registry([MainTable("k", "Compared with Table 1 of the prior study", "")]) isa
          Registry

    # duplicate value set name would make a val path ambiguous
    @test_throws ArgumentError Registry(
        [MainTable("k", "a", "")],
        [ValueSet("v", Dict("a" => 1)), ValueSet("v", Dict("b" => 2))],
    )

    # pending must name a registered entry, or it can never be reported
    @test_throws ArgumentError Registry([MainTable("k", "a", "")]; pending=["ghost"])
    @test Registry([MainTable("k", "a", "")]; pending=["k"]) isa Registry
end

@testset "Registry value index" begin
    reg = Registry([MainTable("k", "a", "")], [ValueSet("descr", Dict("n_0" => 872))])
    @test haskey(reg.valindex, "descr")
    @test reg.valindex["descr"].dict["n_0"] == 872
    @test isempty(Registry([MainTable("k", "a", "")]).values)
end
