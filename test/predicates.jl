import tree_sitter_c_jll, tree_sitter_julia_jll

# Collect the text of every capture a query yields, evaluating all predicates.
function predicate_captures(jll, src, qsrc)
    p = Parser(jll)
    tree = parse(p, src)
    q = Query(jll, qsrc)
    return collect(
        TreeSitter.slice(src, c.node) for c in TreeSitter.each_capture(tree, q, src)
    )
end

@testset "Predicate edge cases" begin
    # tree-sitter 0.25 does not validate predicate arity at query construction, so
    # malformed predicates reach the match-time warning branches in predicate().
    @testset "wrong arity warns and filters: $name" for (name, qsrc, rx) in [
        ("eq?", "((identifier) @x (#eq? @x))", r"'eq\?'"),
        ("not-eq?", "((identifier) @x (#not-eq? @x))", r"'not-eq\?'"),
        ("any-of?", "((identifier) @x (#any-of? @x))", r"'any-of\?'"),
        ("has-ancestor?", "((identifier) @x (#has-ancestor? @x))", r"'has-ancestor\?'"),
        ("match?", "((identifier) @x (#match? @x))", r"'match\?'"),
        ("not-match?", "((identifier) @x (#not-match? @x))", r"'not-match\?'"),
        ("any-eq?", "((identifier) @x (#any-eq? @x))", r"'any-eq\?'"),
        ("any-not-eq?", "((identifier) @x (#any-not-eq? @x))", r"'any-not-eq\?'"),
        ("any-match?", "((identifier) @x (#any-match? @x))", r"'any-match\?'"),
        ("any-not-match?", "((identifier) @x (#any-not-match? @x))", r"'any-not-match\?'"),
    ]
        result = @test_logs (:warn, rx) match_mode = :any predicate_captures(
            tree_sitter_c_jll,
            "int x;",
            qsrc,
        )
        @test isempty(result)
    end

    @testset "has-ancestor? without a captured node warns" begin
        result =
            @test_logs (:warn, r"requires access to node structure") match_mode = :any predicate_captures(
                tree_sitter_c_jll,
                "int x;",
                "((identifier) @x (#has-ancestor? \"a\" \"b\"))",
            )
        @test isempty(result)
    end

    @testset "unknown predicate warns and filters" begin
        result =
            @test_logs (:warn, r"unknown predicate function 'bogus\?'") match_mode = :any predicate_captures(
                tree_sitter_c_jll,
                "int x;",
                "((identifier) @x (#bogus? @x))",
            )
        @test isempty(result)
    end

    @testset "is? built-in properties" begin
        # `missing`/`extra` are false for a plain identifier, so the pattern is filtered out.
        @test isempty(
            predicate_captures(
                tree_sitter_c_jll,
                "int x;",
                "((identifier) @x (#is? missing))",
            ),
        )
        @test isempty(
            predicate_captures(
                tree_sitter_c_jll,
                "int x;",
                "((identifier) @x (#is? extra))",
            ),
        )
    end

    @testset "is-not? built-in properties" begin
        # An identifier is named, so `(#is-not? named)` filters it out.
        @test isempty(
            predicate_captures(
                tree_sitter_c_jll,
                "int x;",
                "((identifier) @x (#is-not? named))",
            ),
        )
        # An identifier is not missing, so `(#is-not? missing)` keeps it.
        @test predicate_captures(
            tree_sitter_c_jll,
            "int x;",
            "((identifier) @x (#is-not? missing))",
        ) == ["x"]
    end
end

@testset "Predicate construction errors" begin
    @test_throws ErrorException Query(tree_sitter_c_jll, "((identifier) @v (#set!))")
    @test_throws ErrorException Query(tree_sitter_c_jll, "((identifier) @v (#set! @v))")
    @test_throws ErrorException Query(tree_sitter_c_jll, "((identifier) @v (#is?))")
    @test_throws ErrorException Query(tree_sitter_c_jll, "((identifier) @v (#is? @v))")
end

@testset "Capture-level set! property" begin
    p = Parser(tree_sitter_julia_jll)
    src = "f(x) = x + 1"
    tree = parse(p, src)
    q = Query(
        tree_sitter_julia_jll,
        """
        ((identifier) @v
         (#set! @v "scope" "local")
         (#set! "kind" "id"))
        """,
    )

    m = first(eachmatch(q, tree))
    c = first(TreeSitter.captures(m))
    @test TreeSitter.property(q, c, "scope") == "local"
    # Capture lookup falls back to a pattern-level property.
    @test TreeSitter.property(q, c, "kind") == "id"
    # Unset key falls through capture-specific and pattern-level lookups.
    @test TreeSitter.property(q, c, "absent") === nothing
    # Match-level lookup of a capture-only property returns nothing.
    @test TreeSitter.property(q, m, "scope") === nothing
end

@testset "Query and node accessors" begin
    p = Parser(tree_sitter_julia_jll)
    tree = parse(p, "f(x) = x")
    q = Query(tree_sitter_julia_jll, "(identifier) @id (integer_literal) @num")
    @test TreeSitter.capture_count(q) == 2
    @test TreeSitter.string_count(q) isa Integer
    @test repr(q) == "Query(Language(:julia))"
    @test repr(TreeSitter.QueryCursor()) == "QueryCursor()"

    leaf = TreeSitter.child(TreeSitter.child(TreeSitter.root(tree), 1), 1)
    @test TreeSitter.is_leaf(leaf) isa Bool
end

@testset "tokens" begin
    p = Parser(tree_sitter_julia_jll)
    q = Query(tree_sitter_julia_jll, "(identifier) @id")
    toks = TreeSitter.tokens(p, q, "f(x) = x")
    @test ("f", "id") in toks
    @test ("x", "id") in toks
end

@testset "Language symbol constructor and errors" begin
    q = Query(:julia, "(identifier) @x")
    @test q.language.name == :julia
    @test_throws ErrorException Language(:this_is_not_a_real_language)
end

@testset "show methods" begin
    p = Parser(tree_sitter_julia_jll)
    tree = parse(p, "f(x) = x")
    @test repr(p.language) == "Language(:julia)"
    @test occursin("Parser(Language(:julia))", repr(p))
    @test occursin("source_file", repr(tree))
    root_node = TreeSitter.root(tree)
    @test TreeSitter.node_string(root_node) isa AbstractString
    @test TreeSitter.node_symbol(root_node) isa Integer
end

# Structural comparison and the ancestor family. Each answers a question the text
# predicates cannot: whether two subtrees are the same code however they are spelled,
# and what a node is enclosed by.

@testset "structure-eq?" begin
    q = "((if_statement . (_) @a (elseif_clause . (_) @b)) (#structure-eq? @a @b))"

    # The same condition respelled. Whitespace lives between tokens rather than in the
    # tree, so the two conditions are one shape and `eq?` on their text would disagree.
    same = "if x > 0\n    a()\nelseif x>0\n    b()\nend\n"
    @test predicate_captures(tree_sitter_julia_jll, same, q) == ["x > 0", "x>0"]

    # A renamed operand is a different condition, which is what separates this from a
    # shape-only hash: leaf text is part of the comparison.
    renamed = "if x > 0\n    a()\nelseif y > 0\n    b()\nend\n"
    @test isempty(predicate_captures(tree_sitter_julia_jll, renamed, q))

    # A different operator differs in an anonymous token, so anonymous children count too.
    operator = "if x > 0\n    a()\nelseif x >= 0\n    b()\nend\n"
    @test isempty(predicate_captures(tree_sitter_julia_jll, operator, q))
end

@testset "not-has-ancestor?" begin
    src = "int g;\nint f(void) { int x; return x; }\n"
    q = "((identifier) @x (#not-has-ancestor? @x \"function_definition\"))"
    @test predicate_captures(tree_sitter_c_jll, src, q) == ["g"]
end

@testset "nearest-ancestor?" begin
    # Both returns sit under a `function_definition`; only the first sits under a
    # `do_clause` first. `has-ancestor?` walks to the root and cannot tell them apart.
    src = """
    function f(xs)
        map(xs) do x
            return x
        end
        return 1
    end
    """
    nearest_do = "((return_statement) @r (#nearest-ancestor? @r \"do_clause\" \"function_definition\"))"
    nearest_fun = "((return_statement) @r (#nearest-ancestor? @r \"function_definition\" \"do_clause\"))"
    @test predicate_captures(tree_sitter_julia_jll, src, nearest_do) == ["return x"]
    @test predicate_captures(tree_sitter_julia_jll, src, nearest_fun) == ["return 1"]
end

@testset "ancestor-match?" begin
    src = """
    function unsafe_get(p)
        load(p)
    end
    function get(p)
        load(p)
    end
    """
    q = "((block (call_expression) @c) (#ancestor-match? @c \"function_definition\" \"^function\\\\s+unsafe_\"))"
    @test predicate_captures(tree_sitter_julia_jll, src, q) == ["load(p)"]
end

@testset "structural and ancestor predicates: malformed calls warn and filter" begin
    @testset "wrong arity: $name" for (name, qsrc, rx) in [
        ("structure-eq?", "((identifier) @x (#structure-eq? @x))", r"'structure-eq\?'"),
        (
            "not-has-ancestor?",
            "((identifier) @x (#not-has-ancestor? @x))",
            r"'not-has-ancestor\?'",
        ),
        (
            "nearest-ancestor?",
            "((identifier) @x (#nearest-ancestor? @x))",
            r"'nearest-ancestor\?'",
        ),
        (
            "ancestor-match?",
            "((identifier) @x (#ancestor-match? @x \"a\"))",
            r"'ancestor-match\?'",
        ),
    ]
        result = @test_logs (:warn, rx) match_mode = :any predicate_captures(
            tree_sitter_c_jll,
            "int x;",
            qsrc,
        )
        @test isempty(result)
    end

    # `structure-eq?` compares nodes, so two string literals have nothing to compare.
    @testset "structure-eq? without two captured nodes warns" begin
        result =
            @test_logs (:warn, r"requires two captured nodes") match_mode = :any predicate_captures(
                tree_sitter_c_jll,
                "int x;",
                "((identifier) @x (#structure-eq? \"a\" \"b\"))",
            )
        @test isempty(result)
    end

    @testset "ancestor predicates without a captured node warn: $name" for (name, qsrc) in [
        ("not-has-ancestor?", "((identifier) @x (#not-has-ancestor? \"a\" \"b\"))"),
        ("nearest-ancestor?", "((identifier) @x (#nearest-ancestor? \"a\" \"b\" \"c\"))"),
        ("ancestor-match?", "((identifier) @x (#ancestor-match? \"a\" \"b\" \"c\"))"),
    ]
        result =
            @test_logs (:warn, r"requires access to node structure") match_mode = :any predicate_captures(
                tree_sitter_c_jll,
                "int x;",
                qsrc,
            )
        @test isempty(result)
    end

    @testset "ancestor-match? with an invalid regex warns" begin
        result =
            @test_logs (:warn, r"invalid regex in predicate") match_mode = :any predicate_captures(
                tree_sitter_c_jll,
                "int x;",
                "((identifier) @x (#ancestor-match? @x \"translation_unit\" \"[\"))",
            )
        @test isempty(result)
    end
end
