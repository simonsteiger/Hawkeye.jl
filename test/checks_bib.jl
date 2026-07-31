using Hawkeye
using Hawkeye.Checks
using Test

const B = Hawkeye.Checks.Bib

const BIBTEXT = """
@article{smith2020,
  title = {A paper},
  author = {Smith, J},
}

@book{jones2019, title = {A book} }

@misc{unused2021, title = {Never cited} }
"""

@testset "bib_keys" begin
    @test sort(B.bib_keys(BIBTEXT)) == ["jones2019", "smith2020", "unused2021"]
    @test isempty(B.bib_keys("no entries here"))
end

@testset "citations — all four pandoc spellings" begin
    @test B.citations("text [@smith2020] more") == [("smith2020", 1)]
    @test B.citations("[@smith2020; @jones2019]") == [("smith2020", 1), ("jones2019", 1)]
    @test B.citations("as @smith2020 [p. 33] showed") == [("smith2020", 1)]
    @test B.citations("[-@smith2020]") == [("smith2020", 1)]
    # keys may contain the punctuation pandoc allows
    @test B.citations("[@smith_2020a:b]") == [("smith_2020a:b", 1)]
    # line numbers are tracked
    @test B.citations("a\nb [@x]") == [("x", 2)]
    # a trailing sentence period is punctuation, not part of the key (matches pandoc)
    @test B.citations("Shown by @smith2020.") == [("smith2020", 1)]
end

@testset "code blocks are not citations" begin
    text = """
    prose [@smith2020]
    ```{julia}
    using Foo
    @model f(x) = x
    @__DIR__
    ```
    more prose
    """
    # Julia macros inside a fenced block must not read as citations
    @test B.citations(Hawkeye.Checks.mask_code_blocks(text)) == [("smith2020", 1)]
end

@testset "analyze" begin
    text = "Intro [@smith2020]. Again [@smith2020; @jones2019]. Also [@ghost2000]."
    rep = B.analyze(BIBTEXT, [src(text)])
    rows = Dict(r.key => r for r in rep.rows)
    @test rows["smith2020"].count == 2
    @test rows["jones2019"].count == 1
    @test rows["unused2021"].count == 0
    @test rows["smith2020"].first == ("manuscript.qmd", 1)

    @test rep.uncited == ["unused2021"]
    @test rep.missing_keys == [("ghost2000", "manuscript.qmd", 1)]
    @test B.has_findings(rep)
    s = B.report_string(rep)
    @test occursin("UNCITED", s) && occursin("MISSING", s)

    # everything cited, nothing dangling
    clean = B.analyze("@article{a,}\n@book{b,}", [src("[@a] and [@b]")])
    @test !B.has_findings(clean)
    @test occursin("2", B.report_string(clean))

    # commented-out citations do not count
    rep2 = B.analyze("@article{a,}", [src("<!-- [@a] -->")])
    @test rep2.uncited == ["a"]

    # a missing key cited repeatedly is reported once, keeping the first occurrence's location
    rep3 = B.analyze(
        "@article{a,}",
        [src("First [@ghost2000] and again [@ghost2000] and once more [@ghost2000].")],
    )
    @test rep3.missing_keys == [("ghost2000", "manuscript.qmd", 1)]
end
