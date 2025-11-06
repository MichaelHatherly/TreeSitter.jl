import tree_sitter_bash_jll,
    tree_sitter_c_jll,
    tree_sitter_cpp_jll,
    tree_sitter_go_jll,
    tree_sitter_html_jll,
    tree_sitter_java_jll,
    tree_sitter_javascript_jll,
    tree_sitter_json_jll,
    tree_sitter_julia_jll,
    tree_sitter_php_jll,
    tree_sitter_python_jll,
    tree_sitter_ruby_jll,
    tree_sitter_rust_jll,
    tree_sitter_typescript_jll

@testset "Load & Parse" begin
    language_jlls = [
        (:bash, tree_sitter_bash_jll),
        (:c, tree_sitter_c_jll),
        (:cpp, tree_sitter_cpp_jll),
        (:go, tree_sitter_go_jll),
        (:html, tree_sitter_html_jll),
        (:java, tree_sitter_java_jll),
        (:javascript, tree_sitter_javascript_jll),
        (:json, tree_sitter_json_jll),
        (:julia, tree_sitter_julia_jll),
        (:php, tree_sitter_php_jll),
        (:python, tree_sitter_python_jll),
        (:ruby, tree_sitter_ruby_jll),
        (:rust, tree_sitter_rust_jll),
        (:typescript, tree_sitter_typescript_jll),
    ]

    for (lang_name, lang_jll) in language_jlls
        @testset "$lang_name" begin
            p = Parser(lang_jll)
            tree = parse(p, "")
            @test !isempty(string(tree))
        end
    end
end

@testset "Languages" begin
    @testset "bash" begin
        p = Parser(:bash)
        tree = parse(p, "echo {1..10}")
        @test string(tree) ==
              "(program (command name: (command_name (word)) argument: (brace_expression (number) (number))))"
    end
    @testset "c" begin
        p = Parser(:c)
        tree = parse(p, "int x = 1;")
        @test string(tree) ==
              "(translation_unit (declaration type: (primitive_type) declarator: (init_declarator declarator: (identifier) value: (number_literal))))"
    end
    @testset "cpp" begin
        p = Parser(:cpp)
        tree = parse(p, "using namespace std;")
        @test string(tree) == "(translation_unit (using_declaration (identifier)))"
    end
    @testset "go" begin
        p = Parser(:go)
        tree = parse(p, "var x = []int{1}")
        @test string(tree) ==
              "(source_file (var_declaration (var_spec name: (identifier) value: (expression_list (composite_literal type: (slice_type element: (type_identifier)) body: (literal_value (literal_element (int_literal))))))))"
    end
    @testset "html" begin
        p = Parser(:html)
        tree = parse(p, "<h1>header</h1>")
        @test string(tree) ==
              "(document (element (start_tag (tag_name)) (text) (end_tag (tag_name))))"
    end
    @testset "java" begin
        p = Parser(:java)
        tree = parse(p, "public static void f() {}")
        @test string(tree) ==
              "(program (method_declaration (modifiers) type: (void_type) name: (identifier) parameters: (formal_parameters) body: (block)))"
    end
    @testset "javascript" begin
        p = Parser(:javascript)
        tree = parse(p, "function f() {}")
        @test string(tree) ==
              "(program (function_declaration name: (identifier) parameters: (formal_parameters) body: (statement_block)))"
    end
    @testset "json" begin
        p = Parser(:json)
        tree = parse(p, "{\"key\": 1}")
        @test string(tree) ==
              "(document (object (pair key: (string (string_content)) value: (number))))"
    end
    @testset "julia" begin
        p = Parser(:julia)
        tree = parse(p, "f(x::Int) = x + 1")
        @test string(tree) ==
              "(source_file (assignment (call_expression (identifier) (argument_list (typed_expression (identifier) (identifier)))) (operator) (binary_expression (identifier) (operator) (integer_literal))))"
    end
    @testset "php" begin
        p = Parser(:php)
        tree = parse(p, "<?php\n\$x = 1;\n?>")
        @test string(tree) ==
              "(program (php_tag) (expression_statement (assignment_expression left: (variable_name (name)) right: (integer))) (text_interpolation (php_end_tag)))"
    end
    @testset "php multi-parser" begin
        # Test list_parsers
        parsers = list_parsers(tree_sitter_php_jll)
        @test :php in parsers
        @test :php_only in parsers
        @test length(parsers) == 2

        # Test default parser (php)
        p1 = Parser(tree_sitter_php_jll)
        @test p1.language.name == :php
        tree1 = parse(p1, "<?php\n\$x = 1;\n?>")
        @test string(tree1) ==
              "(program (php_tag) (expression_statement (assignment_expression left: (variable_name (name)) right: (integer))) (text_interpolation (php_end_tag)))"

        # Test php_only variant
        p2 = Parser(tree_sitter_php_jll, :php_only)
        @test p2.language.name == :php_only
        tree2 = parse(p2, "\$x = 1;")
        @test string(tree2) ==
              "(program (expression_statement (assignment_expression left: (variable_name (name)) right: (integer))))"

        # Test that parsers produce different results for same input
        tree_default = parse(p1, "\$x = 1;")
        tree_only = parse(p2, "\$x = 1;")
        @test string(tree_default) != string(tree_only)
    end
    @testset "python" begin
        p = Parser(:python)
        tree = parse(p, "1 < 2 and 2 < 3")
        @test string(tree) ==
              "(module (expression_statement (boolean_operator left: (comparison_operator (integer) (integer)) right: (comparison_operator (integer) (integer)))))"
    end
    @testset "ruby" begin
        p = Parser(:ruby)
        tree = parse(p, "\"Hello\".method(:class).class")
        @test string(tree) ==
              "(program (call receiver: (call receiver: (string (string_content)) method: (identifier) arguments: (argument_list (simple_symbol))) method: (identifier)))"
    end
    @testset "rust" begin
        p = Parser(:rust)
        tree = parse(p, "let x: i32 = 13i32;")
        @test string(tree) ==
              "(source_file (let_declaration pattern: (identifier) type: (primitive_type) value: (integer_literal)))"
    end
    @testset "typescript" begin
        p = Parser(:typescript)
        tree = parse(p, "let list: number[] = [1];")
        @test string(tree) ==
              "(program (lexical_declaration (variable_declarator name: (identifier) type: (type_annotation (array_type (predefined_type))) value: (array (number)))))"
    end
end
