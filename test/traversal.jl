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
