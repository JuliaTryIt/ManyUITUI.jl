# popup_ops.jl -- the App-facing popup verbs.
#
# These need `App` (they reach `app.popup`, `frame!`'s buffer and the
# dispatch walk), so they live AFTER app.jl. The `Popup` value and its
# placement math are framework-neutral and live in widgets/popup.jl.
#
# The layer is the min-size overlay's, generalized: `_paint_popup!` paints
# the content over the tree in the same `frame!` slot `_paint_overlay!`
# uses, and `_popup_dismiss!` gives the open popup first refusal on a mouse
# press.

"""
$(SIGNATURES)

The open [`Popup`](@ref), or `nothing`.
"""
popup_of(app::App)::Union{Nothing,Popup} = app.popup

"""
$(SIGNATURES)

Bind (or unbind) `app` across the popup content's subtree, so `app(w)`
resolves for a second root that is not in `app.root`'s tree. Internal.
"""
function _bind_popup_app!(content::Widget, app::Union{Nothing,App})::Nothing
    walk(content) do w
        node(w).app = app
        nothing
    end
    return nothing
end

"""
$(SIGNATURES)

Lay the popup's content out at its on-screen region: cascade its styles,
place it with [`popup_region`](@ref) off the owner's head, and lay it out
as a second root. Returns the region. Internal.
"""
function _place_popup!(app::App, p::Popup)::Region
    r = popup_region(region(p.owner), p.size, p.placement, app.viewport)
    recascade!(app.stylesheet, p.content)
    layout!(p.content, r)
    return r
end

"""
$(SIGNATURES)

Open `p` on `app`: whatever popup was open closes first (its owner is
notified), then `p` becomes the one, its content is bound to `app` and laid
out so a hit-test or a paint can find it immediately.

`open_popup!` is the unguarded form. A widget closing its OWN popup uses
`close_popup!(app, owner)`, which no-ops when the open popup belongs to
someone else -- the guard that stops a blur from slamming a popup a
different widget just opened.
"""
function open_popup!(app::App, p::Popup)::Nothing
    old = app.popup
    if old !== nothing
        app.popup = nothing
        _bind_popup_app!(old.content, nothing)
        on_popup_close!(old.owner)
    end
    app.popup = p
    _bind_popup_app!(p.content, app)
    _place_popup!(app, p)
    # A modal takes the keyboard, so it must also take a CARET: focus
    # left on the tree behind would type into a widget the user cannot
    # see the cursor in. Remember where it was, because putting it back
    # at the top of the tree on close is exactly the annoyance a form
    # with eight fields makes obvious.
    if p.modal
        app.focus_before_modal = app.focus
        ws = focusable_widgets(p.content)
        isempty(ws) || focus!(app, first(ws))
    end
    return nothing
end

"""
$(SIGNATURES)

Close the open popup IF it belongs to `owner`, and notify it. Returns true
iff it closed one.

`app.popup` is cleared BEFORE `on_popup_close!`, so an owner that reopens
from its own close hook cannot loop.
"""
function close_popup!(app::App, owner::Widget)::Bool
    p = app.popup
    (p !== nothing && p.owner === owner) || return false
    app.popup = nothing
    _bind_popup_app!(p.content, nothing)
    if p.modal
        back = app.focus_before_modal
        app.focus_before_modal = nothing
        # Only if it is still in the tree: a modal whose owner rebuilt
        # the page beneath it must not restore focus to a dead widget.
        if back !== nothing && root_of(back) === app.root
            focus!(app, back)
        else
            app.focus = nothing
        end
    end
    on_popup_close!(owner)
    return true
end

"""
$(SIGNATURES)

The root a keystroke and the tab order belong to: the content of an open
MODAL popup, otherwise the tree.

THE focus trap, and it is one function rather than a flag threaded
through the dispatch: a modal that could be tabbed out of is a dialog
the user answers by ignoring it. A non-modal popup does NOT take the
keyboard -- a `DropDown` keeps focus itself and forwards, which is why
this asks about `modal` and not merely about `popup`.
"""
function focus_root(app::App)::Widget
    p = app.popup
    return (p !== nothing && p.modal) ? p.content : app.root
end

"""
$(SIGNATURES)

Paint the open popup's content over `app.back`, re-laying it out first so
its region tracks a resize. The `frame!` step that puts the popup over the
tree. Internal.
"""
function _paint_popup!(app::App)::Nothing
    p = app.popup
    p === nothing && return nothing
    _place_popup!(app, p)
    # A modal dims what it covers BEFORE painting itself, so the dialog
    # is the only thing at full strength. `style_region!` MERGES, so
    # this dims whatever was already painted rather than repainting it,
    # and it costs one pass over the viewport only while a modal is up.
    p.modal && style_region!(app.back, buffer_region(app.back), MODAL_DIM)
    paint!(app.back, p.content)
    return nothing
end

"""
$(SIGNATURES)

Give the open popup first refusal on a mouse event. Returns true when it
took the event, so the tree never sees it.

    inside the popup   -> route to the content (a row commits, the list
                          scrolls); taken.
    a scroll outside   -> NOT taken: a wheel notch is never a dismiss.
    a press outside    -> close the popup and SWALLOW the press, so the
                          click that dismissed it does not also fire the
                          widget beneath. The NEXT press reaches the tree.

Internal.
"""
function _popup_dismiss!(app::App, e::MouseEvent)::Bool
    p = app.popup
    p === nothing && return false
    o = Offset(e.x, e.y)
    if o in painted_region(p.content)
        target = something(hit_test(p.content, o), p.content)
        propagate!(p.content, target, e)
        return true
    end
    # A MODAL swallows everything outside it and closes for none of it.
    # That is the whole difference between modal and merely large: a
    # dialog the application cannot proceed without must not be
    # answerable by clicking next to it.
    p.modal && return true
    is_scroll(e) && return false
    if e.action === MouseAction.PRESS
        close_popup!(app, p.owner)
        return true
    end
    return false
end
