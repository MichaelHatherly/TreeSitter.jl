#
# Language
#

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
    Parser(jll_mod::Module, variant::Union{Symbol,Nothing} = nothing) =
        Parser(Language(jll_mod, variant))
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
    n_patterns = pattern_count(q)

    for pattern_idx = 1:n_patterns
        len = Ref{UInt32}()
        # Get predicate steps for this pattern (0-based C API)
        ptr = API.ts_query_predicates_for_pattern(q.ptr, pattern_idx - 1, len)

        if len[] > 0
            # Parse predicate steps into structured metadata
            # Steps alternate: predicate name (string), arguments (captures/strings), DONE marker
            func = ""
            args = String[]

            for i = 1:len[]
                step = unsafe_load(ptr, i)

                if step.type === API.TSQueryPredicateStepTypeString
                    # String argument or predicate name
                    str = query_string(q, step.value_id)
                    func == "" ? (func = str) : push!(args, str)

                elseif step.type === API.TSQueryPredicateStepTypeCapture
                    # Capture reference - store as "@capturename" for now
                    # TODO: track capture indices for quantified predicates
                    push!(args, "@capture_$(step.value_id)")

                elseif step.type === API.TSQueryPredicateStepTypeDone
                    # End of one predicate - route to appropriate storage
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
                    # Other predicates (#eq?, #match?, etc.) handled at match-time in predicate()

                    # Reset for next predicate
                    func = ""
                    empty!(args)
                end
            end
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
    pattern_index::UInt16  # Pattern this capture belongs to (for property lookup)
end

function captures(qm::QueryMatch)
    fn = function (ith)
        ptr = unsafe_load(qm.obj.captures, ith)
        node = Node(ptr.node, qm.tree)
        return QueryCapture(node, ptr.index, qm.obj.pattern_index)
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
    props = property_settings(q, Int(m.obj.pattern_index) + 1)  # C uses 0-based
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

function predicate(q::Query, m::QueryMatch, source::AbstractString)
    len = Ref{UInt32}()
    ptr = API.ts_query_predicates_for_pattern(q.ptr, m.obj.pattern_index, len)
    if len[] > 0
        func, args, nodes = "", [], []
        # Track which args are captures and store ALL their values
        capture_args = Dict{Int,Vector{String}}()  # arg_index => [all values for this capture]
        capture_nodes = Dict{Int,Vector{Node}}()

        for i = 1:len[]
            step = unsafe_load(ptr, i)
            if step.type === API.TSQueryPredicateStepTypeCapture
                # Collect ALL matching captures, not just first
                arg_idx = length(args) + 1
                values = String[]
                nodes_for_capture = Node[]

                for address = 1:capture_count(m)
                    capture = unsafe_load(m.obj.captures, address)
                    if capture.index == step.value_id
                        node = Node(capture.node, m.tree)
                        str = slice(source, node)
                        push!(values, str)
                        push!(nodes_for_capture, node)
                    end
                end

                # Store first value in args for backwards compatibility with non-quantified predicates
                if !isempty(values)
                    push!(args, values[1])
                    push!(nodes, nodes_for_capture[1])
                    capture_args[arg_idx] = values
                    capture_nodes[arg_idx] = nodes_for_capture
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
                    # Check if node has built-in property: named, missing, extra
                    # Formats:
                    #   (#is? @capture "property") - property is second arg
                    #   (#is? property) - property is first arg (no capture ref)
                    if isempty(args)
                        @warn "incorrect number of arguments to '$func', expected property name"
                        false
                    else
                        # Property is first arg if no capture ref, second if capture ref present
                        property_name =
                            startswith(args[1], "@") ? get(args, 2, "") : args[1]
                        if isempty(property_name)
                            @warn "'$func' missing property name"
                            false
                        else
                            # For single-arg format, use match's first capture if nodes is empty
                            check_nodes = if isempty(nodes)
                                [Node(unsafe_load(m.obj.captures, 1).node, m.tree)]
                            else
                                nodes
                            end
                            node = check_nodes[1]
                            if property_name == "named"
                                is_named(node)
                            elseif property_name == "missing"
                                is_missing(node)
                            elseif property_name == "extra"
                                is_extra(node)
                            else
                                # Unknown properties (e.g., "local" from locals.scm) are treated as no-ops
                                # to preserve backwards compatibility with upstream queries. The property
                                # assertion is still stored in property_predicates for inspection.
                                # Returning true prevents filtering the pattern.
                                true
                            end
                        end
                    end
                elseif func == "is-not?"
                    # Negated property check
                    # Formats:
                    #   (#is-not? @capture "property") - property is second arg
                    #   (#is-not? property) - property is first arg (no capture ref)
                    if isempty(args)
                        @warn "incorrect number of arguments to '$func', expected property name"
                        false
                    else
                        # Property is first arg if no capture ref, second if capture ref present
                        property_name =
                            startswith(args[1], "@") ? get(args, 2, "") : args[1]
                        if isempty(property_name)
                            @warn "'$func' missing property name"
                            false
                        else
                            # For single-arg format, use match's first capture if nodes is empty
                            check_nodes = if isempty(nodes)
                                [Node(unsafe_load(m.obj.captures, 1).node, m.tree)]
                            else
                                nodes
                            end
                            node = check_nodes[1]
                            if property_name == "named"
                                !is_named(node)
                            elseif property_name == "missing"
                                !is_missing(node)
                            elseif property_name == "extra"
                                !is_extra(node)
                            else
                                # Unknown properties (e.g., "local" from locals.scm) are treated as no-ops.
                                # Returning true (property not set) preserves backwards compatibility with
                                # upstream queries like (#is-not? local) which expect non-local identifiers
                                # to match. The property assertion is stored in property_predicates.
                                true
                            end
                        end
                    end
                elseif func == "match?"
                    if length(args) != 2
                        @warn "incorrect number of arguments to '$func', expected 2"
                        false
                    else
                        arg_1, arg_2 = args
                        occursin(Regex(arg_2), arg_1)
                    end
                elseif func == "not-match?"
                    # Negated regex match
                    if length(args) != 2
                        @warn "incorrect number of arguments to '$func', expected 2"
                        false
                    else
                        arg_1, arg_2 = args
                        !occursin(Regex(arg_2), arg_1)
                    end
                elseif func == "any-eq?"
                    # Quantified equality: check if ANY captured value equals ANY comparison value
                    # Format: (#any-eq? @capture "value1" "value2" ...)
                    if length(args) < 2
                        @warn "incorrect number of arguments to '$func', expected at least 2"
                        false
                    else
                        # Get all values for the first capture (which may be quantified)
                        all_capture_values = get(capture_args, 1, [args[1]])
                        comparison_values = args[2:end]
                        # Check if ANY captured value equals ANY comparison value
                        any(cv -> cv in comparison_values, all_capture_values)
                    end
                elseif func == "any-not-eq?"
                    # Quantified inequality: check if ANY captured value doesn't equal ALL comparison values
                    if length(args) < 2
                        @warn "incorrect number of arguments to '$func', expected at least 2"
                        false
                    else
                        all_capture_values = get(capture_args, 1, [args[1]])
                        comparison_values = args[2:end]
                        # Check if ANY captured value is not in comparison values
                        any(cv -> cv ∉ comparison_values, all_capture_values)
                    end
                elseif func == "any-match?"
                    # Quantified regex: check if ANY captured value matches regex
                    # Format: (#any-match? @capture "pattern")
                    if length(args) != 2
                        @warn "incorrect number of arguments to '$func', expected 2"
                        false
                    else
                        # Get all values for the first capture
                        all_capture_values = get(capture_args, 1, [args[1]])
                        pattern = Regex(args[2])
                        # Check if ANY value matches the pattern
                        any(cv -> occursin(pattern, cv), all_capture_values)
                    end
                elseif func == "any-not-match?"
                    # Quantified negated regex: check if ANY captured value doesn't match regex
                    # Format: (#any-not-match? @capture "pattern")
                    if length(args) != 2
                        @warn "incorrect number of arguments to '$func', expected 2"
                        false
                    else
                        all_capture_values = get(capture_args, 1, [args[1]])
                        pattern = Regex(args[2])
                        # Check if ANY value doesn't match the pattern
                        any(cv -> !occursin(pattern, cv), all_capture_values)
                    end
                elseif func == "set!"
                    # Metadata directive, not a filter - always returns true
                    # Metadata already parsed at construction and accessible via property_settings()
                    true
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
