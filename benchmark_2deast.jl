# =====================================================================
# MSc Dissertation: SQISign2D-East Julia Telemetry Harness
# =====================================================================
# import Pkg
# Pkg.activate(@__DIR__)
# using Nemo
# using SQIsign2D
# using Serialization
# using SHA

# const LIB_MAC_OS = joinpath(@__DIR__, "libbench_macos.dylib")

# # Simple struct to hold our data before flushing to disk
# mutable struct TelemetryRow
#     key_index::UInt64
#     keygen_cycles::UInt64
#     sign_cycles::UInt64
#     verify_cycles::UInt64
# end

# function main()
#     iterations = 100
#     num_keys = 50
#     warmup_runs = 15
#     mode = 0
#     level = 1

#     # Parse the exact same command line arguments the Rust orchestrator sends
#     for arg in ARGS
#         if startswith(arg, "--iterations=")
#             iterations = parse(Int, split(arg, "=")[2])
#         elseif startswith(arg, "--keys=")
#             num_keys = parse(Int, split(arg, "=")[2])
#         elseif startswith(arg, "--warmup=")
#             warmup_runs = parse(Int, split(arg, "=")[2])
#         elseif startswith(arg, "--mode=")
#             mode = parse(Int, split(arg, "=")[2])
#         elseif startswith(arg, "--level=") # <-- 2. Catch the new flag
#             level = parse(Int, split(arg, "=")[2])
#         end
#     end

#     ccall((:macos_init_rdtsc, LIB_MAC_OS), Cvoid, ())

#     telemetry = TelemetryRow[]
#     msg = "dissertation_message"

#     # =========================================================
#     # CRYPTOGRAPHIC PARAMETER SETUP
#     # =========================================================
#     # Explicitly target Level 1 to match the 2D-West baseline
#     param = if level == 1
#         SQIsign2D.Level1
#     elseif level == 3
#         SQIsign2D.Level3
#     elseif level == 5
#         SQIsign2D.Level5
#     else
#         error("Unsupported NIST security level: $level")
#     end
#     is_compact = false
    
#     # Precompute global parameters BEFORE any timing starts
#     # println("[*] Precomputing Global Math Parameters...")
#     global_data = param.make_precomputed_values()

#     # =========================================================
#     # PHASE 1: MODE 0 (Key Generation)
#     # =========================================================
#     if mode == 0
#         println("    - Beginning Keygen...");
        
        
#         # 1. JIT WARMUP: Force LLVM to compile the math before we start the timer
#         for _ in 1:warmup_runs
#             pk, sk = param.key_gen(global_data)
#         end

#         # Determine expected byte size for the Rust orchestrator
#         expected_size = if level == 1 
#             64 
#         elseif level == 3 
#             96 
#         else 
#             128 
#         end

#         pk_exports = Vector{Vector{UInt8}}()
#         sk_exports = Vector{Vector{UInt8}}()
        
#         # --- NEW: The Julia Key Vault ---
#         # A dictionary mapping your key_index to the live Nemo objects
#         key_vault = Dict{UInt64, Tuple{Any, Any}}()

#         function extract_unique_id_bytes(obj, expected_size)
#             io = IOBuffer()
#             serialize(io, obj) 
#             fingerprint = sha512(take!(io))
            
#             padded = zeros(UInt8, expected_size)
#             for i in 1:expected_size
#                 padded[i] = fingerprint[((i - 1) % length(fingerprint)) + 1]
#             end
#             return padded
#         end

#         for i in 0:(num_keys-1)
#             GC.gc()
#             GC.enable(false)
            
#             t0 = ccall((:macos_rdtsc, LIB_MAC_OS), UInt64, ())
#             pk, sk = param.key_gen(global_data)
#             t1 = ccall((:macos_rdtsc, LIB_MAC_OS), UInt64, ())
            
#             GC.enable(true)

#             push!(telemetry, TelemetryRow(i, t1 - t0, 0, 0))

#             # 1. Satisfy the Rust Orchestrator (Telemetry)
#             push!(pk_exports, extract_unique_id_bytes(pk, expected_size))
#             push!(sk_exports, extract_unique_id_bytes(sk, expected_size))
            
#             # 2. Save the true mathematical objects for debugging
#             key_vault[UInt64(i)] = (pk, sk)
#         end

#         # Write binary telemetry for Rust
#         open("fixed_pk.bin", "w") do io for b in pk_exports write(io, b) end end
#         open("fixed_sk.bin", "w") do io for b in sk_exports write(io, b) end end
        
#         # Write the exact mathematical state to disk for Julia
#         open("sqisign2deast_key_vault.jls", "w") do io 
#             serialize(io, key_vault) 
#         end

#         println("    - Keygen Complete: $num_keys total keys.")

#     # =========================================================
#     # PHASE 2: MODE 1 (Signing & Verification)
#     # =========================================================
#     elseif mode == 1
#         println("    - Beginning Sign/Verify Loop...")
        
#         # Generate the keys we need for the loop (untimed)
#         keys = [param.key_gen(global_data) for _ in 1:num_keys]
        
#         # JIT WARMUP
#         warmup_pk, warmup_sk = keys[1]
#         for _ in 1:warmup_runs
#             sig = param.signing(warmup_pk, warmup_sk, msg, global_data, is_compact)
#             param.verify(warmup_pk, sig, msg, global_data)
#         end

#         for k in 0:(num_keys-1)
#             pk, sk = keys[k+1] # Julia is 1-indexed

#             # Trigger a manual garbage collection sweep before the deep loop
            

#             for i in 1:iterations
#                 GC.gc() 
#                 GC.enable(false)
                
#                 st0 = ccall((:macos_rdtsc, LIB_MAC_OS), UInt64, ())
#                 sig = param.signing(pk, sk, msg, global_data, is_compact)
#                 st1 = ccall((:macos_rdtsc, LIB_MAC_OS), UInt64, ())

#                 vt0 = ccall((:macos_rdtsc, LIB_MAC_OS), UInt64, ())
#                 valid = param.verify(pk, sig, msg, global_data)
#                 vt1 = ccall((:macos_rdtsc, LIB_MAC_OS), UInt64, ())
                
#                 GC.enable(true)

#                 if !valid error("Cryptographic failure!") end

#                 push!(telemetry, TelemetryRow(k, 0, st1 - st0, vt1 - vt0))
#             end
#         end
#         total_runs = num_keys * iterations
#         println("    - Sign/Verify Loops Complete: $total_runs total signatures.");

#     end

#     # =========================================================
#     # BINARY SERIALIZATION FOR RUST
#     # =========================================================
#     open("sqisign_telemetry.bin", "w") do io
#         for row in telemetry
#             write(io, row.key_index)
#             write(io, row.keygen_cycles)
#             write(io, row.sign_cycles)
#             write(io, row.verify_cycles)
#         end
#     end
# end

# main()

import Pkg
Pkg.activate(@__DIR__)
using Nemo
using SQIsign2D
using Serialization
using SHA

const LIB_MAC_OS = joinpath(@__DIR__, "libbench_macos.dylib")

# Simple struct to hold our data before flushing to disk
mutable struct TelemetryRow
    key_index::UInt64
    keygen_cycles::UInt64
    sign_cycles::UInt64
    verify_cycles::UInt64
end

function main()
    iterations = 100
    num_keys = 50
    warmup_runs = 15
    mode = 0
    level = 1

    # Parse the exact same command line arguments the Rust orchestrator sends
    for arg in ARGS
        if startswith(arg, "--iterations=")
            iterations = parse(Int, split(arg, "=")[2])
        elseif startswith(arg, "--keys=")
            num_keys = parse(Int, split(arg, "=")[2])
        elseif startswith(arg, "--warmup=")
            warmup_runs = parse(Int, split(arg, "=")[2])
        elseif startswith(arg, "--mode=")
            mode = parse(Int, split(arg, "=")[2])
        elseif startswith(arg, "--level=") 
            level = parse(Int, split(arg, "=")[2])
        end
    end

    ccall((:macos_init_rdtsc, LIB_MAC_OS), Cvoid, ())
    telemetry = TelemetryRow[]

    # =========================================================
    # CRYPTOGRAPHIC PARAMETER SETUP
    # =========================================================
    param = if level == 1
        SQIsign2D.Level1
    elseif level == 3
        SQIsign2D.Level3
    elseif level == 5
        SQIsign2D.Level5
    else
        error("Unsupported NIST security level: $level")
    end
    is_compact = false
    
    global_data = param.make_precomputed_values()

    # Determine expected byte size for the Rust orchestrator
    expected_size = if level == 1 
        64 
    elseif level == 3 
        96 
    else 
        128 
    end

    # Helper function to convert complex Nemo objects into padded hashes for Rust
    function extract_unique_id_bytes(obj, expected_size)
        io = IOBuffer()
        serialize(io, obj) 
        fingerprint = sha512(take!(io))
        
        padded = zeros(UInt8, expected_size)
        for i in 1:expected_size
            padded[i] = fingerprint[((i - 1) % length(fingerprint)) + 1]
        end
        return padded
    end

    # =========================================================
    # PHASE 1: MODE 0 (Key Generation)
    # =========================================================
    if mode == 0
        println("    - Beginning Keygen...");
        
        for _ in 1:warmup_runs
            pk, sk = param.key_gen(global_data)
        end

        pk_exports = Vector{Vector{UInt8}}()
        sk_exports = Vector{Vector{UInt8}}()
        key_vault = Dict{UInt64, Tuple{Any, Any}}()

        for i in 0:(num_keys-1)
            GC.gc()
            GC.enable(false)
            
            t0 = ccall((:macos_rdtsc, LIB_MAC_OS), UInt64, ())
            pk, sk = param.key_gen(global_data)
            t1 = ccall((:macos_rdtsc, LIB_MAC_OS), UInt64, ())
            
            GC.enable(true)

            push!(telemetry, TelemetryRow(i, t1 - t0, 0, 0))

            push!(pk_exports, extract_unique_id_bytes(pk, expected_size))
            push!(sk_exports, extract_unique_id_bytes(sk, expected_size))
            key_vault[UInt64(i)] = (pk, sk)
        end

        open("fixed_pk.bin", "w") do io for b in pk_exports write(io, b) end end
        open("fixed_sk.bin", "w") do io for b in sk_exports write(io, b) end end
        open("sqisign2deast_key_vault.jls", "w") do io serialize(io, key_vault) end
        
        println("    - Keygen Complete: $num_keys total keys.")

    # =========================================================
    # PHASE 2: MODE 1 (Standard Nested Loop)
    # =========================================================
    elseif mode == 1
        println("    - Beginning Sign/Verify Loop...")
        
        keys = [param.key_gen(global_data) for _ in 1:num_keys]
        msg = rand(UInt8, 32) # Replaced string with raw 32-byte array
        
        warmup_pk, warmup_sk = keys[1]
        for _ in 1:warmup_runs
            sig = param.signing(warmup_pk, warmup_sk, msg, global_data, is_compact)
            param.verify(warmup_pk, sig, msg, global_data)
        end

        for k in 0:(num_keys-1)
            pk, sk = keys[k+1] 
            for i in 1:iterations
                GC.gc() 
                GC.enable(false)
                
                st0 = ccall((:macos_rdtsc, LIB_MAC_OS), UInt64, ())
                sig = param.signing(pk, sk, bytes2hex(msg), global_data, is_compact)
                st1 = ccall((:macos_rdtsc, LIB_MAC_OS), UInt64, ())

                vt0 = ccall((:macos_rdtsc, LIB_MAC_OS), UInt64, ())
                valid = param.verify(pk, sig, bytes2hex(msg), global_data)
                vt1 = ccall((:macos_rdtsc, LIB_MAC_OS), UInt64, ())
                
                GC.enable(true)

                if !valid error("Cryptographic failure!") end

                push!(telemetry, TelemetryRow(k, 0, st1 - st0, vt1 - vt0))
            end
        end
        total_runs = num_keys * iterations
        println("    - Sign/Verify Loops Complete: $total_runs total signatures.");

    # =========================================================
    # PHASE 3: MODE 2 (Fixed Key, Random Messages)
    # =========================================================
    elseif mode == 2
        println("    - Running Fixed-Key, Random-Message Suite...")
        total_runs = iterations

        # JIT WARMUP (Sign & Verify)
        warmup_pk, warmup_sk = param.key_gen(global_data)
        warmup_msg = rand(UInt8, 32)
        for _ in 1:warmup_runs
            wsig = param.signing(warmup_pk, warmup_sk, bytes2hex(warmup_msg), global_data, is_compact)
            param.verify(warmup_pk, wsig, bytes2hex(warmup_msg), global_data)
        end

        # 1. Generate the single batch key
        GC.gc()
        GC.enable(false)
        t0 = ccall((:macos_rdtsc, LIB_MAC_OS), UInt64, ())
        pk, sk = param.key_gen(global_data)
        t1 = ccall((:macos_rdtsc, LIB_MAC_OS), UInt64, ())
        GC.enable(true)
        batch_keygen_cycles = t1 - t0

        # 2. Roll all random 32-byte messages
        messages = [rand(UInt8, 32) for _ in 1:total_runs]

        # 3. Execute signatures against random messages
        for i in 1:total_runs
            GC.gc()
            GC.enable(false)
            
            st0 = ccall((:macos_rdtsc, LIB_MAC_OS), UInt64, ())
            sig = param.signing(pk, sk, bytes2hex(messages[i]), global_data, is_compact)
            st1 = ccall((:macos_rdtsc, LIB_MAC_OS), UInt64, ())

            vt0 = ccall((:macos_rdtsc, LIB_MAC_OS), UInt64, ())
            valid = param.verify(pk, sig, bytes2hex(messages[i]), global_data)
            vt1 = ccall((:macos_rdtsc, LIB_MAC_OS), UInt64, ())
            
            GC.enable(true)

            if !valid error("Cryptographic failure!") end
            
            # Note: Using key_index 0 to match C behaviour
            push!(telemetry, TelemetryRow(0, batch_keygen_cycles, st1 - st0, vt1 - vt0))
        end

        # Dump variables
        open("batch_pk.bin", "w") do io write(io, extract_unique_id_bytes(pk, expected_size)) end
        open("batch_sk.bin", "w") do io write(io, extract_unique_id_bytes(sk, expected_size)) end
        open("batch_messages.bin", "w") do io 
            for m in messages write(io, m) end 
        end
        println("    - Batch Run Complete: $total_runs messages processed.")

    # =========================================================
    # PHASE 4: MODE 3 (Fixed Message, Random Keys)
    # =========================================================
    elseif mode == 3
        println("    - Running Fixed-Message, Random-Key Suite...")
        total_runs = num_keys

        # JIT WARMUP (Keygen, Sign & Verify)
        warmup_msg = rand(UInt8, 32)
        for _ in 1:warmup_runs
            wpk, wsk = param.key_gen(global_data)
            wsig = param.signing(wpk, wsk, bytes2hex(warmup_msg), global_data, is_compact)
            param.verify(wpk, wsig, bytes2hex(warmup_msg), global_data)
        end

        # Generate single static random message
        static_msg = rand(UInt8, 32)

        pk_exports = Vector{Vector{UInt8}}()
        sk_exports = Vector{Vector{UInt8}}()

        for k in 0:(total_runs-1)
            GC.gc()
            GC.enable(false)
            
            t0 = ccall((:macos_rdtsc, LIB_MAC_OS), UInt64, ())
            pk, sk = param.key_gen(global_data)
            t1 = ccall((:macos_rdtsc, LIB_MAC_OS), UInt64, ())
            kg_cycles = t1 - t0

            st0 = ccall((:macos_rdtsc, LIB_MAC_OS), UInt64, ())
            sig = param.signing(pk, sk, bytes2hex(static_msg), global_data, is_compact)
            st1 = ccall((:macos_rdtsc, LIB_MAC_OS), UInt64, ())

            vt0 = ccall((:macos_rdtsc, LIB_MAC_OS), UInt64, ())
            valid = param.verify(pk, sig, bytes2hex(static_msg), global_data)
            vt1 = ccall((:macos_rdtsc, LIB_MAC_OS), UInt64, ())
            
            GC.enable(true)

            if !valid error("Cryptographic failure!") end

            push!(telemetry, TelemetryRow(k, kg_cycles, st1 - st0, vt1 - vt0))
            push!(pk_exports, extract_unique_id_bytes(pk, expected_size))
            push!(sk_exports, extract_unique_id_bytes(sk, expected_size))
        end

        open("batch_pk.bin", "w") do io for b in pk_exports write(io, b) end end
        open("batch_sk.bin", "w") do io for b in sk_exports write(io, b) end end
        open("batch_msg_single.bin", "w") do io write(io, static_msg) end
        
        println("    - Batch Run Complete: $total_runs keys evaluated.")
    end

    # =========================================================
    # BINARY SERIALIZATION FOR RUST
    # =========================================================
    open("sqisign_telemetry.bin", "w") do io
        for row in telemetry
            write(io, row.key_index)
            write(io, row.keygen_cycles)
            write(io, row.sign_cycles)
            write(io, row.verify_cycles)
        end
    end
end

main()