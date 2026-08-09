# widgets_markdown_tests.jl -- the Markdown pane.
# Written BEFORE the implementation (TDD, CLAUDE.md).
#
# The pane parses with the stdlib and only PROJECTS: AST to a
# `Vector{RichText}`. So these test the projection, which is the only
# part that is ours -- and above all they test the two things a
# hand-rolled renderer gets wrong: what a wrapped list item looks like,
# and what happens when the box changes width.

@testitem "markdown: a document is lines, not a subtree" begin
    using ManyUI, ManyUITUI

    p = MarkdownPane("# Title\n\nSome text.")
    @test isempty(children(p))          # a document is ONE node
    ls = md_lines(p, 40)
    @test plain(ls[1]) == "Title"
    @test isempty(ls[2])                # one blank row between blocks
    @test plain(ls[3]) == "Some text."
    @test content_extent(p).height == length(ls)
end

@testitem "markdown: inline styling becomes runs, not nodes" begin
    using ManyUI, ManyUITUI

    p = MarkdownPane("Some **bold** and *ital* and `code` and [x](http://y).")
    l = md_lines(p, 60)[1]

    @test plain(l) == "Some bold and ital and code and x."
    # A link shows its TEXT, never its URL: a pane is for reading.
    @test !occursin("http", plain(l))

    # Each fragment carries its own style, all on one line.
    styles = Dict(r.text => r.style for r in l.runs)
    @test has(styles["bold"], Attr.BOLD)
    @test has(styles["ital"], Attr.ITALIC)
    @test styles["code"] == MD_CODE
    @test has(styles["x"], Attr.UNDERLINE)
end

@testitem "markdown: a wrapped list item is ONE item" begin
    using ManyUI, ManyUITUI

    # THE bug a single prefix produces: repeating the bullet on the
    # continuation, so one item reads as two.
    p = MarkdownPane("- aaa bbb ccc ddd eee\n- short")
    ls = md_lines(p, 12)

    @test startswith(plain(ls[1]), "• ")
    @test !startswith(plain(ls[2]), "• ")     # indent, not a bullet
    @test startswith(plain(ls[2]), "  ")
    @test startswith(plain(ls[end]), "• short")
end

@testitem "markdown: an ordered list numbers and indents under itself" begin
    using ManyUI, ManyUITUI

    p = MarkdownPane("1. aaa bbb ccc ddd\n2. two")
    ls = md_lines(p, 12)
    @test startswith(plain(ls[1]), "1. ")
    @test startswith(plain(ls[2]), "   ")     # three, matching "1. "
    @test any(l -> startswith(plain(l), "2. two"), ls)
end

@testitem "markdown: a quote marks every line it covers" begin
    using ManyUI, ManyUITUI

    # A quote is the opposite case: the marker repeats, because a
    # continuation without it has left the quote.
    p = MarkdownPane("> aaa bbb ccc ddd eee fff")
    ls = md_lines(p, 12)
    @test length(ls) >= 2
    @test all(l -> startswith(plain(l), "│ "), ls)
end

@testitem "markdown: a code block is never wrapped" begin
    using ManyUI, ManyUITUI

    src = "```julia\nf(x) = a_very_long_expression_here(x)\ng(x) = x\n```"
    p = MarkdownPane(src)
    ls = md_lines(p, 10)

    # A broken line of code is a DIFFERENT line of code, so it is left
    # long and the pane scrolls sideways instead.
    @test length(ls) == 2
    @test plain(ls[1]) == "f(x) = a_very_long_expression_here(x)"
    @test plain(ls[2]) == "g(x) = x"
    @test ls[1].runs[1].style == MD_CODE
    @test content_extent(p).width > 10
end

@testitem "markdown: the line cache is keyed on the width" begin
    using ManyUI, ManyUITUI

    p = MarkdownPane("aaa bbb ccc ddd eee fff ggg")
    wide = md_lines(p, 40)
    @test length(wide) == 1
    # Same width: the SAME vector, not an equal one -- that is the
    # cache doing its job rather than reflowing once a frame.
    @test md_lines(p, 40) === wide

    narrow = md_lines(p, 10)
    @test length(narrow) > 1
    @test narrow !== wide
    # And back again rebuilds rather than returning the narrow breaks.
    @test length(md_lines(p, 40)) == 1
end

@testitem "markdown: replacing the source reparses and drops the cache" begin
    using ManyUI, ManyUITUI

    p = MarkdownPane("one")
    md_lines(p, 20)
    clean!(p)

    set_source!(p, "one")
    @test !is_dirty(p)                  # E1: an equal write is a no-op

    set_source!(p, "# two")
    @test is_dirty(p, Dirty.PAINT)
    @test plain(md_lines(p, 20)[1]) == "two"
    @test md_lines(p, 20)[1].runs[1].style == MD_HEADING
end

@testitem "markdown: headings and rules are themed, not hard-coded" begin
    using ManyUI, ManyUITUI

    # The styles name TOKENS, so a document tracks the palette instead
    # of being repainted for it.
    @test is_token(MD_HEADING.fg)
    @test is_token(MD_CODE.fg)
    @test is_token(MD_LINK.fg)

    before = theme()
    try
        set_theme!(:dark)
        dark = resolve_token(MD_HEADING.fg)
        set_theme!(:light)
        @test resolve_token(MD_HEADING.fg) != dark
    finally
        set_theme!(before)
    end
end

@testitem "markdown: it paints and scrolls" begin
    using ManyUI, ManyUITUI

    p = MarkdownPane("# T\n\naaa\n\nbbb")
    apply_stylesheet!(STYLESHEET_EMPTY, p)
    buf = Buffer(6, 2)
    render!(p, buf)
    rows = [join(String(buf[x, y].content) for x = 1:6) for y = 1:2]
    @test rstrip(rows[1]) == "T"

    # Scrolled: the same document, a later window of it.
    set_scroll!(p, Offset(0, 2))
    buf2 = Buffer(6, 2)
    render!(p, buf2)
    @test rstrip(join(String(buf2[x, 1].content) for x = 1:6)) == "aaa"

    # An over-scroll is blank rows, never a BoundsError.
    set_scroll!(p, Offset(0, 500))
    render!(p, Buffer(6, 2))
end

@testitem "markdown: an empty document is empty, not an error" begin
    using ManyUI, ManyUITUI

    p = MarkdownPane()
    @test isempty(md_lines(p, 20))
    @test content_extent(p) == Size(0, 0) || content_extent(p).height == 0
    render!(p, Buffer(4, 2))
end
