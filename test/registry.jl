using Hawkeye
using Test

const NUMBERING_ENTRIES = [
    MainTable("t1", "a", ""),
    MainTable("t2", "b", ""),
    SuppTable("s1", "c", ""),
    MainFigure("f1", "d", "f1.svg"),
    SuppFigure("g1", "e", "g1.svg"),
    SuppTable("s2", "f", ""),
]

qmd(text) = Source("manuscript.qmd", text)

@testset "Registry numbering" begin
    reg = Registry(NUMBERING_ENTRIES; sources=[cite_in_order(NUMBERING_ENTRIES)])
    # numbers count within a bucket, not across the registry
    @test Hawkeye.number(reg, "t1") == 1
    @test Hawkeye.number(reg, "t2") == 2
    @test Hawkeye.number(reg, "s1") == 1
    @test Hawkeye.number(reg, "s2") == 2
    @test Hawkeye.number(reg, "f1") == 1
    @test Hawkeye.number(reg, "g1") == 1
    @test isempty(reg.dropped)

    @test reg.bucket_order ==
          [(:table, :main), (:table, :supp), (:figure, :main), (:figure, :supp)]

    @test_throws "unknown manuscript key" Hawkeye._entry(reg, "nope")

    # the sources are required
    @test_throws UndefKeywordError Registry(NUMBERING_ENTRIES)
end

@testset "Registry numbers by first reference" begin
    text = """
    First \$(ref("t2")) and \$(ref("s2")), then \$(ref("g1")).
    Later \$(ref("t1")), \$(ref("s1")), \$(ref("t2")) and \$(ref("f1")).
    """
    reg = Registry(NUMBERING_ENTRIES; sources=[qmd(text)])
    @test Hawkeye.number(reg, "t2") == 1
    @test Hawkeye.number(reg, "t1") == 2
    @test Hawkeye.number(reg, "s2") == 1
    @test Hawkeye.number(reg, "s1") == 2
    @test Hawkeye.number(reg, "g1") == 1
    @test Hawkeye.number(reg, "f1") == 1
    # buckets in the order they are first cited
    @test reg.bucket_order ==
          [(:table, :main), (:table, :supp), (:figure, :supp), (:figure, :main)]

    # argument order within one call counts
    reg = Registry(NUMBERING_ENTRIES; sources=[qmd("\$(ref(\"t2\", \"t1\"))")])
    @test Hawkeye.number(reg, "t2") == 1
    @test Hawkeye.number(reg, "t1") == 2

    # calls on one line count in source order
    reg = Registry(
        NUMBERING_ENTRIES;
        sources=[qmd("\$(ref(\"t2\")) and then \$(ref(\"t1\"))")],
    )
    @test Hawkeye.number(reg, "t2") == 1

    # later references do not change numbers
    reg = Registry(
        NUMBERING_ENTRIES;
        sources=[qmd("\$(ref(\"t1\"))\n\$(ref(\"t2\"))\n\$(ref(\"t2\", \"t1\"))")],
    )
    @test Hawkeye.number(reg, "t1") == 1
    @test Hawkeye.number(reg, "t2") == 2

    # sources are read in the order given
    a = Source("a.qmd", "\$(ref(\"t2\"))")
    b = Source("b.qmd", "\$(ref(\"t1\"))")
    @test Hawkeye.number(Registry(NUMBERING_ENTRIES; sources=[a, b]), "t2") == 1
    @test Hawkeye.number(Registry(NUMBERING_ENTRIES; sources=[b, a]), "t2") == 2

    # a reference inside a comment does not count
    reg = Registry(
        NUMBERING_ENTRIES;
        sources=[qmd("<!-- \$(ref(\"t2\")) -->\n\$(ref(\"t1\")) \$(ref(\"t2\"))")],
    )
    @test Hawkeye.number(reg, "t1") == 1
    @test Hawkeye.number(reg, "t2") == 2
end

@testset "Registry drops uncited entries" begin
    reg = Registry(NUMBERING_ENTRIES; sources=[qmd("\$(ref(\"t2\", \"s2\"))")])
    @test reg.dropped == ["t1", "s1", "f1", "g1"]
    @test length(reg.entries) == length(NUMBERING_ENTRIES)
    @test !haskey(reg.index, "t1")
    @test !haskey(reg.numbers, "t1")
    @test Hawkeye.number(reg, "t2") == 1
    @test Hawkeye.number(reg, "s2") == 1
    @test reg.bucket_order == [(:table, :main), (:table, :supp)]

    msg = "\"t1\" is registered but never referenced in the sources"
    @test_throws msg Hawkeye.number(reg, "t1")
    @test_throws msg Hawkeye.ref(reg, "t1")
    @test_throws msg Hawkeye.ref(reg, "t2", "t1")

    # a reference inside a footer does not count
    entries = [MainTable("t1", "a", "See \$(ref(\"t2\"))."), MainTable("t2", "b", "")]
    reg = Registry(entries; sources=[qmd("\$(ref(\"t1\"))")])
    @test reg.dropped == ["t2"]

    # with no sources every entry is dropped
    @test Registry(NUMBERING_ENTRIES; sources=Source[]).dropped ==
          [e.key for e in NUMBERING_ENTRIES]
end

@testset "Registry rejects unreadable or unknown references" begin
    a = Source("a.qmd", "\$(ref(\"t1\"))")
    multiline = Source("b.qmd", "fine\n\$(ref(\n\"t2\"))")
    @test_throws "b.qmd:2" Registry(NUMBERING_ENTRIES; sources=[a, multiline])
    @test_throws "cannot read the ref( call" Registry(
        NUMBERING_ENTRIES;
        sources=[multiline],
    )

    ghost = Source("b.qmd", "line\nline\n\$(ref(\"t1\", \"ghost\"))")
    @test_throws "b.qmd:3: ref(\"ghost\") names no registered entry" Registry(
        NUMBERING_ENTRIES;
        sources=[a, ghost],
    )
    # an unknown key inside a comment is ignored
    commented = Source("d.qmd", "<!-- \$(ref(\"ghost\")) -->")
    @test Registry(NUMBERING_ENTRIES; sources=[commented]) isa Registry
end

@testset "Registry validation" begin
    none = Source[]
    # a duplicate entry key is rejected
    @test_throws "duplicate entry key" Registry(
        [MainTable("k", "a", ""), SuppTable("k", "b", "")];
        sources=none,
    )

    # caption carrying its own number prefix would render the number twice
    @test_throws "number prefix" Registry([MainTable("k", "Table 1: a", "")]; sources=none)
    @test_throws "number prefix" Registry(
        [SuppFigure("k", "supplementary Figure 2: a", "x.svg")];
        sources=none,
    )
    # a caption that merely mentions a number mid-sentence is fine
    mentions = [MainTable("k", "Compared with Table 1 of the prior study", "")]
    @test Registry(mentions; sources=[cite_in_order(mentions)]) isa Registry

    # duplicate value set name would make a val path ambiguous
    @test_throws "duplicate value set name" Registry(
        [MainTable("k", "a", "")],
        [ValueSet("v", Dict("a" => 1)), ValueSet("v", Dict("b" => 2))];
        sources=none,
    )

    # a pending key must name a registered entry, cited or not
    k = [MainTable("k", "a", "")]
    @test_throws "pending key is not a registered entry" Registry(
        k;
        sources=[cite_in_order(k)],
        pending=["ghost"],
    )
    @test Registry(k; sources=[cite_in_order(k)], pending=["k"]) isa Registry
    uncited_pending = Registry(k; sources=none, pending=["k"])
    @test uncited_pending.dropped == ["k"]
end

@testset "Registry value index" begin
    k = [MainTable("k", "a", "")]
    reg = Registry(k, [ValueSet("descr", Dict("n_0" => 872))]; sources=[cite_in_order(k)])
    @test reg.valindex["descr"].dict["n_0"] == 872
end
