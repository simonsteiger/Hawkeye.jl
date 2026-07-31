using Hawkeye
using Hawkeye.Checks
using Test

const S = Hawkeye.Checks

@testset "mask_comments" begin
    # newline count preserved, so later line numbers stay correct
    text = "a\n<!-- x\ny -->\nb"
    masked = S.mask_comments(text)
    @test count(==('\n'), masked) == count(==('\n'), text)
    @test split(masked, '\n')[4] == "b"
    @test !occursin("x", masked)

    # non-greedy: a second comment is not swallowed with the text between
    @test occursin("keep", S.mask_comments("<!-- a --> keep <!-- b -->"))
    @test !occursin("a", S.mask_comments("<!-- a --> keep <!-- b -->"))
    @test S.mask_comments("plain\ntext") == "plain\ntext"
end

@testset "mask_code_blocks" begin
    text = "before\n```{julia}\nusing Foo\n@macro x\n```\nafter"
    masked = S.mask_code_blocks(text)
    @test count(==('\n'), masked) == count(==('\n'), text)
    @test occursin("before", masked)
    @test occursin("after", masked)
    @test !occursin("@macro", masked)
    # inline code spans survive — ref calls live in `{julia} ref("k")` spans
    @test occursin("ref(", S.mask_code_blocks("see `{julia} ref(\"k\")`"))
end

@testset "extract_calls" begin
    calls, unparsed = S.extract_calls("x\n\$(ref(\"a\"))\n", "ref")
    @test [(c.args, c.line) for c in calls] == [(["a"], 2)]
    @test isempty(unparsed)

    # several keys in one call, order preserved
    calls, _ = S.extract_calls("\$(ref(\"a\", \"b\", \"c\"))", "ref")
    @test calls[1].args == ["a", "b", "c"]

    # two calls on one line: order across calls preserved
    calls, _ = S.extract_calls("\$(ref(\"a\")), \$(ref(\"b\"))", "ref")
    @test [c.args for c in calls] == [["a"], ["b"]]

    # inline `{julia} ref("k")` form
    calls, _ = S.extract_calls("see `{julia} ref(\"k\")`.", "ref")
    @test calls[1].args == ["k"]

    # whitespace tolerance
    calls, _ = S.extract_calls("\$(ref( \"a\" ,  \"b\" ))", "ref")
    @test calls[1].args == ["a", "b"]

    # a call the regex cannot read is reported, not silently dropped
    _, unparsed = S.extract_calls("\$(ref(\n\"a\"))", "ref")
    @test unparsed == [1]
    _, unparsed = S.extract_calls("\$(ref(k))", "ref")
    @test unparsed == [1]

    # the function name is a parameter, so val() reuses the same scanner
    calls, _ = S.extract_calls("\$(val(\"descr\", \"n_0\"))", "val")
    @test calls[1].args == ["descr", "n_0"]
    # and does not pick up the other function
    calls, _ = S.extract_calls("\$(ref(\"a\"))", "val")
    @test isempty(calls)
end

@testset "find_literals" begin
    hits = S.find_literals(
        "See Table 3 for details.\nnothing here\nsupplementary Figure 2 too",
    )
    @test hits == [(1, "Table 3"), (3, "supplementary Figure 2")]
    @test isempty(S.find_literals("Tables in general, no number."))
end

@testset "find_adjacent" begin
    # the real bug, manuscript.qmd:385
    l385 = "pattern (\$(ref(\"fig_rem_High\", \"prop_rem_High\")), \$(ref(\"prop_trt_High\", \"fig_trt_High\")))."
    @test S.find_adjacent(l385, "ref") == [1]

    # manuscript.qmd:254 — separated by real prose, correctly two calls
    l254 = "respectively (\$(ref(\"fig_descr\")); for details on all remission outcomes, see \$(ref(\"prop_rem\")))."
    @test isempty(S.find_adjacent(l254, "ref"))

    # a single call never fires
    @test isempty(S.find_adjacent("see `{julia} ref(\"def_rem\")`.", "ref"))
    # a semicolon alone is treated as a deliberate separator
    @test isempty(S.find_adjacent("(\$(ref(\"a\")); \$(ref(\"b\")))", "ref"))
    # a non-ASCII character before the calls must not corrupt offsets
    @test S.find_adjacent("dash – here (\$(ref(\"a\")), \$(ref(\"b\")))", "ref") == [1]
end
