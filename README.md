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
