using Hawkeye
using Test

@testset "sanitize_join" begin
    # a part without a trailing period gains one
    @test sanitize_join("A: alpha", "note.") == "A: alpha. note."
    # a part that already ends in a period does not double it
    @test sanitize_join("A: alpha.", "note.") == "A: alpha. note."
    # three parts in one call
    @test sanitize_join("A: a", "n1.", "n2.") == "A: a. n1. n2."
    # a single part is still normalised
    @test sanitize_join("A: a") == "A: a."
    # empty parts are dropped, leaving no stray separator or period
    @test sanitize_join("a", "", "b") == "a. b."

    # surrounding whitespace is stripped with a warning
    res = @test_logs (:warn,) sanitize_join("A: a ", "note.")
    @test res == "A: a. note."
    # clean input warns about nothing
    @test_logs sanitize_join("A: a.", "note.")
end
