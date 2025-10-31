@testset "Node Inspection" begin
    @testset "is_named" begin
        p = Parser(:julia)
        tree = parse(p, "[1, 2]")
        root_node = TreeSitter.root(tree)

        # Structural nodes should be named
        @test TreeSitter.is_named(root_node)  # source_file
        array_node = TreeSitter.child(root_node, 1)
        @test TreeSitter.is_named(array_node)  # array_expression

        # Punctuation should not be named
        bracket_open = TreeSitter.child(array_node, 1)
        @test !TreeSitter.is_named(bracket_open)  # "["
        comma = TreeSitter.child(array_node, 3)
        @test !TreeSitter.is_named(comma)  # ","

        # Numbers should be named
        num1 = TreeSitter.child(array_node, 2)
        @test TreeSitter.is_named(num1)  # number
    end

    @testset "is_missing" begin
        p = Parser(:c)
        # Missing semicolon - creates ERROR and MISSING nodes
        tree = parse(p, "int x")
        root_node = TreeSitter.root(tree)

        # Traverse to find if any node is marked as missing
        found_error = false
        traverse(tree) do node, enter
            if enter && TreeSitter.is_missing(node)
                found_error = true
            end
        end
        @test found_error
    end

    @testset "is_extra" begin
        p = Parser(:c)
        tree = parse(p, "int x; // comment")

        # Find comment node and verify it's marked as extra
        found_comment = false
        traverse(tree) do node, enter
            if enter && TreeSitter.node_type(node) == "comment"
                @test TreeSitter.is_extra(node)
                found_comment = true
            end
        end
        @test found_comment
    end
end

@testset "Field-Based Child Access" begin
    @testset "C function declaration" begin
        p = Parser(:c)
        tree = parse(p, "int main(void) { return 0; }")
        root_node = TreeSitter.root(tree)

        # Get function definition node
        func_def = TreeSitter.child(root_node, 1)
        @test TreeSitter.node_type(func_def) == "function_definition"

        # Access fields by name
        type_node = TreeSitter.child(func_def, "type")
        @test TreeSitter.node_type(type_node) == "primitive_type"
        @test TreeSitter.slice("int main(void) { return 0; }", type_node) == "int"

        declarator = TreeSitter.child(func_def, "declarator")
        @test TreeSitter.node_type(declarator) == "function_declarator"

        body = TreeSitter.child(func_def, "body")
        @test TreeSitter.node_type(body) == "compound_statement"
    end

    @testset "JavaScript function declaration" begin
        p = Parser(:javascript)
        tree = parse(p, "function greet(name) { return name; }")
        root_node = TreeSitter.root(tree)

        func_decl = TreeSitter.child(root_node, 1)
        @test TreeSitter.node_type(func_decl) == "function_declaration"

        # Access name field
        name_node = TreeSitter.child(func_decl, "name")
        @test TreeSitter.node_type(name_node) == "identifier"
        @test TreeSitter.slice("function greet(name) { return name; }", name_node) ==
              "greet"

        # Access parameters field
        params = TreeSitter.child(func_decl, "parameters")
        @test TreeSitter.node_type(params) == "formal_parameters"

        # Access body field
        body = TreeSitter.child(func_decl, "body")
        @test TreeSitter.node_type(body) == "statement_block"
    end

    @testset "Julia function definition" begin
        p = Parser(:julia)
        tree = parse(p, "function add(x, y)\n    x + y\nend")
        root_node = TreeSitter.root(tree)

        func_def = TreeSitter.child(root_node, 1)
        @test TreeSitter.node_type(func_def) == "function_definition"

        # Access name field
        name_node = TreeSitter.child(func_def, "name")
        @test TreeSitter.node_type(name_node) == "identifier"
        @test TreeSitter.slice("function add(x, y)\n    x + y\nend", name_node) == "add"

        # Access parameters field (note: grammar has typo "parametere")
        params = TreeSitter.child(func_def, "parametere")
        @test TreeSitter.node_type(params) == "parameter_list"
    end

    @testset "Invalid field name" begin
        p = Parser(:c)
        tree = parse(p, "int main(void) { return 0; }")
        root_node = TreeSitter.root(tree)

        func_def = TreeSitter.child(root_node, 1)
        @test TreeSitter.node_type(func_def) == "function_definition"

        # Try to access a non-existent field
        @test_throws ArgumentError TreeSitter.child(func_def, "nonexistent_field")
    end
end

@testset "Node Equality" begin
    p = Parser(:julia)
    tree = parse(p, "f(x) = x")
    root_node = TreeSitter.root(tree)

    # Access same node via different paths
    node1 = TreeSitter.child(root_node, 1)

    # Access via children iterator
    node2 = first(children(root_node))

    # They should be equal
    @test node1 == node2

    # Different nodes should not be equal
    node3 = TreeSitter.child(root_node, 1)
    node4 = TreeSitter.child(node3, 1)  # Deeper node
    @test node3 != node4
end

@testset "Parent Navigation" begin
    p = Parser(:c)
    tree = parse(p, "int x = 1;")
    root_node = TreeSitter.root(tree)

    # Navigate down to a number literal
    decl = TreeSitter.child(root_node, 1)
    init_declarator = TreeSitter.child(decl, "declarator")
    value = TreeSitter.child(init_declarator, "value")
    @test TreeSitter.node_type(value) == "number_literal"

    # Navigate back up via parent
    parent_node = TreeSitter.parent(value)
    @test TreeSitter.node_type(parent_node) == "init_declarator"

    grandparent = TreeSitter.parent(parent_node)
    @test TreeSitter.node_type(grandparent) == "declaration"
end

@testset "Sibling Navigation" begin
    p = Parser(:julia)
    tree = parse(p, "[1, 2, 3]")
    root_node = TreeSitter.root(tree)

    array_node = TreeSitter.child(root_node, 1)

    # Get first number
    first_num = TreeSitter.child(array_node, 2)  # First number node
    @test TreeSitter.node_type(first_num) == "number"
    @test TreeSitter.slice("[1, 2, 3]", first_num) == "1"

    # Navigate to next sibling (comma)
    next_node = TreeSitter.next_sibling(first_num)
    @test TreeSitter.node_type(next_node) == ","

    # Navigate to next sibling (second number)
    second_num = TreeSitter.next_sibling(next_node)
    @test TreeSitter.node_type(second_num) == "number"
    @test TreeSitter.slice("[1, 2, 3]", second_num) == "2"

    # Navigate back via prev_sibling
    prev_node = TreeSitter.prev_sibling(second_num)
    @test TreeSitter.node_type(prev_node) == ","

    # Test named sibling navigation
    third_num = TreeSitter.next_named_sibling(second_num)
    @test TreeSitter.node_type(third_num) == "number"
    @test TreeSitter.slice("[1, 2, 3]", third_num) == "3"

    prev_named = TreeSitter.prev_named_sibling(third_num)
    @test TreeSitter.node_type(prev_named) == "number"
    @test TreeSitter.slice("[1, 2, 3]", prev_named) == "2"
end

@testset "TSPoint Positions" begin
    p = Parser(:julia)
    source = "f(x) = x + 1"
    tree = parse(p, source)
    root_node = TreeSitter.root(tree)
    node = TreeSitter.child(root_node, 1)

    # Verify we can get start and end points
    start_pt = TreeSitter.start_point(node)
    end_pt = TreeSitter.end_point(node)

    # Points should have row and column fields
    @test isa(start_pt.row, Integer)
    @test isa(start_pt.column, Integer)
    @test isa(end_pt.row, Integer)
    @test isa(end_pt.column, Integer)

    # End should be after start
    @test (start_pt.row < end_pt.row) ||
          (start_pt.row == end_pt.row && start_pt.column < end_pt.column)
end
