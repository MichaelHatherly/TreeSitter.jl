# TreeSitter

*Julia bindings for [tree-sitter](https://github.com/tree-sitter/tree-sitter) &mdash;
"An incremental parsing system for programming tools."*

[![Build Status](https://travis-ci.org/MichaelHatherly/TreeSitter.jl.svg?branch=master)](https://travis-ci.org/MichaelHatherly/TreeSitter.jl)
[![Codecov](https://codecov.io/gh/MichaelHatherly/TreeSitter.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/MichaelHatherly/TreeSitter.jl)

## Installation

This package is not registered yet and so can be installed using:

```
pkg> add https://github.com/MichaelHatherly/TreeSitter.jl
```

## Usage

```
julia> using TreeSitter
julia> c = Parser(:c)
Parser(Language(c))

julia> ast = parse(c, "int x;")
(translation_unit (declaration type: (primitive_type) declarator: (identifier)))

julia> json = Parser(:json)
Parser(Language(json))

julia> ast = parse(json, "{\"one\": 1}")
(document (object (pair key: (string (string_content)) value: (number))))
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
