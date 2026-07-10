# TreeSitter

*Julia bindings for [tree-sitter](https://github.com/tree-sitter/tree-sitter) &mdash;
"An incremental parsing system for programming tools."*

[![CI](https://github.com/MichaelHatherly/TreeSitter.jl/actions/workflows/CI.yml/badge.svg?branch=master)](https://github.com/MichaelHatherly/TreeSitter.jl/actions/workflows/CI.yml)
[![Codecov](https://codecov.io/gh/MichaelHatherly/TreeSitter.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/MichaelHatherly/TreeSitter.jl)

## Installation

This package is registered in the Julia General registry and can be installed using:

```
pkg> add TreeSitter
```

Additionally, you need to install the language parser(s) you want to use:

```
pkg> add tree_sitter_julia_jll tree_sitter_c_jll
```

## Migration from v0.1

**Breaking change in v0.2:** Language parsers are no longer bundled with TreeSitter.jl. You must now:

1. Install the specific language JLL packages you need
2. Import them explicitly in your code
3. Pass the JLL module to the parser constructor

### Old API (deprecated)
```julia
using TreeSitter
parser = Parser(:julia)  # Deprecated - will show warning
```

### New API (recommended)
```julia
using TreeSitter, tree_sitter_julia_jll
parser = Parser(tree_sitter_julia_jll)
```

The symbol-based API still works but is deprecated and will be removed in a future version.

## Usage

```
julia> using TreeSitter, tree_sitter_c_jll

julia> c = Parser(tree_sitter_c_jll)
Parser(Language(:c))

julia> ast = parse(c, "int x;")
(translation_unit (declaration type: (primitive_type) declarator: (identifier)))

julia> using tree_sitter_json_jll

julia> json = Parser(tree_sitter_json_jll)
Parser(Language(:json))

julia> ast = parse(json, "{\"key\": [1, 2]}")
(document (object (pair key: (string (string_content)) value: (array (number) (number)))))

julia> traverse(ast) do node, enter
           if enter
               @show node
           end
       end
node = (document (object (pair key: (string (string_content)) value: (array (number) (number)))))
node = (object (pair key: (string (string_content)) value: (array (number) (number))))
node = ("{")
node = (pair key: (string (string_content)) value: (array (number) (number)))
node = (string (string_content))
node = ("\"")
node = (string_content)
node = ("\"")
node = (":")
node = (array (number) (number))
node = ("[")
node = (number)
node = (",")
node = (number)
node = ("]")
node = ("}")

julia> using tree_sitter_julia_jll

julia> julia_parser = Parser(tree_sitter_julia_jll)
Parser(Language(:julia))

julia> ast = parse(julia_parser, "f(x)")
(source_file (call_expression (identifier) (argument_list (identifier))))

julia> traverse(ast, named_children) do node, enter
           if !enter
               @show node
           end
       end
node = (identifier)
node = (identifier)
node = (argument_list (identifier))
node = (call_expression (identifier) (argument_list (identifier)))
node = (source_file (call_expression (identifier) (argument_list (identifier))))
```

## Available Languages

TreeSitter.jl supports any tree-sitter language parser packaged as a JLL. The following are available:

| Language   | JLL Package                  |
|------------|------------------------------|
| Bash       | `tree_sitter_bash_jll`       |
| C          | `tree_sitter_c_jll`          |
| C++        | `tree_sitter_cpp_jll`        |
| Go         | `tree_sitter_go_jll`         |
| HTML       | `tree_sitter_html_jll`       |
| Java       | `tree_sitter_java_jll`       |
| JavaScript | `tree_sitter_javascript_jll` |
| JSON       | `tree_sitter_json_jll`       |
| Julia      | `tree_sitter_julia_jll`      |
| PHP        | `tree_sitter_php_jll`        |
| Python     | `tree_sitter_python_jll`     |
| Ruby       | `tree_sitter_ruby_jll`       |
| Rust       | `tree_sitter_rust_jll`       |
| TypeScript | `tree_sitter_typescript_jll` |

Install only the languages you need:
```
pkg> add tree_sitter_julia_jll tree_sitter_python_jll
```

Additional languages can be added by writing new `jll` packages to wrap the
upstream parsers: see [Yggdrasil](https://github.com/JuliaPackaging/Yggdrasil)
for details.

## Multiple Parsers per Language

Some language packages provide multiple parser variants. For example, `tree_sitter_php_jll` provides both `php` (with HTML support) and `php_only` (pure PHP) parsers.

Discover available parsers:
```julia
julia> using TreeSitter, tree_sitter_php_jll

julia> list_parsers(tree_sitter_php_jll)
2-element Vector{Symbol}:
 :php
 :php_only
```

Use a specific parser variant:
```julia
julia> # Default parser (php with HTML support)
julia> p1 = Parser(tree_sitter_php_jll)
Parser(Language(:php))

julia> # PHP-only variant
julia> p2 = Parser(tree_sitter_php_jll, :php_only)
Parser(Language(:php_only))
```

The same variant parameter works for `Language` and `Query` constructors:
```julia
julia> lang = Language(tree_sitter_php_jll, :php_only)
Language(:php_only)

julia> query = Query(tree_sitter_php_jll, "(identifier) @id", :php_only)
Query(Language(:php_only))
```

## Local Grammar Repositories

For grammars not yet packaged as JLLs, load parsers directly from local tree-sitter grammar repositories:

```julia
# Clone and build the grammar
# $ git clone https://github.com/tree-sitter/tree-sitter-python
# $ cd tree-sitter-python && tree-sitter build

using TreeSitter
parser = Parser("/path/to/tree-sitter-python")
tree = parse(parser, "def foo(): pass")
```

**Requirements:**
- Repository must contain `tree-sitter.json` (tree-sitter v0.21+ format)
- Shared library must be built (`tree-sitter build` or `make`)

**Multi-grammar repositories:**
```julia
# tree-sitter-php has both :php and :php_only variants
parser = Parser("/path/to/tree-sitter-php", :php_only)
```

Query files from the repository's `queries/` directory are automatically loaded.

## Query Predicates and Metadata

TreeSitter.jl supports tree-sitter query predicates for filtering matches and attaching metadata to patterns.

### Supported Filtering Predicates

**String Comparison:**
- `#eq?` - String equality: `(#eq? @var "foo")`
- `#not-eq?` - String inequality: `(#not-eq? @method "constructor")`
- `#any-of?` - Multi-value equality: `(#any-of? @type "int" "void" "char")`

**Pattern Matching:**
- `#match?` - Regex match: `(#match? @lowercase "^[a-z]+$")`
- `#not-match?` - Negated regex: `(#not-match? @public "^_")`

**Node Properties:**
- `#is?` - Property assertion: `(#is? @node "named")`
- `#is-not?` - Negated property: `(#is-not? @node "extra")`

Only built-in properties are checked: `named`, `missing`, `extra`

**Tree Structure:**
- `#has-ancestor?` - Ancestor check: `(#has-ancestor? @indexer index_expression)`

**Quantified Predicates:**

For patterns with quantified captures (e.g., `(comment)+ @comments`), these predicates check if the condition holds for ANY of the captured nodes:

- `#any-eq?` - ANY capture equals value: `(#any-eq? @comments "// TODO")`
- `#any-not-eq?` - ANY capture not equal: `(#any-not-eq? @ids "reserved")`
- `#any-match?` - ANY capture matches regex: `(#any-match? @comments "TODO")`
- `#any-not-match?` - ANY capture doesn't match: `(#any-not-match? @lines "^\\s*$")`

Example usage:
```julia
# Match comment blocks where at least one comment contains "TODO"
q = query```
((comment)+ @comments
 (#any-match? @comments "TODO"))
```julia
```

## Language Injection

Many files embed one language in another: JavaScript and CSS inside HTML `<script>`/`<style>`, PHP inside HTML, heredocs and phpdoc inside PHP, regex and jsdoc inside JavaScript. Grammars describe these regions in an `injections.scm` query, marking the embedded text with `@injection.content` and naming the language either statically (`#set! injection.language "..."`) or dynamically (the text of an `@injection.language` capture). TreeSitter.jl reads those queries and parses the embedded languages for you.

`parse` does the whole job; `injection_sites` stops at the analysis; `ts_range` is the low-level range helper.

### Recursive parse

`parse` parses a source and every language embedded in it, to a bounded depth. A `Tree` is recursive: it carries its `language`, the shared `source`, the `ranges` it covers, and the `children` layers for embedded languages. A grammar that declares no injections leaves a single-layer tree, so the plain case is the base case of an injected one.

```julia
tree = parse(Parser(:html), "<p>hi</p><script>f(x)</script>")

tree.language.name                        # :html
child = tree.children[1]
child.language.name                       # :javascript
TreeSitter.slice(child)                    # "f(x)"

# The layer covering a 1-based byte offset, deepest first.
TreeSitter.layer_at(tree, 20).language.name   # :javascript

# Every layer, depth-first with the root first.
[l.language.name for l in TreeSitter.layers(tree)]   # [:html, :javascript]
```

A sub-tree's node offsets stay in the original document's coordinate space, so a query on a child layer reports positions into the shared source:

```julia
q = Query(:javascript, "(call_expression) @c")
for c in TreeSitter.each_capture(child, q, tree.source)
    TreeSitter.slice(tree.source, c.node)   # "f(x)"
end
```

### Language resolution

Injected languages resolve dynamically by default: an injection name maps through `INJECTION_ALIASES` (case-insensitive, e.g. `"js"` to `:javascript`, `"c++"` to `:cpp`) to a grammar symbol, and the JLL loads on demand. Pass `Parser(lang; languages=[...])` to pin the set from JLL modules, `Language`s, or local grammar paths, which disables dynamic loading. A site whose grammar is unavailable is recorded in the root tree's `unresolved` rather than raised:

```julia
tree = parse(Parser(:html), "<style>a{}</style>")
tree.unresolved   # [UnresolvedInjection("css", :unavailable)] when tree_sitter_css_jll is absent

# Pin the grammars, including a local one, and skip dynamic loading:
parse(Parser(:html; languages = [tree_sitter_javascript_jll, Language("path/to/tree-sitter-css")]), source)
```

Bound the recursion with `max_depth` (default 8); `max_depth=0` parses no embedded languages.

### Analysis only

`injection_sites` returns the embedded regions without parsing them, for callers that drive parsing themselves. Each `InjectionSite` carries the resolved language name, the 0-based `ranges`, and the `combined`/`include_children` flags.

```julia
p = Parser(:html)
source = "<script>let x=1;</script><style>a{}</style>"
tree = parse(p, source)
for site in TreeSitter.injection_sites(p, tree, source)
    site.language                                  # "javascript", then "css"
    TreeSitter.slice(source, site.content_nodes[1])
end
```

`ts_range(node)` builds the 0-based `API.TSRange` that `set_included_ranges!` expects, bridging the 1-based node coordinates and the 0-based C ranges.

### Limitations

- `include-children` follows tree-sitter's `intersect_ranges`: with the flag, the whole content node is injected; without it, every child node is excluded, leaving the gaps between them.
- `#offset!` is applied to single-line adjustments only; a directive with a non-zero row delta falls back to the unadjusted range.
- `injection.combined` groups content ranges by pattern index, matching how a grammar's own patterns combine.
