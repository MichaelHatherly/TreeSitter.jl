#
# Language
#

const JLL_MODULE_CACHE = Dict{Symbol,Module}()

function list_parsers(jll_mod::Module)
    # Scan the module for all libtreesitter_*_handle globals
    parsers = Symbol[]
    for name in names(jll_mod; all = true)
        name_str = string(name)
        if endswith(name_str, "_handle") && startswith(name_str, "libtreesitter_")
            # Extract the parser name from "libtreesitter_<parser>_handle"
            parser_name = name_str[15:(end-7)]  # Strip "libtreesitter_" and "_handle"
            push!(parsers, Symbol(parser_name))
        end
    end
    return sort!(parsers)
end

mutable struct Language
    name::Symbol
    ptr::Ptr{API.TSLanguage}
    queries::Dict{String,String}

    function Language(jll_mod::Module, variant::Union{Symbol,Nothing} = nothing)
        if variant === nothing
            name = API.extract_lang_name(jll_mod)
        else
            name = variant
        end
        ptr = API.get_lang_ptr(jll_mod, variant)
        queries = API.load_queries(jll_mod, variant)
        new(name, ptr, queries)
    end

    function Language(name::Symbol)
        jll_mod = get!(JLL_MODULE_CACHE, name) do
            pkg_name = "tree_sitter_$(name)_jll"
            pkg_id = Base.identify_package(pkg_name)
            if pkg_id === nothing
                error(
                    "Language package '$pkg_name' not found. Please add and import it first:\n" *
                    "  using tree_sitter_$(name)_jll",
                )
            end
            Base.root_module(pkg_id)
        end
        return Language(jll_mod)
    end

    # Internal constructor for local grammar repos
    Language(name::Symbol, ptr::Ptr{API.TSLanguage}, queries::Dict{String,String}) =
        new(name, ptr, queries)
end

function Language(path::AbstractString, variant::Union{Symbol,Nothing} = nothing)
    isdir(path) || return Language(Symbol(path))
    name, ptr, queries = API.load_local_grammar(path, variant)
    return Language(name, ptr, queries)
end
Base.show(io::IO, l::Language) = print(io, "Language(", repr(l.name), ")")

#
# Parser
#

mutable struct Parser
    language::Language
    ptr::Ptr{API.TSParser}
    logger_sink::Union{Function,Nothing}  # keeps a set_logger! callback alive while installed
    function Parser(lang::Language)
        parser = new(lang, API.ts_parser_new(), nothing)
        finalizer(p -> API.ts_parser_delete(p.ptr), parser)
        set_language!(parser, lang)
        return parser
    end
    Parser(jll_mod::Module, variant::Union{Symbol,Nothing} = nothing) =
        Parser(Language(jll_mod, variant))
    Parser(name::Symbol) = Parser(Language(name))
    Parser(path::AbstractString, variant::Union{Symbol,Nothing} = nothing) =
        Parser(Language(path, variant))
end
Base.show(io::IO, p::Parser) = print(io, "Parser(", p.language, ")")

function set_language!(parser::Parser, language::Language)
    API.ts_parser_set_language(parser.ptr, language.ptr)
    parser.language = language
    return parser
end

"""
    parse(parser::Parser, text::AbstractString; encoding=:utf8) -> Tree
    parse(parser::Parser, source::Function; encoding=:utf8) -> Tree
    parse(parser::Parser, text::AbstractString, old::Tree) -> Tree

Parse source into a `Tree`. `encoding` is `:utf8` or `:utf16`.

Pass a `source` callback to parse a source not held as a single `String`:
`source(offset)` returns the chunk at a 1-based byte offset, or an empty string at end
of input.

Pass an `old` tree that has had the matching `edit!` applied to reparse incrementally,
reusing the unchanged subtrees.

# Example
```julia
parser = Parser(tree_sitter_julia_jll)
tree = parse(parser, "f(x) = x + 1")
```
"""
function Base.parse(p::Parser, text::AbstractString; encoding::Symbol = :utf8)
    encoding === :utf8 &&
        return Tree(API.ts_parser_parse_string(p.ptr, C_NULL, text, sizeof(text)))
    encoding === :utf16 || throw(ArgumentError("unknown encoding $encoding"))
    units = transcode(UInt16, String(text))
    GC.@preserve units begin
        buffer = Cstring(reinterpret(Ptr{Cchar}, pointer(units)))
        return Tree(
            API.ts_parser_parse_string_encoding(
                p.ptr,
                C_NULL,
                buffer,
                UInt32(2 * length(units)),
                API.TSInputEncodingUTF16LE,
            ),
        )
    end
end

# Holds the user's chunk producer and the current chunk, kept alive across read calls.
mutable struct InputState
    source::Function
    chunk::Vector{UInt8}
end

# C-callable read callback: returns the source chunk starting at a 1-based byte index,
# or signals EOF with a zero length.
function _input_trampoline(
    payload::Ptr{Cvoid},
    byte_index::UInt32,
    ::API.TSPoint,
    bytes_read::Ptr{UInt32},
)
    state = unsafe_pointer_to_objref(payload)::InputState
    state.chunk = Vector{UInt8}(codeunits(String(state.source(Int(byte_index) + 1))))
    unsafe_store!(bytes_read, UInt32(length(state.chunk)))
    return isempty(state.chunk) ? Ptr{Cchar}(C_NULL) : Ptr{Cchar}(pointer(state.chunk))
end

function Base.parse(p::Parser, source::Function; encoding::Symbol = :utf8)
    enc =
        encoding === :utf8 ? API.TSInputEncodingUTF8 :
        encoding === :utf16 ? API.TSInputEncodingUTF16LE :
        throw(ArgumentError("unknown encoding $encoding"))
    state = InputState(source, UInt8[])
    trampoline = @cfunction(
        _input_trampoline,
        Ptr{Cchar},
        (Ptr{Cvoid}, UInt32, API.TSPoint, Ptr{UInt32})
    )
    GC.@preserve state begin
        input = API.TSInput(pointer_from_objref(state), trampoline, enc, C_NULL)
        return Tree(API.ts_parser_parse(p.ptr, C_NULL, input))
    end
end

"""
    reset!(parser::Parser) -> Parser

Discard the parser's state so the next `parse` starts fresh rather than resuming a
cancelled parse.
"""
reset!(p::Parser) = (API.ts_parser_reset(p.ptr); p)

"""
    set_included_ranges!(parser::Parser, ranges::Vector{API.TSRange}) -> Parser

Restrict parsing to the given source ranges (byte and point fields are 0-based). Used
for language injection, such as parsing only the script regions of an HTML document.
Throws if the ranges are not ordered and disjoint.
"""
function set_included_ranges!(p::Parser, ranges::Vector{API.TSRange})
    ok = GC.@preserve ranges API.ts_parser_set_included_ranges(
        p.ptr,
        pointer(ranges),
        length(ranges),
    )
    ok || throw(ArgumentError("TreeSitter: included ranges must be ordered and disjoint"))
    return p
end

"""
    included_ranges(parser::Parser) -> Vector{API.TSRange}

Return the ranges the parser is restricted to. A fresh parser reports a single range
covering the whole document.
"""
function included_ranges(p::Parser)
    len = Ref{UInt32}()
    ptr = API.ts_parser_included_ranges(p.ptr, len)
    # The array is owned by the parser; do not free it.
    return [unsafe_load(ptr, i) for i = 1:Int(len[])]
end

# C-callable trampoline: payload is the Parser, whose logger_sink field holds the sink.
function _logger_trampoline(
    payload::Ptr{Cvoid},
    log_type::API.TSLogType,
    buffer::Ptr{Cchar},
)
    parser = unsafe_pointer_to_objref(payload)::Parser
    sink = parser.logger_sink
    sink === nothing ||
        sink(log_type === API.TSLogTypeLex ? :lex : :parse, unsafe_string(buffer))
    return nothing
end

"""
    set_logger!(parser::Parser, sink::Function) -> Parser

Install a logging callback invoked as `sink(kind::Symbol, message::String)` during
parsing, where `kind` is `:parse` or `:lex`.
"""
function set_logger!(p::Parser, sink::Function)
    p.logger_sink = sink
    trampoline =
        @cfunction(_logger_trampoline, Cvoid, (Ptr{Cvoid}, API.TSLogType, Ptr{Cchar}))
    API.ts_parser_set_logger(p.ptr, API.TSLogger(pointer_from_objref(p), trampoline))
    return p
end

"""
    logger(parser::Parser) -> API.TSLogger

Return the parser's current logger. The `log` field is null when none is installed.
"""
logger(p::Parser) = API.ts_parser_logger(p.ptr)

"""
    print_dot_graphs!(parser::Parser, dest) -> Parser

Write parser DOT graphs during subsequent parses. `dest` is a file path, an `IO`, or
`nothing` to disable. tree-sitter owns a duplicate of the underlying file descriptor and
flushes it when graphs are disabled or redirected, so call `print_dot_graphs!(parser,
nothing)` to finish writing.
"""
function print_dot_graphs!(p::Parser, io::IO)
    API.ts_parser_print_dot_graphs(p.ptr, _dup_fd(Base.fd(io)))
    return p
end

print_dot_graphs!(p::Parser, path::AbstractString) =
    open(io -> print_dot_graphs!(p, io), path; write = true)

print_dot_graphs!(p::Parser, ::Nothing) = (API.ts_parser_print_dot_graphs(p.ptr, -1); p)

_dup_fd(fd) = @static Sys.iswindows() ? ccall(:_dup, Cint, (Cint,), fd) :
        ccall(:dup, Cint, (Cint,), fd)

#
# Tree
#

mutable struct Tree
    ptr::Ptr{API.TSTree}
    function Tree(ptr::Ptr{API.TSTree})
        tree = new(ptr)
        finalizer(t -> API.ts_tree_delete(t.ptr), tree)
        return tree
    end
end
Base.show(io::IO, t::Tree) = show(io, root(t))

root(t::Tree) = Node(API.ts_tree_root_node(t.ptr), t)

"""
    copy(tree::Tree) -> Tree

Return an independent copy of `tree`, useful for keeping the pre-edit tree when reparsing
incrementally.
"""
Base.copy(t::Tree) = Tree(API.ts_tree_copy(t.ptr))

Base.parse(p::Parser, text::AbstractString, old::Tree) =
    Tree(API.ts_parser_parse_string(p.ptr, old.ptr, text, sizeof(text)))

traverse(f, tree::Tree, iter = children) = traverse(f, root(tree), iter)

#
# Node
#

struct Node
    ptr::API.TSNode
    tree::Tree
    Node(ptr::API.TSNode, tree::Tree) = new(ptr, tree)
end

ensure_not_null(n::Node) =
    is_null(n) ? throw(ArgumentError("TreeSitter: node is null")) : nothing

Base.show(io::IO, n::Node) = print(io, node_string(n))

function node_string(n::Node)
    ensure_not_null(n)
    # ts_node_string returns a malloc'd C string that the caller must free.
    ptr = API.ts_node_string(n.ptr)
    str = unsafe_string(ptr)
    Libc.free(ptr)
    return str
end
node_symbol(n::Node) = (ensure_not_null(n); API.ts_node_symbol(n.ptr))
node_type(n::Node) = (ensure_not_null(n); unsafe_string(API.ts_node_type(n.ptr)))

is_null(n::Node) = API.ts_node_is_null(n.ptr)
is_named(n::Node) = API.ts_node_is_named(n.ptr)
is_missing(n::Node) = API.ts_node_is_missing(n.ptr)
is_extra(n::Node) = API.ts_node_is_extra(n.ptr)
is_leaf(n::Node) = iszero(count_nodes(n))

"""
    has_error(n::Node) -> Bool

Return `true` if `n` or any node beneath it is a syntax error.
"""
has_error(n::Node) = API.ts_node_has_error(n.ptr)

"""
    has_changes(n::Node) -> Bool

Return `true` if `n` overlaps a region edited since the last parse.
"""
has_changes(n::Node) = API.ts_node_has_changes(n.ptr)

count_nodes(n::Node) = Int(API.ts_node_child_count(n.ptr))
count_named_nodes(n::Node) = Int(API.ts_node_named_child_count(n.ptr))

child(n::Node, nth::Integer) = Node(API.ts_node_child(n.ptr, nth - 1), n.tree)
named_child(n::Node, nth::Integer) = Node(API.ts_node_named_child(n.ptr, nth - 1), n.tree)

children(n::Node) = (child(n, ind) for ind = 1:count_nodes(n))
named_children(n::Node) = (named_child(n, ind) for ind = 1:count_named_nodes(n))

function traverse(f, n::Node, iter = children)
    f(n, true)
    for child in iter(n)
        traverse(f, child, iter)
    end
    f(n, false)
    return nothing
end

Base.:(==)(left::Node, right::Node) = API.ts_node_eq(left.ptr, right.ptr)

byte_range(n::Node) =
    (Int(API.ts_node_start_byte(n.ptr)) + 1, Int(API.ts_node_end_byte(n.ptr)))

slice(src::AbstractString, n::Node) = slice(src, byte_range(n))
slice(src::AbstractString, (from, to)) = SubString(src, from, thisind(src, to))

function child(n::Node, name::AbstractString)
    result =
        Node(API.ts_node_child_by_field_name(n.ptr, String(name), sizeof(name)), n.tree)
    if is_null(result)
        throw(
            ArgumentError(
                "TreeSitter: field '$name' not found on node of type '$(node_type(n))'",
            ),
        )
    end
    return result
end

# Navigation
parent(n::Node) = Node(API.ts_node_parent(n.ptr), n.tree)
next_sibling(n::Node) = Node(API.ts_node_next_sibling(n.ptr), n.tree)
prev_sibling(n::Node) = Node(API.ts_node_prev_sibling(n.ptr), n.tree)
next_named_sibling(n::Node) = Node(API.ts_node_next_named_sibling(n.ptr), n.tree)
prev_named_sibling(n::Node) = Node(API.ts_node_prev_named_sibling(n.ptr), n.tree)

# Position info
start_point(n::Node) = API.ts_node_start_point(n.ptr)
end_point(n::Node) = API.ts_node_end_point(n.ptr)

"""
    descendant_for_byte_range(n::Node, from, to) -> Node
    named_descendant_for_byte_range(n::Node, from, to) -> Node
    descendant_for_point_range(n::Node, from::API.TSPoint, to::API.TSPoint) -> Node
    named_descendant_for_point_range(n::Node, from::API.TSPoint, to::API.TSPoint) -> Node

Return the smallest node under `n` that spans the given range. Byte offsets are 1-based,
matching `byte_range`; points are the 0-based `TSPoint` values returned by `start_point`
and `end_point`. The `named_` variants skip anonymous nodes.
"""
descendant_for_byte_range(n::Node, from::Integer, to::Integer) =
    Node(API.ts_node_descendant_for_byte_range(n.ptr, from - 1, to - 1), n.tree)
named_descendant_for_byte_range(n::Node, from::Integer, to::Integer) =
    Node(API.ts_node_named_descendant_for_byte_range(n.ptr, from - 1, to - 1), n.tree)
descendant_for_point_range(n::Node, from::API.TSPoint, to::API.TSPoint) =
    Node(API.ts_node_descendant_for_point_range(n.ptr, from, to), n.tree)
named_descendant_for_point_range(n::Node, from::API.TSPoint, to::API.TSPoint) =
    Node(API.ts_node_named_descendant_for_point_range(n.ptr, from, to), n.tree)

"""
    first_child_for_byte(n::Node, byte) -> Node
    first_named_child_for_byte(n::Node, byte) -> Node

Return the first child of `n` whose extent reaches the given 1-based byte offset. The
`named_` variant skips anonymous nodes.
"""
first_child_for_byte(n::Node, byte::Integer) =
    Node(API.ts_node_first_child_for_byte(n.ptr, byte - 1), n.tree)
first_named_child_for_byte(n::Node, byte::Integer) =
    Node(API.ts_node_first_named_child_for_byte(n.ptr, byte - 1), n.tree)

"""
    child_by_field_id(n::Node, field_id::Integer) -> Node

Return the child of `n` for the numeric `field_id`. Throws if there is no such child.
Use `field_id_for_name` to resolve a field name to an id.
"""
function child_by_field_id(n::Node, field_id::Integer)
    result = Node(API.ts_node_child_by_field_id(n.ptr, field_id), n.tree)
    is_null(result) && throw(ArgumentError("TreeSitter: no child for field id $field_id"))
    return result
end

#
# Grammar introspection
#

# Anything carrying a language pointer: the Language itself, or a Tree/Parser to query
# the grammar they were built with.
const HasLanguage = Union{Language,Tree,Parser}
language_ptr(l::Language) = l.ptr
language_ptr(t::Tree) = API.ts_tree_language(t.ptr)
language_ptr(p::Parser) = API.ts_parser_language(p.ptr)

"""
    symbol_count(x) -> Int

Number of distinct node types in the grammar. `x` is a `Language`, `Tree`, or `Parser`.
"""
symbol_count(x::HasLanguage) = Int(API.ts_language_symbol_count(language_ptr(x)))

"""
    symbol_name(x, id::Integer) -> String

Name of the node type with the given symbol id.
"""
symbol_name(x::HasLanguage, id::Integer) =
    unsafe_string(API.ts_language_symbol_name(language_ptr(x), id))

"""
    symbol_for_name(x, name::AbstractString, named::Bool) -> Int

Symbol id for a node type. `named` selects a named node type over an anonymous one of
the same name.
"""
symbol_for_name(x::HasLanguage, name::AbstractString, named::Bool) =
    Int(API.ts_language_symbol_for_name(language_ptr(x), String(name), sizeof(name), named))

"""
    symbol_type(x, id::Integer) -> API.TSSymbolType

Whether the symbol id is a regular, anonymous, or auxiliary node type.
"""
symbol_type(x::HasLanguage, id::Integer) = API.ts_language_symbol_type(language_ptr(x), id)

"""
    field_count(x) -> Int

Number of distinct field names in the grammar.
"""
field_count(x::HasLanguage) = Int(API.ts_language_field_count(language_ptr(x)))

"""
    field_name_for_id(x, id::Integer) -> String

Field name for the given field id.
"""
field_name_for_id(x::HasLanguage, id::Integer) =
    unsafe_string(API.ts_language_field_name_for_id(language_ptr(x), id))

"""
    field_id_for_name(x, name::AbstractString) -> Int

Field id for the given field name.
"""
field_id_for_name(x::HasLanguage, name::AbstractString) =
    Int(API.ts_language_field_id_for_name(language_ptr(x), String(name), sizeof(name)))

#
# TreeCursor
#

"""
    TreeCursor(n::Node)
    TreeCursor(t::Tree)

A stateful cursor over a tree. Cheaper than repeated `Node` navigation for full
traversals, and exposes the field name a node occupies in its parent. Move it with the
`goto_*` methods and read its position with `current_node`, `current_field_name`, and
`current_field_id`.
"""
mutable struct TreeCursor
    ref::Base.RefValue{API.TSTreeCursor}
    tree::Tree
    function TreeCursor(ref::Base.RefValue{API.TSTreeCursor}, tree::Tree)
        cursor = new(ref, tree)
        finalizer(c -> API.ts_tree_cursor_delete(c.ref), cursor)
        return cursor
    end
end
TreeCursor(n::Node) = TreeCursor(Ref(API.ts_tree_cursor_new(n.ptr)), n.tree)
TreeCursor(t::Tree) = TreeCursor(root(t))
Base.show(io::IO, ::TreeCursor) = print(io, "TreeCursor()")

"""
    current_node(c::TreeCursor) -> Node

The node the cursor is currently on.
"""
current_node(c::TreeCursor) = Node(API.ts_tree_cursor_current_node(c.ref), c.tree)

"""
    current_field_id(c::TreeCursor) -> Int

Field id the current node occupies in its parent, or `0` for none.
"""
current_field_id(c::TreeCursor) = Int(API.ts_tree_cursor_current_field_id(c.ref))

"""
    current_field_name(c::TreeCursor) -> Union{String,Nothing}

Field name the current node occupies in its parent, or `nothing` at the root and for
children with no field.
"""
function current_field_name(c::TreeCursor)
    str = API.ts_tree_cursor_current_field_name(c.ref)
    return reinterpret(Ptr{Cchar}, str) == C_NULL ? nothing : unsafe_string(str)
end

"""
    goto_parent!(c::TreeCursor) -> Bool
    goto_next_sibling!(c::TreeCursor) -> Bool
    goto_first_child!(c::TreeCursor) -> Bool

Move the cursor to the parent, next sibling, or first child. Return `false` and leave the
cursor in place when there is no such node.
"""
goto_parent!(c::TreeCursor) = API.ts_tree_cursor_goto_parent(c.ref) != 0
goto_next_sibling!(c::TreeCursor) = API.ts_tree_cursor_goto_next_sibling(c.ref) != 0
goto_first_child!(c::TreeCursor) = API.ts_tree_cursor_goto_first_child(c.ref) != 0

"""
    goto_first_child_for_byte!(c::TreeCursor, byte) -> Union{Int,Nothing}

Move to the first child reaching the given 1-based byte offset, returning its 1-based
index, or `nothing` if there is none.
"""
function goto_first_child_for_byte!(c::TreeCursor, byte::Integer)
    index = API.ts_tree_cursor_goto_first_child_for_byte(c.ref, byte - 1)
    return index < 0 ? nothing : Int(index) + 1
end

"""
    reset!(c::TreeCursor, n::Node) -> TreeCursor

Move the cursor to `n`, discarding its position.
"""
reset!(c::TreeCursor, n::Node) =
    (API.ts_tree_cursor_reset(c.ref, n.ptr); c.tree = n.tree; c)

"""
    copy(c::TreeCursor) -> TreeCursor

An independent cursor at the same position as `c`.
"""
Base.copy(c::TreeCursor) = TreeCursor(Ref(API.ts_tree_cursor_copy(c.ref)), c.tree)

"""
    traverse(f, c::TreeCursor)

Walk the subtree under the cursor depth-first, calling `f(node, field_name, enter)` on
the way down (`enter=true`) and up (`enter=false`). `field_name` is `nothing` when the
node occupies no field.
"""
function traverse(f, c::TreeCursor)
    node, field = current_node(c), current_field_name(c)
    f(node, field, true)
    if goto_first_child!(c)
        traverse(f, c)
        while goto_next_sibling!(c)
            traverse(f, c)
        end
        goto_parent!(c)
    end
    f(node, field, false)
    return nothing
end

#
# Editing
#

"""
    input_edit(start_byte, old_end_byte, new_end_byte,
               start_point, old_end_point, new_end_point) -> API.TSInputEdit

Describe a source edit for `edit!`. Byte offsets are 1-based, matching `byte_range`;
points are 0-based `TSPoint` values, as returned by `start_point` and `end_point`.
"""
input_edit(
    start_byte::Integer,
    old_end_byte::Integer,
    new_end_byte::Integer,
    start_point::API.TSPoint,
    old_end_point::API.TSPoint,
    new_end_point::API.TSPoint,
) = API.TSInputEdit(
    start_byte - 1,
    old_end_byte - 1,
    new_end_byte - 1,
    start_point,
    old_end_point,
    new_end_point,
)

"""
    edit!(tree::Tree, e::API.TSInputEdit) -> Tree
    edit!(n::Node, e::API.TSInputEdit) -> Node

Apply an edit so the tree can be reparsed incrementally. Edit the tree, then call
`parse(parser, new_text, tree)`. The `Node` form adjusts a node held outside a tree and
returns the updated node. Build `e` with `input_edit`.
"""
edit!(t::Tree, e::API.TSInputEdit) = (API.ts_tree_edit(t.ptr, Ref(e)); t)

function edit!(n::Node, e::API.TSInputEdit)
    ref = Ref(n.ptr)
    API.ts_node_edit(ref, Ref(e))
    return Node(ref[], n.tree)
end

"""
    changed_ranges(old::Tree, new::Tree) -> Vector{API.TSRange}

Ranges that differ between an edited `old` tree and its incremental reparse `new`. Byte
and point fields on each `TSRange` are 0-based.
"""
function changed_ranges(old::Tree, new::Tree)
    len = Ref{UInt32}()
    ptr = API.ts_tree_get_changed_ranges(old.ptr, new.ptr, len)
    ranges = [unsafe_load(ptr, i) for i = 1:Int(len[])]
    Libc.free(ptr)
    return ranges
end

#
# Query
#

struct QueryException <: Exception
    msg::String
end

# Represents metadata attached to query patterns via #set! or property checks via #is?/#is-not?
# Example: (#set! "priority" "100") creates QueryProperty("priority", "100", nothing)
# capture_id is set when property applies to specific capture: (#set! @capture "key" "value")
struct QueryProperty
    key::String
    value::Union{String,Nothing}  # Nothing for flag-style properties: (#set! "local")
    capture_id::Union{Int,Nothing}  # Nothing for pattern-level, Int for capture-specific
end

mutable struct Query
    language::Language
    ptr::Ptr{API.TSQuery}
    # Metadata storage: outer vector indexed by pattern (1-based), inner vector = all properties for that pattern
    # Parsed once at construction from TSQueryPredicateStep arrays, enabling O(1) lookup by pattern index
    # Separates metadata (#set!) from filtering predicates (#eq?, #match?) for correctness and performance
    property_settings::Vector{Vector{QueryProperty}}  # #set! directives
    property_predicates::Vector{Vector{Tuple{QueryProperty,Bool}}}  # #is?/#is-not? (Bool = positive/negative)
    unknown_properties::Set{String}  # Track unimplemented properties for warning

    function Query(language::Language, source)
        source_text = load_source(language, source)
        error_offset_ref = Ref{UInt32}()
        error_type_ref = Ref{API.TSQueryError}()
        ptr = API.ts_query_new(
            language.ptr,
            String(source_text),
            sizeof(source_text),
            error_offset_ref,
            error_type_ref,
        )
        if ptr === C_NULL
            type =
                error_type_ref[] === API.TSQueryErrorSyntax ? "syntax" :
                error_type_ref[] === API.TSQueryErrorNodeType ? "node type" :
                error_type_ref[] === API.TSQueryErrorField ? "field" :
                error_type_ref[] === API.TSQueryErrorCapture ? "capture" :
                error("unknown query error type: $(error_type_ref[])")
            offset = error_offset_ref[] + 1
            throw(QueryException("'$type' error starting at index $offset"))
        else
            # Initialize metadata storage: one inner vector per pattern for O(1) lookup
            # Each pattern can have 0-N properties, stored in its inner vector
            n_patterns = Int(API.ts_query_pattern_count(ptr))
            property_settings = [QueryProperty[] for _ = 1:n_patterns]
            property_predicates = [Tuple{QueryProperty,Bool}[] for _ = 1:n_patterns]
            unknown_properties = Set{String}()
            query = new(
                language,
                ptr,
                property_settings,
                property_predicates,
                unknown_properties,
            )
            finalizer(q -> API.ts_query_delete(q.ptr), query)
            # Parse predicates once at construction for performance and correctness
            # Separates metadata directives (#set!, #is?) from filtering predicates (#eq?, #match?)
            parse_predicates!(query)
            # Warn about unknown properties once at construction
            if !isempty(query.unknown_properties)
                props_str = join(sort(collect(query.unknown_properties)), ", ")
                @warn "Query uses unimplemented properties that will be treated as no-ops: $props_str"
            end
            return query
        end
    end
    Query(jll_mod::Module, source, variant::Union{Symbol,Nothing} = nothing) =
        Query(Language(jll_mod, variant), source)
    Query(language::Symbol, source) = Query(Language(language), source)
    Query(path::AbstractString, source, variant::Union{Symbol,Nothing} = nothing) =
        Query(Language(path, variant), source)

    function load_source(lang::Language, files)
        out = IOBuffer()
        for file in files
            println(out, get(lang.queries, file, ""))
        end
        return String(take!(out))
    end
    load_source(::Language, source::AbstractString) = source
end
Base.show(io::IO, q::Query) = print(io, "Query(", q.language, ")")

# Parse all predicates at query construction, separating metadata (#set!, #is?) from filtering predicates
# Filtering predicates (#eq?, #match?, etc.) remain evaluated at match-time via predicate() function
# This follows the Rust binding pattern for performance (parse once vs per-match) and correctness (#set! shouldn't filter)
function parse_predicates!(q::Query)
    for pattern_idx = 1:pattern_count(q)
        parse_pattern_predicates!(q, pattern_idx)
    end
end

# Walk the predicate steps for one pattern, routing each completed predicate to storage.
# Steps alternate: predicate name (string), arguments (captures/strings), DONE marker.
function parse_pattern_predicates!(q::Query, pattern_idx)
    len = Ref{UInt32}()
    # Get predicate steps for this pattern (0-based C API)
    ptr = API.ts_query_predicates_for_pattern(q.ptr, pattern_idx - 1, len)

    func = ""
    args = String[]
    for i = 1:len[]
        step = unsafe_load(ptr, i)

        if step.type === API.TSQueryPredicateStepTypeString
            # String argument or predicate name
            str = query_string(q, step.value_id)
            func == "" ? (func = str) : push!(args, str)

        elseif step.type === API.TSQueryPredicateStepTypeCapture
            # Capture reference, stored as "@capture_N". The N placeholder stands in
            # for capture indices needed by quantified predicates.
            push!(args, "@capture_$(step.value_id)")

        elseif step.type === API.TSQueryPredicateStepTypeDone
            route_predicate!(q, pattern_idx, func, args)
            # Reset for next predicate
            func = ""
            empty!(args)
        end
    end
end

# Route a completed predicate to metadata storage. Filtering predicates (#eq?,
# #match?, etc.) are left for match-time evaluation in predicate().
function route_predicate!(q::Query, pattern_idx, func, args)
    if func == "set!"
        # Metadata directive: (#set! key value) or (#set! key)
        prop = parse_set_property(args)
        push!(q.property_settings[pattern_idx], prop)

    elseif func == "is?" || func == "is-not?"
        # Property assertion: (#is? @capture "property") or (#is-not? @capture "property")
        prop = parse_property_predicate(args)
        is_positive = (func == "is?")
        push!(q.property_predicates[pattern_idx], (prop, is_positive))
        # Track unknown properties for warning at construction
        if prop.key ∉ ("named", "missing", "extra", "local")
            push!(q.unknown_properties, prop.key)
        end
    end
end

# Parse #set! directive arguments into QueryProperty
# Formats: (#set! "key" "value"), (#set! "key"), (#set! @capture "key" "value")
function parse_set_property(args::Vector{String})
    if isempty(args)
        error("set! requires at least a key")
    end

    # Check if first arg is capture reference (@capture_N)
    if startswith(args[1], "@capture_")
        # Capture-specific: (#set! @capture "key" "value")
        capture_id = parse(Int, args[1][10:end])  # Extract N from @capture_N
        key = get(args, 2, nothing)
        value = get(args, 3, nothing)
        key === nothing && error("set! with capture requires key")
        return QueryProperty(key, value, capture_id)
    else
        # Pattern-level: (#set! "key" "value")
        key = args[1]
        value = get(args, 2, nothing)
        return QueryProperty(key, value, nothing)
    end
end

# Parse #is?/#is-not? directive arguments into QueryProperty
# Formats:
#   (#is? @capture "property") - with explicit capture
#   (#is? "property") - property only, applies to pattern's captures
function parse_property_predicate(args::Vector{String})
    if isempty(args)
        error("is?/is-not? requires at least a property name")
    end

    # Check if first arg is capture reference (@capture_N) or property name
    if startswith(args[1], "@capture_")
        # Format: (#is? @capture "property")
        capture_id = parse(Int, args[1][10:end])
        key = get(args, 2, nothing)
        key === nothing && error("is?/is-not? with capture requires property name")
        value = get(args, 3, nothing)
    else
        # Format: (#is? property) - applies to pattern's captures
        capture_id = nothing
        key = args[1]
        value = get(args, 2, nothing)
    end

    return QueryProperty(key, value, capture_id)
end

"""
    property_settings(q::Query, pattern_index::Int) -> Vector{QueryProperty}

Get all properties set by `(#set! key value)` directives for the given pattern (1-indexed).
Returns empty vector if no properties set for this pattern.

# Example
```julia
q = Query(:julia, \"\"\"
    ((identifier) @var
     (#set! "priority" "100")
     (#set! "scope" "local"))
\"\"\")
props = property_settings(q, 1)  # [QueryProperty("priority", "100", nothing), ...]
```
"""
property_settings(q::Query, pattern_index::Int) = q.property_settings[pattern_index]

"""
    property_predicates(q::Query, pattern_index::Int) -> Vector{Tuple{QueryProperty,Bool}}

Get property assertions (`#is?`/`#is-not?`) for the given pattern (1-indexed).
Bool indicates positive (true for `#is?`) or negative (false for `#is-not?`) assertion.
Returns empty vector if no property assertions for this pattern.

# Example
```julia
q = Query(:julia, \"\"\"
    ((identifier) @var
     (#is? @var "named"))
\"\"\")
props = property_predicates(q, 1)  # [(QueryProperty("named", nothing, nothing), true)]
```
"""
property_predicates(q::Query, pattern_index::Int) = q.property_predicates[pattern_index]

macro query_cmd(body, language = error("no language provided in query"))
    # Convert short name "julia" to module name :tree_sitter_julia_jll
    modname = Symbol("tree_sitter_", language, "_jll")
    # Look up in caller's scope
    return :(Query($(esc(modname)), $(esc(body))))
end

pattern_count(q::Query) = Int(API.ts_query_pattern_count(q.ptr))
capture_count(q::Query) = Int(API.ts_query_capture_count(q.ptr))
string_count(q::Query) = Int(API.ts_query_string_count(q.ptr))

"""
    start_byte_for_pattern(q::Query, pattern::Integer) -> Int

1-based byte offset where the 1-based `pattern` starts in the query source.
"""
start_byte_for_pattern(q::Query, pattern::Integer) =
    Int(API.ts_query_start_byte_for_pattern(q.ptr, pattern - 1)) + 1

"""
    disable_pattern!(q::Query, pattern::Integer) -> Query

Disable the 1-based `pattern` so it produces no matches. Irreversible.
"""
disable_pattern!(q::Query, pattern::Integer) =
    (API.ts_query_disable_pattern(q.ptr, pattern - 1); q)

"""
    disable_capture!(q::Query, name::AbstractString) -> Query

Disable a capture by name so it is dropped from results. Irreversible.
"""
disable_capture!(q::Query, name::AbstractString) =
    (API.ts_query_disable_capture(q.ptr, String(name), sizeof(name)); q)

mutable struct QueryCursor
    ptr::Ptr{API.TSQueryCursor}
    tree::Union{Tree,Nothing}

    function QueryCursor()
        ptr = API.ts_query_cursor_new()
        cursor = new(ptr, nothing)
        finalizer(c -> API.ts_query_cursor_delete(c.ptr), cursor)
        return cursor
    end
end
Base.show(io::IO, ::QueryCursor) = print(io, "QueryCursor()")

exec(c::QueryCursor, q::Query, n::Node) =
    (c.tree = n.tree; API.ts_query_cursor_exec(c.ptr, q.ptr, n.ptr); c)
exec(c::QueryCursor, q::Query, t::Tree) = (c.tree = t; exec(c, q, root(t)); c)

Base.eachmatch(query::Query, tree::Tree) = exec(QueryCursor(), query, tree)

function Base.iterate(cursor::QueryCursor, state = nothing)
    result = next_match(cursor)
    return result === nothing ? nothing : (result, nothing)
end

# The number of matches is only known by exhausting the cursor; each QueryMatch now owns a
# copy of its captures, so collecting/retaining matches is safe.
Base.IteratorSize(::Type{QueryCursor}) = Base.SizeUnknown()
Base.eltype(::Type{QueryCursor}) = QueryMatch

mutable struct QueryMatch
    id::UInt32
    pattern_index::UInt16
    # Eager copy of the captures. The C `captures` pointer is owned by the cursor and is
    # invalidated by the next `next_match`/`next_capture`, so we copy it out immediately to
    # keep retained matches safe after the cursor advances.
    captures::Vector{API.TSQueryCapture}
    tree::Tree
end

# Build a QueryMatch from a raw TSQueryMatch, copying its captures while the C pointer is
# still valid.
function QueryMatch(obj::API.TSQueryMatch, tree::Tree)
    caps = [unsafe_load(obj.captures, i) for i = 1:Int(obj.capture_count)]
    return QueryMatch(obj.id, obj.pattern_index, caps, tree)
end

capture_count(qm::QueryMatch) = length(qm.captures)

function next_match(cursor::QueryCursor)
    match_ref = Ref{API.TSQueryMatch}()
    success = API.ts_query_cursor_next_match(cursor.ptr, match_ref)
    return success ? QueryMatch(match_ref[], cursor.tree) : nothing
end

"""
    set_byte_range!(c::QueryCursor, from, to) -> QueryCursor
    set_point_range!(c::QueryCursor, from::API.TSPoint, to::API.TSPoint) -> QueryCursor

Restrict the cursor's matches to a range. Call before `exec`. Byte offsets are 1-based;
points are 0-based `TSPoint` values.
"""
# `byte_range` returns inclusive 1-based (from, to); tree-sitter wants a half-open 0-based
# [start, end) range, so the exclusive end is `to`, not `to - 1`. Passing `to - 1` would
# turn `to == 1` into C end_byte 0, which tree-sitter reinterprets as "unbounded".
set_byte_range!(c::QueryCursor, from::Integer, to::Integer) =
    (API.ts_query_cursor_set_byte_range(c.ptr, from - 1, to); c)
set_point_range!(c::QueryCursor, from::API.TSPoint, to::API.TSPoint) =
    (API.ts_query_cursor_set_point_range(c.ptr, from, to); c)

"""
    remove_match!(c::QueryCursor, id::Integer) -> QueryCursor

Drop the match with the given id so the cursor will not return it.
"""
remove_match!(c::QueryCursor, id::Integer) =
    (API.ts_query_cursor_remove_match(c.ptr, id); c)

"""
    next_capture(c::QueryCursor) -> Union{Tuple{QueryMatch,Int},Nothing}

The next capture in document order as a `(match, index)` pair where `index` is 1-based
into the match's captures, or `nothing` when exhausted. Requires a prior `exec`.
"""
function next_capture(cursor::QueryCursor)
    match_ref = Ref{API.TSQueryMatch}()
    index_ref = Ref{UInt32}()
    success = API.ts_query_cursor_next_capture(cursor.ptr, match_ref, index_ref)
    return success ? (QueryMatch(match_ref[], cursor.tree), Int(index_ref[]) + 1) : nothing
end

struct QueryCapture
    node::Node
    id::UInt32
    pattern_index::UInt16  # Pattern this capture belongs to (for property lookup)
end

function captures(qm::QueryMatch)
    fn = function (ith)
        cap = qm.captures[ith]
        node = Node(cap.node, qm.tree)
        return QueryCapture(node, cap.index, qm.pattern_index)
    end
    return (fn(i) for i = 1:capture_count(qm))
end

function capture_name(q::Query, qc::QueryCapture)
    unsafe_string(API.ts_query_capture_name_for_id(q.ptr, qc.id, Ref{UInt32}()))
end

"""
    property(q::Query, m::QueryMatch, key::String) -> Union{String,Nothing}

Get a match-level property value, or `nothing` if not set.
Convenience accessor for properties on QueryMatch.

# Example
```julia
for m in eachmatch(query, tree)
    priority = property(query, m, "priority")  # "100" or nothing
end
```
"""
function property(q::Query, m::QueryMatch, key::String)
    props = property_settings(q, Int(m.pattern_index) + 1)  # C uses 0-based
    for prop in props
        if prop.key == key && prop.capture_id === nothing
            return prop.value
        end
    end
    return nothing
end

"""
    property(q::Query, c::QueryCapture, key::String) -> Union{String,Nothing}

Get a capture-level property value, or `nothing` if not set.
First checks for capture-specific properties, then falls back to pattern-level.

# Example
```julia
for c in each_capture(tree, query, source)
    scope = property(query, c, "scope")  # "local" or nothing
end
```
"""
function property(q::Query, c::QueryCapture, key::String)
    props = property_settings(q, Int(c.pattern_index) + 1)  # C uses 0-based

    # First check for capture-specific property
    for prop in props
        if prop.key == key && prop.capture_id == Int(c.id)
            return prop.value
        end
    end

    # Fall back to pattern-level property
    for prop in props
        if prop.key == key && prop.capture_id === nothing
            return prop.value
        end
    end

    return nothing
end

query_string(q, id) =
    unsafe_string(API.ts_query_string_value_for_id(q.ptr, id, Ref{UInt32}()))

# A single predicate from a query pattern: its name, the resolved string
# arguments, the captured nodes among those arguments, and every value bound to
# each captured argument (a capture may be quantified and match several nodes).
# `arg_is_capture` runs parallel to `args`: true where the argument came from a
# capture, false for a string literal. Predicates that need the literal (e.g.
# #is?) use it to tell a property name from captured node text.
struct PredicateCall
    func::String
    args::Vector{String}
    arg_is_capture::Vector{Bool}
    nodes::Vector{Node}
    capture_args::Dict{Int,Vector{String}}
end

# Compile a predicate regex, warning and returning `nothing` (rather than
# throwing) when the pattern is not valid for Julia's regex engine.
function _try_regex(pat::AbstractString)
    try
        return Regex(pat)
    catch
        @warn "invalid regex in predicate: $(repr(pat))"
        return nothing
    end
end

# Decode tree-sitter's flat predicate-step stream for a match into one
# PredicateCall per predicate. A capture step contributes the text of every node
# it binds; the first value also enters `args` so non-quantified predicates read
# it positionally. A string step names the predicate (first) or adds a literal
# argument. A done step closes the current predicate.
function parse_predicate_calls(q::Query, m::QueryMatch, source::AbstractString)
    len = Ref{UInt32}()
    ptr = API.ts_query_predicates_for_pattern(q.ptr, m.pattern_index, len)
    calls = PredicateCall[]
    func, args, arg_is_capture, nodes = "", String[], Bool[], Node[]
    capture_args = Dict{Int,Vector{String}}()
    for i = 1:len[]
        step = unsafe_load(ptr, i)
        if step.type === API.TSQueryPredicateStepTypeCapture
            arg_idx = length(args) + 1
            values, capture_nodes = String[], Node[]
            for address = 1:capture_count(m)
                capture = m.captures[address]
                if capture.index == step.value_id
                    node = Node(capture.node, m.tree)
                    push!(values, slice(source, node))
                    push!(capture_nodes, node)
                end
            end
            if !isempty(values)
                push!(args, values[1])
                push!(arg_is_capture, true)
                push!(nodes, capture_nodes[1])
                capture_args[arg_idx] = values
            end
        elseif step.type === API.TSQueryPredicateStepTypeString
            str = query_string(q, step.value_id)
            if func == ""
                func = str
            else
                push!(args, str)
                push!(arg_is_capture, false)
            end
        elseif step.type === API.TSQueryPredicateStepTypeDone
            push!(
                calls,
                PredicateCall(
                    func,
                    copy(args),
                    copy(arg_is_capture),
                    copy(nodes),
                    copy(capture_args),
                ),
            )
            func = ""
            empty!(args)
            empty!(arg_is_capture)
            empty!(nodes)
            empty!(capture_args)
        else
            error("unreachable reached")
        end
    end
    return calls
end

# Warn and return false when a predicate has the wrong number of arguments.
function check_arity(c::PredicateCall, n::Integer)
    length(c.args) == n && return true
    @warn "incorrect number of arguments to '$(c.func)', expected $n"
    return false
end

function check_min_arity(c::PredicateCall, n::Integer)
    length(c.args) >= n && return true
    @warn "incorrect number of arguments to '$(c.func)', expected at least $n"
    return false
end

eval_eq(c::PredicateCall) = check_arity(c, 2) && c.args[1] == c.args[2]
eval_not_eq(c::PredicateCall) = check_arity(c, 2) && c.args[1] != c.args[2]

function eval_match(c::PredicateCall; negate::Bool)
    check_arity(c, 2) || return false
    rx = _try_regex(c.args[2])
    rx === nothing && return false
    matched = occursin(rx, c.args[1])
    return negate ? !matched : matched
end

function eval_any_of(c::PredicateCall)
    check_min_arity(c, 2) || return false
    capture_value = c.args[1]
    return any(arg -> arg == capture_value, c.args[2:end])
end

# A quantified predicate tests one capture, which may match several nodes,
# against literal comparison values. The capture is the first argument (every
# tree-sitter binding requires this); the comparison values follow. With no
# capture argument, the first argument stands in as the sole tested value.
function quantified_args(c::PredicateCall)
    values = get(c.capture_args, 1, [c.args[1]])
    return (values, c.args[2:end])
end

function eval_any_eq(c::PredicateCall)
    check_min_arity(c, 2) || return false
    values, comparison = quantified_args(c)
    return any(cv -> cv in comparison, values)
end

function eval_any_not_eq(c::PredicateCall)
    check_min_arity(c, 2) || return false
    values, comparison = quantified_args(c)
    return any(cv -> cv ∉ comparison, values)
end

function eval_any_match(c::PredicateCall)
    check_arity(c, 2) || return false
    values, comparison = quantified_args(c)
    pattern = _try_regex(comparison[1])
    pattern === nothing && return false
    return any(cv -> occursin(pattern, cv), values)
end

function eval_any_not_match(c::PredicateCall)
    check_arity(c, 2) || return false
    values, comparison = quantified_args(c)
    pattern = _try_regex(comparison[1])
    pattern === nothing && return false
    return any(cv -> !occursin(pattern, cv), values)
end

function eval_has_ancestor(c::PredicateCall)
    check_min_arity(c, 2) || return false
    if isempty(c.nodes)
        @warn "'$(c.func)' requires access to node structure"
        return false
    end
    ancestor_types = c.args[2:end]
    current = parent(c.nodes[1])
    while !is_null(current)
        node_type(current) in ancestor_types && return true
        current = parent(current)
    end
    return false
end

# Built-in property checks (`named`, `missing`, `extra`). The property is the
# string-literal argument, not captured node text, so select the first
# non-capture arg. The node tested is an explicit capture's node, else the
# match's first capture; bail out (rather than read out of bounds) when neither
# exists. Unknown properties (e.g. `local` from locals.scm) are no-ops that keep
# the pattern, so both `is?` and `is-not?` return true for them.
function eval_is(c::PredicateCall, m::QueryMatch; negate::Bool)
    lit_idx = findfirst(!, c.arg_is_capture)
    property_name = lit_idx === nothing ? "" : c.args[lit_idx]
    node =
        !isempty(c.nodes) ? c.nodes[1] :
        capture_count(m) > 0 ? Node(m.captures[1].node, m.tree) : nothing
    if isempty(property_name)
        @warn "'$(c.func)' missing property name"
        return false
    elseif node === nothing
        @warn "'$(c.func)' requires a captured node"
        return false
    end
    held = if property_name == "named"
        is_named(node)
    elseif property_name == "missing"
        is_missing(node)
    elseif property_name == "extra"
        is_extra(node)
    else
        return true
    end
    return negate ? !held : held
end

# Predicate names follow the tree-sitter rust library. `set!` is a metadata
# directive parsed at construction, so as a filter it always passes.
function eval_predicate(c::PredicateCall, m::QueryMatch)
    if c.func == "eq?"
        eval_eq(c)
    elseif c.func == "not-eq?"
        eval_not_eq(c)
    elseif c.func == "any-of?"
        eval_any_of(c)
    elseif c.func == "has-ancestor?"
        eval_has_ancestor(c)
    elseif c.func == "is?"
        eval_is(c, m; negate = false)
    elseif c.func == "is-not?"
        eval_is(c, m; negate = true)
    elseif c.func == "match?"
        eval_match(c; negate = false)
    elseif c.func == "not-match?"
        eval_match(c; negate = true)
    elseif c.func == "any-eq?"
        eval_any_eq(c)
    elseif c.func == "any-not-eq?"
        eval_any_not_eq(c)
    elseif c.func == "any-match?"
        eval_any_match(c)
    elseif c.func == "any-not-match?"
        eval_any_not_match(c)
    elseif c.func == "set!"
        true
    else
        @warn "unknown predicate function '$(c.func)'"
        false
    end
end

# A match satisfies a pattern when every predicate passes. Evaluation
# short-circuits on the first failure.
predicate(q::Query, m::QueryMatch, source::AbstractString) =
    all(c -> eval_predicate(c, m), parse_predicate_calls(q, m, source))

function each_capture(tree::Tree, query::Query, source::AbstractString)
    return (
        c for m in eachmatch(query, tree) for
        c in captures(m) if predicate(query, m, source)
    )
end

function tokens(parser::Parser, query::Query, source::AbstractString)
    out = Tuple{String,String}[]
    tree = parse(parser, source)
    for m in eachmatch(query, tree)
        if predicate(query, m, source)
            for c in captures(m)
                id = capture_name(query, c)
                text = slice(source, c.node)
                push!(out, (text, id))
            end
        end
    end
    return out
end
