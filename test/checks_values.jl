using Hawkeye
using Hawkeye.Checks
using Test

const V = Hawkeye.Checks.Values

@testset "value check" begin
    text = "n=\$(val(\"descr\", [\"n_0\"])) and \$(val(\"props\", [\"Moderate\", \"das28\"]))"
    rep = V.analyze(CHECKREG, [src(text)])
    rows = Dict(r.name => r for r in rep.rows)
    @test rows["descr"].leaves == 2
    @test rows["descr"].referenced == 1
    @test rows["props"].leaves == 1
    @test rows["props"].referenced == 1
    @test isempty(rep.unknown)
    # n_6 is registered but never read — the half nothing else can answer
    @test ["descr", "n_6"] in rep.unused
    @test V.has_findings(rep)

    # everything read: no findings at all
    all_read =
        "\$(val(\"descr\", [\"n_0\"])) \$(val(\"descr\", [\"n_6\"])) " *
        "\$(val(\"props\", [\"Moderate\", \"das28\"]))"
    clean = V.analyze(CHECKREG, [src(all_read)])
    @test isempty(clean.unused)
    @test !V.has_findings(clean)
    @test occursin("descr", V.report_string(clean))
end

@testset "unknown paths" begin
    rep = V.analyze(CHECKREG, [src("\$(val(\"descr\", [\"n_9\"]))")])
    @test rep.unknown == [(["descr", "n_9"], "manuscript.qmd", 1)]
    @test occursin("UNKNOWN PATH", V.report_string(rep))
    # findings show the call in the form the author must fix
    @test occursin("val(\"descr\", [\"n_9\"])", V.report_string(rep))

    # an unregistered value set is also an unknown path
    rep2 = V.analyze(CHECKREG, [src("\$(val(\"ghost\", [\"x\"]))")])
    @test rep2.unknown == [(["ghost", "x"], "manuscript.qmd", 1)]

    # a path that stops on an interior node is not a leaf reference and is unknown
    rep3 = V.analyze(CHECKREG, [src("\$(val(\"props\", [\"Moderate\"]))")])
    @test rep3.unknown == [(["props", "Moderate"], "manuscript.qmd", 1)]

    rep4 = V.analyze(CHECKREG, [src("\$(val(\n\"descr\", [\"n_0\"]))")])
    @test rep4.unparsed == [("manuscript.qmd", 1)]

    # a helper-built path is unparsed, not silently uncounted
    rep5 = V.analyze(CHECKREG, [src("\$(val(\"descr\", f(\"n_0\")))")])
    @test rep5.unparsed == [("manuscript.qmd", 1)]

    # commented-out reads do not count
    rep6 = V.analyze(CHECKREG, [src("<!-- \$(val(\"descr\", [\"n_0\"])) -->")])
    @test ["descr", "n_0"] in rep6.unused
end
