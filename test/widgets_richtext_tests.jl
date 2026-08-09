# widgets_richtext_tests.jl -- Label and Static carrying a RichText.
# Written BEFORE the implementation (TDD, CLAUDE.md).
#
# The point of these: a run's style is a DIFFERENCE folded over the
# widget's computed style, so the same RichText paints correctly under
# any theme, and adding style to a label must not move where it wraps.

@testitem "richtext widgets: Label accepts a plain string unchanged" begin
    using ManyUI, ManyUITUI

    l = Label("hello world")
    @test plain(l.text[]) == "hello world"
    @test l.text[] == RichText("hello world")
    @test measure(l, Size(5, 5)) == Size(5, 2)

    buf = Buffer(5, 3)
    render!(l, buf)
    @test string(buf) == "hello\nworld\n     "
end

@testitem "richtext widgets: a string assignment still converts" begin
    using ManyUI, ManyUITUI

    # reactive.jl documents `label.text[] = \"hi\"` verbatim. It must
    # keep working now that the cell holds a RichText.
    l = Label("one")
    clean!(l)
    l.text[] = "one"
    @test !is_dirty(l)                 # E1: an equal write is a no-op
    l.text[] = "two"
    @test plain(l.text[]) == "two"
    @test is_dirty(l, Dirty.LAYOUT)

    # And an equal write spelled as a RichText is a no-op too, which is
    # only true because RichText has value equality.
    clean!(l)
    l.text[] = RichText("two")
    @test !is_dirty(l)
end

@testitem "richtext widgets: Label paints a run's style over its own" begin
    using ManyUI, ManyUITUI

    warn = Style(fg = rgb(255, 200, 0), bold = true)
    l = Label(RichText(TextRun("1", warn), TextRun(" Server")))

    buf = Buffer(8, 1)
    render!(l, buf)
    @test string(buf) == "1 Server"

    # The styled run: exactly what it named.
    @test buf[1, 1].style.fg == rgb(255, 200, 0)
    @test has(buf[1, 1].style, Attr.BOLD)
    # The unstyled run: the widget's own style, NOT a reset -- and in
    # particular not bold, or the override would have leaked right.
    @test !has(buf[3, 1].style, Attr.BOLD)
end

@testitem "richtext widgets: an unstyled run inherits the widget style" begin
    using ManyUI, ManyUITUI

    # A Label under a theme: the widget's computed style supplies the
    # colours, the run supplies only `bold`. Both must survive.
    l = Label(RichText(TextRun("ab", Style(bold = true)), TextRun("cd")))
    root = Container(l)
    apply_stylesheet!(parse_css("Label { color: #00ff00; }"), root)
    layout!(root, Region(1, 1, 4, 1))

    buf = Buffer(4, 1)
    paint!(buf, root)

    @test string(buf) == "abcd"
    for x = 1:4
        @test buf[x, 1].style.fg == rgb(0, 255, 0)   # from the cascade
    end
    @test has(buf[1, 1].style, Attr.BOLD)            # from the run
    @test has(buf[2, 1].style, Attr.BOLD)
    @test !has(buf[3, 1].style, Attr.BOLD)
    @test !has(buf[4, 1].style, Attr.BOLD)
end

@testitem "richtext widgets: Label wraps a RichText where it wraps the text" begin
    using ManyUI, ManyUITUI

    bold = Style(bold = true)
    rt = RichText(TextRun("aaa", bold), TextRun(" bbb"))
    l = Label(rt)

    # Styling changed nothing about the geometry.
    @test measure(l, Size(3, 5)) == measure(Label(plain(rt)), Size(3, 5))

    buf = Buffer(3, 2)
    render!(l, buf)
    @test string(buf) == "aaa\nbbb"
    @test has(buf[1, 1].style, Attr.BOLD)
    @test !has(buf[1, 2].style, Attr.BOLD)   # the style did not run on
end

@testitem "richtext widgets: Static paints runs and truncates at the edge" begin
    using ManyUI, ManyUITUI

    bold = Style(bold = true)
    s = Static(RichText(TextRun("abc", bold), TextRun("def")))

    @test measure(s, Size(10, 10)) == Size(6, 1)
    @test plain(s.text[]) == "abcdef"

    buf = Buffer(4, 1)
    render!(s, buf)
    @test string(buf) == "abcd"
    @test has(buf[3, 1].style, Attr.BOLD)
    @test !has(buf[4, 1].style, Attr.BOLD)
end

@testitem "richtext widgets: a clipped run stops the ones behind it" begin
    using ManyUI, ManyUITUI

    bold = Style(bold = true)
    # "好" is width 2 and cannot be halved at the edge. The narrow "a"
    # behind it must NOT be pulled forward into the freed cell: what is
    # painted is a prefix, the same rule truncate_width applies.
    s = Static(RichText(TextRun("x好", bold), TextRun("a")))

    buf = Buffer(2, 1)
    render!(s, buf)
    @test buf[1, 1].content == "x"
    @test buf[2, 1] == CELL_BLANK
end

@testitem "richtext widgets: a tab caption may be styled mid-word" begin
    using ManyUI, ManyUITUI

    # The Kaimon idiom: the shortcut key in a warning colour, the
    # caption in the inherited one. This is the case that motivated the
    # whole primitive -- three nodes per tab was the alternative.
    warn = Style(fg = rgb(255, 200, 0), bold = true)
    cap = RichText(TextRun("1", warn), TextRun(" Server"))

    t = Tabs(cap => Container(), "2 Sessions" => Container())
    @test n_tabs(t) == 2
    @test tab_title(t, 1) == cap
    @test tab_title(t, 2) == RichText("2 Sessions")

    strip = t.strip
    apply_stylesheet!(STYLESHEET_EMPTY, t)
    # " 1 Server " is 10 cells, " 2 Sessions " is 12.
    @test measure(strip, Size(80, 1)) == Size(22, 1)

    buf = Buffer(22, 1)
    render!(strip, buf)
    @test string(buf) == " 1 Server  2 Sessions "

    # Column 2 is the styled digit; column 4 is inside " Server".
    @test buf[2, 1].content == "1"
    @test buf[2, 1].style.fg == rgb(255, 200, 0)
    @test has(buf[2, 1].style, Attr.BOLD)
    @test !has(buf[4, 1].style, Attr.BOLD)
end

@testitem "richtext widgets: a rich caption still hit-tests by width" begin
    using ManyUI, ManyUITUI

    bold = Style(bold = true)
    t = Tabs(RichText("ab", bold) => Container(), "cdef" => Container())
    strip = t.strip

    # Styling must not shift the clickable regions: " ab " is columns
    # 1-4, " cdef " is 5-10.
    @test ManyUI.tab_at(strip.titles, 1) == 1
    @test ManyUI.tab_at(strip.titles, 4) == 1
    @test ManyUI.tab_at(strip.titles, 5) == 2
    @test ManyUI.tab_at(strip.titles, 10) == 2
    @test ManyUI.tab_at(strip.titles, 11) == 0
end

@testitem "richtext widgets: a List format may return a RichText" begin
    using ManyUI, ManyUITUI

    warn = Style(fg = rgb(255, 0, 0))
    # A log list: the level coloured, the message not.
    rows = [(:error, "disk full"), (:info, "ok")]
    fmt = r -> RichText(TextRun(String(r[1]), r[1] === :error ? warn : STYLE_NONE),
                        TextRun(" " * r[2]))
    l = List(rows; format = fmt)

    apply_stylesheet!(STYLESHEET_EMPTY, l)
    buf = Buffer(16, 2)
    render!(l, buf)

    row1 = join(String(buf[x, 1].content) for x = 1:16)
    @test rstrip(row1) == "error disk full"
    @test buf[1, 1].style.fg == rgb(255, 0, 0)     # the level
    @test buf[7, 1].style.fg != rgb(255, 0, 0)     # the message
    @test buf[1, 2].style.fg != rgb(255, 0, 0)     # :info is unstyled
end

@testitem "richtext widgets: a Table cell may return a RichText" begin
    using ManyUI, ManyUITUI

    bold = Style(bold = true)
    t = Table([1, 2], [Column("N"; width = cells(6))];
              cell = (r, j) -> RichText(TextRun("a", bold), TextRun("b")))

    apply_stylesheet!(STYLESHEET_EMPTY, t)
    buf = Buffer(6, 3)
    render!(t, buf)

    # Row 1 sits under the header.
    @test buf[1, 2].content == "a"
    @test has(buf[1, 2].style, Attr.BOLD)
    @test buf[2, 2].content == "b"
    @test !has(buf[2, 2].style, Attr.BOLD)
end

@testitem "richtext widgets: a rich cell too wide is cut and marked" begin
    using ManyUI, ManyUITUI

    bold = Style(bold = true)
    # Four cells for six characters: the column must cut and mark the
    # cut exactly as it does for a plain string.
    t = Table([1], [Column("N"; width = cells(4))];
              cell = (r, j) -> RichText(TextRun("abc", bold), TextRun("def")))

    apply_stylesheet!(STYLESHEET_EMPTY, t)
    buf = Buffer(4, 2)
    render!(t, buf)

    @test buf[1, 2].content == "a"
    @test buf[2, 2].content == "b"
    @test buf[3, 2].content == "c"
    @test String(buf[4, 2].content) == ManyUI.TC_ELLIPSIS
    @test has(buf[1, 2].style, Attr.BOLD)
end
