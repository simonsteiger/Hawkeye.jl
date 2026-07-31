using Hawkeye
using Hawkeye.Checks
using Test

const R = Hawkeye.Checks.Refs

# every entry referenced once, in registry order within each bucket
const CLEAN = """
Intro \$(ref("pop1")) then \$(ref("prop_rem")).
Supplement \$(ref("def_rem")) and \$(ref("pop2")).
Figures \$(ref("fig_descr")) and \$(ref("fig_high")).
"""

@testset "clean run" begin
    rep = R.analyze(CHECKREG, [src(CLEAN)]; figdir="")
    # pop2 is pending, so it is reported even though everything else is clean
    @test length(rep.rows) == 6
    @test isempty(rep.unknown)
    @test isempty(rep.adjacent)
    @test isempty(rep.literals)
    statuses = Dict(r.key => r.status for r in rep.rows)
    @test statuses["pop1"] == "ok"
    @test statuses["pop2"] == "PENDING (no body)"
    # the entry table prints even on a clean run, so a passing check shows what it covered
    @test occursin("pop1", R.report_string(rep))
end

@testset "pending does not gate has_findings" begin
    # everything referenced and in order, pop2 pending; figdir=nothing disables the unrelated
    # missing-figure check so only the pending status is in play
    rep = R.analyze(CHECKREG, [src(CLEAN)]; figdir=nothing)
    @test Dict(r.key => r.status for r in rep.rows)["pop2"] == "PENDING (no body)"
    @test !R.has_findings(rep)
end

@testset "unreferenced and order" begin
    rep = R.analyze(CHECKREG, [src("Only \$(ref(\"pop1\")).")]; figdir="")
    statuses = Dict(r.key => r.status for r in rep.rows)
    @test statuses["prop_rem"] == "UNREFERENCED"
    @test R.has_findings(rep)

    # Table 2 referenced before Table 1: recorded against the earlier, higher-numbered entry
    rep2 = R.analyze(
        CHECKREG,
        [src("\$(ref(\"prop_rem\")) then \$(ref(\"pop1\")).")];
        figdir="",
    )
    st2 = Dict(r.key => r.status for r in rep2.rows)
    @test occursin("OUT OF ORDER", st2["prop_rem"])
    @test occursin("pop1", st2["prop_rem"])
    # buckets are independent: a figure after a table is not out of order
    rep3 =
        R.analyze(CHECKREG, [src("\$(ref(\"fig_descr\")) \$(ref(\"pop1\")).")]; figdir="")
    st3 = Dict(r.key => r.status for r in rep3.rows)
    @test st3["fig_descr"] == "ok" && st3["pop1"] == "ok"
end

@testset "findings" begin
    rep = R.analyze(CHECKREG, [src("\$(ref(\"ghost\"))")]; figdir="")
    @test rep.unknown == [("ghost", "manuscript.qmd", 1)]

    rep = R.analyze(CHECKREG, [src("See Table 3 there.")]; figdir="")
    @test rep.literals == [("manuscript.qmd", 1, "Table 3")]

    rep =
        R.analyze(CHECKREG, [src("(\$(ref(\"fig_high\")), \$(ref(\"pop2\")))")]; figdir="")
    @test rep.adjacent == [("manuscript.qmd", 1)]

    rep = R.analyze(CHECKREG, [src("\$(ref(\n\"pop1\"))")]; figdir="")
    @test rep.unparsed == [("manuscript.qmd", 1)]

    # a commented-out reference does not count as a reference
    rep = R.analyze(CHECKREG, [src("<!-- \$(ref(\"pop1\")) -->")]; figdir="")
    @test Dict(r.key => r.status for r in rep.rows)["pop1"] == "UNREFERENCED"
end

@testset "multiple sources" begin
    a = Hawkeye.Checks.Source("manuscript.qmd", "\$(ref(\"pop1\"))")
    b = Hawkeye.Checks.Source("supplementary.qmd", "\$(ref(\"def_rem\"))")
    rep = R.analyze(CHECKREG, [a, b]; figdir="")
    rows = Dict(r.key => r for r in rep.rows)
    # an entry referenced only from the supplement is not UNREFERENCED
    @test rows["def_rem"].status == "ok"
    @test rows["def_rem"].first == ("supplementary.qmd", 1)
    @test rows["pop1"].first == ("manuscript.qmd", 1)
    @test occursin("supplementary.qmd", R.report_string(rep))
end

@testset "missing figure files" begin
    # figdir points nowhere, so both figure paths are missing
    rep = R.analyze(CHECKREG, [src(CLEAN)]; figdir="/nonexistent")
    @test length(rep.missing_figures) == 2
    @test R.has_findings(rep)
    @test occursin("MISSING FIGURE", R.report_string(rep))
    # figdir = nothing disables the check entirely
    rep2 = R.analyze(CHECKREG, [src(CLEAN)]; figdir=nothing)
    @test isempty(rep2.missing_figures)
end
