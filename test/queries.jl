@testset "Captures & Predicates" begin
    @testset "match? predicate" begin
        p = Parser(:julia)
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
        p = Parser(:javascript)
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
        p = Parser(:javascript)
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
end

@testset "Loading Query Files" begin
    p = Parser(:c)
    source = """
             int main(void) {
                 // comment
             }
             """
    tree = parse(p, source)
    q = Query(:c, ["highlights"])
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
