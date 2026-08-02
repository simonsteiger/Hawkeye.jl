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
    # dashes unified, whitespace collapsed
    @test RV.normalize_text("a–b") == "a-b"
    @test RV.normalize_text("  a   b\n c ") == "a b c"

    # double quotes carry no content and are dropped, straight and curly alike
    @test RV.normalize_text("\"quoted\"") == "quoted"
    @test RV.normalize_text("a" * Char(0x201C) * "b" * Char(0x201D)) == "ab"
    @test RV.normalize_text("«guillemets»") == "guillemets"

    # inline markup is dropped so a quote matches whether or not it carries it
    @test RV.normalize_text("**bold** and `code`") == "bold and code"
    @test RV.normalize_text("tau\$^2\$ = 3.3") == "tau2 = 3.3"
    @test RV.normalize_text("ends with a hard break\\") == "ends with a hard break"

    # apostrophes carry meaning in prose and survive
    @test RV.normalize_text("don" * Char(0x2019) * "t") == "don't"
end

@testset "line_needles" begin
    # a quote may open, close, or do neither on any given line
    @test RV.line_needles("\"A quoted sentence.\"") == ["A quoted sentence."]
    @test RV.line_needles("\"An unclosed opening quote.") == ["An unclosed opening quote."]
    @test RV.line_needles("A closing quote only.\"") == ["A closing quote only."]
    @test RV.line_needles("\"Ends with a hard break.\"\\") == ["Ends with a hard break."]

    # block markers are not part of the quoted text
    @test RV.line_needles("> \"Inside a blockquote.\"") == ["Inside a blockquote."]
    @test RV.line_needles("- A bullet.") == ["A bullet."]
    @test RV.line_needles("1. An ordered item.") == ["An ordered item."]

    # [...] marks an elided citation, so each side of it must match separately
    @test RV.line_needles("Before [...] after.") == ["Before", "after."]

    # a line with no letters or digits would match any manuscript
    @test isempty(RV.line_needles("\""))
    @test isempty(RV.line_needles("\\"))
    @test isempty(RV.line_needles("   "))
end

@testset "extract" begin
    revs, comments = RV.extract(REPLY)
    @test [r.id for r in revs] == ["R1.1", "R1.2", "R2.1"]
    @test revs[1].section == "Methods"
    @test revs[2].section == ""
    @test revs[1].lines == ["We included 872 patients at baseline."]
    @test revs[2].lines == ["The revised text appears here."]

    # status rides on the comment div and is carried onto its revision
    @test revs[1].status == "done"
    @test revs[2].status == "in-progress"
    @test [c.id for c in comments] == ["R1.1", "R1.2", "R1.3", "R2.1"]
    @test [c.responded for c in comments] == [true, true, false, true]
end

@testset "analyze" begin
    manuscript = "Methods. We included 872 patients at baseline. The revised text appears here."
    rep = RV.analyze(REPLY, manuscript)
    found = Dict(r.id => RV.found(r) for r in rep.results)
    @test found["R1.1"]
    @test found["R1.2"]
    @test !found["R2.1"]
    @test RV.has_findings(rep)

    # a comment with no revision is an ORPHAN — a reviewer point with no recorded response
    @test [c.id for c in rep.orphans] == ["R1.3"]

    # single-line revisions report one content-bearing line
    @test Dict(r.id => r.nlines for r in rep.results)["R1.1"] == 1

    s = RV.report_string(rep)
    @test occursin("ORPHAN", s)
    @test occursin("done", s)
    @test occursin("R2.1", s)

    # normalisation applies to both sides: curly quotes in the manuscript still match
    rep2 = RV.analyze(
        "::: {.comment}\nc\n:::\n\n::: {.revision}\nthe \"quoted\" bit\n:::\n",
        "text with the " * Char(0x201C) * "quoted" * Char(0x201D) * " bit inside",
    )
    @test RV.found(rep2.results[1])
    @test !RV.has_findings(rep2)
end
