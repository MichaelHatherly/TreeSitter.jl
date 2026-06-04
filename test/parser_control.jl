import tree_sitter_c_jll

@testset "Parser control" begin
    p = Parser(tree_sitter_c_jll)

    @testset "reset" begin
        @test TreeSitter.reset!(p) === p
    end

    @testset "UTF-16 parsing" begin
        tree = parse(p, "int x = 1;"; encoding = :utf16)
        @test TreeSitter.node_type(TreeSitter.root(tree)) == "translation_unit"
        @test !TreeSitter.has_error(TreeSitter.root(tree))
        @test_throws ArgumentError parse(p, "x"; encoding = :latin1)
    end

    @testset "included ranges" begin
        # A fresh parser reports one range covering the whole document.
        @test length(TreeSitter.included_ranges(p)) == 1

        r = TreeSitter.API.TSRange(
            TreeSitter.API.TSPoint(0, 0),
            TreeSitter.API.TSPoint(0, 6),
            0,
            6,
        )
        TreeSitter.set_included_ranges!(p, [r])
        got = TreeSitter.included_ranges(p)
        @test length(got) == 1
        @test got[1].end_byte == 6

        # An empty range list restores the whole document.
        TreeSitter.set_included_ranges!(p, TreeSitter.API.TSRange[])
        @test length(TreeSitter.included_ranges(p)) == 1
    end

    @testset "logger" begin
        logs = Tuple{Symbol,String}[]
        TreeSitter.set_logger!(p, (kind, msg) -> push!(logs, (kind, msg)))
        parse(p, "int y;")
        @test !isempty(logs)
        @test all(t -> t[1] in (:parse, :lex), logs)
        @test TreeSitter.logger(p).log != C_NULL
    end

    @testset "dot graphs" begin
        @testset "io" begin
            mktemp() do path, io
                TreeSitter.print_dot_graphs!(p, io)
                parse(p, "int z;")
                TreeSitter.print_dot_graphs!(p, nothing)
                @test filesize(path) > 0
            end
        end
        @testset "path" begin
            mktemp() do path, io
                close(io)
                TreeSitter.print_dot_graphs!(p, path)
                parse(p, "int z;")
                TreeSitter.print_dot_graphs!(p, nothing)
                @test filesize(path) > 0
            end
        end
    end
end
