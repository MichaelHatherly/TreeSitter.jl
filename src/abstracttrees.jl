import AbstractTrees

AbstractTrees.children(n::Node) = TreeSitter.children(n)

function AbstractTrees.printnode(io::IO, n::Node)
    print(io, node_type(n))
end
