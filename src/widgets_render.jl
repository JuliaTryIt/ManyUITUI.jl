# --- from widgets/label.jl ---
function render!(w::Label, buf::AbstractMatrix{Cell})::Nothing
    width, height = size(buf)
    (width <= 0 || height <= 0) && return nothing
    st = computed_style(w)
    y = 1
    for line in wrap_width(w.text[], width)
        y > height && break
        write_text!(buf, 1, y, line, st)
        y += 1
    end
    return nothing
end
function render!(w::Static, buf::AbstractMatrix{Cell})::Nothing
    width, height = size(buf)
    (width <= 0 || height <= 0) && return nothing
    write_text!(buf, 1, 1, w.text[], computed_style(w))
    return nothing
end

# --- from widgets/button.jl ---
function render!(w::Button, buf::AbstractMatrix{Cell})::Nothing
    width, height = size(buf)
    (width <= 0 || height <= 0) && return nothing
    st = computed_style(w)
    is_disabled = w.disabled[]
    is_disabled && (st = merge(st, ManyUI.Style(dim=true)))
    w.pressed[] && !is_disabled && (st = with(st, Attr.REVERSE, true))
    caption = truncate_width(w.label[], width)
    x = 1 + (width - text_width(caption)) ÷ 2
    y = 1 + (height - 1) ÷ 2
    write_text!(buf, x, y, caption, st)
    return nothing
end

# --- from widgets/progressbar.jl ---
function render!(w::ProgressBar, buf::AbstractMatrix{Cell})::Nothing
    width, height = size(buf)
    (width <= 0 || height <= 0) && return nothing
    st = computed_style(w)

    val = w.progress[]
    filled_len = round(Int, val * width)

    bar = repeat("█", filled_len) * repeat("░", width - filled_len)

    y = 1 + (height - 1) ÷ 2
    write_text!(buf, 1, y, bar, st)
    return nothing
end

# --- from widgets/scroll.jl ---
function render!(w::Scrollpane, ::AbstractMatrix{Cell})::Nothing
    scroll_to!(w.canvas, scroll_of(w.canvas))
    return nothing
end
function render!(w::Scrollbar, buf::AbstractMatrix{Cell})::Nothing
    width, height = size(buf)
    (width <= 0 || height <= 0) && return nothing
    w.mode === ScrollMode.NEVER && return nothing
    vert = w.axis === ScrollAxis.VERTICAL
    track = vert ? height : width
    st = computed_style(w)
    (start, len) = thumb_span(ManyUI._sb_metrics(w, track)...)
    if len == 0
        # Nothing to scroll. AUTO keeps the gutter and drops the ink;
        # ALWAYS says so with a thumb that fills the track.
        w.mode === ScrollMode.AUTO && return nothing
        start, len = 1, track
    else
        g = vert ? ManyUI.SB_TRACK_V : ManyUI.SB_TRACK_H
        for i in 1:track
            _sb_put!(w, buf, i, g, st)
        end
    end
    for i in start:(start + len - 1)
        _sb_put!(w, buf, i, ManyUI.SB_THUMB, st)
    end
    return nothing
end

# --- from widgets/textinput.jl ---
function render!(w::TextInput, buf::AbstractMatrix{Cell})::Nothing
    width, height = size(buf)
    (width <= 0 || height <= 0) && return nothing
    st = computed_style(w)
    is_disabled = w.disabled[]
    is_disabled && (st = merge(st, ManyUI.Style(dim=true)))
    s = w.text[]
    if w.is_password
        s = repeat("*", length(s)) # each character becomes a star
    end
    lo, cw = ManyUI._ti_caret_cells(w)
    if w.is_password
        lo = w.cursor[] # Since it's all stars (1 cell each), lo is just the cursor index
        cw = 1
    end
    off = ManyUI._ti_window(w, width, lo, cw)
    if isempty(s)
        isempty(w.placeholder) ||
            write_text!(buf, 1, 1, w.placeholder,
                        with(st, Attr.DIM, true))
    else
        write_text!(buf, 1 - off, 1, s, st)
    end
    w.focused[] && !is_disabled || return nothing
    # `style_region!` clips, so a caret column outside the box is a
    # no-op rather than a throw, and it keeps the cell's content and
    # width -- reversing a head must not turn it into a fresh cell.
    style_region!(buf, Region(lo - off + 1, 1, 1, 1), ManyUI._TI_CARET)
    return nothing
end

# --- from widgets/list.jl ---
function render!(w::List, buf::AbstractMatrix{Cell})::Nothing
    width, height = size(buf)
    (width <= 0 || height <= 0) && return nothing
    ManyUI._tc_sync!(w)
    st = computed_style(w)
    off = scroll_of(w)
    n = length(w.items)
    foc = w.focused[]
    for row in 1:height
        i = off.y + row
        # `1 <= i` and not just `i <= n`: `set_scroll!` clamps at zero
        # but has NO upper bound (widget.jl:185), so a caller bypassing
        # `scroll_to!` can over-scroll far enough to wrap `i` negative.
        # An over-scroll is blank rows, NEVER a BoundsError.
        (1 <= i <= n) || break
        rst = ManyUI._tc_row_style(w, st, i, foc)
        reached = _tc_paint_slice!(buf, row, width, off.x,
                                   w.format(w.items[i]), rst)
        w.widest = max(w.widest, reached)
        (is_selected(w.sel, i) || (foc && w.sel.cursor == i)) &&
            style_region!(buf, Region(1, row, width, 1),
                          ManyUI._tc_bar_style(w.sel, i, foc))
    end
    return nothing
end

# --- from widgets/toggle.jl ---
function render!(w::Checkbox, buf::AbstractMatrix{Cell})::Nothing
    width, height = size(buf)
    (width <= 0 || height <= 0) && return nothing
    st = computed_style(w)
    w.focused[] && (st = merge(st, ManyUI.CB_FOCUS))
    write_text!(buf, 1, 1, ManyUI._cb_glyph(w.state[]), st)
    lbl = w.label[]
    isempty(lbl) ||
        _tc_slice!(buf, ManyUI.CB_WIDTH + ManyUI.CB_GAP + 1, 1, width, lbl, st)
    return nothing
end
function render!(w::RadioGroup, buf::AbstractMatrix{Cell})::Nothing
    width, height = size(buf)
    (width <= 0 || height <= 0) && return nothing
    st = computed_style(w)
    foc = w.focused[]
    cur = w.cursor[]
    sel = w.selected[]
    disabled = w.disabled[]
    n = length(w.options)
    for row in 1:height
        row > n && break
        is_disabled = row in disabled
        base_st = is_disabled ? merge(st, ManyUI.Style(dim=true)) : st
        rst = (foc && row == cur && !is_disabled) ? merge(base_st, ManyUI.CB_FOCUS) : base_st
        write_text!(buf, 1, row, sel == row ? ManyUI.RB_ON : ManyUI.RB_OFF, rst)
        cap = w.options[row]
        isempty(cap) ||
            _tc_slice!(buf, ManyUI.CB_WIDTH + ManyUI.CB_GAP + 1, row, width, cap, rst)
    end
    return nothing
end

# --- from widgets/tabs.jl ---
function render!(w::TabStrip, buf::AbstractMatrix{Cell})::Nothing
    width, height = size(buf)
    (width <= 0 || height <= 0) && return nothing
    st = computed_style(w)
    w.focused[] && (st = merge(st, ManyUI.TABS_FOCUS))
    sel = w.selected[]
    x = 1
    for (i, title) in enumerate(w.titles)
        cap = " "^ManyUI.TABS_PAD * title * " "^ManyUI.TABS_PAD
        cst = i == sel ? merge(st, ManyUI.TABS_ACTIVE) : st
        _tc_slice!(buf, x, 1, width, cap, cst)
        x += text_width(title) + 2 * ManyUI.TABS_PAD
        x > width && break
    end
    return nothing
end

# --- from widgets/tree.jl ---
function render!(w::TreeView, buf::AbstractMatrix{Cell})::Nothing
    width, height = size(buf)
    (width <= 0 || height <= 0) && return nothing
    ManyUI._tv_flat!(w)
    ManyUI._tc_sync!(w)
    st = computed_style(w)
    off = scroll_of(w)
    n = length(w.rows)
    foc = w.focused[]
    for row in 1:height
        i = off.y + row
        # `1 <= i` and not just `i <= n`: `set_scroll!` clamps at zero
        # but has NO upper bound (widget.jl:204), so a caller bypassing
        # `scroll_to!` can over-scroll far enough to wrap `i` negative.
        # An over-scroll is blank rows, NEVER a BoundsError. This is
        # `List.render!`'s guard, verbatim (list.jl:342).
        (1 <= i <= n) || break
        r = w.rows[i]
        rst = ManyUI._tc_row_style(w, st, i, foc)
        ind = ManyUI.TV_INDENT * r.depth
        g = is_leaf(r.node) ? ManyUI.TV_LEAF :
            r.node.expanded ? ManyUI.TV_OPEN : ManyUI.TV_CLOSED
        _tc_slice!(buf, 1 + ind - off.x, row, width, g, rst)
        _tc_slice!(buf, 1 + ind + 1 + ManyUI.TV_GAP - off.x, row, width,
                   w.format(r.node.value), rst)
        (is_selected(w.sel, i) || (foc && w.sel.cursor == i)) &&
            style_region!(buf, Region(1, row, width, 1),
                          ManyUI._tc_bar_style(w.sel, i, foc))
    end
    return nothing
end

# --- from widgets/dropdown.jl ---
function render!(w::DropDown, buf::AbstractMatrix{Cell})::Nothing
    width, height = size(buf)
    (width <= 0 || height <= 0) && return nothing
    st = computed_style(w)
    w.focused[] && (st = merge(st, ManyUI.DD_FOCUS))
    _tc_slice!(buf, 1, 1, width - ManyUI.DD_ARROW_W, ManyUI._dd_caption(w), st)
    arrow = w.open[] ? ManyUI.DD_OPEN : ManyUI.DD_CLOSED
    write_text!(buf, width, 1, arrow, st)
    return nothing
end

# --- from widgets/table.jl ---
render!(w::Table, buf::AbstractMatrix{Cell})::Nothing = _tc_render_table!(w, buf)
# --- from widgets/tablecore.jl ---
function _tc_slice!(buf::AbstractMatrix{Cell}, x::Int, y::Int,
                    width::Int, s::AbstractString, st::Style)::Int
    cx = x
    for g in graphemes(s)
        cx > width && break
        gw = grapheme_width(g)
        cx >= 1 && set_cell!(buf, cx, y, Cell(g, st))
        cx += gw
    end
    return cx
end
function _tc_paint_slice!(buf::AbstractMatrix{Cell}, y::Int, width::Int,
                          skip::Int, s::AbstractString, st::Style)::Int
    cx = _tc_slice!(buf, 1 - skip, y, width, s, st)
    # `cx > width` means the loop broke early and the row was CUT: it
    # reached at least the right edge of the window. Understating a cut
    # row is exactly what a high-water mark does.
    cx > width && return skip + width
    return cx - 1 + skip
end
function _tc_put!(buf::AbstractMatrix{Cell}, x0::Int, y::Int, cw::Int,
                  text::AbstractString, align::Align.T,
                  st::Style)::Nothing
    cw <= 0 && return nothing
    width = size(buf, 1)
    t = truncate_width(text, cw)
    if ManyUI._tc_truncated(t, text)
        # LEFT-ANCHORED, whatever `align` says, and the marker last.
        _tc_slice!(buf, x0, y, width, truncate_width(text, cw - 1), st)
        set_cell!(buf, x0 + cw - 1, y, Cell(ManyUI.TC_ELLIPSIS, st))
        return nothing
    end
    lead = first(cross_align(text_width(t), align, cw))
    _tc_slice!(buf, x0 + lead, y, width, t, st)
    return nothing
end
function _tc_rule!(buf::AbstractMatrix{Cell}, y::Int, width::Int,
                   glyph::AbstractString, st::Style)::Nothing
    for x in 1:width
        set_cell!(buf, x, y, Cell(glyph, st))
    end
    return nothing
end
function _tc_seps!(buf::AbstractMatrix{Cell}, g::TableGrid,
                   ws::Vector{Int}, lo::Int, hi::Int, off_x::Int,
                   y::Int, st::Style, width::Int)::Nothing
    g.sep_w > 0 || return nothing
    n = length(g.cols)
    # `lo - 1`: the separator to the LEFT of the first visible column can
    # itself be visible when that column's left edge is past `off_x`.
    for j in max(1, lo - 1):min(hi, n - 1)
        _tc_slice!(buf, g.xs[j] + ws[j] - off_x + 1, y, width, g.sep, st)
    end
    return nothing
end
function _tc_render_table!(w::W,
                           buf::AbstractMatrix{Cell})::Nothing where
                          {W<:RowsWidget}
    width, height = size(buf)
    (width <= 0 || height <= 0) && return nothing
    ManyUI._tc_sync!(w)
    g = grid_of(w)
    ws = ManyUI._tc_resolve!(w, width)              # O(1) on a hit, 0 alloc
    hh = ManyUI._tc_header_rows(w)
    off = scroll_of(w)
    n = view_count(w)
    st = computed_style(w)
    lo, hi = ManyUI._tc_visible_cols(g, off.x, width)
    if g.show_header && hh >= 1
        hst = merge(st, ManyUI.TC_HEADER)
        for j in lo:hi
            ws[j] > 0 && _tc_put!(buf, g.xs[j] - off.x + 1, 1, ws[j],
                                  ManyUI._tc_header_text(w, j),
                                  g.cols[j].align, hst)
        end
        g.rule && _tc_rule!(buf, hh, width, g.rule_glyph, st)
    end
    s = selection_of(w)
    foc = is_focused(w)
    for r in 1:(height - hh)
        k = off.y + r
        # `1 <= k` and not just `k <= n`: `set_scroll!` clamps at zero
        # but has NO upper bound (widget.jl:185), so a caller bypassing
        # `scroll_to!` can over-scroll far enough to wrap `k` negative.
        # An over-scroll is blank rows, NEVER a BoundsError.
        (1 <= k <= n) || break
        y = hh + r
        src = view_source(w, k)
        rst = ManyUI._tc_row_style(w, st, src, foc)
        for j in lo:hi
            ws[j] > 0 && _tc_put!(buf, g.xs[j] - off.x + 1, y, ws[j],
                                  ManyUI._tc_cell_text(w, src, j),
                                  g.cols[j].align, rst)
        end
        _tc_seps!(buf, g, ws, lo, hi, off.x, y, rst, width)
        (is_selected(s, src) || (foc && s.cursor === src)) &&
            style_region!(buf, Region(1, y, width, 1),
                          ManyUI._tc_bar_style(s, src, foc))
    end
    return nothing
end

# --- from widgets/textarea.jl ---
function render!(w::TextArea, buf::AbstractMatrix{Cell})::Nothing
    width, height = size(buf)
    (width <= 0 || height <= 0) && return nothing
    st = computed_style(w)
    off = scroll_of(w)
    n = length(w.lines)
    for row in 1:height
        li = off.y + row
        # `1 <= li` and not just `li <= n`: `set_scroll!` clamps at zero
        # but has no upper bound, so a caller bypassing `scroll_to!` can
        # over-scroll far enough to wrap `li` negative. An over-scroll
        # is blank cells, never a BoundsError.
        (1 <= li <= n) || break
        cx = 1 - off.x
        for g in graphemes(w.lines[li])
            cx > width && break
            gw = grapheme_width(g)
            cx >= 1 && set_cell!(buf, cx, row, Cell(g, st))
            cx += gw
        end
    end
    w.focused[] || return nothing
    cy = w.line - off.y
    (1 <= cy <= height) || return nothing
    cx = ManyUI._ta_cells_before(w.lines[w.line], w.col) - off.x + 1
    (1 <= cx <= width) || return nothing
    # The caret reverses the cell it sits on -- the HEAD of a wide
    # cluster, whose continuation stays a continuation, so the grid
    # never desynchronises.
    style_region!(buf, Region(cx, cy, 1, 1), ManyUI._TA_CARET)
    return nothing
end

# --- from widgets/overlay.jl ---
function _ov_center!(buf::AbstractMatrix{Cell}, line::AbstractString,
                     y::Int, width::Int, st::Style)::Nothing
    shown = truncate_width(line, width)
    x = 1 + (width - text_width(shown)) ÷ 2
    write_text!(buf, x, y, shown, st)
    return nothing
end
function _ov_block!(buf::AbstractMatrix{Cell},
                    lines::Tuple{Vararg{String}}, width::Int,
                    height::Int, st::Style)::Nothing
    n = min(length(lines), height)
    y0 = 1 + (height - n) ÷ 2
    for i in 1:n
        _ov_center!(buf, lines[i], y0 + i - 1, width, st)
    end
    return nothing
end
function render!(w::MinSizeOverlay, buf::AbstractMatrix{Cell})::Nothing
    width, height = size(buf)
    (width <= 0 || height <= 0) && return nothing
    _ov_block!(buf, (w.message[], ManyUI._ov_dims(w.required[], w.actual[])),
               width, height, computed_style(w))
    return nothing
end
function render_min_size_overlay!(buf::Buffer, actual::Size,
                                  required::Size)::Nothing
    clear!(buf)
    width, height = size(buf)
    (width <= 0 || height <= 0) && return nothing
    dims = ManyUI._ov_dims(required, actual)
    msg_w = text_width(ManyUI.OVERLAY_MESSAGE)
    st = STYLE_NONE
    if height >= 2 && width >= max(msg_w, text_width(dims))
        _ov_block!(buf, (ManyUI.OVERLAY_MESSAGE, dims), width, height, st)
    elseif width >= msg_w
        _ov_block!(buf, (ManyUI.OVERLAY_MESSAGE,), width, height, st)
    elseif width >= text_width(ManyUI.OVERLAY_TINY_MESSAGE)
        _ov_block!(buf, (ManyUI.OVERLAY_TINY_MESSAGE,), width, height, st)
    end
    return nothing
end

render!(w::DataTable, buf::AbstractMatrix{Cell})::Nothing = _tc_render_table!(w, buf)

"""
Write one cell of the bar, in the bar's own long-axis coordinate.
Internal.
"""
function _sb_put!(w::Scrollbar, buf::AbstractMatrix{Cell}, i::Int,
         g::AbstractString, st::Style)::Int
    w.axis === ScrollAxis.VERTICAL ? set_cell!(buf, 1, i, g, st) :
                                     set_cell!(buf, i, 1, g, st)
end
