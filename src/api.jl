module API

import TreeSitter
import tree_sitter_jll

using CEnum
using Libdl

const libtreesitter = tree_sitter_jll.libtreesitter_path

# Structs

const TREE_SITTER_LANGUAGE_VERSION = 11
const TREE_SITTER_MIN_COMPATIBLE_LANGUAGE_VERSION = 9
const TSSymbol = UInt16
const TSFieldId = UInt16

struct TSSymbolMetadata
    visible::Cint
    named::Cint
end

struct ANONYMOUS3_reduce
    symbol::TSSymbol
    dynamic_precedence::Int16
    child_count::UInt8
    production_id::UInt8
end

struct ANONYMOUS2_params
    reduce::ANONYMOUS3_reduce
end

@cenum TSParseActionType::UInt32 begin
    TSParseActionTypeShift = 0
    TSParseActionTypeReduce = 1
    TSParseActionTypeAccept = 2
    TSParseActionTypeRecover = 3
end

struct TSParseAction
    params::ANONYMOUS2_params
    type::TSParseActionType
end

struct TSParseActionEntry
    action::TSParseAction
end

struct TSLexMode
    lex_state::UInt16
    external_lex_state::UInt16
end

struct ANONYMOUS1_external_scanner
    states::Ptr{Cint}
    symbol_map::Ptr{TSSymbol}
    create::Ptr{Cvoid}
    destroy::Ptr{Cvoid}
    bool::Cvoid
    serialize::Ptr{Cvoid}
    deserialize::Ptr{Cvoid}
end

struct TSFieldMapSlice
    index::UInt16
    length::UInt16
end

struct TSFieldMapEntry
    field_id::TSFieldId
    child_index::UInt8
    inherited::Cint
end

struct TSLanguage
    version::UInt32
    symbol_count::UInt32
    alias_count::UInt32
    token_count::UInt32
    external_token_count::UInt32
    symbol_names::Ptr{Cstring}
    symbol_metadata::Ptr{TSSymbolMetadata}
    parse_table::Ptr{UInt16}
    parse_actions::Ptr{TSParseActionEntry}
    lex_modes::Ptr{TSLexMode}
    alias_sequences::Ptr{TSSymbol}
    max_alias_sequence_length::UInt16
    bool::Cvoid
    keyword_capture_token::TSSymbol
    external_scanner::ANONYMOUS1_external_scanner
    field_count::UInt32
    field_map_slices::Ptr{TSFieldMapSlice}
    field_map_entries::Ptr{TSFieldMapEntry}
    field_names::Ptr{Cstring}
    large_state_count::UInt32
    small_parse_table::Ptr{UInt16}
    small_parse_table_map::Ptr{UInt32}
    public_symbol_map::Ptr{TSSymbol}
end

const TSParser = Cvoid
const TSTree = Cvoid
const TSQuery = Cvoid
const TSQueryCursor = Cvoid

@cenum TSInputEncoding::UInt32 begin
    TSInputEncodingUTF8 = 0
    TSInputEncodingUTF16 = 1
end

@cenum TSSymbolType::UInt32 begin
    TSSymbolTypeRegular = 0
    TSSymbolTypeAnonymous = 1
    TSSymbolTypeAuxiliary = 2
end

struct TSPoint
    row::UInt32
    column::UInt32
end

struct TSRange
    start_point::TSPoint
    end_point::TSPoint
    start_byte::UInt32
    end_byte::UInt32
end

struct TSInput
    payload::Ptr{Cvoid}
    read::Ptr{Cvoid}
    encoding::TSInputEncoding
end

@cenum TSLogType::UInt32 begin
    TSLogTypeParse = 0
    TSLogTypeLex = 1
end

struct TSLogger
    payload::Ptr{Cvoid}
    log::Ptr{Cvoid}
end

struct TSInputEdit
    start_byte::UInt32
    old_end_byte::UInt32
    new_end_byte::UInt32
    start_point::TSPoint
    old_end_point::TSPoint
    new_end_point::TSPoint
end

struct TSNode
    context::NTuple{4,UInt32}
    id::Ptr{Cvoid}
    tree::Ptr{TSTree}
end

struct TSTreeCursor
    tree::Ptr{Cvoid}
    id::Ptr{Cvoid}
    context::NTuple{2,UInt32}
end

struct TSQueryCapture
    node::TSNode
    index::UInt32
end

struct TSQueryMatch
    id::UInt32
    pattern_index::UInt16
    capture_count::UInt16
    captures::Ptr{TSQueryCapture}
end

@cenum TSQueryPredicateStepType::UInt32 begin
    TSQueryPredicateStepTypeDone = 0
    TSQueryPredicateStepTypeCapture = 1
    TSQueryPredicateStepTypeString = 2
end

struct TSQueryPredicateStep
    type::TSQueryPredicateStepType
    value_id::UInt32
end

@cenum TSQueryError::UInt32 begin
    TSQueryErrorNone = 0
    TSQueryErrorSyntax = 1
    TSQueryErrorNodeType = 2
    TSQueryErrorField = 3
    TSQueryErrorCapture = 4
end

const ts_builtin_sym_end = 0
const TREE_SITTER_SERIALIZATION_BUFFER_SIZE = 1024

const TSStateId = UInt16

struct TSLexer
    lookahead::Int32
    result_symbol::TSSymbol
    advance::Ptr{Cvoid}
    mark_end::Ptr{Cvoid}
    get_column::Ptr{Cvoid}
    bool::Cvoid
end

struct ANONYMOUS4_external_scanner
    states::Ptr{Cint}
    symbol_map::Ptr{TSSymbol}
    create::Ptr{Cvoid}
    destroy::Ptr{Cvoid}
    bool::Cvoid
    serialize::Ptr{Cvoid}
    deserialize::Ptr{Cvoid}
end

# Functions

function ts_parser_new()
    ccall((:ts_parser_new, libtreesitter), Ptr{TSParser}, ())
end

function ts_parser_delete(self)
    ccall((:ts_parser_delete, libtreesitter), Cvoid, (Ptr{TSParser},), self)
end

function ts_parser_set_language(self, lang)
    ccall(
        (:ts_parser_set_language, libtreesitter),
        Cint,
        (Ptr{TSParser}, Ptr{TSLanguage}),
        self,
        lang,
    )
end

function ts_parser_language(self)
    ccall((:ts_parser_language, libtreesitter), Ptr{TSLanguage}, (Ptr{TSParser},), self)
end

function ts_parser_set_included_ranges()
    ccall((:ts_parser_set_included_ranges, libtreesitter), Cint, ())
end

function ts_parser_included_ranges(self, length)
    ccall(
        (:ts_parser_included_ranges, libtreesitter),
        Ptr{TSRange},
        (Ptr{TSParser}, Ptr{UInt32}),
        self,
        length,
    )
end

function ts_parser_parse(self, old_tree, input)
    ccall(
        (:ts_parser_parse, libtreesitter),
        Ptr{TSTree},
        (Ptr{TSParser}, Ptr{TSTree}, TSInput),
        self,
        old_tree,
        input,
    )
end

function ts_parser_parse_string(self, old_tree, string, length)
    ccall(
        (:ts_parser_parse_string, libtreesitter),
        Ptr{TSTree},
        (Ptr{TSParser}, Ptr{TSTree}, Cstring, UInt32),
        self,
        old_tree,
        string,
        length,
    )
end

function ts_parser_parse_string_encoding(self, old_tree, string, length, encoding)
    ccall(
        (:ts_parser_parse_string_encoding, libtreesitter),
        Ptr{TSTree},
        (Ptr{TSParser}, Ptr{TSTree}, Cstring, UInt32, TSInputEncoding),
        self,
        old_tree,
        string,
        length,
        encoding,
    )
end

function ts_parser_reset(self)
    ccall((:ts_parser_reset, libtreesitter), Cvoid, (Ptr{TSParser},), self)
end

function ts_parser_set_timeout_micros(self, timeout)
    ccall(
        (:ts_parser_set_timeout_micros, libtreesitter),
        Cvoid,
        (Ptr{TSParser}, UInt64),
        self,
        timeout,
    )
end

function ts_parser_timeout_micros(self)
    ccall((:ts_parser_timeout_micros, libtreesitter), UInt64, (Ptr{TSParser},), self)
end

function ts_parser_set_cancellation_flag(self, flag)
    ccall(
        (:ts_parser_set_cancellation_flag, libtreesitter),
        Cvoid,
        (Ptr{TSParser}, Ptr{Cint}),
        self,
        flag,
    )
end

function ts_parser_cancellation_flag()
    ccall((:ts_parser_cancellation_flag, libtreesitter), Ptr{Cint}, ())
end

function ts_parser_set_logger(self, logger)
    ccall(
        (:ts_parser_set_logger, libtreesitter),
        Cvoid,
        (Ptr{TSParser}, TSLogger),
        self,
        logger,
    )
end

function ts_parser_logger(self)
    ccall((:ts_parser_logger, libtreesitter), TSLogger, (Ptr{TSParser},), self)
end

function ts_parser_print_dot_graphs(self, file)
    ccall(
        (:ts_parser_print_dot_graphs, libtreesitter),
        Cvoid,
        (Ptr{TSParser}, Cint),
        self,
        file,
    )
end

function ts_tree_copy(self)
    ccall((:ts_tree_copy, libtreesitter), Ptr{TSTree}, (Ptr{TSTree},), self)
end

function ts_tree_delete(self)
    ccall((:ts_tree_delete, libtreesitter), Cvoid, (Ptr{TSTree},), self)
end

function ts_tree_root_node(self)
    ccall((:ts_tree_root_node, libtreesitter), TSNode, (Ptr{TSTree},), self)
end

function ts_tree_language(arg1)
    ccall((:ts_tree_language, libtreesitter), Ptr{TSLanguage}, (Ptr{TSTree},), arg1)
end

function ts_tree_edit(self, edit)
    ccall(
        (:ts_tree_edit, libtreesitter),
        Cvoid,
        (Ptr{TSTree}, Ptr{TSInputEdit}),
        self,
        edit,
    )
end

function ts_tree_get_changed_ranges(old_tree, new_tree, length)
    ccall(
        (:ts_tree_get_changed_ranges, libtreesitter),
        Ptr{TSRange},
        (Ptr{TSTree}, Ptr{TSTree}, Ptr{UInt32}),
        old_tree,
        new_tree,
        length,
    )
end

# TODO: handle FILE.
# function ts_tree_print_dot_graph(arg1, arg2)
#     ccall((:ts_tree_print_dot_graph, libtreesitter), Cvoid, (Ptr{TSTree}, Ptr{FILE}), arg1, arg2)
# end

function ts_node_type(arg1)
    ccall((:ts_node_type, libtreesitter), Cstring, (TSNode,), arg1)
end

function ts_node_symbol(arg1)
    ccall((:ts_node_symbol, libtreesitter), TSSymbol, (TSNode,), arg1)
end

function ts_node_start_byte(arg1)
    ccall((:ts_node_start_byte, libtreesitter), UInt32, (TSNode,), arg1)
end

function ts_node_start_point(arg1)
    ccall((:ts_node_start_point, libtreesitter), TSPoint, (TSNode,), arg1)
end

function ts_node_end_byte(arg1)
    ccall((:ts_node_end_byte, libtreesitter), UInt32, (TSNode,), arg1)
end

function ts_node_end_point(arg1)
    ccall((:ts_node_end_point, libtreesitter), TSPoint, (TSNode,), arg1)
end

function ts_node_string(self)
    ccall((:ts_node_string, libtreesitter), Cstring, (TSNode,), self)
end

function ts_node_is_null(self)
    ccall((:ts_node_is_null, libtreesitter), Bool, (TSNode,), self)
end

function ts_node_is_named(self)
    ccall((:ts_node_is_named, libtreesitter), Bool, (TSNode,), self)
end

function ts_node_is_missing(self)
    ccall((:ts_node_is_missing, libtreesitter), Bool, (TSNode,), self)
end

function ts_node_is_extra(self)
    ccall((:ts_node_is_extra, libtreesitter), Bool, (TSNode,), self)
end

function ts_node_has_changes(self)
    ccall((:ts_node_has_changes, libtreesitter), Bool, (TSNode,), self)
end

function ts_node_has_error(self)
    ccall((:ts_node_has_error, libtreesitter), Bool, (TSNode,), self)
end

function ts_node_parent(self)
    ccall((:ts_node_parent, libtreesitter), TSNode, (TSNode,), self)
end

function ts_node_child(self, nth)
    ccall((:ts_node_child, libtreesitter), TSNode, (TSNode, UInt32), self, nth)
end

function ts_node_child_count(self)
    ccall((:ts_node_child_count, libtreesitter), UInt32, (TSNode,), self)
end

function ts_node_named_child(self, nth)
    ccall((:ts_node_named_child, libtreesitter), TSNode, (TSNode, UInt32), self, nth)
end

function ts_node_named_child_count(self)
    ccall((:ts_node_named_child_count, libtreesitter), UInt32, (TSNode,), self)
end

function ts_node_child_by_field_name(self, field_name, field_name_length)
    ccall(
        (:ts_node_child_by_field_name, libtreesitter),
        TSNode,
        (TSNode, Cstring, UInt32),
        self,
        field_name,
        field_name_length,
    )
end

function ts_node_child_by_field_id(self, field_id)
    ccall(
        (:ts_node_child_by_field_id, libtreesitter),
        TSNode,
        (TSNode, TSFieldId),
        self,
        field_id,
    )
end

function ts_node_next_sibling(self)
    ccall((:ts_node_next_sibling, libtreesitter), TSNode, (TSNode,), self)
end

function ts_node_prev_sibling(self)
    ccall((:ts_node_prev_sibling, libtreesitter), TSNode, (TSNode,), self)
end

function ts_node_next_named_sibling(self)
    ccall((:ts_node_next_named_sibling, libtreesitter), TSNode, (TSNode,), self)
end

function ts_node_prev_named_sibling(self)
    ccall((:ts_node_prev_named_sibling, libtreesitter), TSNode, (TSNode,), self)
end

function ts_node_first_child_for_byte(self, byte)
    ccall(
        (:ts_node_first_child_for_byte, libtreesitter),
        TSNode,
        (TSNode, UInt32),
        self,
        byte,
    )
end

function ts_node_first_named_child_for_byte(self, byte)
    ccall(
        (:ts_node_first_named_child_for_byte, libtreesitter),
        TSNode,
        (TSNode, UInt32),
        self,
        byte,
    )
end

function ts_node_descendant_for_byte_range(self, byte_from, byte_to)
    ccall(
        (:ts_node_descendant_for_byte_range, libtreesitter),
        TSNode,
        (TSNode, UInt32, UInt32),
        self,
        byte_from,
        byte_to,
    )
end

function ts_node_descendant_for_point_range(self, point_from, point_to)
    ccall(
        (:ts_node_descendant_for_point_range, libtreesitter),
        TSNode,
        (TSNode, TSPoint, TSPoint),
        self,
        point_from,
        point_to,
    )
end

function ts_node_named_descendant_for_byte_range(self, byte_from, byte_to)
    ccall(
        (:ts_node_named_descendant_for_byte_range, libtreesitter),
        TSNode,
        (TSNode, UInt32, UInt32),
        self,
        byte_from,
        byte_to,
    )
end

function ts_node_named_descendant_for_point_range(self, point_from, point_to)
    ccall(
        (:ts_node_named_descendant_for_point_range, libtreesitter),
        TSNode,
        (TSNode, TSPoint, TSPoint),
        self,
        point_from,
        point_to,
    )
end

function ts_node_edit(arg1, arg2)
    ccall(
        (:ts_node_edit, libtreesitter),
        Cvoid,
        (Ptr{TSNode}, Ptr{TSInputEdit}),
        arg1,
        arg2,
    )
end

function ts_node_eq(left, right)
    ccall((:ts_node_eq, libtreesitter), Bool, (TSNode, TSNode), left, right)
end

function ts_tree_cursor_new(node)
    ccall((:ts_tree_cursor_new, libtreesitter), TSTreeCursor, (TSNode,), node)
end

function ts_tree_cursor_delete(cursor)
    ccall((:ts_tree_cursor_delete, libtreesitter), Cvoid, (Ptr{TSTreeCursor},), cursor)
end

function ts_tree_cursor_reset(cursor, node)
    ccall(
        (:ts_tree_cursor_reset, libtreesitter),
        Cvoid,
        (Ptr{TSTreeCursor}, TSNode),
        cursor,
        node,
    )
end

function ts_tree_cursor_current_node(cursor)
    ccall(
        (:ts_tree_cursor_current_node, libtreesitter),
        TSNode,
        (Ptr{TSTreeCursor},),
        cursor,
    )
end

function ts_tree_cursor_current_field_name(cursor)
    ccall(
        (:ts_tree_cursor_current_field_name, libtreesitter),
        Cstring,
        (Ptr{TSTreeCursor},),
        cursor,
    )
end

function ts_tree_cursor_current_field_id(cursor)
    ccall(
        (:ts_tree_cursor_current_field_id, libtreesitter),
        TSFieldId,
        (Ptr{TSTreeCursor},),
        cursor,
    )
end

function ts_tree_cursor_goto_parent(cursor)
    ccall((:ts_tree_cursor_goto_parent, libtreesitter), Cint, (Ptr{TSTreeCursor},), cursor)
end

function ts_tree_cursor_goto_next_sibling(cursor)
    ccall(
        (:ts_tree_cursor_goto_next_sibling, libtreesitter),
        Cint,
        (Ptr{TSTreeCursor},),
        cursor,
    )
end

function ts_tree_cursor_goto_first_child(cursor)
    ccall(
        (:ts_tree_cursor_goto_first_child, libtreesitter),
        Cint,
        (Ptr{TSTreeCursor},),
        cursor,
    )
end

function ts_tree_cursor_goto_first_child_for_byte(cursor, byte)
    ccall(
        (:ts_tree_cursor_goto_first_child_for_byte, libtreesitter),
        Int64,
        (Ptr{TSTreeCursor}, UInt32),
        cursor,
        byte,
    )
end

function ts_tree_cursor_copy(cursor)
    ccall((:ts_tree_cursor_copy, libtreesitter), TSTreeCursor, (Ptr{TSTreeCursor},), cursor)
end

function ts_query_new(language, source, source_len, error_offset, error_type)
    ccall(
        (:ts_query_new, libtreesitter),
        Ptr{TSQuery},
        (Ptr{TSLanguage}, Cstring, UInt32, Ptr{UInt32}, Ptr{TSQueryError}),
        language,
        source,
        source_len,
        error_offset,
        error_type,
    )
end

function ts_query_delete(query)
    ccall((:ts_query_delete, libtreesitter), Cvoid, (Ptr{TSQuery},), query)
end

function ts_query_pattern_count(query)
    ccall((:ts_query_pattern_count, libtreesitter), UInt32, (Ptr{TSQuery},), query)
end

function ts_query_capture_count(query)
    ccall((:ts_query_capture_count, libtreesitter), UInt32, (Ptr{TSQuery},), query)
end

function ts_query_string_count(query)
    ccall((:ts_query_string_count, libtreesitter), UInt32, (Ptr{TSQuery},), query)
end

function ts_query_start_byte_for_pattern(query, pattern)
    ccall(
        (:ts_query_start_byte_for_pattern, libtreesitter),
        UInt32,
        (Ptr{TSQuery}, UInt32),
        query,
        pattern,
    )
end

function ts_query_predicates_for_pattern(query, pattern_index, length)
    ccall(
        (:ts_query_predicates_for_pattern, libtreesitter),
        Ptr{TSQueryPredicateStep},
        (Ptr{TSQuery}, UInt32, Ptr{UInt32}),
        query,
        pattern_index,
        length,
    )
end

function ts_query_capture_name_for_id(query, id, length)
    ccall(
        (:ts_query_capture_name_for_id, libtreesitter),
        Cstring,
        (Ptr{TSQuery}, UInt32, Ptr{UInt32}),
        query,
        id,
        length,
    )
end

function ts_query_string_value_for_id(query, id, length)
    ccall(
        (:ts_query_string_value_for_id, libtreesitter),
        Cstring,
        (Ptr{TSQuery}, UInt32, Ptr{UInt32}),
        query,
        id,
        length,
    )
end

function ts_query_disable_capture(arg1, arg2, arg3)
    ccall(
        (:ts_query_disable_capture, libtreesitter),
        Cvoid,
        (Ptr{TSQuery}, Cstring, UInt32),
        arg1,
        arg2,
        arg3,
    )
end

function ts_query_disable_pattern(arg1, arg2)
    ccall(
        (:ts_query_disable_pattern, libtreesitter),
        Cvoid,
        (Ptr{TSQuery}, UInt32),
        arg1,
        arg2,
    )
end

function ts_query_cursor_new()
    ccall((:ts_query_cursor_new, libtreesitter), Ptr{TSQueryCursor}, ())
end

function ts_query_cursor_delete(cursor)
    ccall((:ts_query_cursor_delete, libtreesitter), Cvoid, (Ptr{TSQueryCursor},), cursor)
end

function ts_query_cursor_exec(cursor, query, node)
    ccall(
        (:ts_query_cursor_exec, libtreesitter),
        Cvoid,
        (Ptr{TSQueryCursor}, Ptr{TSQuery}, TSNode),
        cursor,
        query,
        node,
    )
end

function ts_query_cursor_set_byte_range(arg1, arg2, arg3)
    ccall(
        (:ts_query_cursor_set_byte_range, libtreesitter),
        Cvoid,
        (Ptr{TSQueryCursor}, UInt32, UInt32),
        arg1,
        arg2,
        arg3,
    )
end

function ts_query_cursor_set_point_range(arg1, arg2, arg3)
    ccall(
        (:ts_query_cursor_set_point_range, libtreesitter),
        Cvoid,
        (Ptr{TSQueryCursor}, TSPoint, TSPoint),
        arg1,
        arg2,
        arg3,
    )
end

function ts_query_cursor_next_match(cursor, match)
    ccall(
        (:ts_query_cursor_next_match, libtreesitter),
        Bool,
        (Ptr{TSQueryCursor}, Ptr{TSQueryMatch}),
        cursor,
        match,
    )
end

function ts_query_cursor_remove_match(arg1, id)
    ccall(
        (:ts_query_cursor_remove_match, libtreesitter),
        Cvoid,
        (Ptr{TSQueryCursor}, UInt32),
        arg1,
        id,
    )
end

function ts_query_cursor_next_capture()
    ccall((:ts_query_cursor_next_capture, libtreesitter), Cint, ())
end

function ts_language_symbol_count(lang)
    ccall((:ts_language_symbol_count, libtreesitter), UInt32, (Ptr{TSLanguage},), lang)
end

function ts_language_symbol_name(lang, sym)
    ccall(
        (:ts_language_symbol_name, libtreesitter),
        Cstring,
        (Ptr{TSLanguage}, TSSymbol),
        lang,
        sym,
    )
end

function ts_language_symbol_for_name(lang, string, length, is_named)
    ccall(
        (:ts_language_symbol_for_name, libtreesitter),
        TSSymbol,
        (Ptr{TSLanguage}, Cstring, UInt32, Cint),
        lang,
        string,
        length,
        is_named,
    )
end

function ts_language_field_count(lang)
    ccall((:ts_language_field_count, libtreesitter), UInt32, (Ptr{TSLanguage},), lang)
end

function ts_language_field_name_for_id(lang, field_id)
    ccall(
        (:ts_language_field_name_for_id, libtreesitter),
        Cstring,
        (Ptr{TSLanguage}, TSFieldId),
        lang,
        field_id,
    )
end

function ts_language_field_id_for_name(lang, name, name_length)
    ccall(
        (:ts_language_field_id_for_name, libtreesitter),
        TSFieldId,
        (Ptr{TSLanguage}, Cstring, UInt32),
        lang,
        name,
        name_length,
    )
end

function ts_language_symbol_type(lang, sym)
    ccall(
        (:ts_language_symbol_type, libtreesitter),
        TSSymbolType,
        (Ptr{TSLanguage}, TSSymbol),
        lang,
        sym,
    )
end

# Language

function extract_lang_name(jll_mod::Module)
    mod_name = string(nameof(jll_mod))
    m = match(r"^tree_sitter_(\w+)_jll$", mod_name)
    m === nothing &&
        error("Module name '$mod_name' does not match expected pattern 'tree_sitter_*_jll'")
    return Symbol(m.captures[1])
end

function get_lang_ptr(jll_mod::Module, variant::Union{Symbol,Nothing} = nothing)
    # Determine which parser to use
    if variant === nothing
        # Use default: extract from module name
        parser_name = string(extract_lang_name(jll_mod))
    else
        # Use specified variant
        parser_name = string(variant)
    end

    # Get library handle from JLL module (already opened by JLL)
    lib_handle_field = Symbol("libtreesitter_", parser_name, "_handle")
    if !isdefined(jll_mod, lib_handle_field)
        available = TreeSitter.list_parsers(jll_mod)
        error(
            "Parser variant ':$parser_name' not found in $(nameof(jll_mod)). " *
            "Available parsers: $available",
        )
    end
    lib_handle = getfield(jll_mod, lib_handle_field)

    # Get function pointer from the already-opened library
    func_name = "tree_sitter_$parser_name"
    func_ptr = dlsym(lib_handle, func_name)

    # Call to get TSLanguage pointer
    lang_ptr = ccall(func_ptr, Ptr{TSLanguage}, ())

    return lang_ptr
end

# Editor preference for selecting query directories when multiple exist
const EDITOR_PREFERENCE = ["neovim", "helix", "emacs", "zed"]

function load_queries(jll_mod::Module, variant::Union{Symbol,Nothing} = nothing)
    # Determine which parser variant to load queries for
    if variant === nothing
        parser_name = string(extract_lang_name(jll_mod))
    else
        parser_name = string(variant)
    end

    dict = Dict{String,String}()

    # Check for custom/vendored queries first
    custom = joinpath(@__DIR__, "queries", parser_name)

    # Use custom queries if available, otherwise use JLL queries
    if isdir(custom)
        base_dir = custom
    elseif isdefined(jll_mod, :artifact_dir)
        base_dir = joinpath(getfield(jll_mod, :artifact_dir), "queries")
    else
        return dict  # No queries available
    end

    !isdir(base_dir) && return dict

    # Find all directories containing .scm files
    candidates = find_query_dirs(base_dir)
    isempty(candidates) && return dict

    # Select best directory
    best_dir = select_best_query_dir(candidates, base_dir)

    # Load queries from selected directory
    for file in readdir(best_dir)
        path = joinpath(best_dir, file)
        if isfile(path)
            name, ext = splitext(file)
            ext == ".scm" && (dict[name] = read(path, String))
        end
    end

    return dict
end

function find_query_dirs(base_dir::String)
    dirs = String[]
    for (root, _, files) in walkdir(base_dir)
        if any(endswith(f, ".scm") for f in files)
            push!(dirs, root)
        end
    end
    return dirs
end

function select_best_query_dir(candidates::Vector{String}, base_dir::String)
    # Prefer root dir if it has queries
    base_dir in candidates && return base_dir

    # Count .scm files in each candidate
    scored = [(count_scm_files(d), editor_rank(d), d) for d in candidates]

    # Sort by: most files (descending), then editor preference (ascending)
    sort!(scored, by = x -> (-x[1], x[2]))

    return scored[1][3]
end

function count_scm_files(dir::String)
    count(f -> endswith(f, ".scm"), readdir(dir))
end

function editor_rank(dir::String)
    name = basename(dir)
    idx = findfirst(==(name), EDITOR_PREFERENCE)
    return idx === nothing ? length(EDITOR_PREFERENCE) + 1 : idx
end

end
