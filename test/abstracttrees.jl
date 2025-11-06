import AbstractTrees

@testset "AbstractTrees" begin
    parser = Parser(:julia)
    tree = parse(parser, "f(x) = x + 1")
    node = TreeSitter.root(tree)

    @testset "children interface" begin
        # Test that AbstractTrees.children works
        kids = collect(AbstractTrees.children(node))
        @test length(kids) > 0
        @test all(k -> k isa Node, kids)

        # Should match TreeSitter.children
        ts_kids = collect(TreeSitter.children(node))
        @test kids == ts_kids
    end

    @testset "print_tree" begin
        # Test that print_tree produces output without errors
        io = IOBuffer()
        AbstractTrees.print_tree(io, node)
        output = String(take!(io))

        @test !isempty(output)
        @test contains(output, "source_file")
        @test contains(output, "assignment")
    end
end
