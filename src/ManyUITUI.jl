module ManyUITUI

using ManyUI
import ManyUI: Event, Widget, post!, focus!, popup_of, open_popup!, close_popup!, on_popup_close!
using InlineStrings
using DocStringExtensions, REPL, Unicode
import Base: resize!

include("types.jl")
include("buffer.jl")
include("diff.jl")
include("ansi.jl")
include("input.jl")
include("driver.jl")
include("paint.jl")
include("headless.jl")
include("terminal.jl")
include("app.jl")
include("popup_ops.jl")
include("backend.jl")

include("widgets_render.jl")

export Driver, AbstractApp
export Cell, CELL_BLANK, CELL_CONT, is_continuation
export Buffer, BufferView, buffer_size, buffer_region
export clear!, resize_buffer
export set_cell!, write_text!, fill_region!, style_region!, blit!
export ScrolledView, writable_region
export Span, Patch, n_cells, diff, full_patch, apply!
export Ansi, AnsiEncoder, reset!, sgr!, encode!, encode
export parse_events, InputParser, feed!, flush_escape!, pending, pump_input!
export DriverCaps, CAPS_MINIMAL, DriverInterfaceError
export start!, stop!, restore!, emit!, flush!
export display_size, capabilities, events, set_title!, notify_resize!
export REQUIRED_DRIVER_METHODS, check_driver_interface, WEB_BRIDGE_SURFACE
export render!, paint!, paint_border!
export HeadlessDriver, push_event!, take_bytes!, output, clear_output!
export press!, type!, click!, resize!, feed_bytes!
export TerminalDriver, detect_caps, set_raw!
export AppConfig, App, run!, quit!, exit!, post!
export call_later!, set_interval!, invalidate!, pause!, resume!
export handle!, frame!, refresh!
export focused, focus!, focus_next!, focus_prev!, bind!, on_action, popup_of, open_popup!, close_popup!
export Backend, TerminalBackend, HeadlessBackend, make_driver, launch

end
