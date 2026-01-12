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

    @testset "not-match? predicate" begin
        p = Parser(tree_sitter_julia_jll)
        source = """
        _private = 1
        public_var = 2
        another = 3
        _internal = 4
        """
        tree = parse(p, source)

        # Match identifiers that DON'T start with underscore
        q = query```
        ((identifier) @public
         (#not-match? @public "^_"))
        ```julia

        out = []
        for capture in TreeSitter.each_capture(tree, q, source)
            literal = TreeSitter.slice(source, capture.node)
            push!(out, literal)
        end

        # Should match public_var and another, but not _private or _internal
        @test "public_var" in out
        @test "another" in out
        @test !("_private" in out)
        @test !("_internal" in out)
    end

    @testset "is? predicate - named property" begin
        p = Parser(tree_sitter_c_jll)
        source = "int x = 1 + 2;"
        tree = parse(p, source)

        # Match only named nodes (excludes punctuation like '=', ';')
        q = query```
        ((_ ) @node
         (#is? @node "named"))
        ```c

        out = []
        for capture in TreeSitter.each_capture(tree, q, source)
            literal = TreeSitter.slice(source, capture.node)
            push!(out, literal)
        end

        # Should include 'int', 'x', '1', '2', '1 + 2', but not '=' or ';'
        @test "=" ∉ out
        @test ";" ∉ out
        @test "int" in out || "int x = 1 + 2;" in out  # May capture parent nodes
    end

    @testset "is-not? predicate - named property" begin
        p = Parser(tree_sitter_c_jll)
        source = "int x;"
        tree = parse(p, source)

        # Match only named nodes - is-not? should filter them out for "extra" property
        # (there are no extra nodes in this example, so result should be empty)
        q = query```
        ((identifier) @node
         (#is-not? @node "extra"))
        ```c

        out = []
        for capture in TreeSitter.each_capture(tree, q, source)
            literal = TreeSitter.slice(source, capture.node)
            push!(out, literal)
        end

        # Should match identifiers (they are not extra)
        @test "x" in out
        @test length(out) >= 1
    end

    @testset "is? predicate - single-arg format" begin
        p = Parser(tree_sitter_c_jll)
        source = "int x = 1;"
        tree = parse(p, source)

        # Single-arg format (#is? named) without explicit capture reference
        q = query```
        ((_ ) @node
         (#is? named))
        ```c

        out = []
        for capture in TreeSitter.each_capture(tree, q, source)
            literal = TreeSitter.slice(source, capture.node)
            push!(out, literal)
        end

        # Should include named nodes, exclude '=' and ';'
        @test "=" ∉ out
        @test ";" ∉ out
        @test !isempty(out)
    end

    @testset "is-not? predicate - single-arg format" begin
        p = Parser(tree_sitter_c_jll)
        source = "int x;"
        tree = parse(p, source)

        # Single-arg format (#is-not? extra)
        q = query```
        ((identifier) @node
         (#is-not? extra))
        ```c

        out = []
        for capture in TreeSitter.each_capture(tree, q, source)
            literal = TreeSitter.slice(source, capture.node)
            push!(out, literal)
        end

        # Should match identifiers (they are not extra)
        @test "x" in out
    end

    @testset "is-not? predicate - unknown property single-arg" begin
        p = Parser(tree_sitter_c_jll)
        source = "int x;"
        tree = parse(p, source)

        # Unknown property like "local" should not filter matches (compatibility)
        q = query```
        ((identifier) @node
         (#is-not? local))
        ```c

        out = []
        for capture in TreeSitter.each_capture(tree, q, source)
            literal = TreeSitter.slice(source, capture.node)
            push!(out, literal)
        end

        @test "x" in out
    end

    @testset "Anonymous nodes - literal matching" begin
        p = Parser(tree_sitter_c_jll)
        source = "int x;"
        tree = parse(p, source)

        # Match literal semicolon (anonymous node)
        q = query```
        (";" @semi)
        ```c

        found = false
        for capture in TreeSitter.each_capture(tree, q, source)
            # Verify semicolon is anonymous (not named)
            @test !TreeSitter.is_named(capture.node)
            @test TreeSitter.slice(source, capture.node) == ";"
            found = true
        end
        @test found  # Ensure we actually captured something
    end

    @testset "set! directive - metadata storage" begin
        p = Parser(tree_sitter_julia_jll)
        source = "f(x) = x + 1"
        tree = parse(p, source)

        # Query with set! directives
        q = query```
        ((identifier) @var
         (#set! "priority" "100")
         (#set! "scope" "local"))
        ```julia

        # Verify metadata was parsed at construction
        props = TreeSitter.property_settings(q, 1)
        @test length(props) == 2
        @test any(p -> p.key == "priority" && p.value == "100", props)
        @test any(p -> p.key == "scope" && p.value == "local", props)

        # Verify set! doesn't filter matches
        out = []
        for capture in TreeSitter.each_capture(tree, q, source)
            literal = TreeSitter.slice(source, capture.node)
            push!(out, literal)
        end
        @test length(out) > 0  # Should have matches

        # Test convenience accessor
        for m in eachmatch(q, tree)
            priority = TreeSitter.property(q, m, "priority")
            @test priority == "100"
            scope = TreeSitter.property(q, m, "scope")
            @test scope == "local"
        end
    end

    @testset "is? predicate - property assertions storage" begin
        p = Parser(tree_sitter_julia_jll)
        q = query```
        ((identifier) @var
         (#is? @var "named"))
        ```julia

        # Verify property assertions were parsed
        props = TreeSitter.property_predicates(q, 1)
        @test length(props) == 1
        @test props[1][1].key == "named"
        @test props[1][2] == true  # Positive assertion
    end

    @testset "any-match? predicate - quantified captures" begin
        p = Parser(tree_sitter_c_jll)

        # Source with multiple comments, one contains "TODO"
        source = """
        // NOTE: first
        // TODO: second
        // INFO: third
        """
        tree = parse(p, source)

        # Match comment groups where ANY comment contains "TODO"
        q = query```
        ((comment)+ @comments
         (#any-match? @comments "TODO"))
        ```c

        out = []
        for capture in TreeSitter.each_capture(tree, q, source)
            literal = TreeSitter.slice(source, capture.node)
            push!(out, literal)
        end

        # Should capture all three comments since one contains TODO
        @test length(out) == 3
        @test "// NOTE: first" in out
        @test "// TODO: second" in out
        @test "// INFO: third" in out
    end

    @testset "any-match? predicate - no match" begin
        p = Parser(tree_sitter_c_jll)

        # Source with multiple comments, none contains "TODO"
        source = """
        // NOTE: first
        // INFO: second
        """
        tree = parse(p, source)

        # Match comment groups where ANY comment contains "TODO"
        q = query```
        ((comment)+ @comments
         (#any-match? @comments "TODO"))
        ```c

        out = []
        for capture in TreeSitter.each_capture(tree, q, source)
            literal = TreeSitter.slice(source, capture.node)
            push!(out, literal)
        end

        # Should capture nothing since no comment contains TODO
        @test length(out) == 0
    end

    @testset "any-not-match? predicate" begin
        p = Parser(tree_sitter_c_jll)

        # Source where not all comments match a pattern
        source = """
        // TODO: first
        // INFO: second
        """
        tree = parse(p, source)

        # Match comment groups where ANY comment doesn't contain "TODO"
        q = query```
        ((comment)+ @comments
         (#any-not-match? @comments "TODO"))
        ```c

        out = []
        for capture in TreeSitter.each_capture(tree, q, source)
            literal = TreeSitter.slice(source, capture.node)
            push!(out, literal)
        end

        # Should match because second comment doesn't contain TODO
        @test length(out) == 2
    end

    @testset "any-eq? predicate" begin
        p = Parser(tree_sitter_c_jll)

        # Source with consecutive comments (actually adjacent)
        source = """
        // comment one
        // comment two
        // comment three
        """
        tree = parse(p, source)

        # Match comment groups where ANY comment equals a specific string
        q = query```
        ((comment)+ @comments
         (#any-eq? @comments "// comment two"))
        ```c

        out = []
        for capture in TreeSitter.each_capture(tree, q, source)
            literal = TreeSitter.slice(source, capture.node)
            push!(out, literal)
        end

        # Should capture all three comments since one equals the target
        @test length(out) == 3
        @test "// comment one" in out
        @test "// comment two" in out
        @test "// comment three" in out
    end

    @testset "any-not-eq? predicate" begin
        p = Parser(tree_sitter_c_jll)

        # Source with consecutive comments all with same content
        source = """
        // same
        // same
        // same
        """
        tree = parse(p, source)

        # Match comment groups where ANY comment is not "// same"
        q = query```
        ((comment)+ @comments
         (#any-not-eq? @comments "// same"))
        ```c

        out = []
        for capture in TreeSitter.each_capture(tree, q, source)
            literal = TreeSitter.slice(source, capture.node)
            push!(out, literal)
        end

        # Should not match since all comments equal "// same"
        @test length(out) == 0
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

@testset "Unknown property warnings" begin
    # Test 1: Unknown property triggers warning
    @test_logs (:warn, r"unimplemented properties.*nmed") begin
        Query(tree_sitter_c_jll, "((identifier) @node (#is? @node \"nmed\"))")
    end

    # Test 2: Builtin properties don't warn
    @test_logs begin
        Query(tree_sitter_c_jll, "((identifier) @node (#is? @node \"named\"))")
    end

    # Test 3: Known unimplemented "local" doesn't warn
    @test_logs begin
        Query(tree_sitter_c_jll, "((identifier) @node (#is-not? @node \"local\"))")
    end

    # Test 4: Multiple unknown properties shown sorted
    @test_logs (:warn, r"bar, foo") begin
        Query(
            tree_sitter_c_jll,
            """
((identifier) @x (#is? @x "foo"))
((identifier) @y (#is? @y "bar"))
""",
        )
    end

    # Test 5: Verify unknown_properties field is populated
    q = @test_logs (:warn,) Query(
        tree_sitter_c_jll,
        "((identifier) @x (#is? @x \"unknown\"))",
    )
    @test "unknown" in q.unknown_properties
    @test length(q.unknown_properties) == 1
end
