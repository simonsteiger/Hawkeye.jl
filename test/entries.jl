using Hawkeye
using Test

@testset "entry types" begin
    t = MainTable("k", "cap", "foot")
    @test t.key == "k" && t.caption == "cap" && t.footer == "foot"
    f = SuppFigure("g", "cap", "img.svg")
    @test f.path == "img.svg"

    @test Hawkeye.kind(t) == :table
    @test Hawkeye.kind(f) == :figure
    @test Hawkeye.location(t) == :main
    @test Hawkeye.location(f) == :supp

    # the two axes together are what numbering buckets on
    @test Hawkeye.bucket(MainTable("a", "", "")) == (:table, :main)
    @test Hawkeye.bucket(SuppTable("b", "", "")) == (:table, :supp)
    @test Hawkeye.bucket(MainFigure("c", "", "")) == (:figure, :main)
    @test Hawkeye.bucket(SuppFigure("d", "", "")) == (:figure, :supp)

    @test MainTable <: Hawkeye.AbstractTable <: Hawkeye.AbstractEntry
    @test SuppFigure <: Hawkeye.AbstractFigure <: Hawkeye.AbstractEntry
end

@testset "sanitize_join" begin
    # a part without a trailing period gains one
    @test sanitize_join("A: alpha", "note.") == "A: alpha. note."
    # a part that already ends in a period does not double it
    @test sanitize_join("A: alpha.", "note.") == "A: alpha. note."
    # variadic, not chained: three parts in one call
    @test sanitize_join("A: a", "n1.", "n2.") == "A: a. n1. n2."
    # a single part is still normalised
    @test sanitize_join("A: a") == "A: a."
    # empty parts are dropped, leaving no stray separator or period
    @test sanitize_join("a", "", "b") == "a. b."
    @test sanitize_join() == ""

    # surrounding whitespace is stripped, and warned about so the source can be cleaned
    res = @test_logs (:warn,) sanitize_join("A: a ", "note.")
    @test res == "A: a. note."
    # clean input warns about nothing
    @test_logs sanitize_join("A: a.", "note.")
end
