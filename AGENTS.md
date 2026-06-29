# AGENTS.md

This file provides guidance to agentic coding tools when working with code in this repository.

## Project Overview

TreeSitter.jl provides Julia bindings for tree-sitter, an incremental parsing system for programming tools. The package wraps the C library via FFI and supports 14 languages (bash, c, cpp, go, html, java, javascript, json, julia, php, python, ruby, rust, typescript).

## Running Tests

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
```

To run tests interactively:
```bash
julia --project=.
using TreeSitter, Test
include("test/runtests.jl")
```

## Architecture

### Three-Layer Structure

1. **API Layer (`src/api.jl`)**: Low-level FFI bindings to tree-sitter C library
   - Defines C structs (TSNode, TSTree, TSParser, TSQuery, etc.)
   - Wraps all `ccall` functions with `ts_*` prefix
   - Dynamically discovers and loads language parsers via JLL packages
   - Language loading mechanism: Imports `tree_sitter_*_jll` packages at module load time using regex matching (`LANGUAGE_REGEX`), builds `LANGUAGES` dict mapping language symbols to (function, queries_dir) tuples
   - Query files: Loads `.scm` query files from language JLL artifact directories, supports custom queries in `src/queries/<language>/` that override JLL-provided queries

2. **Interface Layer (`src/interface.jl`)**: Julia-friendly wrapper types
   - `list_parsers(jll_mod)`: Discovers available parser variants in a JLL module
   - `Language`: Wraps language pointer with name symbol, supports optional `variant` parameter
   - `Parser`: Manages parser state, auto-finalizes via GC, supports optional `variant` parameter
   - `Tree` and `Node`: Represent parse trees, `Node` uses value type wrapping `API.TSNode`
   - `Query` and `QueryCursor`: Pattern matching with tree-sitter query syntax, supports optional `variant` parameter
   - Core APIs: `parse()`, `traverse()`, `children()`, `named_children()`
   - Query predicates: filtering predicates `eq?`, `not-eq?`, `match?`, `not-match?`, `any-of?`, the quantified `any-eq?`/`any-not-eq?`/`any-match?`/`any-not-match?` family, and `has-ancestor?`; property checks `is?`/`is-not?` (built-in `named`/`missing`/`extra`, unknown properties are no-ops); `set!` attaches metadata read via `property_settings()`/`property()`

3. **Module (`src/TreeSitter.jl`)**: Main entry point, exports public API

### Key Patterns

- **Resource Management**: All C resources (Parser, Tree, Query, QueryCursor) use finalizers for automatic cleanup
- **1-based Indexing**: Julia convention - C API uses 0-based, interface adds/subtracts 1
- **Traversal**: `traverse(f, node, iter)` calls `f(node, enter::Bool)` twice per node (enter=true descending, enter=false ascending)
- **Byte Ranges**: `byte_range(n)` returns 1-based Julia byte indices, use `slice(source, node)` to extract text
- **Query Syntax**: Use `query```...```lang` string macro or `Query(:lang, source)` constructor

### Language Support

Languages are loaded dynamically via JLL dependencies. To add a language:
1. Add `tree_sitter_<lang>_jll` to Project.toml dependencies and compat
2. Uncomment the import in `src/api.jl` lines 597-611
3. The `LANGUAGES` dict auto-populates via regex matching on module load

## Common Patterns

### Parsing
```julia
parser = Parser(:julia)
tree = parse(parser, "f(x) = x + 1")
root_node = root(tree)
```

### Tree Traversal
```julia
# Visit all nodes
traverse(tree) do node, enter
    enter && println(node_type(node))
end

# Visit only named nodes
traverse(tree, named_children) do node, enter
    # ...
end
```

### Queries
```julia
# Using query macro
q = query```
(identifier) @var
(#match? @var "^[a-z]")
```julia

# Or construct directly
q = Query(:c, ["highlights"])  # Load from language query files

# Execute queries
for capture in each_capture(tree, q, source_text)
    name = capture_name(q, capture)
    text = slice(source_text, capture.node)
end
```

### Node Inspection
```julia
node_type(n)           # "identifier", "call_expression", etc.
is_named(n)            # true for named nodes, false for punctuation
count_nodes(n)         # total children count
count_named_nodes(n)   # named children only
child(n, i)            # i-th child (1-based)
child(n, "field_name") # child by field name
slice(source, n)       # extract node text from source
```

### Multi-Parser Support
```julia
# Discover available parsers in a JLL module
parsers = list_parsers(tree_sitter_php_jll)  # [:php, :php_only]

# Use default parser (inferred from module name)
p1 = Parser(tree_sitter_php_jll)  # Uses :php

# Use specific variant
p2 = Parser(tree_sitter_php_jll, :php_only)

# Works with Language and Query constructors too
lang = Language(tree_sitter_php_jll, :php_only)
query = Query(tree_sitter_php_jll, "(identifier) @id", :php_only)
```

Some JLL packages provide multiple parser variants (e.g., `tree_sitter_php_jll` has both `:php` with HTML support and `:php_only` for pure PHP). Use `list_parsers()` to discover what's available, and pass the variant symbol as an optional second parameter to constructors.

## Development Notes

- The package uses Julia 1.6+ (see Project.toml compat)
- tree-sitter C library version 0.16.9 via tree_sitter_jll
- Most language parsers use 0.16.x versions, julia parser is 0.0.4
- Test suite validates all supported languages parse empty strings and checks specific parse outputs
