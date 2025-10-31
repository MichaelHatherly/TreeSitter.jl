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

## Usage

```
julia> using TreeSitter

julia> c = Parser(:c)
Parser(Language(:c))

julia> ast = parse(c, "int x;")
(translation_unit (declaration type: (primitive_type) declarator: (identifier)))

julia> json = Parser(:json)
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

julia> julia = Parser(:julia)
Parser(Language(:julia))

julia> ast = parse(julia, "f(x)")
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

## Languages

  - `:bash`
  - `:c`
  - `:cpp`
  - `:go`
  - `:html`
  - `:java`
  - `:javascript`
  - `:json`
  - `:julia`
  - `:php`
  - `:python`
  - `:ruby`
  - `:rust`
  - `:typescript`

Additional languages can be added by writing new `jll` packages to wrap the
upstream parsers: see [Yggdrasil](https://github.com/JuliaPackaging/Yggdrasil)
for details.
