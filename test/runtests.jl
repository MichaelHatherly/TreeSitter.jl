using TreeSitter, Test

@testset "TreeSitter" begin
    include("parsing.jl")
    include("traversal.jl")
    include("nodes.jl")
    include("queries.jl")
    include("abstracttrees.jl")
    include("local_grammar.jl")
end
