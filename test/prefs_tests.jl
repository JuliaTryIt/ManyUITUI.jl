# prefs_tests.jl -- what survives a restart.
# Written BEFORE the implementation (TDD, CLAUDE.md).
#
# These WRITE to the active project's LocalPreferences.toml, so each
# one activates a throwaway project first: a test suite that edited the
# package's own preferences would change what the next run of the
# application does, which is the one thing a preference must not do by
# accident.

@testitem "prefs: a gensym id cannot key a preference" begin
    using ManyUI, ManyUITUI

    # THE constraint that shapes this file. `gensym(:splitter)` is a
    # different symbol every run, so persisting under it would write a
    # growing pile of dead keys and restore none of them -- silently.
    @test is_persistable_id(:sessions_split)
    @test is_persistable_id(:x)
    @test !is_persistable_id(gensym(:splitter))
    @test !is_persistable_id(id(Splitter(Label("a"), Label("b"))))
    @test is_persistable_id(id(Splitter(Label("a"), Label("b");
                                        id = :named)))
end

@testitem "prefs: theme round trip" begin
    using ManyUI, ManyUITUI

    old_project = Base.active_project()
    dir = mktempdir()
    before = theme()
    try
        write(joinpath(dir, "Project.toml"), "")
        Base.set_active_project(joinpath(dir, "Project.toml"))

        @test theme_pref() === nothing
        @test restore_theme!() === nothing      # nothing saved yet

        save_theme_pref!(:light)
        @test theme_pref() === :light

        set_theme!(:dark)
        @test theme().name === :dark
        th = restore_theme!()
        @test th !== nothing
        @test theme().name === :light

        # A name that is no longer registered is IGNORED, not thrown: a
        # preference file outlives the code that wrote it, and a stale
        # entry must not stop the application starting.
        save_theme_pref!(:no_such_theme)
        set_theme!(:dark)
        @test restore_theme!() === nothing
        @test theme().name === :dark
    finally
        set_theme!(before)
        Base.set_active_project(old_project)
        rm(dir; recursive = true, force = true)
    end
end

@testitem "prefs: splitter positions survive a round trip" begin
    using ManyUI, ManyUITUI

    old_project = Base.active_project()
    dir = mktempdir()
    try
        write(joinpath(dir, "Project.toml"), "")
        Base.set_active_project(joinpath(dir, "Project.toml"))

        mk() = Container(Splitter(Label("a"), Label("b"), Label("c");
                                  id = :panes, weights = [1, 1, 1]))

        root = mk()
        sp = query_one(root, "#panes", Splitter)
        set_weights!(sp, [3, 2, 1])
        @test save_splits!(root) == 1

        # A NEW tree of the same shape gets the remembered geometry.
        root2 = mk()
        sp2 = query_one(root2, "#panes", Splitter)
        @test weights_of(sp2) == Float32[1, 1, 1]
        @test restore_splits!(root2) == 1
        @test weights_of(sp2) == Float32[3, 2, 1]
    finally
        Base.set_active_project(old_project)
        rm(dir; recursive = true, force = true)
    end
end

@testitem "prefs: an unnamed splitter is skipped, and says so" begin
    using ManyUI, ManyUITUI

    old_project = Base.active_project()
    dir = mktempdir()
    try
        write(joinpath(dir, "Project.toml"), "")
        Base.set_active_project(joinpath(dir, "Project.toml"))

        root = Container(Splitter(Label("a"), Label("b")),          # gensym
                         Splitter(Label("c"), Label("d"); id = :kept))
        # The count is the report: a caller can say "one of your two
        # splitters has no id" rather than wondering why nothing came
        # back.
        @test save_splits!(root) == 1
        @test restore_splits!(root) == 1
    finally
        Base.set_active_project(old_project)
        rm(dir; recursive = true, force = true)
    end
end

@testitem "prefs: a reshaped tree is skipped, never misapplied" begin
    using ManyUI, ManyUITUI

    old_project = Base.active_project()
    dir = mktempdir()
    try
        write(joinpath(dir, "Project.toml"), "")
        Base.set_active_project(joinpath(dir, "Project.toml"))

        three = Container(Splitter(Label("a"), Label("b"), Label("c");
                                   id = :panes, weights = [3, 2, 1]))
        save_splits!(three)

        # Same id, two panes now. The old weights either throw or
        # silently mean something else, so they are not applied.
        two = Container(Splitter(Label("a"), Label("b"); id = :panes))
        sp = query_one(two, "#panes", Splitter)
        @test restore_splits!(two) == 0
        @test weights_of(sp) == Float32[1, 1]
    finally
        Base.set_active_project(old_project)
        rm(dir; recursive = true, force = true)
    end
end

@testitem "prefs: nothing remembered restores nothing" begin
    using ManyUI, ManyUITUI

    old_project = Base.active_project()
    dir = mktempdir()
    try
        write(joinpath(dir, "Project.toml"), "")
        Base.set_active_project(joinpath(dir, "Project.toml"))

        root = Container(Splitter(Label("a"), Label("b"); id = :panes))
        @test restore_splits!(root) == 0        # no file at all
        @test weights_of(query_one(root, "#panes", Splitter)) ==
              Float32[1, 1]
    finally
        Base.set_active_project(old_project)
        rm(dir; recursive = true, force = true)
    end
end

@testitem "prefs: the two app verbs do both halves" begin
    using ManyUI, ManyUITUI

    old_project = Base.active_project()
    dir = mktempdir()
    before = theme()
    try
        write(joinpath(dir, "Project.toml"), "")
        Base.set_active_project(joinpath(dir, "Project.toml"))

        root = Container(Splitter(Label("a"), Label("b"); id = :panes))
        app = App(root, HeadlessDriver(Size(30, 8)))
        set_theme!(:light)
        set_weights!(query_one(root, "#panes", Splitter), [4, 1])
        save_ui_prefs!(app)

        root2 = Container(Splitter(Label("a"), Label("b"); id = :panes))
        app2 = App(root2, HeadlessDriver(Size(30, 8)))
        set_theme!(:dark)
        restore_ui_prefs!(app2)

        @test theme().name === :light
        @test weights_of(query_one(root2, "#panes", Splitter)) ==
              Float32[4, 1]
        # A theme swap does not dirty the tree -- nothing in it holds a
        # resolved colour -- so restoring asks for the repaint itself.
        @test app2.needs_full
    finally
        set_theme!(before)
        Base.set_active_project(old_project)
        rm(dir; recursive = true, force = true)
    end
end
