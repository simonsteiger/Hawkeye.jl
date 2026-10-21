using Hawkeye
using Test

module ProjA
using Hawkeye
const REG = Registry(
    [MainTable("pop1", "Descriptives.", "FOOT"), MainFigure("f1", "A fig.", "a.svg")],
    [ValueSet("descr", Dict("n_0" => 872))];
    sources=[Source("a.qmd", "\$(ref(\"pop1\")) and \$(ref(\"f1\"))")],
)
Hawkeye.@bind REG
end

module ProjB
using Hawkeye
const REG = Registry(
    [MainTable("other", "Other.", "F")];
    sources=[Source("b.qmd", "\$(ref(\"other\"))")],
)
Hawkeye.@bind REG
end

@testset "@bind" begin
    @test ProjA.ref("pop1") == "Table 1"
    @test ProjA.val("descr", ["n_0"]) == 872
    @test ProjA.caption("pop1") == "Table 1: Descriptives."
    @test ProjA.footer("pop1") == "FOOT"
    @test ProjA.entry_label("f1") == "Figure 1"

    # generated names are exported from the project module
    @test :ref in names(ProjA)
    @test :val in names(ProjA)

    # two modules bound to different registries do not affect each other
    @test ProjB.ref("other") == "Table 1"
    @test_throws ArgumentError ProjB.ref("pop1")
    @test_throws ArgumentError ProjA.ref("other")

    # Hawkeye itself does not export the bindable names
    @test !(:ref in names(Hawkeye))
    @test !(:val in names(Hawkeye))
    @test !(:caption in names(Hawkeye))
end
