using TreeSitter, Test

@testset "TreeSitter" begin
    include("parsing.jl")
    include("traversal.jl")
    include("nodes.jl")
    include("queries.jl")
    include("predicates.jl")
    include("introspection.jl")
    include("cursor.jl")
    include("editing.jl")
    include("parser_control.jl")
    include("abstracttrees.jl")
    include("local_grammar.jl")
    include("bugfixes.jl")
end
