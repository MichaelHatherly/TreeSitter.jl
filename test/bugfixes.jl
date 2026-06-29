import tree_sitter_c_jll

# Regression tests for bugs found during the bug-exploration audit. Each testset encodes
# the correct (post-fix) behavior and fails on the unfixed code.

# Collect the text of every capture a query yields, evaluating all predicates.
function _bf_captures(jll, src, qsrc)
    p = Parser(jll)
    tree = parse(p, src)
    q = Query(jll, qsrc)
    return collect(
        TreeSitter.slice(src, c.node) for c in TreeSitter.each_capture(tree, q, src)
    )
end

@testset "Bug regressions" begin
    @testset "#1 node_string does not leak (resident memory stays bounded)" begin
        if Sys.islinux()
            rss() = Base.parse(Int, split(read("/proc/self/statm", String))[2]) * 4096
            p = Parser(tree_sitter_c_jll)
            root = TreeSitter.root(parse(p, "int x = 1 + 2 * 3;"))
            for _ = 1:1000
                TreeSitter.node_string(root)
            end
            GC.gc()
            before = rss()
            for _ = 1:500_000
                TreeSitter.node_string(root)
            end
            GC.gc()
            growth = rss() - before
            # The leak was ~256 bytes/call (~128 MB over 500k). Allow generous slack.
            @test growth < 30_000_000
        end
    end

    @testset "#2 captureless is?/is-not? predicate does not segfault" begin
        # Runs in a child process: on the unfixed code this segfaults (signal 11) at the
        # unguarded `unsafe_load(m.obj.captures, 1)`. A clean exit means it is fixed.
        script = """
        using TreeSitter
        import tree_sitter_c_jll
        p = Parser(tree_sitter_c_jll)
        tree = parse(p, "int x;")
        for qsrc in ("((identifier) (#is? named))", "((identifier) (#is-not? extra))")
            q = Query(tree_sitter_c_jll, qsrc)
            cur = TreeSitter.eachmatch(q, tree)
            m = TreeSitter.next_match(cur)
            TreeSitter.predicate(q, m, "int x;")
        end
        print("OK")
        """
        cmd = `$(Base.julia_cmd()) --project=$(Base.active_project()) -e $script`
        out = IOBuffer()
        ok = success(pipeline(cmd; stdout = out, stderr = devnull))
        @test ok
    end

    @testset "#3 is?/is-not? with explicit @capture honors the property" begin
        # `x` is an identifier: named, not missing, not extra.
        @test isempty(
            _bf_captures(
                tree_sitter_c_jll,
                "int x;",
                "((identifier) @v (#is? @v \"missing\"))",
            ),
        )
        @test isempty(
            _bf_captures(
                tree_sitter_c_jll,
                "int x;",
                "((identifier) @v (#is-not? @v \"named\"))",
            ),
        )
        # Positive assertions still keep the node.
        @test _bf_captures(
            tree_sitter_c_jll,
            "int x;",
            "((identifier) @v (#is? @v \"named\"))",
        ) == ["x"]
        @test _bf_captures(
            tree_sitter_c_jll,
            "int x;",
            "((identifier) @v (#is-not? @v \"missing\"))",
        ) == ["x"]
    end

    @testset "#4 set_byte_range! is not off-by-one (to==1 stays bounded)" begin
        p = Parser(tree_sitter_c_jll)
        src = "int x; int y;"
        tree = parse(p, src)
        q = Query(tree_sitter_c_jll, "(identifier) @id")
        captext(c) =
            [TreeSitter.slice(src, cap.node) for m in c for cap in TreeSitter.captures(m)]

        # to==1 must NOT be reinterpreted as "unbounded" (C end_byte 0 => UINT32_MAX).
        c1 = TreeSitter.QueryCursor()
        TreeSitter.set_byte_range!(c1, 1, 1)
        TreeSitter.exec(c1, q, tree)
        @test isempty(captext(c1))

        # A real sub-range still scopes to the first declaration.
        c2 = TreeSitter.QueryCursor()
        TreeSitter.set_byte_range!(c2, 1, 6)
        TreeSitter.exec(c2, q, tree)
        @test captext(c2) == ["x"]
    end

    @testset "#5 invalid regex in #match? warns and filters (no throw)" begin
        local result
        @test_logs (:warn,) match_mode = :any begin
            result = _bf_captures(
                tree_sitter_c_jll,
                "int x;",
                "((identifier) @v (#match? @v \"(\"))",
            )
        end
        @test isempty(result)
    end

    @testset "#8 retained matches keep valid captures after the cursor advances" begin
        p = Parser(tree_sitter_c_jll)
        src = "int aa; int bb; int cc;"
        tree = parse(p, src)
        q = Query(tree_sitter_c_jll, "(identifier) @v")
        ms = collect(eachmatch(q, tree))   # advance the cursor fully, THEN read captures
        texts = [TreeSitter.slice(src, first(TreeSitter.captures(m)).node) for m in ms]
        @test texts == ["aa", "bb", "cc"]
    end

    @testset "#6/#7 query-file selection prefers canonical over editor subdir; knows nvim" begin
        API = TreeSitter.API
        # #7: the common `nvim` directory name must be recognized (not the fallback rank).
        @test API.editor_rank(joinpath("x", "queries", "nvim")) !=
              length(API.EDITOR_PREFERENCE) + 1
        # #6: a canonical top-level queries dir (depth 0) outranks an editor subdir (depth 1).
        base = joinpath("repo", "queries")
        @test API._query_dir_rank(base, base) <
              API._query_dir_rank(joinpath(base, "neovim"), base)
    end
end
