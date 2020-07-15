#
# Language
#

mutable struct Language
    name::Symbol
    ptr::Ptr{API.TSLanguage}
    Language(name::Symbol) = new(name, API.lang_ptr(name))
end
Base.show(io::IO, l::Language) = print(io, "Language(", l.name, ")")

#
# Parser
#

mutable struct Parser
    language::Language
    ptr::Ptr{API.TSParser}
    function Parser(lang::Language)
        parser = new(lang, API.ts_parser_new())
        finalizer(p -> API.ts_parser_delete(p.ptr), parser)
        set_language!(parser, lang)
        return parser
    end
    Parser(name::Symbol) = Parser(Language(name))
end
Base.show(io::IO, p::Parser) = print(io, "Parser(", p.language, ")")

function set_language!(parser::Parser, language::Language)
    API.ts_parser_set_language(parser.ptr, language.ptr)
    parser.language = language
    return parser
end

Base.parse(p::Parser, text::AbstractString) = Tree(API.ts_parser_parse_string(p.ptr, C_NULL, text, sizeof(text)))

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

root(t::Tree) = Node(API.ts_tree_root_node(t.ptr))

traverse(f, tree::Tree, iter=children) = traverse(f, root(tree), iter)

#
# Node
#

struct Node
    ptr::API.TSNode
    Node(ptr::API.TSNode) = new(ptr)
end
Base.show(io::IO, n::Node) = print(io, node_string(n))

node_string(n::Node) = unsafe_string(API.ts_node_string(n.ptr))
node_symbol(n::Node) = API.ts_node_symbol(n.ptr)
node_type(n::Node) = unsafe_string(API.ts_node_type(n.ptr))

is_null(n::Node) = API.ts_node_is_null(n.ptr)
is_named(n::Node) = API.ts_node_is_named(n.ptr)
is_missing(n::Node) = API.ts_node_is_missing(n.ptr)
is_extra(n::Node) = API.ts_node_is_extra(n.ptr)
is_leaf(n::Node) = iszero(count_nodes(n))

count_nodes(n::Node) = Int(API.ts_node_child_count(n.ptr))
count_named_nodes(n::Node) = Int(API.ts_node_named_child_count(n.ptr))

child(n::Node, nth::Integer) = Node(API.ts_node_child(n.ptr, nth-1))
named_child(n::Node, nth::Integer) = Node(API.ts_node_named_child(n.ptr, nth-1))

children(n::Node) = (child(n, ind) for ind = 1:count_nodes(n))
named_children(n::Node) = (named_child(n, ind) for ind = 1:count_named_nodes(n))

function traverse(f, n::Node, iter=children, depth=0)
    for child in iter(n)
        f(child, true, depth)
        traverse(f, child, iter, depth + 1)
        f(child, false, depth)
    end
end

Base.:(==)(left::Node, right::Node) = API.ts_node_eq(left.ptr, right.ptr)

byte_range(n::Node) = (Int(API.ts_node_start_byte(n.ptr)) + 1, Int(API.ts_node_end_byte(n.ptr)))

slice(src::AbstractString, n::Node) = slice(src, byte_range(n))
slice(src::AbstractString, (from, to)) = SubString(src, from, thisind(src, to))

child(n::Node, name::AbstractString) = Node(API.ts_node_child_by_field_name(n.ptr, String(name), sizeof(name)))

#
# Query
#

struct QueryException <: Exception
    msg::String
end

mutable struct Query
    language::Language
    ptr::Ptr{API.TSQuery}

    function Query(language::Language, source::AbstractString)
        error_offset_ref = Ref{UInt32}()
        error_type_ref = Ref{API.TSQueryError}()
        ptr = API.ts_query_new(language.ptr, String(source), sizeof(source), error_offset_ref, error_type_ref)
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
            query = new(language, ptr)
            finalizer(q -> API.ts_query_delete(q.ptr), query)
            return query
        end
    end
    Query(language::Symbol, source::AbstractString) = Query(Language(language), source)
end
Base.show(io::IO, q::Query) = print(io, "Query(", q.language, ")")

macro query_cmd(body, language=error("no language provided in query"))
    return :(Query($(esc(Meta.quot(Symbol(language)))), $(esc(body))))
end

pattern_count(q::Query) = Int(API.ts_query_pattern_count(q.ptr))
capture_count(q::Query) = Int(API.ts_query_capture_count(q.ptr))
string_count(q::Query) = Int(API.ts_query_string_count(q.ptr))

mutable struct QueryCursor
    ptr::Ptr{API.TSQueryCursor}

    function QueryCursor()
        ptr = API.ts_query_cursor_new()
        cursor = new(ptr)
        finalizer(c -> API.ts_query_cursor_delete(c.ptr), cursor)
        return cursor
    end
end
Base.show(io::IO, ::QueryCursor) = print(io, "QueryCursor()")

exec(cursor::QueryCursor, query::Query, node::Node) = API.ts_query_cursor_exec(cursor.ptr, query.ptr, node.ptr)
exec(cursor::QueryCursor, query::Query, tree::Tree) = exec(cursor, query, root(tree))

struct QueryMatch
    obj::API.TSQueryMatch
end

capture_count(qm::QueryMatch) = Int(qm.obj.capture_count)

captures(qm::QueryMatch) = (Node(unsafe_load(qm.obj.captures, i).node) for i = 1:capture_count(qm))

function next_match(cursor::QueryCursor)
    match_ref = Ref{API.TSQueryMatch}()
    success = API.ts_query_cursor_next_match(cursor.ptr, match_ref)
    return success ? QueryMatch(match_ref[]) : nothing
end

struct QueryPredicate
    steps::Vector{API.TSQueryPredicateStep}
    function QueryPredicate(query::Query, match::QueryMatch)
        pattern_index = match.obj.pattern_index
        len = Ref{UInt32}()
        ptr = API.ts_query_predicates_for_pattern(query.ptr, pattern_index, len)
        return new(collect(unsafe_load(ptr, i) for i = 1:len[]))
    end
end
Base.show(io::IO, qp::QueryPredicate) = print(io, "QueryPredicate(length=$(length(qp.steps)))")

function exec(query::Query, qp::QueryPredicate)

end

match_name(q::Query, m::QueryMatch) = unsafe_string(API.ts_query_capture_name_for_id(q.ptr, m.obj.id, Ref{UInt32}()))
