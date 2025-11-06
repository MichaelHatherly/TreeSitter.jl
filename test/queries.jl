import tree_sitter_julia_jll, tree_sitter_javascript_jll, tree_sitter_c_jll

@testset "Captures & Predicates" begin
    @testset "match? predicate" begin
        p = Parser(tree_sitter_julia_jll)
        source = """
                 const X = 1
                 f(x) = x
                 """
        tree = parse(p, source)
        q = query```
        (
            (identifier) @lowercase
            (#match? @lowercase "^[a-z]+$")
        )
        (
            (identifier) @uppercase
            (#match? @uppercase "^[A-Z]+$")
        )
        ```julia
        out = []
        for capture in TreeSitter.each_capture(tree, q, source)
            id = TreeSitter.capture_name(q, capture)
            literal = TreeSitter.slice(source, capture.node)
            push!(out, (id, literal))
        end
        @test out[1] == ("uppercase", "X")
        @test out[2] == ("lowercase", "f")
        @test out[3] == ("lowercase", "x")
        @test out[4] == ("lowercase", "x")
    end

    @testset "eq? predicate" begin
        p = Parser(tree_sitter_javascript_jll)
        source = """
        require('fs')
        import('path')
        require('util')
        """
        tree = parse(p, source)

        # Match only 'require' function calls, not 'import'
        q = query```
        (call_expression
          function: (identifier) @function
          (#eq? @function "require"))
        ```javascript

        out = []
        for capture in TreeSitter.each_capture(tree, q, source)
            id = TreeSitter.capture_name(q, capture)
            literal = TreeSitter.slice(source, capture.node)
            push!(out, (id, literal))
        end

        # Should match exactly 2 'require' calls
        @test length(out) == 2
        @test all(t -> t == ("function", "require"), out)
    end

    @testset "not-eq? predicate" begin
        p = Parser(tree_sitter_javascript_jll)
        source = """
        class Foo {
          constructor() {}
          method() {}
          helper() {}
        }
        """
        tree = parse(p, source)

        # Match method definitions that are NOT constructors
        q = query```
        (method_definition
          name: (property_identifier) @method
          (#not-eq? @method "constructor"))
        ```javascript

        out = []
        for capture in TreeSitter.each_capture(tree, q, source)
            id = TreeSitter.capture_name(q, capture)
            literal = TreeSitter.slice(source, capture.node)
            push!(out, (id, literal))
        end

        # Should match 'method' and 'helper' but not 'constructor'
        @test length(out) == 2
        method_names = [t[2] for t in out]
        @test "method" in method_names
        @test "helper" in method_names
        @test !("constructor" in method_names)
    end

    @testset "any-of? predicate" begin
        p = Parser(tree_sitter_c_jll)
        source = """
        int foo() { return 0; }
        void bar() { return; }
        char baz() { return 'x'; }
        float qux() { return 1.0; }
        """
        tree = parse(p, source)

        # Match function declarations with return type 'int', 'void', or 'char'
        q = query```
        (function_definition
          type: (primitive_type) @type
          (#any-of? @type "int" "void" "char"))
        ```c

        out = []
        for capture in TreeSitter.each_capture(tree, q, source)
            id = TreeSitter.capture_name(q, capture)
            literal = TreeSitter.slice(source, capture.node)
            push!(out, (id, literal))
        end

        # Should match 'int', 'void', and 'char', but not 'float'
        @test length(out) == 3
        types = [t[2] for t in out]
        @test "int" in types
        @test "void" in types
        @test "char" in types
        @test !("float" in types)
    end

    @testset "has-ancestor? predicate" begin
        p = Parser(tree_sitter_julia_jll)
        # Julia code with 'begin' and 'end' in different contexts
        # In index expressions like a[begin:end], they should be captured
        # In other contexts (like begin/end blocks or standalone ranges), they should not
        source = """
        x = a[begin:end]
        y = begin:end
        begin
            z = 1
        end
        """

        # Query that uses has-ancestor? to match begin/end only in index_expression
        q = query```
        ((identifier) @indexer
          (#any-of? @indexer "begin" "end")
          (#has-ancestor? @indexer index_expression))
        ```julia

        tree = parse(p, source)
        out = []
        for capture in TreeSitter.each_capture(tree, q, source)
            id = TreeSitter.capture_name(q, capture)
            literal = TreeSitter.slice(source, capture.node)
            push!(out, (id, literal))
        end

        # Should only match 'begin' and 'end' inside a[begin:end]
        # Not in the standalone range 'begin:end' or the begin/end block keywords
        @test length(out) == 2
        @test ("indexer", "begin") in out
        @test ("indexer", "end") in out
    end
end

@testset "Loading Query Files" begin
    p = Parser(tree_sitter_c_jll)
    source = """
             int main(void) {
                 // comment
             }
             """
    tree = parse(p, source)
    q = Query(tree_sitter_c_jll, ["highlights"])
    out = []
    for capture in TreeSitter.each_capture(tree, q, source)
        id = TreeSitter.capture_name(q, capture)
        literal = TreeSitter.slice(source, capture.node)
        push!(out, (id, literal))
    end
    @test out[1] == ("type", "int")
    @test out[2] == ("function", "main")
    @test out[3] == ("variable", "main")
    @test out[4] == ("type", "void")
    @test out[5] == ("comment", "// comment")
end

@testset "Query Syntax Errors" begin
    @testset "Invalid syntax" begin
        # Malformed query syntax should throw QueryException
        @test_throws TreeSitter.QueryException query```
        (invalid_node_type_that_doesnt_exist) @x
        ```julia
    end
end
