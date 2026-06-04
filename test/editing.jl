import tree_sitter_c_jll

@testset "Incremental editing" begin
    p = Parser(tree_sitter_c_jll)
    src1 = "int x = 1;"
    src2 = "int x = 1+1;"
    tree = parse(p, src1)

    @testset "tree copy" begin
        clone = copy(tree)
        @test clone !== tree
        @test TreeSitter.node_type(TreeSitter.root(clone)) == "translation_unit"
    end

    # Insert "+1" after the literal "1", turning it into a binary expression. The edit
    # starts at 1-based byte 10 (0-based column 9) and adds two characters.
    e = TreeSitter.input_edit(
        10,
        10,
        12,
        TreeSitter.API.TSPoint(0, 9),
        TreeSitter.API.TSPoint(0, 9),
        TreeSitter.API.TSPoint(0, 11),
    )
    TreeSitter.edit!(tree, e)
    new_tree = parse(p, src2, tree)

    @testset "reparse reflects the structural change" begin
        node = TreeSitter.descendant_for_byte_range(TreeSitter.root(new_tree), 9, 11)
        @test TreeSitter.node_type(node) == "binary_expression"
        @test TreeSitter.slice(src2, node) == "1+1"
    end

    @testset "changed_ranges reports the edited span" begin
        ranges = TreeSitter.changed_ranges(tree, new_tree)
        @test length(ranges) == 1
        # The new binary expression spans 0-based bytes 8..11.
        r = only(ranges)
        @test r.start_byte <= 8
        @test r.end_byte >= 11
    end

    @testset "node edit returns the adjusted node" begin
        fresh = parse(p, src1)
        adjusted = TreeSitter.edit!(TreeSitter.root(fresh), e)
        @test TreeSitter.node_type(adjusted) == "translation_unit"
    end
end
