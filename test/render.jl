using Hawkeye
using Test

const REG = Registry([
    MainTable("pop1", "Descriptives.", "F1"),
    MainTable("prop_rem", "Proportions.", "F2"),
    MainTable("prop_trt", "Prescriptions.", "F3"),
    SuppTable("def_rem", "Definitions.", "F4"),
    SuppTable("pop2", "More descriptives.", "F5"),
    SuppTable("s3", "Third.", "F6"),
    SuppTable("s4", "Fourth.", "F7"),
    SuppTable("s5", "Fifth.", "F8"),
    MainFigure("fig_descr", "A figure.", "figs/descr.svg"),
    MainFigure("fig_rem", "Another figure.", "figs/rem.svg"),
    SuppFigure("fig_high", "Supp figure.", "figs/high.svg"),
    SuppFigure("fig_trt_high", "Supp figure 2.", "figs/trt.svg"),
])

@testset "entry_label" begin
    @test Hawkeye.entry_label(REG, "pop1") == "Table 1"
    @test Hawkeye.entry_label(REG, "def_rem") == "supplementary Table 1"
    # figures are numbered in their own bucket, so this is 1 despite following eight tables
    @test Hawkeye.entry_label(REG, "fig_descr") == "Figure 1"
    @test Hawkeye.entry_label(REG, "fig_high") == "supplementary Figure 1"
    @test_throws ArgumentError Hawkeye.entry_label(REG, "no_such_key")
end

@testset "ref single bucket" begin
    @test Hawkeye.ref(REG, "prop_trt") == "Table 3"
    @test Hawkeye.ref(REG, "def_rem", "pop2") == "supplementary Tables 1 and 2"
    # BMJ style: no Oxford comma
    @test Hawkeye.ref(REG, "def_rem", "pop2", "s3") == "supplementary Tables 1–3"
    # duplicates collapse
    @test Hawkeye.ref(REG, "pop1", "pop1") == "Table 1"
    @test_throws ArgumentError Hawkeye.ref(REG)
    @test_throws ArgumentError Hawkeye.ref(REG, "ghost")
end

@testset "ref run collapsing" begin
    # three or more contiguous numbers collapse to a range; two do not
    @test Hawkeye._collapse([1, 2]) == ["1", "2"]
    @test Hawkeye._collapse([1, 2, 3]) == ["1–3"]
    @test Hawkeye._collapse([1, 2, 3, 5]) == ["1–3", "5"]
    @test Hawkeye._collapse([1, 3, 5]) == ["1", "3", "5"]
end

@testset "BMJ joining is Base.join" begin
    # no helper: Base.join takes a distinct final separator, and gives BMJ style directly
    @test join(["a"], ", ", " and ") == "a"
    @test join(["a", "b"], ", ", " and ") == "a and b"
    @test join(["a", "b", "c"], ", ", " and ") == "a, b and c"
end

@testset "ref mixed buckets" begin
    # same kind, two locations: joined with "and"
    @test Hawkeye.ref(REG, "pop1", "def_rem") == "Table 1 and supplementary Table 1"
    # mixed kinds: joined with a comma
    @test Hawkeye.ref(REG, "fig_descr", "pop1") == "Table 1, Figure 1"
end

@testset "ref bucket order is canonical" begin
    # the bug from manuscript.qmd:385 — merged into one call, tables group correctly
    merged = Hawkeye.ref(REG, "fig_high", "s4", "s5", "fig_trt_high")
    @test occursin("supplementary Tables 4 and 5", merged)
    @test occursin("supplementary Figures 1 and 2", merged)

    # argument order no longer affects output
    @test Hawkeye.ref(REG, "s4", "fig_high") == Hawkeye.ref(REG, "fig_high", "s4")
    # and the canonical order is the registry's: supp tables precede supp figures
    r = Hawkeye.ref(REG, "fig_high", "s4")
    @test findfirst("supplementary Table", r)[1] < findfirst("supplementary Figure", r)[1]
end

const VREG = Registry(
    [
        MainTable("pop1", "Descriptives.", "F1"),
        MainFigure("fig_descr", "A figure.", "figs/descr.svg"),
        SuppFigure("fig_high", "Supp figure.", "figs/high.svg"),
    ],
    [
        ValueSet("descr", Dict("n_0" => 872, "age_mean_0" => 55.2)),
        ValueSet(
            "props",
            Dict(
                "Moderate" => Dict(
                    "decomposition" => Dict("das28_remission" => (e=5, n=10, p="50%")),
                ),
            ),
        ),
    ],
)

@testset "val" begin
    @test Hawkeye.val(VREG, "descr", ["n_0"]) == 872
    @test Hawkeye.val(VREG, "props", ["Moderate", "decomposition", "das28_remission"]) ==
          (e=5, n=10, p="50%")
    # an empty path returns the whole dict
    @test Hawkeye.val(VREG, "descr", String[]) isa AbstractDict

    # a Symbol-keyed dictionary is rejected when the value set is built, not at read time
    @test_throws ArgumentError ValueSet("sym", Dict(:a => 1))

    # unknown value set names the known sets
    err = try
        Hawkeye.val(VREG, "ghost", ["x"])
    catch e
        sprint(showerror, e)
    end
    @test occursin("ghost", err) && occursin("descr", err)

    # unknown key names the level that failed and the valid keys there
    err2 = try
        Hawkeye.val(VREG, "descr", ["n_9"])
    catch e
        sprint(showerror, e)
    end
    @test occursin("n_9", err2) && occursin("n_0", err2)
    # the message shows the call in its bracketed form
    @test occursin("[\"n_9\"]", err2)

    # descending past a leaf is an error, not a silent nothing
    @test_throws ArgumentError Hawkeye.val(VREG, "descr", ["n_0", "deeper"])
end

@testset "caption and footer" begin
    @test Hawkeye.caption(VREG, "pop1") == "Table 1: Descriptives."
    @test Hawkeye.caption(VREG, "fig_high") == "Supplementary Figure 1: Supp figure."
    @test Hawkeye.footer(VREG, "pop1") == "F1"
    # figures have no footer
    @test Hawkeye.footer(VREG, "fig_descr") == ""
end

@testset "figures_md" begin
    md = Hawkeye.figures_md(VREG)
    @test occursin("## Main article figures", md)
    @test occursin("## Supplementary figures", md)
    @test occursin("![Figure 1: A figure.](figs/descr.svg)", md)
    @test occursin("![Supplementary Figure 1: Supp figure.](figs/high.svg)", md)
    # a pagebreak between consecutive figures, but not before the first
    @test occursin("{{< pagebreak >}}", md)
    @test !startswith(md, "{{< pagebreak >}}")
    # tables contribute nothing
    @test !occursin("Descriptives", md)
end
