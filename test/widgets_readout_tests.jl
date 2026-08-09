# widgets_readout_tests.jl -- Sparkline, StatusBar, and the labelled
# ProgressBar that other toolkits call a gauge.
# Written BEFORE the implementation (TDD, CLAUDE.md).

@testitem "sparkline: a series is data, not a widget per point" begin
    using ManyUI, ManyUITUI

    sp = Sparkline([1, 2, 3])
    @test n_values(sp) == 3
    @test isempty(children(sp))
    @test measure(sp, Size(80, 24)) == Size(3, 1)

    clean!(sp)                 # a fresh node is dirty in every plane
    push_value!(sp, 4)
    @test n_values(sp) == 4
    @test is_dirty(sp, Dirty.PAINT)
    # PAINT and not LAYOUT even though the series grew: `measure` is a
    # function of the widget, and the row it occupies is one row
    # whatever the series says.
    @test !is_dirty(sp, Dirty.LAYOUT)

    set_values!(sp, [9, 9])
    @test n_values(sp) == 2
end

@testitem "sparkline: cap bounds a live series" begin
    using ManyUI, ManyUITUI

    sp = Sparkline([1, 2, 3, 4, 5]; cap = 3)
    # Trimmed on construction too, not only on push: a series handed in
    # over the cap would otherwise stay over it forever.
    @test n_values(sp) == 3
    @test sp.values == [3.0, 4.0, 5.0]

    push_value!(sp, 6)
    @test sp.values == [4.0, 5.0, 6.0]

    @test n_values(Sparkline([1, 2, 3])) == 3      # 0 keeps every one
    @test_throws ArgumentError Sparkline([1]; cap = -1)
end

@testitem "sparkline: levels scale, clamp and stay put" begin
    using ManyUI, ManyUITUI

    @test spark_level(0, 0, 8) == 1
    @test spark_level(8, 0, 8) == 8
    @test spark_level(4, 0, 8) == 5
    # Outside a FIXED scale is pinned, never dropped: a sparkline that
    # silently omits its outliers is worse than one that flattens them.
    @test spark_level(-100, 0, 8) == 1
    @test spark_level(100, 0, 8) == 8
    # No range is no lie: every level would be false except "no change".
    @test spark_level(5, 3, 3) == 1

    # A fixed scale is what makes two sparklines comparable, so it must
    # not move when an outlier arrives.
    fixed = Sparkline([1, 2]; lo = 0, hi = 10)
    @test spark_bounds(fixed) == (0.0, 10.0)
    push_value!(fixed, 999)
    @test spark_bounds(fixed) == (0.0, 10.0)

    auto = Sparkline([1, 2])
    @test spark_bounds(auto) == (1.0, 2.0)
    push_value!(auto, 8)
    @test spark_bounds(auto) == (1.0, 8.0)
    @test spark_bounds(Sparkline()) == (0.0, 1.0)
end

@testitem "sparkline: it paints the LAST samples that fit" begin
    using ManyUI, ManyUITUI

    sp = Sparkline([1, 2, 3, 4, 5, 6, 7, 8]; lo = 1, hi = 8)
    buf = Buffer(8, 1)
    render!(sp, buf)
    @test string(buf) == join(SPARK_GLYPHS)

    # Narrower than the series: the newest data wins the row, because a
    # live series scrolls in from the right.
    buf3 = Buffer(3, 1)
    render!(sp, buf3)
    @test string(buf3) == join(SPARK_GLYPHS[6:8])

    # A flat series draws the lowest level rather than dividing by zero.
    flat = Sparkline([5, 5, 5])
    fb = Buffer(3, 1)
    render!(flat, fb)
    @test string(fb) == SPARK_FLAT^3

    render!(Sparkline(), Buffer(4, 1))          # empty is a no-op
end

@testitem "statusbar: three segments on one row" begin
    using ManyUI, ManyUITUI

    b = StatusBar(; left = "L", center = "C", right = "R")
    @test segments(b) == (RichText("L"), RichText("C"), RichText("R"))
    @test measure(b, Size(80, 24)) == Size(5, 1)   # 3 text + 2 gaps

    buf = Buffer(11, 1)
    render!(b, buf)
    row = string(buf)
    @test startswith(row, "L")
    @test endswith(row, "R")
    @test row[6] == 'C'                            # centred in 11
end

@testitem "statusbar: it drops in priority order, never in fragments" begin
    using ManyUI, ManyUITUI

    b = StatusBar(; left = "LEFT", center = "MIDDLE", right = "RIGHT")

    # Everything fits.
    got = status_layout(b, 40)
    @test length(got) == 3

    # The centre goes first: a bar that shrank all three would show
    # three fragments and say nothing.
    got = status_layout(b, 12)
    @test length(got) == 2
    @test plain(got[1][2]) == "LEFT"
    @test plain(got[2][2]) == "RIGHT"

    # Then the right.
    got = status_layout(b, 8)
    @test length(got) == 1
    @test plain(got[1][2]) == "LEFT"

    # The left is truncated only when it is alone and still too wide.
    got = status_layout(b, 3)
    @test length(got) == 1
    @test plain(got[1][2]) == "LEF"

    @test isempty(status_layout(b, 0))
end

@testitem "statusbar: a segment keeps its own styling" begin
    using ManyUI, ManyUITUI

    warn = Style(fg = rgb(255, 0, 0), bold = true)
    b = StatusBar(; left = RichText(TextRun("!", warn), TextRun(" up")),
                    right = "ok")

    buf = Buffer(12, 1)
    render!(b, buf)
    @test String(buf[1, 1].content) == "!"
    @test buf[1, 1].style.fg == rgb(255, 0, 0)
    @test has(buf[1, 1].style, Attr.BOLD)
    @test !has(buf[3, 1].style, Attr.BOLD)
end

@testitem "progressbar: an unlabelled bar is unchanged" begin
    using ManyUI, ManyUITUI

    p = ProgressBar(0.5)
    @test isempty(p.label[])
    @test progress_cells(p, 10) == 5

    buf = Buffer(10, 1)
    render!(p, buf)
    @test string(buf) == "█████░░░░░"
end

@testitem "progressbar: a labelled bar is a gauge" begin
    using ManyUI, ManyUITUI

    # A gauge is this widget plus one field, which is why it is not a
    # second widget.
    p = ProgressBar(0.5; label = "50%")
    @test plain(p.label[]) == "50%"

    buf = Buffer(10, 1)
    render!(p, buf)
    row = string(buf)
    # The block glyphs are gone: text over "█" is unreadable, so a
    # labelled bar fills with a reversed span instead.
    @test !occursin("█", row)
    @test occursin("50%", row)

    # The boundary stays legible THROUGH the caption: the filled half
    # is reversed, the empty half is not.
    @test has(buf[1, 1].style, Attr.REVERSE)
    @test has(buf[5, 1].style, Attr.REVERSE)
    @test !has(buf[6, 1].style, Attr.REVERSE)
    @test !has(buf[10, 1].style, Attr.REVERSE)
end

@testitem "progressbar: the split is the same with and without a label" begin
    using ManyUI, ManyUITUI

    for v in (0.0, 0.25, 0.5, 0.75, 1.0), w in (7, 10, 13)
        bare = ProgressBar(v)
        lbl = ProgressBar(v; label = "x")
        # One pure function decides it, so the two render paths cannot
        # disagree about where the boundary is.
        @test progress_cells(bare, w) == progress_cells(lbl, w)
        @test 0 <= progress_cells(bare, w) <= w
    end
end

@testitem "progresslist: a row is data, not a widget" begin
    using ManyUI, ManyUITUI

    pl = ProgressList([ProgressItem("build", 0.5),
                       ProgressItem("test", 1.0)])
    @test n_items(pl) == 2
    @test isempty(children(pl))          # two rows, ONE node
    @test content_extent(pl).height == 2

    clean!(pl)
    @test set_progress!(pl, 1, 0.75)
    @test pl.items[1].progress == 0.75
    @test is_dirty(pl, Dirty.PAINT)
    # Out of range is clamped at the door, so render! never sees one.
    @test set_progress!(pl, 2, 5.0) == false      # already 1.0
    set_progress!(pl, 1, -3)
    @test pl.items[1].progress == 0.0
    @test !set_progress!(pl, 99, 0.5)             # no such row
end

@testitem "progresslist: the label column does not move as it scrolls" begin
    using ManyUI, ManyUITUI

    pl = ProgressList([ProgressItem("a", 0.1),
                       ProgressItem("longest", 0.2),
                       ProgressItem("bb", 0.3)])
    # AUTO measures EVERY caption, not a sample: a column that changed
    # width mid-scroll would make every bar jump sideways.
    @test pl_label_width(pl) == 7

    fixed = ProgressList([ProgressItem("longest", 0.1)];
                         label_width = cells(3))
    @test pl_label_width(fixed) == 3
end

@testitem "progresslist: rows paint a caption then a bar" begin
    using ManyUI, ManyUITUI

    pl = ProgressList([ProgressItem("ab", 0.5), ProgressItem("cd", 0.0)])
    apply_stylesheet!(STYLESHEET_EMPTY, pl)
    buf = Buffer(11, 2)
    render!(pl, buf)

    rows = [join(String(buf[x, y].content) for x = 1:11) for y = 1:2]
    # 2 label + 1 gap leaves 8 for the bar; half of 8 is 4.
    @test rows[1] == "ab ████░░░░"
    @test rows[2] == "cd ░░░░░░░░"

    # Too narrow for a bar: the row is all caption rather than a
    # misleading two-cell bar.
    narrow = Buffer(5, 1)
    render!(pl, narrow)
    @test startswith(join(String(narrow[x, 1].content) for x = 1:5), "ab")
end

@testitem "dialog: it is a Container, not a new widget type" begin
    using ManyUI, ManyUITUI

    hit = Ref(0)
    d = Dialog("Discard changes?";
               title = "Confirm",
               buttons = ["OK" => (_ -> hit[] += 1),
                          "Cancel" => (_ -> nothing)])

    # A dialog is an ARRANGEMENT of things that already exist, so it
    # composes, restyles and is queried like anything else.
    @test d isa Container
    @test plain(border_title(d)) == "Confirm"
    @test border_title_align(d) === Align.CENTER
    @test length(children(d)) == 2                 # message, button row

    btns = children(children(d)[2])
    @test length(btns) == 2
    @test all(b -> b isa Button, btns)
    btns[1].on_click(btns[1])
    @test hit[] == 1

    # The buttons are the tab stops; the message is not.
    @test length(focusable_widgets(d)) == 2
end

@testitem "dialog: dialog_size wraps the message it will show" begin
    using ManyUI, ManyUITUI

    small = dialog_size("hi")
    @test small.width >= ManyUI.DIALOG_MIN_WIDTH
    @test small.height >= 3

    long = "a b c d e f g h i j k l m n o p q r s t u v w x y z " ^ 3
    big = dialog_size(long; max = Size(30, 20))
    # Bounded by `max`, and TALL because the message wrapped -- the
    # layer takes a declared size, so guessing one line here would show
    # as a clipped question.
    @test big.width <= 30
    @test big.height > small.height
    @test big.height <= 20

    # Buttons add their row.
    @test dialog_size("hi"; buttons = ["OK" => identity]).height >
          dialog_size("hi").height
end

@testitem "dialog: it opens modal and centred" begin
    using ManyUI, ManyUITUI

    owner = Button("open", identity)
    root = Container(owner)
    app = App(root, HeadlessDriver(Size(50, 16)))
    apply_stylesheet!(STYLESHEET_EMPTY, root)
    layout!(root, Region(1, 1, 50, 16))

    msg = "Discard changes?"
    d = Dialog(msg; title = "Confirm",
               buttons = ["OK" => (_ -> close_popup!(app, owner))])
    open_popup!(app, Popup(d, owner, dialog_size(msg; title = "Confirm",
                                                 buttons = ["OK" => identity]);
                           placement = PopupPlacement.CENTER, modal = true))

    @test popup_of(app) !== nothing
    @test focus_root(app) === d              # trapped
    # An outside press does not answer the question.
    handle!(app, MouseEvent(MouseAction.PRESS, MouseButton.LEFT, 1, 1,
                            MOD_NONE))
    @test popup_of(app) !== nothing

    # Its own button does.
    btn = children(children(d)[2])[1]
    btn.on_click(btn)
    @test popup_of(app) === nothing
end
