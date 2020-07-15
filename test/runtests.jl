using TreeSitter, Test

@testset "TreeSitter" begin
    @testset "Load & Parse" begin
        for lang in TreeSitter.API.LANGUAGES
            @testset "$lang" begin
                p = Parser(lang)
                tree = parse(p, "")
                @test !isempty(string(tree))
            end
        end
    end
end
