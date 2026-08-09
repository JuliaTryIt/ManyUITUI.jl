# widgets_splitter_tests.jl -- draggable panes (layer 7).
# Written BEFORE the implementation (TDD, CLAUDE.md).
#
# Every assertion is about CELLS or about integers. A resize bug is
# invisible in a type signature and obvious in a laid-out tree.
#
# The two properties that matter and that a hand-rolled splitter gets
# wrong: a drag must move ONLY the two panes it is between, and a drag
# that outruns the redraw must keep working after the pointer has left
# the one-cell handle.

@testitem "splitter: panes and handles interleave" begin
    using ManyUI, ManyUITUI

    a, b, c = Label("a"), Label("b"), Label("c")
    sp = Splitter(a, b, c)

    @test pane_count(sp) == 3
    @test panes(sp) == Widget[a, b, c]
    @test length(handles(sp)) == 2
    @test length(children(sp)) == 5
    @test children(sp)[2] === handles(sp)[1]
    @test children(sp)[4] === handles(sp)[2]
    @test is_horizontal(sp)
    @test !is_horizontal(Splitter(Label("x"), Label("y");
                                  direction = Direction.COLUMN))

    # A stray child would shift the parity and turn a pane into a
    # handle, so the constructor is the only way in.
    @test_throws ArgumentError mount!(sp, Label("z"))
end

@testitem "splitter: weights are ratios and must be positive" begin
    using ManyUI, ManyUITUI

    sp = Splitter(Label("a"), Label("b"); weights = [3, 1])
    @test weights_of(sp) == Float32[3, 1]

    set_weights!(sp, [1, 1])
    @test weights_of(sp) == Float32[1, 1]

    @test_throws ArgumentError set_weights!(sp, [1, 1, 1])
    @test_throws ArgumentError set_weights!(sp, [1, 0])
    @test_throws ArgumentError Splitter(Label("a"), Label("b");
                                        weights = [1])
    @test_throws ArgumentError Splitter(Label("a"); weights = [-1])
end

@testitem "splitter: the handle takes exactly one column" begin
    using ManyUI, ManyUITUI

    a, b = Label("a"), Label("b")
    sp = Splitter(a, b)
    apply_stylesheet!(STYLESHEET_EMPTY, sp)
    layout!(sp, Region(1, 1, 21, 4))

    # 21 cells less one for the handle is 20, split evenly.
    @test layout_of(a).border_box.width == 10
    @test layout_of(handles(sp)[1]).border_box.width == 1
    @test layout_of(b).border_box.width == 10
    # The handle is stretched across the cross axis: a divider you can
    # only grab on one row is a divider nobody grabs.
    @test layout_of(handles(sp)[1]).border_box.height == 4
end

@testitem "splitter: a handle paints along its length" begin
    using ManyUI, ManyUITUI

    sp = Splitter(Label("a"), Label("b"))
    apply_stylesheet!(STYLESHEET_EMPTY, sp)
    layout!(sp, Region(1, 1, 5, 3))

    buf = Buffer(5, 3)
    paint!(buf, sp)

    h = layout_of(handles(sp)[1]).border_box
    for y = 1:3
        @test String(buf[h.x, y].content) == ManyUI.SPLIT_GLYPH_V
    end
end

@testitem "splitter: a column splitter runs the other way" begin
    using ManyUI, ManyUITUI

    a, b = Label("a"), Label("b")
    sp = Splitter(a, b; direction = Direction.COLUMN)
    apply_stylesheet!(STYLESHEET_EMPTY, sp)
    layout!(sp, Region(1, 1, 6, 7))

    @test layout_of(a).border_box.height == 3
    @test layout_of(handles(sp)[1]).border_box.height == 1
    @test layout_of(b).border_box.height == 3

    buf = Buffer(6, 7)
    paint!(buf, sp)
    hy = layout_of(handles(sp)[1]).border_box.y
    for x = 1:6
        @test String(buf[x, hy].content) == ManyUI.SPLIT_GLYPH_H
    end
end

@testitem "splitter: dragging a handle moves the split" begin
    using ManyUI, ManyUITUI

    a, b = Label("a"), Label("b")
    sp = Splitter(a, b)
    apply_stylesheet!(STYLESHEET_EMPTY, sp)
    layout!(sp, Region(1, 1, 21, 4))
    @test layout_of(a).border_box.width == 10

    h = handles(sp)[1]
    hx = layout_of(h).border_box.x

    # Press on the handle, drag three columns right, release.
    dispatch_event!(sp, MouseEvent(MouseAction.PRESS, MouseButton.LEFT,
                                   hx, 2, MOD_NONE))
    dispatch_event!(sp, MouseEvent(MouseAction.DRAG, MouseButton.LEFT,
                                   hx + 3, 2, MOD_NONE))
    dispatch_event!(sp, MouseEvent(MouseAction.RELEASE, MouseButton.LEFT,
                                   hx + 3, 2, MOD_NONE))

    apply_stylesheet!(STYLESHEET_EMPTY, sp)
    layout!(sp, Region(1, 1, 21, 4))
    @test layout_of(a).border_box.width == 13
    @test layout_of(b).border_box.width == 7
    # The total is conserved: a drag redistributes, it does not create.
    @test layout_of(a).border_box.width + layout_of(b).border_box.width == 20
end

@testitem "splitter: a drag never disturbs a pane it is not between" begin
    using ManyUI, ManyUITUI

    a, b, c = Label("a"), Label("b"), Label("c")
    sp = Splitter(a, b, c)
    apply_stylesheet!(STYLESHEET_EMPTY, sp)
    layout!(sp, Region(1, 1, 32, 4))
    before_c = layout_of(c).border_box.width

    h = handles(sp)[1]
    hx = layout_of(h).border_box.x
    dispatch_event!(sp, MouseEvent(MouseAction.PRESS, MouseButton.LEFT,
                                   hx, 2, MOD_NONE))
    dispatch_event!(sp, MouseEvent(MouseAction.DRAG, MouseButton.LEFT,
                                   hx + 2, 2, MOD_NONE))
    dispatch_event!(sp, MouseEvent(MouseAction.RELEASE, MouseButton.LEFT,
                                   hx + 2, 2, MOD_NONE))
    apply_stylesheet!(STYLESHEET_EMPTY, sp)
    layout!(sp, Region(1, 1, 32, 4))

    @test layout_of(a).border_box.width > layout_of(b).border_box.width
    @test layout_of(c).border_box.width == before_c
end

@testitem "splitter: a drag that outruns the pointer keeps working" begin
    using ManyUI, ManyUITUI

    # THE case a handle cannot handle alone: the pointer is now over a
    # PANE, not over the one-cell handle. The splitter consumes it in
    # the capture phase because it is an ancestor of whatever is under
    # the cursor -- pointer capture out of the propagation order that
    # already exists.
    a, b = Label("a"), Label("b")
    sp = Splitter(a, b)
    apply_stylesheet!(STYLESHEET_EMPTY, sp)
    layout!(sp, Region(1, 1, 21, 4))

    hx = layout_of(handles(sp)[1]).border_box.x
    dispatch_event!(sp, MouseEvent(MouseAction.PRESS, MouseButton.LEFT,
                                   hx, 2, MOD_NONE))
    # Five columns away, squarely inside pane b.
    far = hx + 5
    @test Offset(far, 2) in layout_of(b).border_box
    dispatch_event!(sp, MouseEvent(MouseAction.DRAG, MouseButton.LEFT,
                                   far, 2, MOD_NONE))
    dispatch_event!(sp, MouseEvent(MouseAction.RELEASE, MouseButton.LEFT,
                                   far, 2, MOD_NONE))

    apply_stylesheet!(STYLESHEET_EMPTY, sp)
    layout!(sp, Region(1, 1, 21, 4))
    @test layout_of(a).border_box.width == 15
end

@testitem "splitter: a drag past the end cannot invert the panes" begin
    using ManyUI, ManyUITUI

    a, b = Label("a"), Label("b")
    sp = Splitter(a, b)
    apply_stylesheet!(STYLESHEET_EMPTY, sp)
    layout!(sp, Region(1, 1, 21, 4))

    hx = layout_of(handles(sp)[1]).border_box.x
    dispatch_event!(sp, MouseEvent(MouseAction.PRESS, MouseButton.LEFT,
                                   hx, 2, MOD_NONE))
    for target in (hx + 500, hx - 500)
        dispatch_event!(sp, MouseEvent(MouseAction.DRAG, MouseButton.LEFT,
                                       target, 2, MOD_NONE))
        apply_stylesheet!(STYLESHEET_EMPTY, sp)
        layout!(sp, Region(1, 1, 21, 4))
        @test layout_of(a).border_box.width >= SPLIT_MIN_PANE
        @test layout_of(b).border_box.width >= SPLIT_MIN_PANE
        @test all(>(0), weights_of(sp))
    end
end

@testitem "splitter: the dragged handle marks itself active" begin
    using ManyUI, ManyUITUI

    sp = Splitter(Label("a"), Label("b"))
    apply_stylesheet!(STYLESHEET_EMPTY, sp)
    layout!(sp, Region(1, 1, 21, 4))
    h = handles(sp)[1]
    hx = layout_of(h).border_box.x

    @test !h.active[]
    dispatch_event!(sp, MouseEvent(MouseAction.PRESS, MouseButton.LEFT,
                                   hx, 2, MOD_NONE))
    @test h.active[]
    dispatch_event!(sp, MouseEvent(MouseAction.RELEASE, MouseButton.LEFT,
                                   hx, 2, MOD_NONE))
    @test !h.active[]
end

@testitem "splitter: on_resize fires once per change, not per event" begin
    using ManyUI, ManyUITUI

    hits = Ref(0)
    a, b = Label("a"), Label("b")
    sp = Splitter(a, b; on_resize = _ -> (hits[] += 1))
    apply_stylesheet!(STYLESHEET_EMPTY, sp)
    layout!(sp, Region(1, 1, 21, 4))
    hx = layout_of(handles(sp)[1]).border_box.x

    dispatch_event!(sp, MouseEvent(MouseAction.PRESS, MouseButton.LEFT,
                                   hx, 2, MOD_NONE))
    @test hits[] == 0                      # a press has moved nothing
    dispatch_event!(sp, MouseEvent(MouseAction.DRAG, MouseButton.LEFT,
                                   hx + 2, 2, MOD_NONE))
    @test hits[] == 1
    # The same coordinate again changes nothing, so it reports nothing.
    dispatch_event!(sp, MouseEvent(MouseAction.DRAG, MouseButton.LEFT,
                                   hx + 2, 2, MOD_NONE))
    @test hits[] == 1
    dispatch_event!(sp, MouseEvent(MouseAction.RELEASE, MouseButton.LEFT,
                                   hx + 2, 2, MOD_NONE))
    @test hits[] == 1
end

@testitem "splitter: a mouse event with no drag in flight is ignored" begin
    using ManyUI, ManyUITUI

    a, b = Label("a"), Label("b")
    sp = Splitter(a, b)
    apply_stylesheet!(STYLESHEET_EMPTY, sp)
    layout!(sp, Region(1, 1, 21, 4))
    before = weights_of(sp)

    # Moving over a pane, dragging over a pane, releasing over a pane:
    # none of it is a resize, and the splitter must not treat it as one.
    for act in (MouseAction.MOVE, MouseAction.DRAG, MouseAction.RELEASE)
        dispatch_event!(sp, MouseEvent(act, MouseButton.LEFT, 3, 2,
                                       MOD_NONE))
    end
    @test weights_of(sp) == before
end
