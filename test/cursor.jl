import tree_sitter_c_jll

@testset "TreeCursor" begin
    p = Parser(tree_sitter_c_jll)
    tree = parse(p, "int main(void){return 0;}")

    @testset "cursor traversal exposes field names" begin
        visited = Tuple{String,Union{String,Nothing}}[]
        TreeSitter.traverse(TreeSitter.TreeCursor(tree)) do node, field, enter
            enter && push!(visited, (TreeSitter.node_type(node), field))
        end

        types = first.(visited)
        @test types[1] == "translation_unit"
        @test "function_definition" in types
        # The field name a node occupies in its parent surfaces during the walk.
        @test ("primitive_type", "type") in visited
        @test ("function_declarator", "declarator") in visited
        # The root has no field.
        @test visited[1][2] === nothing
    end

    @testset "manual navigation" begin
        cursor = TreeSitter.TreeCursor(tree)
        @test TreeSitter.node_type(TreeSitter.current_node(cursor)) == "translation_unit"
        @test TreeSitter.current_field_name(cursor) === nothing

        @test TreeSitter.goto_first_child!(cursor)
        @test TreeSitter.node_type(TreeSitter.current_node(cursor)) == "function_definition"

        @test TreeSitter.goto_first_child!(cursor)
        @test TreeSitter.node_type(TreeSitter.current_node(cursor)) == "primitive_type"
        @test TreeSitter.current_field_name(cursor) == "type"
        @test TreeSitter.current_field_id(cursor) == TreeSitter.field_id_for_name(p, "type")

        @test TreeSitter.goto_next_sibling!(cursor)
        @test TreeSitter.node_type(TreeSitter.current_node(cursor)) == "function_declarator"

        @test TreeSitter.goto_parent!(cursor)
        @test TreeSitter.node_type(TreeSitter.current_node(cursor)) == "function_definition"
    end

    @testset "copy is independent" begin
        cursor = TreeSitter.TreeCursor(tree)
        TreeSitter.goto_first_child!(cursor)  # function_definition
        clone = copy(cursor)
        TreeSitter.goto_first_child!(clone)  # primitive_type
        @test TreeSitter.node_type(TreeSitter.current_node(cursor)) == "function_definition"
        @test TreeSitter.node_type(TreeSitter.current_node(clone)) == "primitive_type"
    end

    @testset "reset and goto_first_child_for_byte" begin
        cursor = TreeSitter.TreeCursor(tree)
        TreeSitter.goto_first_child!(cursor)
        @test TreeSitter.node_type(TreeSitter.current_node(cursor)) == "function_definition"

        TreeSitter.reset!(cursor, TreeSitter.root(tree))
        @test TreeSitter.node_type(TreeSitter.current_node(cursor)) == "translation_unit"

        TreeSitter.goto_first_child!(cursor)
        @test TreeSitter.goto_first_child_for_byte!(cursor, 1) == 1
        @test TreeSitter.goto_first_child_for_byte!(cursor, 1000) === nothing
    end

    @test repr(TreeSitter.TreeCursor(tree)) == "TreeCursor()"
end
