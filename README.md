# TreeSitter

*Julia bindings for [tree-sitter](https://github.com/tree-sitter/tree-sitter) &mdash;
"An incremental parsing system for programming tools."*

[![Build Status](https://travis-ci.org/MichaelHatherly/TreeSitter.jl.svg?branch=1.4)](https://travis-ci.org/MichaelHatherly/TreeSitter.jl)
[![Codecov](https://codecov.io/gh/MichaelHatherly/TreeSitter.jl/branch/1.4/graph/badge.svg)](https://codecov.io/gh/MichaelHatherly/TreeSitter.jl)

## Installation

This package is not registered yet and so can be installed using:

```
pkg> add https://github.com/MichaelHatherly/TreeSitter.jl
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

julia> ast = parse(json, "{1: [2]}")
(document (object (pair key: (number) value: (array (number)))))

julia> traverse(ast) do node, enter
           if enter
               @show node
           end
       end
node = (document (object (pair key: (number) value: (array (number)))))
node = (object (pair key: (number) value: (array (number))))
node = ("{")
node = (pair key: (number) value: (array (number)))
node = (number)
node = (":")
node = (array (number))
node = ("[")
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

Additional languages can be added by writing new build scripts for
[tree-sitter-binaries](https://github.com/MichaelHatherly/tree-sitter-binaries).
