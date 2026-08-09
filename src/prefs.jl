# prefs.jl -- what survives a restart.
#
# Two things an application is expected to remember: which theme the
# user picked, and where they dragged the splitters. Both were left out
# of `ManyUI` on purpose -- it has no dependency beyond the stdlib and
# should keep it that way -- so they live HERE, with the `App`, where a
# dependency on Preferences.jl is unremarkable.
#
# THE CONSTRAINT THAT SHAPES THIS FILE: a preference needs a key that
# is the same next time. A widget's `id` defaults to `gensym`, which is
# a DIFFERENT symbol every run, so a splitter with no explicit id
# cannot be persisted at all. Storing it anyway would write a growing
# pile of dead keys and restore none of them -- silently, which is the
# worst way for a feature like this to not work. So it is detected and
# reported instead.

"Preferences key holding the theme name."
const PREF_THEME = "theme"
"Preferences key holding splitter weights, by widget id."
const PREF_SPLITS = "splitter_weights"

"""
True when `id` is stable enough to key a preference on.

`gensym` ids are not: `gensym(:splitter)` is `##splitter#277` this run
and something else next. A widget whose geometry should survive a
restart must be given an explicit `id`.
"""
is_persistable_id(id::Symbol)::Bool = !startswith(String(id), "##")

"""
Remember `name` as the theme to use next time.

Writes to the ACTIVE project's `LocalPreferences.toml`, so a theme is
remembered per project rather than per user -- which is what an
application wants when two of them disagree about what looks right.
"""
function save_theme_pref!(name::Symbol)::Nothing
    @set_preferences!(PREF_THEME => String(name))
    return nothing
end

"""
The remembered theme name, or `nothing`.
"""
function theme_pref()::Union{Nothing,Symbol}
    s = @load_preference(PREF_THEME, nothing)
    s === nothing && return nothing
    return Symbol(s)
end

"""
Put the remembered theme in force, if there is one and it is still
registered. Returns the theme applied, or `nothing`.

A theme that has since been un-registered is IGNORED rather than
thrown: a preference file outlives the code that wrote it, and a
stale name in it must not stop the application starting.
"""
function restore_theme!()::Union{Nothing,ManyUI.Theme}
    name = theme_pref()
    name === nothing && return nothing
    name in themes() || return nothing
    return set_theme!(name)
end

"""
Every `Splitter` in `root`'s tree with a persistable id, in order.
Internal.
"""
function _pref_splitters(root::Widget)::Vector{Splitter}
    out = Splitter[]
    walk(root) do w
        w isa Splitter && is_persistable_id(id(w)) && push!(out, w)
        nothing
    end
    return out
end

"""
Remember where every splitter in `root` is dragged to.

Splitters with a `gensym` id are SKIPPED and their number returned, so
a caller can say so rather than wondering why nothing came back. See
`is_persistable_id`.
"""
function save_splits!(root::Widget)::Int
    saved = Dict{String,Vector{Float64}}()
    for sp in _pref_splitters(root)
        saved[String(id(sp))] = Float64.(weights_of(sp))
    end
    @set_preferences!(PREF_SPLITS => saved)
    return length(saved)
end

"""
Restore remembered splitter positions into `root`. Returns how many
splitters were moved.

A remembered entry whose pane COUNT no longer matches is skipped: the
tree has been rebuilt with a different shape since, and applying the
old weights would either throw or silently mean something else.
"""
function restore_splits!(root::Widget)::Int
    saved = @load_preference(PREF_SPLITS, nothing)
    saved === nothing && return 0
    n = 0
    for sp in _pref_splitters(root)
        ws = get(saved, String(id(sp)), nothing)
        ws === nothing && continue
        length(ws) == pane_count(sp) || continue
        all(>(0), ws) || continue
        set_weights!(sp, ws)
        n += 1
    end
    return n
end

"""
Remember the theme and every splitter position in `app`.

The one verb an application calls on the way out.
"""
function save_ui_prefs!(app::App)::Nothing
    save_theme_pref!(theme().name)
    save_splits!(app.root)
    return nothing
end

"""
Apply the remembered theme and splitter positions to `app`.

The one verb an application calls on the way in. A theme swap does not
dirty the tree -- nothing in it holds a resolved colour -- so this asks
for a full repaint itself rather than leaving the caller to remember.
"""
function restore_ui_prefs!(app::App)::Nothing
    th = restore_theme!()
    n = restore_splits!(app.root)
    (th === nothing && n == 0) && return nothing
    invalidate!(app)
    return nothing
end
