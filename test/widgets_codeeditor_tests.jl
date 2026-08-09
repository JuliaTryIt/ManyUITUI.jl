# widgets_codeeditor_tests.jl -- a TextArea that lexes.
# Written BEFORE the implementation (TDD, CLAUDE.md).
#
# A code editor is a TextArea with a highlighter, not a second widget
# type -- the same call a Gauge did not deserve a type for. So these
# test the SEAM and the one highlighter, and above all the two things a
# per-line highlighter gets wrong: a string that spans lines, and text
# that does not lex because it is mid-edit.

@testitem "codeeditor: it is a TextArea with one field set" begin
    using ManyUI, ManyUITUI

    e = CodeEditor("x = 1")
    @test e isa TextArea
    @test e.highlight !== nothing
    # Every TextArea verb still applies, because it IS one.
    @test text(e) == "x = 1"
    insert_text!(e, "0")             # at the caret, which starts at 0
    @test text(e) == "0x = 1"

    plainarea = TextArea("x = 1")
    @test plainarea.highlight === nothing
    @test isempty(code_lines(plainarea))     # no highlighter, no lines

    @test CodeEditor("x"; language = :none).highlight === nothing
    @test_throws ArgumentError CodeEditor("x"; language = :cobol)
end

@testitem "codeeditor: tokens become runs on their own line" begin
    using ManyUI, ManyUITUI

    e = CodeEditor("function f(x)\n    return 1\nend")
    ls = code_lines(e)
    @test length(ls) == 3
    @test plain(ls[1]) == "function f(x)"
    @test plain(ls[2]) == "    return 1"
    @test plain(ls[3]) == "end"

    # The keyword is styled and the rest of its line is not the same.
    kw = ls[1].runs[1]
    @test kw.text == "function"
    @test kw.style == code_face_style(:julia_keyword)
    @test length(ls[1].runs) > 1
end

@testitem "codeeditor: the plain text survives highlighting exactly" begin
    using ManyUI, ManyUITUI

    src = "s = \"héllo 世界\"  # a comment\nf(x) = x^2"
    e = CodeEditor(src)
    # Styling must not add, drop or reorder a single character, and a
    # run boundary must land on a character boundary or the substring
    # would have thrown on the way in.
    @test join(plain.(code_lines(e)), "\n") == src
end

@testitem "codeeditor: highlighting is WHOLE-document, not per line" begin
    using ManyUI, ManyUITUI

    # THE case a per-line highlighter gets wrong: line 2 is inside a
    # string, and nothing on line 2 says so.
    e = CodeEditor("s = \"\"\"\nnot code\n\"\"\"\nx = 1")
    ls = code_lines(e)
    @test length(ls) == 4

    strstyle = code_face_style(:julia_string)
    @test any(r -> r.style == strstyle, ls[2].runs)
    # And line 4, back outside the string, is not string-coloured.
    @test !all(r -> r.style == strstyle, ls[4].runs)
end

@testitem "codeeditor: unlexable text is drawn, never refused" begin
    using ManyUI, ManyUITUI

    # Text under a cursor is invalid most of the time it is being
    # typed. An editor that refused to draw then would be unusable.
    for src in ("function f(", "\"unterminated", "end end end", "((((")
        e = CodeEditor(src)
        ls = code_lines(e)
        @test join(plain.(ls), "\n") == src
    end
end

@testitem "codeeditor: the cache is keyed on version" begin
    using ManyUI, ManyUITUI

    e = CodeEditor("x = 1")
    first = code_lines(e)
    # Same version: the SAME vector, not an equal one -- one relex per
    # edit, none per frame.
    @test code_lines(e) === first

    insert_text!(e, "1")
    second = code_lines(e)
    @test second !== first
    @test plain(second[1]) == text(e)
end

@testitem "codeeditor: faces are themed, not hard-coded" begin
    using ManyUI, ManyUITUI

    @test is_token(code_face_style(:julia_keyword).fg)
    @test is_token(code_face_style(:julia_comment).fg)
    # An unknown face is INVISIBLE rather than wrong: it falls back to
    # the widget's own style.
    @test code_face_style(:no_such_face) == STYLE_NONE

    before = theme()
    try
        set_theme!(:dark)
        dark = resolve_token(code_face_style(:julia_keyword).fg)
        set_theme!(:light)
        @test resolve_token(code_face_style(:julia_keyword).fg) != dark
    finally
        set_theme!(before)
    end
end

@testitem "codeeditor: it paints its runs, and still has a caret" begin
    using ManyUI, ManyUITUI

    # A COMPLETE construct: "end" on its own does not lex, and would
    # take the graceful plain path the previous testitem pins.
    e = CodeEditor("function f()\nend")
    apply_stylesheet!(STYLESHEET_EMPTY, e)
    buf = Buffer(16, 2)
    render!(e, buf)

    @test join(String(buf[x, 1].content) for x = 1:8) == "function"
    @test buf[1, 1].style.fg == code_face_style(:julia_keyword).fg

    # A plain TextArea is byte-for-byte what it was: one field decides
    # which path a frame takes.
    p = TextArea("function f()\nend")
    apply_stylesheet!(STYLESHEET_EMPTY, p)
    pb = Buffer(16, 2)
    render!(p, pb)
    @test join(String(pb[x, 1].content) for x = 1:8) == "function"
    @test pb[1, 1].style.fg != code_face_style(:julia_keyword).fg

    # The caret still reverses its cell.
    e.focused[] = true
    move_by!(e, 2)
    cb = Buffer(16, 2)
    render!(e, cb)
    @test any(x -> has(cb[x, 1].style, Attr.REVERSE), 1:16)
end
