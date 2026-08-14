#
# Language injection
#
# Parsing embedded languages: JavaScript/CSS in HTML, PHP in HTML, heredocs and
# phpdoc in PHP, regex and jsdoc in JavaScript. A grammar's `injections.scm`
# marks the embedded regions with `@injection.content` and names the language
# either statically (`#set! injection.language "..."`) or dynamically (the text
# of an `@injection.language` capture). All layers share one source string; a
# sub-parse positioned with `set_included_ranges!` keeps its node offsets in the
# original document's coordinate space.
#

#
# Layer 1 — range ergonomics
#

"""
    ts_range(n::Node) -> API.TSRange

Build the raw 0-based `API.TSRange` (byte and point fields) spanning `n`, ready for
`set_included_ranges!`. Bridges the 1-based `Node`/`byte_range` world and the 0-based C
range world.
"""
function ts_range(n::Node)
    from, to = byte_range(n)
    return API.TSRange(start_point(n), end_point(n), UInt32(from - 1), UInt32(to))
end

"""
    ts_range(start_byte::Integer, end_byte::Integer, s::API.TSPoint, e::API.TSPoint) -> API.TSRange

Construct a range from explicit 0-based half-open byte bounds and 0-based points.
"""
ts_range(start_byte::Integer, end_byte::Integer, s::API.TSPoint, e::API.TSPoint) =
    API.TSRange(s, e, UInt32(start_byte), UInt32(end_byte))

#
# Layer 2 — injection site analysis
#

"""
    InjectionSite

One embedded-language region set discovered by an injections query. Does not parse.

- `language`: injection name as written or derived (e.g. `"javascript"`, `"HTML"`).
- `ranges`: 0-based, sorted, disjoint `API.TSRange`s to inject into.
- `combined`: `#set! injection.combined` was present.
- `include_children`: `#set! injection.include-children` was present.
- `pattern_index`: 1-based query pattern that produced this site.
- `content_nodes`: the `@injection.content` node(s).
- `language_node`: the `@injection.language` node for a dynamic language, else `nothing`.
"""
struct InjectionSite
    language::String
    ranges::Vector{API.TSRange}
    combined::Bool
    include_children::Bool
    pattern_index::Int
    content_nodes::Vector{Node}
    language_node::Union{Node,Nothing}
end

Base.show(io::IO, s::InjectionSite) =
    print(io, "InjectionSite(", repr(s.language), ", ", length(s.ranges), " ranges)")

# 0-based half-open bounds of a node as (start_byte, end_byte, start_point, end_point).
function _node_bounds(n::Node)
    from, to = byte_range(n)
    return (from - 1, to, start_point(n), end_point(n))
end

# Apply a single-line #offset! delta (Δstart_row, Δstart_col, Δend_row, Δend_col) to a
# node's bounds. Columns are byte columns, so byte and column deltas coincide. Multi-line
# offsets are unsupported and fall back to the unadjusted bounds.
function _apply_offset(bounds, off)
    off === nothing && return bounds
    sb, eb, sp, ep = bounds
    dsr, dsc, der, dec = off
    if dsr != 0 || der != 0
        @warn "TreeSitter: multi-line #offset! is unsupported; using unadjusted range" maxlog =
            1
        return bounds
    end
    nsp = API.TSPoint(sp.row, UInt32(Int(sp.column) + dsc))
    nep = API.TSPoint(ep.row, UInt32(Int(ep.column) + dec))
    return (sb + dsc, eb + dec, nsp, nep)
end

# Ranges to inject for one content node. With `include_children` (or a childless node) the
# whole content node is injected; otherwise every child is punched out, leaving only the gaps
# between them (tree-sitter's `intersect_ranges`, which excludes all children, not only named).
function content_ranges(node::Node, include_children::Bool, off = nothing)
    sb, eb, sp, ep = _apply_offset(_node_bounds(node), off)
    (include_children || count_nodes(node) == 0) && return [ts_range(sb, eb, sp, ep)]
    out = API.TSRange[]
    cur_byte, cur_pt = sb, sp
    for c in children(node)
        cf, _ = byte_range(c)
        cb0 = cf - 1
        cb0 > cur_byte && push!(out, ts_range(cur_byte, cb0, cur_pt, start_point(c)))
        cur_byte, cur_pt = _node_bounds(c)[2], end_point(c)
    end
    eb > cur_byte && push!(out, ts_range(cur_byte, eb, cur_pt, ep))
    return out
end

# Static #set! injection.language, else dynamic @injection.language capture text, else nothing.
function _site_language(props, language_node, source)
    for p in props
        p.key == "injection.language" && p.value !== nothing && return p.value
    end
    language_node !== nothing && return String(slice(source, language_node))
    return nothing
end

# (target_node, deltas) pairs for every #offset! directive on this match.
function _match_offsets(query::Query, m::QueryMatch, source::AbstractString)
    offs = Tuple{Node,NTuple{4,Int}}[]
    for c in parse_predicate_calls(query, m, source)
        c.func == "offset!" || continue
        length(c.args) >= 5 && !isempty(c.nodes) || continue
        push!(offs, (c.nodes[1], ntuple(i -> Base.parse(Int, c.args[i+1]), 4)))
    end
    return offs
end

function _offset_for(offs, node::Node)
    for (n, d) in offs
        n == node && return d
    end
    return nothing
end

"""
    injection_sites(query::Query, tree::Tree, source::AbstractString) -> Vector{InjectionSite}
    injection_sites(lang::Language, tree, source)
    injection_sites(parser::Parser, tree, source)

Run the injections `query` against `tree` and return the embedded-language regions it
describes, resolving static and dynamic languages, honoring `#eq?`/`#match?` gating,
`injection.combined`, `injection.include-children`, and single-line `#offset!`. Does not
parse the regions; see [`parse_injected`](@ref).
"""
function injection_sites(query::Query, tree::Tree, source::AbstractString)
    sites = InjectionSite[]
    combined = Dict{Int,InjectionSite}()
    for m in eachmatch(query, tree)
        site = _match_site(query, m, source)
        site === nothing && continue
        site.combined ? _accumulate_combined!(combined, site) : push!(sites, site)
    end
    for site in values(combined)
        unique!(sort!(site.ranges, by = r -> r.start_byte))
        push!(sites, site)
    end
    sort!(sites, by = s -> isempty(s.ranges) ? typemax(UInt32) : s.ranges[1].start_byte)
    return sites
end

# The @injection.content nodes and the first @injection.language node of a match.
function _match_captures(query::Query, m::QueryMatch)
    content_nodes = Node[]
    language_node = nothing
    for cap in captures(m)
        name = capture_name(query, cap)
        if name == "injection.content"
            push!(content_nodes, cap.node)
        elseif name == "injection.language" && language_node === nothing
            language_node = cap.node
        end
    end
    return content_nodes, language_node
end

# Non-empty injection ranges for a match's content nodes, offsets applied.
function _site_ranges(content_nodes, include_children, offs)
    ranges = API.TSRange[]
    for cn in content_nodes
        for r in content_ranges(cn, include_children, _offset_for(offs, cn))
            r.end_byte > r.start_byte && push!(ranges, r)
        end
    end
    return ranges
end

# One InjectionSite for a match, or nothing when it is gated out, has no content, or
# resolves to no language or no ranges.
function _match_site(query::Query, m::QueryMatch, source::AbstractString)
    predicate(query, m, source) || return nothing
    content_nodes, language_node = _match_captures(query, m)
    isempty(content_nodes) && return nothing
    pidx = Int(m.pattern_index) + 1
    props = property_settings(query, pidx)
    language = _site_language(props, language_node, source)
    language === nothing && return nothing
    include_children = any(p -> p.key == "injection.include-children", props)
    ranges = _site_ranges(content_nodes, include_children, _match_offsets(query, m, source))
    isempty(ranges) && return nothing
    combined = any(p -> p.key == "injection.combined", props)
    return InjectionSite(
        language,
        sort!(ranges, by = r -> r.start_byte),
        combined,
        include_children,
        pidx,
        content_nodes,
        language_node,
    )
end

# Merge a combined site into the accumulator keyed by pattern, mutating the stored vectors.
function _accumulate_combined!(combined, site::InjectionSite)
    prev = get(combined, site.pattern_index, nothing)
    if prev === nothing
        combined[site.pattern_index] = site
    else
        append!(prev.ranges, site.ranges)
        append!(prev.content_nodes, site.content_nodes)
    end
    return combined
end
injection_sites(lang::Language, tree::Tree, source::AbstractString) =
    injection_sites(Query(lang, ["injections"]), tree, source)
injection_sites(parser::Parser, tree::Tree, source::AbstractString) =
    injection_sites(parser.language, tree, source)


#
# Layer 3 — recursive injected parse
#

# The compiled injections query per grammar. `Query(lang, ["injections"])` is a function of
# the language alone: the source it reads is loaded once, when the `Language` is built. It
# was compiled once per layer per parse instead, which put a query compile on the parse path
# of every file.
#
# Keyed by language rather than by parser or by caller, because that is what the value
# depends on. `_inject!` recurses into a child layer and asks again for *that* layer's
# language, so anything keyed further out would cover the top layer alone and a document
# embedding three languages would keep compiling per layer per parse.
#
# Entries live for the process, deliberately. One query per grammar ever loaded is bounded
# by the grammars a program uses, and a `Query` holds its own `Language`, so weak keys would
# keep every entry reachable and buy nothing. Identity-keyed: a `Language` wraps a grammar
# pointer, and two of them built from one grammar are two caches, not a collision.
const _INJECTION_QUERY_CACHE = IdDict{Language,Union{Query,Nothing}}()

# Guards both grammar-derived caches. `parse` runs on whatever thread its caller is on, and
# `get!` on a shared dictionary corrupts it when two of them resize it at once, so an entry
# is taken under this rather than left to a race that looks benign until it is not.
const _GRAMMAR_LOCK = ReentrantLock()

# A layer's injections query, compiled on first use and reused after. A compiled `Query` is
# immutable once constructed (its predicates are parsed there, and a `QueryCursor` carries
# the per-match state), so one shared across concurrent parses is safe.
_injection_query(lang::Language) = lock(_GRAMMAR_LOCK) do
    get!(() -> _compile_injection_query(lang), _INJECTION_QUERY_CACHE, lang)
end

# Compile a layer's injections query, or nothing when the grammar ships none. A query that
# does not compile warns and yields nothing; cached, so a broken grammar warns once rather
# than once per parse.
function _compile_injection_query(lang::Language)
    src = get(lang.queries, "injections", "")
    isempty(strip(src)) && return nothing
    try
        return Query(lang, ["injections"])
    catch e
        e isa QueryException || rethrow()
        @warn "TreeSitter: failed to compile injections query for $(lang.name)" exception =
            e
        return nothing
    end
end

_span(ranges) = (ranges[1].start_byte, maximum(r -> r.end_byte, ranges))

"""
    INJECTION_ALIASES :: Dict{String,Symbol}

Maps lowercased injection language names to grammar symbols for
[`default_language_resolver`](@ref).
"""
const INJECTION_ALIASES = Dict{String,Symbol}(
    "js" => :javascript,
    "javascript" => :javascript,
    "ts" => :typescript,
    "typescript" => :typescript,
    "c" => :c,
    "cpp" => :cpp,
    "c++" => :cpp,
    "cxx" => :cpp,
    "css" => :css,
    "html" => :html,
    "py" => :python,
    "python" => :python,
    "rb" => :ruby,
    "ruby" => :ruby,
    "rs" => :rust,
    "rust" => :rust,
    "sh" => :bash,
    "bash" => :bash,
    "go" => :go,
    "java" => :java,
    "json" => :json,
    "php" => :php,
    "regex" => :regex,
    "jsdoc" => :jsdoc,
    "phpdoc" => :phpdoc,
)

const _LANGUAGE_CACHE = Dict{Symbol,Union{Language,Nothing}}()

# Map an injection name to a grammar symbol, applying INJECTION_ALIASES case-insensitively.
_injection_symbol(name::AbstractString) =
    get(INJECTION_ALIASES, lowercase(strip(name)), Symbol(lowercase(strip(name))))

"""
    default_language_resolver(name::AbstractString) -> Union{Language,Nothing}

Map an injection language `name` to a `Language`, or `nothing` when its grammar is not
available. Applies [`INJECTION_ALIASES`](@ref) then `Language(sym)`, caching results. This
is the dynamic resolution a `Parser` uses when it was not given an explicit `languages` set.
"""
function default_language_resolver(name::AbstractString)
    sym = _injection_symbol(name)
    # Under `_GRAMMAR_LOCK` for the reason the injections query is: a nested injection
    # resolves its grammar during a parse, so two threads parsing at once enter this
    # dictionary at once.
    return lock(_GRAMMAR_LOCK) do
        get!(_LANGUAGE_CACHE, sym) do
            try
                Language(sym)
            catch
                nothing
            end
        end
    end
end

# Resolve an injection name to a grammar. A parser given an explicit `languages` set resolves
# only within it (no dynamic loading); otherwise it resolves dynamically.
function resolve_injection_language(parser::Parser, name::AbstractString)
    parser.injections === nothing && return default_language_resolver(name)
    return get(parser.injections, _injection_symbol(name), nothing)
end

"""
    resolve_injections!(tree::Tree, parser::Parser, max_depth::Integer) -> Tree

Populate `tree.children` with the layers for every language embedded in `tree.source`, up to
`max_depth` levels, and record sites that could not be parsed in `tree.unresolved`. Called by
[`parse`](@ref); a grammar that declares no injections leaves `tree` a single layer.
"""
function resolve_injections!(tree::Tree, parser::Parser, max_depth::Integer)
    isempty(tree.source) && return tree
    _inject!(
        tree,
        parser,
        0,
        max_depth,
        Set{Tuple{Symbol,UInt32,UInt32}}(),
        tree.unresolved,
    )
    return tree
end

# Build one layer's children, appending unparseable sites to the shared `unresolved`
# accumulator (the root tree's vector, so the root aggregates the whole recursion).
function _inject!(tree::Tree, parser::Parser, depth, max_depth, visited, unresolved)
    query = _injection_query(tree.language)
    query === nothing && return tree
    for site in injection_sites(query, tree, tree.source)
        record(reason) =
            push!(unresolved, UnresolvedInjection(site.language, site.ranges, reason))
        if depth >= max_depth
            record(:depth_limit)
            continue
        end
        sublang = resolve_injection_language(parser, site.language)
        if sublang === nothing
            record(:unavailable)
            continue
        end
        # A layer's own (language, span) is in `visited`, so an injection that repeats it is
        # caught here as a cycle.
        span = (sublang.name, _span(site.ranges)...)
        if span in visited
            record(:cycle)
            continue
        end
        subparser = Parser(sublang)
        subparser.injections = parser.injections
        try
            set_included_ranges!(subparser, site.ranges)
        catch e
            e isa ArgumentError || rethrow()
            record(:overlapping)
            continue
        end
        subptr = API.ts_parser_parse_string(
            subparser.ptr,
            C_NULL,
            tree.source,
            sizeof(tree.source),
        )
        child = _tree(subptr, sublang, tree.source, site.ranges, site.combined)
        _inject!(
            child,
            subparser,
            depth + 1,
            max_depth,
            union(visited, (span,)),
            unresolved,
        )
        push!(tree.children, child)
    end
    return tree
end

#
# Injection tree accessors
#

"""
    layers(tree::Tree) -> Vector{Tree}

Every layer of `tree`, depth-first with the root first.
"""
function layers(tree::Tree)
    out = Tree[]
    walk(t) = (push!(out, t); foreach(walk, t.children))
    walk(tree)
    return out
end

"""
    layer_at(tree::Tree, byte::Integer) -> Tree

The deepest layer whose ranges contain the 1-based `byte`. `tree` itself is returned when no
deeper layer matches.
"""
function layer_at(tree::Tree, byte::Integer)
    b = UInt32(byte - 1)
    best = tree
    function descend(t)
        for c in t.children
            if any(r -> r.start_byte <= b < r.end_byte, c.ranges)
                best = c
                descend(c)
            end
        end
    end
    descend(tree)
    return best
end

"""
    slice(tree::Tree) -> AbstractString

The source text `tree` covers: the whole source for the root, otherwise its ranges joined.
"""
function slice(tree::Tree)
    isempty(tree.ranges) && return tree.source
    return join(
        slice(tree.source, (Int(r.start_byte) + 1, Int(r.end_byte))) for r in tree.ranges
    )
end
