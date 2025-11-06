#
# Language
#

mutable struct Language
    name::Symbol
    ptr::Ptr{API.TSLanguage}
    queries::Dict{String,String}

    function Language(jll_mod::Module)
        name = API.extract_lang_name(jll_mod)
        ptr = API.get_lang_ptr(jll_mod)
        queries = API.load_queries(jll_mod)
        new(name, ptr, queries)
    end

    function Language(name::Symbol)
        Base.depwarn(
            "Symbol-based Language construction is deprecated. " *
            "Please pass the JLL module directly: Language(tree_sitter_$(name)_jll)",
            :Language;
            force = true,
        )

        # Look up the JLL module using Base.identify_package
        pkg_name = "tree_sitter_$(name)_jll"
        pkg_id = Base.identify_package(pkg_name)

        if pkg_id === nothing
            error(
                "Language package '$pkg_name' not found. Please add and import it first:\n" *
                "  using tree_sitter_$(name)_jll",
            )
        end

        jll_mod = Base.root_module(pkg_id)
        return Language(jll_mod)
    end
end
Base.show(io::IO, l::Language) = print(io, "Language(", repr(l.name), ")")

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
    Parser(jll_mod::Module) = Parser(Language(jll_mod))
    Parser(name::Symbol) = Parser(Language(name))
end
Base.show(io::IO, p::Parser) = print(io, "Parser(", p.language, ")")

function set_language!(parser::Parser, language::Language)
    API.ts_parser_set_language(parser.ptr, language.ptr)
    parser.language = language
    return parser
end

Base.parse(p::Parser, text::AbstractString) =
    Tree(API.ts_parser_parse_string(p.ptr, C_NULL, text, sizeof(text)))

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

node_string(n::Node) = (ensure_not_null(n); unsafe_string(API.ts_node_string(n.ptr)))
node_symbol(n::Node) = (ensure_not_null(n); API.ts_node_symbol(n.ptr))
node_type(n::Node) = (ensure_not_null(n); unsafe_string(API.ts_node_type(n.ptr)))

is_null(n::Node) = API.ts_node_is_null(n.ptr)
is_named(n::Node) = API.ts_node_is_named(n.ptr)
is_missing(n::Node) = API.ts_node_is_missing(n.ptr)
is_extra(n::Node) = API.ts_node_is_extra(n.ptr)
is_leaf(n::Node) = iszero(count_nodes(n))

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

#
# Query
#

struct QueryException <: Exception
    msg::String
end

mutable struct Query
    language::Language
    ptr::Ptr{API.TSQuery}

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
            query = new(language, ptr)
            finalizer(q -> API.ts_query_delete(q.ptr), query)
            return query
        end
    end
    Query(jll_mod::Module, source) = Query(Language(jll_mod), source)
    Query(language::Symbol, source) = Query(Language(language), source)

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

macro query_cmd(body, language = error("no language provided in query"))
    # Convert short name "julia" to module name :tree_sitter_julia_jll
    modname = Symbol("tree_sitter_", language, "_jll")
    # Look up in caller's scope
    return :(Query($(esc(modname)), $(esc(body))))
end

pattern_count(q::Query) = Int(API.ts_query_pattern_count(q.ptr))
capture_count(q::Query) = Int(API.ts_query_capture_count(q.ptr))
string_count(q::Query) = Int(API.ts_query_string_count(q.ptr))

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

mutable struct QueryMatch
    obj::API.TSQueryMatch
    tree::Tree
end

capture_count(qm::QueryMatch) = Int(qm.obj.capture_count)

function next_match(cursor::QueryCursor)
    match_ref = Ref{API.TSQueryMatch}()
    success = API.ts_query_cursor_next_match(cursor.ptr, match_ref)
    return success ? QueryMatch(match_ref[], cursor.tree) : nothing
end

struct QueryCapture
    node::Node
    id::UInt32
end

function captures(qm::QueryMatch)
    fn = function (ith)
        ptr = unsafe_load(qm.obj.captures, ith)
        node = Node(ptr.node, qm.tree)
        return QueryCapture(node, ptr.index)
    end
    return (fn(i) for i = 1:capture_count(qm))
end

function capture_name(q::Query, qc::QueryCapture)
    unsafe_string(API.ts_query_capture_name_for_id(q.ptr, qc.id, Ref{UInt32}()))
end

query_string(q, id) =
    unsafe_string(API.ts_query_string_value_for_id(q.ptr, id, Ref{UInt32}()))

function predicate(q::Query, m::QueryMatch, source::AbstractString)
    len = Ref{UInt32}()
    ptr = API.ts_query_predicates_for_pattern(q.ptr, m.obj.pattern_index, len)
    if len[] > 0
        func, args, nodes = "", [], []
        for i = 1:len[]
            step = unsafe_load(ptr, i)
            if step.type === API.TSQueryPredicateStepTypeCapture
                # Iterate over the captures rather than allocating a dict.
                for address = 1:capture_count(m)
                    capture = unsafe_load(m.obj.captures, address)
                    if capture.index == step.value_id
                        node = Node(capture.node, m.tree)
                        str = slice(source, node)
                        push!(args, str)
                        push!(nodes, node)
                        break
                    end
                end
            elseif step.type === API.TSQueryPredicateStepTypeString
                # Either a literal argument name, or predicate name.
                str = query_string(q, step.value_id)
                func == "" ? (func = str) : push!(args, str)
            elseif step.type === API.TSQueryPredicateStepTypeDone
                # This marks the end of an individual predicate. Check whether
                # we actually have enough arguments to call the predicate and
                # then continue.

                # Handle the following predicates. Source: tree-sitter rust lib.
                #
                #   - eq?
                #   - not-eq?
                #   - is?
                #   - is-not?
                #   - match?
                #   - any-of?
                #   - set!
                #
                result = if func == "eq?"
                    if length(args) != 2
                        @warn "incorrect number of arguments to '$func', expected 2"
                        false
                    else
                        left, right = args
                        left == right
                    end
                elseif func == "not-eq?"
                    if length(args) != 2
                        @warn "incorrect number of arguments to '$func', expected 2"
                        false
                    else
                        left, right = args
                        left != right
                    end
                elseif func == "any-of?"
                    if length(args) < 2
                        @warn "incorrect number of arguments to '$func', expected at least 2"
                        false
                    else
                        # First arg is the capture value, rest are possible matches
                        capture_value = args[1]
                        any(arg -> arg == capture_value, args[2:end])
                    end
                elseif func == "has-ancestor?"
                    if length(args) < 2
                        @warn "incorrect number of arguments to '$func', expected at least 2"
                        false
                    else
                        # First arg is the captured node (we need the node, not its text)
                        # Rest are node type names to check for in ancestors
                        if isempty(nodes)
                            @warn "'$func' requires access to node structure"
                            false
                        else
                            captured_node = nodes[1]
                            ancestor_types = args[2:end]

                            # Walk up the tree checking each ancestor
                            current = parent(captured_node)
                            found = false
                            while !is_null(current)
                                if node_type(current) in ancestor_types
                                    found = true
                                    break
                                end
                                current = parent(current)
                            end
                            found
                        end
                    end
                elseif func == "is?"
                    @warn "'$func' not implemented" # TODO
                    false
                elseif func == "is-not?"
                    @warn "'$func' not implemented" # TODO
                    false
                elseif func == "match?"
                    if length(args) != 2
                        @warn "incorrect number of arguments to '$func', expected 2"
                        false
                    else
                        arg_1, arg_2 = args
                        occursin(Regex(arg_2), arg_1)
                    end
                elseif func == "set!"
                    @warn "'$func' not implemented" # TODO
                    false
                else
                    # Invalid predicate functions will fail with a warning:
                    @warn "unknown predicate function '$func'"
                    false
                end
                if result
                    # Success, reset for the next predicate.
                    func = ""
                    empty!(args)
                    empty!(nodes)
                else
                    # Failed to match the current predicate, so we can bale here.
                    return false
                end
            else
                # We really shouldn't get here if all is well.
                error("unreachable reached")
            end
        end
    end
    return true
end

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
