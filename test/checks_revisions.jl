using Hawkeye
using Hawkeye.Checks
using Test

const RV = Hawkeye.Checks.Revisions

const REPLY = """
# Reviewer 1

::: {.comment status="done"}
Please clarify the sample size.
:::

::: {.revision section="Methods"}
We included 872 patients at baseline.
:::

::: {.comment status="in-progress"}
A second point.
:::

::: {.revision}
The revised text appears here.
:::

::: {.comment status="todo"}
A point we never answered.
:::

# Reviewer 2

::: {.comment}
First point for reviewer two.
:::

::: {.revision}
Something not in the manuscript at all.
:::
"""

@testset "normalize_text" begin
    # curly quotes straightened, dashes unified, whitespace collapsed
    @test RV.normalize_text("a" * Char(0x201C) * "b" * Char(0x201D)) == "a\"b\""
    @test RV.normalize_text("a–b") == "a-b"
    @test RV.normalize_text("  a   b\n c ") == "a b c"
end

@testset "extract" begin
    revs, comments = RV.extract(REPLY)
    @test [r.id for r in revs] == ["R1.1", "R1.2", "R2.1"]
    @test revs[1].section == "Methods"
    @test revs[2].section == ""
    @test occursin("872 patients", revs[1].text)

    # status rides on the comment div and is carried onto its revision
    @test revs[1].status == "done"
    @test revs[2].status == "in-progress"
    @test [c.id for c in comments] == ["R1.1", "R1.2", "R1.3", "R2.1"]
    @test [c.responded for c in comments] == [true, true, false, true]
end

@testset "analyze" begin
    manuscript = "Methods. We included 872 patients at baseline. The revised text appears here."
    rep = RV.analyze(REPLY, manuscript)
    found = Dict(r.id => r.found for r in rep.results)
    @test found["R1.1"]
    @test found["R1.2"]
    @test !found["R2.1"]
    @test RV.has_findings(rep)

    # a comment with no revision is an ORPHAN — a reviewer point with no recorded response
    @test [c.id for c in rep.orphans] == ["R1.3"]

    s = RV.report_string(rep)
    @test occursin("ORPHAN", s)
    @test occursin("done", s)
    @test occursin("R2.1", s)

    # normalisation applies to both sides: curly quotes in the manuscript still match
    rep2 = RV.analyze(
        "::: {.comment}\nc\n:::\n\n::: {.revision}\nthe \"quoted\" bit\n:::\n",
        "text with the " * Char(0x201C) * "quoted" * Char(0x201D) * " bit inside",
    )
    @test rep2.results[1].found
    @test !RV.has_findings(rep2)
end
