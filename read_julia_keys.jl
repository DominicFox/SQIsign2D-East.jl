import Pkg
Pkg.activate(@__DIR__)
using Nemo
using SQIsign2D
using Serialization

vault = deserialize("sqisign2deast_key_vault.jls")
println("Keys in vault: ", keys(vault))