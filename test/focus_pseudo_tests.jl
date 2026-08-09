# focus_pseudo_tests.jl -- `:focus` and `:focus-within` in the cascade.
# Written BEFORE the implementation (TDD, CLAUDE.md).
#
# The point of these is what they REPLACE. A focus ring drawn by hand is
# a branch in every widget's `render!` and a style recomputed at every
# call site -- Kaimon has 63 of them for its pane borders alone. As a
# stylesheet rule it is one line, and the widgets stop knowing about it.

@testitem "focus pseudo: the parser accepts both and ranks them" begin
    using ManyUI, ManyUITUI

    ss = parse_css("""
        Button:focus         { color: #ff0000; }
        Container:focus-within { color: #00ff00; }
    """)
    @test length(ss.rules) == 2

    # A pseudo-class ranks with a class, exactly as in CSS: it beats a
    # bare type and loses to an id.
    @test specificity(ss.rules[1].selector) == Specificity(0, 1, 1)
    @test specificity(parse_css("Button { color: red; }").rules[1].selector) ==
          Specificity(0, 0, 1)
    @test specificity(parse_css("#x { color: red; }").rules[1].selector) >
          specificity(ss.rules[1].selector)

    # An unknown one is a parse error with a position, like every other
    # bad token -- not a selector that silently never matches.
    @test_throws CssParseError parse_css("Button:hover { color: red; }")
    @test_throws CssParseError parse_css("Button:nope { color: red; }")
end

@testitem "focus pseudo: a descendant combinator may end in a pseudo" begin
    using ManyUI, ManyUITUI

    ss = parse_css("Container > Button:focus { color: #ff0000; }")
    @test length(ss.rules) == 1
    ss2 = parse_css("Container :focus { color: #ff0000; }")
    @test length(ss2.rules) == 1
end

@testitem "focus pseudo: focus! sets the node flags along one chain" begin
    using ManyUI, ManyUITUI

    b = Button("b", identity)
    inner = Container(b)
    root = Container(inner)
    app = App(root, HeadlessDriver(Size(20, 5)))

    @test !ManyUITUI.node(b).focused
    @test !ManyUITUI.node(inner).focus_within

    focus!(app, b)
    @test ManyUITUI.node(b).focused
    # Every ancestor, and only ancestors.
    @test ManyUITUI.node(inner).focus_within
    @test ManyUITUI.node(root).focus_within
    @test !ManyUITUI.node(inner).focused
    @test !ManyUITUI.node(root).focused

    other = Button("o", identity)
    mount!(root, other)
    focus!(app, other)
    @test !ManyUITUI.node(b).focused
    @test !ManyUITUI.node(inner).focus_within   # cleared on the way out
    @test ManyUITUI.node(other).focused
    @test ManyUITUI.node(root).focus_within
end

@testitem "focus pseudo: a focus ring is a stylesheet rule" begin
    using ManyUI, ManyUITUI

    a = Button("a", identity)
    b = Button("b", identity)
    root = Container(a, b)
    sheet = parse_css("""
        Button        { color: #808080; }
        Button:focus  { color: #ff0000; }
    """)
    app = App(root, HeadlessDriver(Size(20, 5)); stylesheet = sheet)

    apply_stylesheet!(sheet, root)
    @test computed_style(a).fg == rgb(0x80, 0x80, 0x80)
    @test computed_style(b).fg == rgb(0x80, 0x80, 0x80)

    focus!(app, a)
    recascade!(sheet, root)
    # The rule fired, and only for the focused one. No widget's render!
    # knows anything about it.
    @test computed_style(a).fg == rgb(0xff, 0x00, 0x00)
    @test computed_style(b).fg == rgb(0x80, 0x80, 0x80)

    focus!(app, b)
    recascade!(sheet, root)
    @test computed_style(a).fg == rgb(0x80, 0x80, 0x80)
    @test computed_style(b).fg == rgb(0xff, 0x00, 0x00)
end

@testitem "focus pseudo: focus-within styles the PANE, not the widget" begin
    using ManyUI, ManyUITUI

    # THE case that removes the hand-written pane rings: focus lands on
    # a widget inside a pane, and it is the PANE that must light up.
    table = Button("rows", identity)
    pane = Container(table; classes = [:pane])
    other = Container(Button("x", identity); classes = [:pane])
    root = Container(pane, other)

    sheet = parse_css("""
        .pane              { color: #303030; }
        .pane:focus-within { color: #00ffff; }
    """)
    app = App(root, HeadlessDriver(Size(30, 6)); stylesheet = sheet)
    apply_stylesheet!(sheet, root)
    @test computed_style(pane).fg == rgb(0x30, 0x30, 0x30)

    focus!(app, table)
    recascade!(sheet, root)
    @test computed_style(pane).fg == rgb(0x00, 0xff, 0xff)
    @test computed_style(other).fg == rgb(0x30, 0x30, 0x30)
    # The focused widget itself is not a .pane and is untouched by it.
    @test ManyUITUI.node(table).focused
    @test !ManyUITUI.node(table).focus_within
end

@testitem "focus pseudo: a ring may be the BORDER, not just the text" begin
    using ManyUI, ManyUITUI

    # A pane ring is a border colour, and the border lives in the BOX,
    # not in the text style -- so the pseudo-class has to reach the box
    # half of the cascade too, which is a different code path.
    inner = Button("x", identity)
    pane = Container(inner; title = "Pane")
    root = Container(pane)
    sheet = parse_css("""
        Container              { border: solid #303030; }
        Container:focus-within { border: solid #00ffff; }
    """)
    app = App(root, HeadlessDriver(Size(14, 4)); stylesheet = sheet)

    apply_stylesheet!(sheet, root)
    @test box(pane).border.kind === BorderKind.SOLID
    @test box(pane).border.style.fg == rgb(0x30, 0x30, 0x30)

    focus!(app, inner)
    recascade!(sheet, root)
    @test box(pane).border.style.fg == rgb(0x00, 0xff, 0xff)
    @test box(pane).border.kind === BorderKind.SOLID

    # And a box change is LAYOUT-dirty, not merely PAINT: a border that
    # appears takes a cell from the content.
    @test is_dirty(pane, Dirty.LAYOUT) || is_dirty(pane, Dirty.PAINT)
end

@testitem "focus pseudo: TAB moves the ring with the focus" begin
    using ManyUI, ManyUITUI

    a, b = Button("a", identity), Button("b", identity)
    pa, pb = Container(a; classes = [:pane]), Container(b; classes = [:pane])
    root = Container(pa, pb)
    sheet = parse_css(".pane:focus-within { color: #00ffff; }")
    app = App(root, HeadlessDriver(Size(30, 6)); stylesheet = sheet)
    apply_stylesheet!(sheet, root)

    focus_next!(app)
    recascade!(sheet, root)
    @test computed_style(pa).fg == rgb(0x00, 0xff, 0xff)
    @test computed_style(pb).fg != rgb(0x00, 0xff, 0xff)

    focus_next!(app)
    recascade!(sheet, root)
    @test computed_style(pa).fg != rgb(0x00, 0xff, 0xff)
    @test computed_style(pb).fg == rgb(0x00, 0xff, 0xff)
end
