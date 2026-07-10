import tree_sitter_html_jll, tree_sitter_javascript_jll, tree_sitter_php_jll

# First named node of a given type, or nothing.
function find_node(tree, ty)
    result = nothing
    traverse(tree) do n, enter
        if enter && result === nothing && TreeSitter.node_type(n) == ty
            result = n
        end
    end
    return result
end

range_text(src, r) = TreeSitter.slice(src, (Int(r.start_byte) + 1, Int(r.end_byte)))

@testset "Language injection" begin
    @testset "ts_range conversion" begin
        p = Parser(:javascript)
        tree = parse(p, "f(x)")
        n = TreeSitter.root(tree)
        from, to = TreeSitter.byte_range(n)
        r = TreeSitter.ts_range(n)
        @test r.start_byte == from - 1
        @test r.end_byte == to
        @test r.start_point == TreeSitter.start_point(n)
        @test r.end_point == TreeSitter.end_point(n)
    end

    @testset "injection_sites: HTML static" begin
        source = "<script>let x=1;</script><style>a{}</style>"
        p = Parser(:html)
        tree = parse(p, source)
        sites = TreeSitter.injection_sites(p, tree, source)
        @test [s.language for s in sites] == ["javascript", "css"]
        @test all(s -> !s.combined, sites)
        @test TreeSitter.slice(source, sites[1].content_nodes[1]) == "let x=1;"
        @test TreeSitter.slice(source, sites[2].content_nodes[1]) == "a{}"
    end

    @testset "injection_sites: PHP heredoc dynamic language" begin
        # The language name comes from the `heredoc_end` capture's text, not a #set!.
        source = "<?php\n\$x = <<<HTML\n<p>hi</p>\nHTML;\n"
        p = Parser(tree_sitter_php_jll)
        tree = parse(p, source)
        sites = TreeSitter.injection_sites(p, tree, source)
        @test "HTML" in [s.language for s in sites]
    end

    @testset "injection_sites: #offset! trims range" begin
        p = Parser(:javascript)
        source = "x = `abc`"
        tree = parse(p, source)
        q = Query(
            :javascript,
            """
((template_string) @injection.content
 (#set! injection.language "javascript")
 (#set! injection.include-children)
 (#offset! @injection.content 0 1 0 -1))
""",
        )
        sites = TreeSitter.injection_sites(q, tree, source)
        @test length(sites) == 1
        @test range_text(source, sites[1].ranges[1]) == "abc"
    end

    @testset "#offset! multi-line falls back" begin
        p = Parser(:javascript)
        tree = parse(p, "f(x)")
        n = TreeSitter.root(tree)
        local r
        @test_logs (:warn, r"multi-line") begin
            r = TreeSitter.content_ranges(n, true, (1, 0, 0, 0))
        end
        @test r == [TreeSitter.ts_range(n)]
    end

    @testset "site without a language is skipped" begin
        p = Parser(:javascript)
        source = "f(x)"
        tree = parse(p, source)
        q = Query(:javascript, "((identifier) @injection.content)")
        @test isempty(TreeSitter.injection_sites(q, tree, source))
    end

    @testset "combined injection merges ranges" begin
        p = Parser(:javascript)
        source = "js`a`; js`b`"
        tree = parse(p, source)
        combined =
            only(filter(s -> s.combined, TreeSitter.injection_sites(p, tree, source)))
        @test length(combined.ranges) == 2
    end

    @testset "show methods" begin
        source = "<style>a{}</style><script>f()</script>"
        tree = parse(Parser(:html), source)
        @test occursin("Tree(html", repr(tree))
        @test occursin("UnresolvedInjection", repr(only(tree.unresolved)))
        site = first(TreeSitter.injection_sites(Parser(:html), tree, source))
        @test occursin("InjectionSite", repr(site))
    end

    @testset "include-children hole punching" begin
        p = Parser(:javascript)
        source = "f(a, b)"
        tree = parse(p, source)
        args = find_node(tree, "arguments")
        @test args !== nothing
        incl = TreeSitter.content_ranges(args, true)
        excl = TreeSitter.content_ranges(args, false)
        @test length(incl) == 1
        @test incl[1].start_byte == TreeSitter.byte_range(args)[1] - 1
        incl_text = join(range_text(source, r) for r in incl)
        excl_text = join(range_text(source, r) for r in excl)
        @test occursin("a", incl_text) && occursin("b", incl_text)
        @test !occursin("a", excl_text) && !occursin("b", excl_text)
    end

    @testset "parse: HTML into JavaScript" begin
        source = "<p>hi</p><script>f(x)</script>"
        tree = parse(Parser(:html), source)
        @test tree.language.name == :html
        @test length(tree.children) == 1
        js = tree.children[1]
        @test js.language.name == :javascript
        @test TreeSitter.slice(js) == "f(x)"
        # Sub-tree offsets live in the original document's coordinate space.
        q = Query(:javascript, "(call_expression) @c")
        calls = [
            TreeSitter.slice(tree.source, c.node) for
            c in TreeSitter.each_capture(js, q, tree.source)
        ]
        @test calls == ["f(x)"]
    end

    @testset "parse: grammar with no injections is a single layer" begin
        tree = parse(Parser(:javascript), "f(x)")
        @test isempty(tree.children)
        @test isempty(tree.unresolved)
        @test length(TreeSitter.layers(tree)) == 1
    end

    @testset "parse: unavailable language recorded" begin
        tree = parse(Parser(:html), "<style>a{}</style>")
        @test isempty(tree.children)
        css = only(filter(u -> u.language == "css", tree.unresolved))
        @test css.reason == :unavailable
    end

    @testset "parse: depth limit recorded" begin
        tree = parse(Parser(:html), "<script>f(x)</script>"; max_depth = 0)
        @test isempty(tree.children)
        js = only(filter(u -> u.language == "javascript", tree.unresolved))
        @test js.reason == :depth_limit
    end

    @testset "injection tree accessors" begin
        source = "<p>hi</p><script>f(x)</script>"
        tree = parse(Parser(:html), source)
        @test length(TreeSitter.layers(tree)) == 2
        inside = first(findfirst("f(x)", source))
        @test TreeSitter.layer_at(tree, inside).language.name == :javascript
        @test TreeSitter.layer_at(tree, 2).language.name == :html
    end

    @testset "parse: dynamic tagged template" begin
        # `js` tags the template as JavaScript (dynamic @injection.language), with
        # injection.combined and injection.include-children set.
        source = "js`f(x)`"
        tree = parse(Parser(:javascript), source)
        child = only(tree.children)
        @test child.language.name == :javascript
        @test child.combined
        @test TreeSitter.slice(child) == "f(x)"
        q = Query(:javascript, "(call_expression) @c")
        calls = [
            TreeSitter.slice(tree.source, c.node) for
            c in TreeSitter.each_capture(child, q, tree.source)
        ]
        @test "f(x)" in calls
    end

    @testset "parse: pinned languages disable dynamic loading" begin
        source = "<style>a{}</style><script>f(x)</script>"
        # Only javascript is offered, so css cannot resolve even though its alias is known.
        tree = parse(Parser(:html; languages = [tree_sitter_javascript_jll]), source)
        @test [c.language.name for c in tree.children] == [:javascript]
        css = only(filter(u -> u.language == "css", tree.unresolved))
        @test css.reason == :unavailable
    end

    @testset "parse: incremental reparse keeps injection layers" begin
        p = Parser(:html)
        old = parse(p, "<script>f(x)</script>")
        tree = parse(p, "<script>g(y)</script>", old)
        js = only(tree.children)
        @test js.language.name == :javascript
        @test TreeSitter.slice(js) == "g(y)"
    end
end
