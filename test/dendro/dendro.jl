# Run Dendro over TreeSitter.jl's own source so complexity and structural smells
# cannot regress unnoticed. This lives in a separate environment
# (test/dendro/Project.toml) and a separate CI job because Dendro is unregistered,
# sourced from git, and needs Julia 1.12, none of which belong in the main test env.
#
# The gate mirrors Dendro's own self-analysis: absolute :high bands plus presence
# flags, none of which depend on the corpus distribution, so the result is
# deterministic. Percentile flags surface the top of a distribution and are not
# part of the gate.
#
# Tuned for a C-binding package, this deviates from the REPLicant template in two
# ways: SMELL_METRICS drops :low_cohesion, and FLAG_METRICS drops :duplicate and
# :near_duplicate. The thin C-API forwarders (ts_* ccall wrappers, the
# children/named_children and descendant_for_* pairs, the goto_*! family,
# predicate-eval pairs) are near-identical by idiom, not by accident, and trip
# those metrics without signalling a real smell.

using Dendro

# Genuine complexity smells, plus the naturalness floor, checked on their absolute
# :high band only.
const SMELL_METRICS = (
    :cyclomatic,
    :cognitive_complexity,
    :nesting_depth,
    :function_length,
    :boolean_complexity,
    :unnatural,
)

# Presence-based flags: stubs, swallowed errors, empty bodies, returns that discard
# errors from a finally clause, and identical operands or duplicated branches.
const FLAG_METRICS = (
    :stub_marker,
    :empty_catch,
    :empty_body,
    :return_in_finally,
    :identical_operands,
    :duplicate_branches,
)

srcdir = normpath(joinpath(@__DIR__, "..", "..", "src"))
findings = Dendro.active(Dendro.analyze(srcdir))

gating = filter(findings) do f
    (f.absolute == :high && f.metric in SMELL_METRICS) || f.metric in FLAG_METRICS
end

if isempty(gating)
    println("Dendro analysis clean: $(length(findings)) active finding(s), none gating.")
else
    println(stderr, "Dendro analysis: $(length(gating)) gating finding(s) over $srcdir:\n")
    for f in gating
        band = f.absolute == :high ? " [high]" : ""
        for loc in f.locations
            println(stderr, "  $(f.metric)$band  $(loc.file):$(loc.line)  $(loc.unit)")
        end
    end
    exit(1)
end
