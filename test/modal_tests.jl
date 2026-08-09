# modal_tests.jl -- what makes a popup MODAL rather than merely large.
# Written BEFORE the implementation (TDD, CLAUDE.md).
#
# Three things, and each is a way the user can otherwise walk around a
# question the application cannot proceed without: a press outside must
# not answer it, TAB must not leave it, and a keystroke must not reach
# the tree behind it. The dimming is the fourth and is only how the
# first three are made visible.

@testitem "modal: an ordinary popup is not one" begin
    using ManyUI, ManyUITUI

    owner = Button("open", identity)
    content = Container(Button("ok", identity))
    p = Popup(content, owner, Size(10, 3))

    @test !p.modal
    @test Popup(content, owner, Size(10, 3); modal = true).modal
    # CENTER is the placement a dialog wants, but it is independent of
    # modality: a centred popup is still dismissible unless it says so.
    @test !Popup(content, owner, Size(10, 3);
                 placement = PopupPlacement.CENTER).modal
end

@testitem "modal: an outside press does not dismiss it" begin
    using ManyUI, ManyUITUI

    owner = Button("open", identity)
    root = Container(owner)
    app = App(root, HeadlessDriver(Size(40, 12)))
    apply_stylesheet!(STYLESHEET_EMPTY, root)
    layout!(root, Region(1, 1, 40, 12))

    content = Container(Button("ok", identity))
    open_popup!(app, Popup(content, owner, Size(12, 3);
                           placement = PopupPlacement.CENTER,
                           modal = true))
    @test popup_of(app) !== nothing

    # Top-left corner: as far outside the centred dialog as it gets.
    handle!(app, MouseEvent(MouseAction.PRESS, MouseButton.LEFT, 1, 1,
                            MOD_NONE))
    @test popup_of(app) !== nothing        # still up

    # The same press dismisses a NON-modal one, which is the behaviour
    # this had to be carved out of.
    close_popup!(app, owner)
    open_popup!(app, Popup(content, owner, Size(12, 3);
                           placement = PopupPlacement.CENTER))
    handle!(app, MouseEvent(MouseAction.PRESS, MouseButton.LEFT, 1, 1,
                            MOD_NONE))
    @test popup_of(app) === nothing
end

@testitem "modal: focus is trapped inside it" begin
    using ManyUI, ManyUITUI

    a, b = Button("a", identity), Button("b", identity)
    root = Container(a, b)
    app = App(root, HeadlessDriver(Size(40, 12)))
    apply_stylesheet!(STYLESHEET_EMPTY, root)
    layout!(root, Region(1, 1, 40, 12))

    @test focus_root(app) === root

    yes, no = Button("yes", identity), Button("no", identity)
    content = Container(yes, no)
    open_popup!(app, Popup(content, a, Size(12, 3);
                           placement = PopupPlacement.CENTER,
                           modal = true))

    @test focus_root(app) === content
    # Opening it moved focus in: a modal owns the keyboard, so it must
    # own the caret too.
    @test focused(app) === yes

    # TAB cycles WITHIN the dialog and never reaches a or b.
    focus_next!(app)
    @test focused(app) === no
    focus_next!(app)
    @test focused(app) === yes
    focus_prev!(app)
    @test focused(app) === no

    for _ = 1:6
        focus_next!(app)
        @test focused(app) !== a
        @test focused(app) !== b
    end
end

@testitem "modal: a non-modal popup leaves the tab order alone" begin
    using ManyUI, ManyUITUI

    a = Button("a", identity)
    root = Container(a, Button("b", identity))
    app = App(root, HeadlessDriver(Size(40, 12)))
    apply_stylesheet!(STYLESHEET_EMPTY, root)
    layout!(root, Region(1, 1, 40, 12))

    content = Container(Button("x", identity))
    open_popup!(app, Popup(content, a, Size(12, 3)))

    # A DropDown keeps focus itself and forwards, so a non-modal popup
    # must NOT take the keyboard. That is why the trap asks about
    # `modal` and not merely about `popup`.
    @test focus_root(app) === root
end

@testitem "modal: closing puts focus back where it was" begin
    using ManyUI, ManyUITUI

    a, b = Button("a", identity), Button("b", identity)
    root = Container(a, b)
    app = App(root, HeadlessDriver(Size(40, 12)))
    apply_stylesheet!(STYLESHEET_EMPTY, root)
    layout!(root, Region(1, 1, 40, 12))

    focus!(app, b)
    @test focused(app) === b

    content = Container(Button("ok", identity))
    open_popup!(app, Popup(content, b, Size(12, 3);
                           placement = PopupPlacement.CENTER,
                           modal = true))
    @test focused(app) !== b

    close_popup!(app, b)
    # Back to b, not to the top of the tree: a dialog opened from the
    # eighth field of a form must not land the user on the first.
    @test focused(app) === b
    @test focus_root(app) === root
end

@testitem "modal: a modal paints over a dimmed viewport" begin
    using ManyUI, ManyUITUI

    owner = Button("open", identity)
    root = Container(Label("背 background text"), owner)
    app = App(root, HeadlessDriver(Size(30, 8)))
    apply_stylesheet!(STYLESHEET_EMPTY, root)

    frame!(app)
    behind = app.front[2, 1].style
    @test !has(behind, Attr.DIM)

    content = Container(Label("ok"))
    open_popup!(app, Popup(content, owner, Size(6, 1);
                           placement = PopupPlacement.CENTER,
                           modal = true))
    invalidate!(app)
    frame!(app)

    # Everything the dialog does not cover is dimmed, and the content
    # underneath is still THERE -- dimming keeps the tree readable,
    # which is what says the application is waiting rather than gone.
    dimmed = app.front[2, 1]
    @test has(dimmed.style, Attr.DIM)
    @test String(dimmed.content) != " " || String(app.front[1, 1].content) != " "
end

@testitem "modal: a non-modal popup dims nothing" begin
    using ManyUI, ManyUITUI

    owner = Button("open", identity)
    root = Container(Label("background"), owner)
    app = App(root, HeadlessDriver(Size(30, 8)))
    apply_stylesheet!(STYLESHEET_EMPTY, root)

    content = Container(Label("ok"))
    open_popup!(app, Popup(content, owner, Size(6, 1)))
    frame!(app)

    @test !has(app.front[2, 1].style, Attr.DIM)
end
