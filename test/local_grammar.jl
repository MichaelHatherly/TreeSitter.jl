using TreeSitter, Test
using TreeSitter: API
import tree_sitter_json_jll

@testset "Local Grammar" begin
    @testset "find_shared_lib" begin
        ext = Sys.iswindows() ? ".dll" : Sys.isapple() ? ".dylib" : ".so"

        mktempdir() do dir
            # Test primary pattern: name.ext (tree-sitter build output)
            touch(joinpath(dir, "foo$ext"))
            @test API.find_shared_lib(dir, :foo) == joinpath(dir, "foo$ext")
        end

        mktempdir() do dir
            # Test fallback: libtree-sitter-name.ext
            touch(joinpath(dir, "libtree-sitter-bar$ext"))
            @test API.find_shared_lib(dir, :bar) == joinpath(dir, "libtree-sitter-bar$ext")
        end

        mktempdir() do dir
            # Test priority: name.ext takes precedence over libtree-sitter-name.ext
            touch(joinpath(dir, "baz$ext"))
            touch(joinpath(dir, "libtree-sitter-baz$ext"))
            @test API.find_shared_lib(dir, :baz) == joinpath(dir, "baz$ext")
        end

        mktempdir() do dir
            # Test not found
            @test API.find_shared_lib(dir, :nonexistent) === nothing
        end
    end

    @testset "load_local_queries" begin
        mktempdir() do dir
            # Setup: queries/ with .scm files
            mkdir(joinpath(dir, "queries"))
            write(joinpath(dir, "queries", "highlights.scm"), "(identifier) @var")
            write(joinpath(dir, "queries", "tags.scm"), "(function) @func")

            grammar = Dict("name" => "test", "path" => ".")
            queries = API.load_local_queries(dir, grammar)

            @test queries["highlights"] == "(identifier) @var"
            @test queries["tags"] == "(function) @func"
        end

        mktempdir() do dir
            # Test subpath queries take precedence
            mkdir(joinpath(dir, "queries"))
            mkdir(joinpath(dir, "src"))
            mkdir(joinpath(dir, "src", "queries"))
            write(joinpath(dir, "queries", "highlights.scm"), "root")
            write(joinpath(dir, "src", "queries", "highlights.scm"), "subpath")

            grammar = Dict("name" => "test", "path" => "src")
            queries = API.load_local_queries(dir, grammar)

            # root-level queries/ is checked first
            @test queries["highlights"] == "root"
        end

        mktempdir() do dir
            # Test no queries dir
            grammar = Dict("name" => "test", "path" => ".")
            queries = API.load_local_queries(dir, grammar)
            @test isempty(queries)
        end
    end

    @testset "error handling" begin
        mktempdir() do dir
            # Missing tree-sitter.json
            @test_throws ErrorException Language(dir)
        end

        mktempdir() do dir
            # Invalid variant
            write(
                joinpath(dir, "tree-sitter.json"),
                """{"grammars": [{"name": "foo", "path": "."}]}""",
            )
            @test_throws ErrorException Language(dir, :nonexistent)
        end

        mktempdir() do dir
            # Valid JSON but missing shared library
            write(
                joinpath(dir, "tree-sitter.json"),
                """{"grammars": [{"name": "foo", "path": "."}]}""",
            )
            @test_throws ErrorException Language(dir)
        end
    end

    @testset "integration with JLL fixture" begin
        # Use existing JLL as fixture to test full path without building
        mktempdir() do dir
            ext = Sys.iswindows() ? ".dll" : Sys.isapple() ? ".dylib" : ".so"

            # Create tree-sitter.json
            write(
                joinpath(dir, "tree-sitter.json"),
                """{"grammars": [{"name": "json", "path": "."}]}""",
            )

            # Symlink JLL library into temp dir
            jll_lib = tree_sitter_json_jll.libtreesitter_json_path
            symlink(jll_lib, joinpath(dir, "json$ext"))

            # Create queries dir with test query
            mkdir(joinpath(dir, "queries"))
            write(joinpath(dir, "queries", "test.scm"), "(string) @str")

            # Test Language constructor
            lang = Language(dir)
            @test lang.name == :json
            @test haskey(lang.queries, "test")
            @test lang.queries["test"] == "(string) @str"

            # Test Parser constructor
            p = Parser(dir)
            @test p.language.name == :json

            # Test parsing works
            t = parse(p, """{"a": 1}""")
            @test TreeSitter.node_type(TreeSitter.root(t)) == "document"

            # Test Query constructor
            q = Query(dir, "(string) @s")
            @test q.language.name == :json
        end
    end

    @testset "multi-grammar repo" begin
        mktempdir() do dir
            ext = Sys.iswindows() ? ".dll" : Sys.isapple() ? ".dylib" : ".so"

            # Create tree-sitter.json with multiple grammars
            write(
                joinpath(dir, "tree-sitter.json"),
                """{
    "grammars": [
        {"name": "json", "path": "."},
        {"name": "jsonc", "path": "jsonc"}
    ]
}""",
            )

            # Setup main grammar
            jll_lib = tree_sitter_json_jll.libtreesitter_json_path
            symlink(jll_lib, joinpath(dir, "json$ext"))

            # Default selects first grammar
            lang = Language(dir)
            @test lang.name == :json

            # Explicit variant selection
            lang2 = Language(dir, :json)
            @test lang2.name == :json
        end
    end
end
