using TreeSitter, Test

@testset "TreeSitter" begin
    @testset "Load & Parse" begin
        for lang in TreeSitter.API.LANGUAGES
            @testset "$lang" begin
                p = Parser(lang)
                tree = parse(p, "")
                @test !isempty(string(tree))
            end
        end
    end
    @testset "Tree Traversal" begin
        p = Parser(:julia)
        tree = parse(p, "[1, 2]")

        out = String[]
        traverse(tree) do node, enter
            enter && push!(out, TreeSitter.node_type(node))
        end
        @test out == ["source_file", "array_expression", "[", "number", ",", "number", "]"]

        out = String[]
        traverse(tree) do node, enter
            enter || push!(out, TreeSitter.node_type(node))
        end
        @test out == ["[", "number", ",", "number", "]", "array_expression", "source_file"]

        out = String[]
        traverse(tree, named_children) do node, enter
            enter && push!(out, TreeSitter.node_type(node))
        end
        @test out == ["source_file", "array_expression", "number", "number"]

        out = String[]
        traverse(tree, named_children) do node, enter
            enter || push!(out, TreeSitter.node_type(node))
        end
        @test out == ["number", "number", "array_expression", "source_file"]
    end
    @testset "Languages" begin
        @testset "bash" begin
            p = Parser(:bash)
            tree = parse(p, "echo {1..10}")
            @test string(tree) == "(program (command name: (command_name (word)) argument: (concatenation (word))))"
        end
        @testset "c" begin
            p = Parser(:c)
            tree = parse(p, "int x = 1;")
            @test string(tree) == "(translation_unit (declaration type: (primitive_type) declarator: (init_declarator declarator: (identifier) value: (number_literal))))"
        end
        @testset "cpp" begin
            p = Parser(:cpp)
            tree = parse(p, "using namespace std;")
            @test string(tree) == "(translation_unit (using_declaration (identifier)))"
        end
        @testset "go" begin
            p = Parser(:go)
            tree = parse(p, "var x := []int{1}")
            @test string(tree) == "(source_file (var_declaration (var_spec name: (identifier) (ERROR) type: (slice_type element: (type_identifier)))) (ERROR (int_literal)))"
        end
        @testset "html" begin
            p = Parser(:html)
            tree = parse(p, "<h1>header</h1>")
            @test string(tree) == "(fragment (element (start_tag (tag_name)) (text) (end_tag (tag_name))))"
        end
        @testset "java" begin
            p = Parser(:java)
            tree = parse(p, "public static void f() {}")
            @test string(tree) == "(program (local_variable_declaration_statement (local_variable_declaration (modifiers) type: (void_type) declarator: (variable_declarator name: (identifier))) (MISSING \";\")) (ERROR (formal_parameters)) (block))"
        end
        @testset "javascript" begin
            p = Parser(:javascript)
            tree = parse(p, "function f() {}")
            @test string(tree) == "(program (function_declaration name: (identifier) parameters: (formal_parameters) body: (statement_block)))"
        end
        @testset "json" begin
            p = Parser(:json)
            tree = parse(p, "{1: 1}")
            @test string(tree) == "(document (object (pair key: (number) value: (number))))"
        end
        @testset "julia" begin
            p = Parser(:julia)
            tree = parse(p, "f(x::Int) = x + 1")
            @test string(tree) == "(source_file (assignment_expression (call_expression (identifier) (argument_list (typed_expression (identifier) (identifier)))) (binary_expression (identifier) (number))))"
        end
        @testset "php" begin
            p = Parser(:php)
            tree = parse(p, "<?php\n\$x = 1;\n?>")
            @test string(tree) == "(program (php_tag) (expression_statement (assignment_expression left: (variable_name (name)) right: (integer))) (text_interpolation))"
        end
        @testset "python" begin
            p = Parser(:python)
            tree = parse(p, "1 < 2 and 2 < 3")
            @test string(tree) == "(module (expression_statement (boolean_operator left: (comparison_operator (integer) (integer)) right: (comparison_operator (integer) (integer)))))"
        end
        @testset "ruby" begin
            p = Parser(:ruby)
            tree = parse(p, "\"Hello\".method(:class).class")
            @test string(tree) == "(program (call receiver: (method_call method: (call receiver: (string) method: (identifier)) arguments: (argument_list (symbol))) method: (identifier)))"
        end
        @testset "rust" begin
            p = Parser(:rust)
            tree = parse(p, "let x: i32 = 13i32;")
            @test string(tree) == "(source_file (let_declaration pattern: (identifier) type: (primitive_type) value: (integer_literal)))"
        end
        @testset "typescript" begin
            p = Parser(:typescript)
            tree = parse(p, "let list: number[] = [1];")
            @test string(tree) == "(program (lexical_declaration (variable_declarator name: (identifier) type: (type_annotation (array_type (predefined_type))) value: (array (number)))))"
        end
    end
end
