# border_title_tests.jl -- captions drawn ON the border.
# Written BEFORE the implementation (TDD, CLAUDE.md).
#
# A widget CANNOT paint its own border: `_paint_node!` hands `render!`
# the CONTENT box, and the border is outside it. So a title is not a
# `render!` concern at all -- it is painted by the paint pass, which
# asks each node for one through `border_title`. These tests pin that
# seam and, above all, pin that a title NEVER touches a corner: an
# overwritten corner is a broken frame, and it is the failure mode of
# every hand-rolled version of this.

@testitem "border title: a widget has none by default" begin
    using ManyUI, ManyUITUI

    @test border_title(Container()) == RichText()
    @test border_title(Label("x")) == RichText()
    @test border_title_align(Container()) === Align.START

    # An untitled bordered box is an unbroken frame.
    c = Container()
    apply_stylesheet!(parse_css("Container { border: solid; }"), c)
    layout!(c, Region(1, 1, 6, 3))
    buf = Buffer(6, 3)
    paint!(buf, c)

    g = border_glyphs(BorderKind.SOLID)
    top = join(String(buf[x, 1].content) for x = 1:6)
    @test top == string(g[1], g[2], g[2], g[2], g[2], g[3])
end

@testitem "border title: a Container caption lands on the top edge" begin
    using ManyUI, ManyUITUI

    c = Container(; title = "Log")
    @test plain(border_title(c)) == "Log"

    apply_stylesheet!(parse_css("Container { border: solid; }"), c)
    layout!(c, Region(1, 1, 12, 3))
    buf = Buffer(12, 3)
    paint!(buf, c)

    g = border_glyphs(BorderKind.SOLID)
    top = join(String(buf[x, 1].content) for x = 1:12)
    # Padded with one space each side so the caption does not touch the
    # line, and inset from the corner.
    @test top == string(g[1], g[2], " Log ", g[2], g[2], g[2], g[2], g[3])
    # The corners are still corners.
    @test String(buf[1, 1].content) == string(g[1])
    @test String(buf[12, 1].content) == string(g[3])
end

@testitem "border title: alignment moves it along the edge" begin
    using ManyUI, ManyUITUI

    function top_of(align)
        c = Container(; title = "ab", title_align = align)
        apply_stylesheet!(parse_css("Container { border: solid; }"), c)
        layout!(c, Region(1, 1, 12, 3))
        buf = Buffer(12, 3)
        paint!(buf, c)
        return join(String(buf[x, 1].content) for x = 1:12)
    end

    g = border_glyphs(BorderKind.SOLID)
    e = string(g[2])
    @test top_of(Align.START) == string(g[1], e, " ab ", e^5, g[3])
    @test top_of(Align.END) == string(g[1], e^5, " ab ", e, g[3])
    mid = top_of(Align.CENTER)
    @test occursin(" ab ", mid)
    @test startswith(mid, string(g[1], e, e))
    @test endswith(mid, string(e, e, g[3]))
end

@testitem "border title: a caption too long is cut, never the corners" begin
    using ManyUI, ManyUITUI

    # Eight cells of frame leave four for a padded caption once the
    # two corners and the two kept edge glyphs are taken out. Anything
    # more is cut -- the alternative is writing over a corner, which
    # breaks the frame.
    c = Container(; title = "abcdefghij")
    apply_stylesheet!(parse_css("Container { border: solid; }"), c)
    layout!(c, Region(1, 1, 8, 3))
    buf = Buffer(8, 3)
    paint!(buf, c)

    g = border_glyphs(BorderKind.SOLID)
    @test String(buf[1, 1].content) == string(g[1])
    @test String(buf[8, 1].content) == string(g[3])
    top = join(String(buf[x, 1].content) for x = 1:8)
    @test top == string(g[1], g[2], " ab ", g[2], g[3])
end

@testitem "border title: a box too narrow for a caption keeps its frame" begin
    using ManyUI, ManyUITUI

    for w in 1:6
        c = Container(; title = "abc")
        apply_stylesheet!(parse_css("Container { border: solid; }"), c)
        layout!(c, Region(1, 1, w, 3))
        buf = Buffer(w, 3)
        # No room for a padded caption between two corners: the frame
        # must survive untouched rather than lose a corner to it.
        paint!(buf, c)
        row = join(String(buf[x, 1].content) for x = 1:w)
        @test !occursin("a", row)
    end
end

@testitem "border title: no border means no title" begin
    using ManyUI, ManyUITUI

    c = Container(; title = "Log")
    apply_stylesheet!(STYLESHEET_EMPTY, c)      # BORDER_NONE
    layout!(c, Region(1, 1, 12, 3))
    buf = Buffer(12, 3)
    paint!(buf, c)

    @test !occursin("Log", string(buf))
end

@testitem "border title: a rich caption keeps its runs" begin
    using ManyUI, ManyUITUI

    warn = Style(fg = rgb(255, 200, 0), bold = true)
    c = Container(; title = RichText(TextRun("!", warn), TextRun(" Log")))

    apply_stylesheet!(parse_css("Container { border: solid cyan; }"), c)
    layout!(c, Region(1, 1, 14, 3))
    buf = Buffer(14, 3)
    paint!(buf, c)

    # Column 1 is the corner, 2 the kept edge glyph, 3 the pad, and 4
    # the styled "!".
    @test String(buf[4, 1].content) == "!"
    @test buf[4, 1].style.fg == rgb(255, 200, 0)
    @test has(buf[4, 1].style, Attr.BOLD)
    # An unstyled run falls back to the BORDER's style, so a plain
    # caption matches the line it sits on rather than resetting. Column
    # 6 is inside " Log"; column 12 is bare edge.
    @test String(buf[6, 1].content) == "L"
    @test buf[6, 1].style.fg == buf[12, 1].style.fg
    @test !has(buf[6, 1].style, Attr.BOLD)
end

@testitem "border title: setting one repaints without relayout" begin
    using ManyUI, ManyUITUI

    c = Container(; title = "a")
    apply_stylesheet!(parse_css("Container { border: solid; }"), c)
    layout!(c, Region(1, 1, 10, 3))
    clean!(c)

    c.title[] = "a"
    @test !is_dirty(c)                    # E1: an equal write is a no-op

    c.title[] = "bb"
    @test is_dirty(c, Dirty.PAINT)
    # PAINT and not LAYOUT, and it is provable rather than optimistic:
    # `measure` does not read the title, so a new caption cannot move
    # this widget or any of its siblings. The border row it lands on
    # exists whether or not there is a caption on it.
    @test !is_dirty(c, Dirty.LAYOUT)
end
