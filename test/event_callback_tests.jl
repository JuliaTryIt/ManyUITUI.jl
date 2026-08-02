@testitem "events: public callback names are uniform" begin
    using ManyUI, ManyUITUI

    button = Button("Save", _ -> nothing)
    list = List(["a", "b"])
    table = Table([(1,), (2,)], [Column("N")])
    tree = TreeView([TreeNode("a"), TreeNode("b")])

    @test hasfield(typeof(button), :on_click)
    @test !hasfield(typeof(button), :on_press)
    @test hasfield(typeof(list), :on_submit)
    @test hasfield(typeof(table), :on_submit)
    @test hasfield(typeof(tree), :on_submit)
    @test !hasfield(typeof(list), :on_activate)
    @test !hasfield(typeof(table), :on_activate)
    @test !hasfield(typeof(tree), :on_activate)
end

@testitem "events: row selections fire on_change exactly once" begin
    using ManyUI, ManyUITUI

    list_changes = Ref(0)
    table_changes = Ref(0)
    datatable_changes = Ref(0)
    tree_changes = Ref(0)

    list = List(["a", "b"]; on_change = _ -> (list_changes[] += 1))
    table = Table([(1,), (2,)], [Column("N")];
                  on_change = _ -> (table_changes[] += 1))
    datatable = DataTable([(2,), (1,)], [Column("N")];
                          key = (row, column) -> row[column],
                          on_change = _ -> (datatable_changes[] += 1))
    tree = TreeView([TreeNode("a"), TreeNode("b")];
                    on_change = _ -> (tree_changes[] += 1))

    @test set_cursor!(list, 2)
    @test set_cursor!(table, 2)
    @test set_cursor!(datatable, 2)
    @test set_cursor!(tree, 2)
    @test (list_changes[], table_changes[], datatable_changes[], tree_changes[]) ==
          (1, 1, 1, 1)

    @test !set_cursor!(list, 2)
    @test !set_cursor!(table, 2)
    @test !set_cursor!(datatable, 2)
    @test !set_cursor!(tree, 2)
    @test (list_changes[], table_changes[], datatable_changes[], tree_changes[]) ==
          (1, 1, 1, 1)
end

@testitem "events: WidgetNode focus callbacks survive specialized hooks" begin
    using ManyUI, ManyUITUI

    focused = Ref(0)
    blurred = Ref(0)
    list = List(["a"])
    node(list).on_focus = _ -> (focused[] += 1)
    node(list).on_blur = _ -> (blurred[] += 1)

    @test on_focus!(list) === nothing
    @test on_blur!(list) === nothing
    @test focused[] == 1
    @test blurred[] == 1
end
