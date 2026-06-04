import tree_sitter_c_jll, tree_sitter_php_jll

@testset "Parser variant errors" begin
    # A JLL exposes a fixed set of parser variants; an unknown one is an error.
    @test_throws ErrorException Language(tree_sitter_php_jll, :nonexistent_variant)
end

@testset "Grammar introspection" begin
    p = Parser(tree_sitter_c_jll)

    @test TreeSitter.symbol_count(p) > 0
    id_sym = TreeSitter.symbol_for_name(p, "identifier", true)
    @test id_sym > 0
    @test TreeSitter.symbol_name(p, id_sym) == "identifier"
    @test TreeSitter.symbol_type(p, id_sym) == TreeSitter.API.TSSymbolTypeRegular

    @test TreeSitter.field_count(p) > 0
    fid = TreeSitter.field_id_for_name(p, "type")
    @test fid > 0
    @test TreeSitter.field_name_for_id(p, fid) == "type"

    tree = parse(p, "int main(void){return 0;}")
    # Introspection resolves the grammar from a Language, Tree, or Parser.
    @test TreeSitter.symbol_count(tree) == TreeSitter.symbol_count(p)
    @test TreeSitter.symbol_count(p.language) == TreeSitter.symbol_count(p)

    func_def = TreeSitter.child(TreeSitter.root(tree), 1)
    type_node = TreeSitter.child_by_field_id(func_def, fid)
    @test TreeSitter.node_type(type_node) == "primitive_type"
    @test_throws ArgumentError TreeSitter.child_by_field_id(func_def, 9999)
end

@testset "Query scoping" begin
    p = Parser(tree_sitter_c_jll)
    src = "int x; int y;"
    tree = parse(p, src)
    q = Query(tree_sitter_c_jll, "(identifier) @id")

    @test TreeSitter.start_byte_for_pattern(q, 1) == 1

    capture_text(cursor) =
        [TreeSitter.slice(src, c.node) for m in cursor for c in TreeSitter.captures(m)]

    # Byte range restricts matches to the first declaration "int x;".
    by_byte = TreeSitter.QueryCursor()
    TreeSitter.set_byte_range!(by_byte, 1, 7)
    TreeSitter.exec(by_byte, q, tree)
    @test capture_text(by_byte) == ["x"]

    # Point range (0-based TSPoint) restricts the same way.
    by_point = TreeSitter.QueryCursor()
    TreeSitter.set_point_range!(
        by_point,
        TreeSitter.API.TSPoint(0, 0),
        TreeSitter.API.TSPoint(0, 6),
    )
    TreeSitter.exec(by_point, q, tree)
    @test capture_text(by_point) == ["x"]

    # next_capture walks captures in document order.
    walk = TreeSitter.QueryCursor()
    TreeSitter.exec(walk, q, tree)
    order = String[]
    while (nc = TreeSitter.next_capture(walk)) !== nothing
        match, idx = nc
        capture = first(Iterators.drop(TreeSitter.captures(match), idx - 1))
        push!(order, TreeSitter.slice(src, capture.node))
    end
    @test order == ["x", "y"]

    # remove_match! returns the cursor; exercises the removal binding.
    removable = TreeSitter.QueryCursor()
    TreeSitter.exec(removable, q, tree)
    @test TreeSitter.remove_match!(removable, 0) === removable
end

@testset "Disabling patterns and captures" begin
    p = Parser(tree_sitter_c_jll)
    src = "int x; int y;"
    tree = parse(p, src)

    # Disabling the only capture drops it from results.
    q_cap = Query(tree_sitter_c_jll, "(identifier) @id")
    TreeSitter.disable_capture!(q_cap, "id")
    cursor = TreeSitter.QueryCursor()
    TreeSitter.exec(cursor, q_cap, tree)
    @test isempty([c for m in cursor for c in TreeSitter.captures(m)])

    # Disabling a pattern removes its matches, leaving the other pattern.
    q_pat = Query(tree_sitter_c_jll, "(identifier) @a\n(primitive_type) @b")
    TreeSitter.disable_pattern!(q_pat, 1)
    cursor2 = TreeSitter.QueryCursor()
    TreeSitter.exec(cursor2, q_pat, tree)
    names =
        [TreeSitter.capture_name(q_pat, c) for m in cursor2 for c in TreeSitter.captures(m)]
    @test all(==("b"), names)
    @test !isempty(names)
end
