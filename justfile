# Show available recipes
help:
    @just --list

# Install dependencies for changelog script
changelog-install:
    julia --project=.ci -e 'using Pkg; Pkg.instantiate()'

# Update changelog link references
changelog-links:
    julia --project=.ci .ci/changelog.jl

# Format code with JuliaFormatter
format:
    julia --project=.ci -e 'using JuliaFormatter; format(".")'

# Run test suite
test:
    julia --project=. -e 'using Pkg; Pkg.test()'
