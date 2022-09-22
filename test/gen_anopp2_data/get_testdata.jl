module GetTestData

using ANOPP2
using JLD2

include("test_functions.jl")

function gen_nbs()
    a2_nbs_freq = Dict{Tuple{Int, Int}, Vector{Float64}}()
    a2_nbs_amp = Dict{Tuple{Int, Int}, Vector{Float64}}()
    a2_nbs_phase = Dict{Tuple{Int, Int}, Vector{Float64}}()
    for T in [1, 2]
        for n in [19, 20]

            dt = T/n
            t = (0:n-1).*dt
            p = apth_for_nbs.(t)

            t_a2 = range(0, T, length=n) |> collect # This needs to be an array, since we'll eventually be passing it to C/Fortran via ccall.
            if mod(n, 2) == 0
                p_a2 = p
            else
                p_a2 = apth_for_nbs.(t_a2)
            end
            freq_a2, nbs_msp_a2, nbs_phase_a2 = ANOPP2.a2jl_aa_nbs(ANOPP2.a2_aa_pa, ANOPP2.a2_aa_pa, t_a2, p_a2)
            a2_nbs_freq[T, n] = freq_a2
            a2_nbs_amp[T, n] = nbs_msp_a2
            a2_nbs_phase[T, n] = nbs_phase_a2
        end
    end
    return Dict("a2_nbs_freq"=>a2_nbs_freq,
                "a2_nbs_amp"=>a2_nbs_amp,
                "a2_nbs_phase"=>a2_nbs_phase)
end

function gen_psd()
    a2_psd_freq = Dict{Tuple{Int, Int}, Vector{Float64}}()
    a2_psd_amp = Dict{Tuple{Int, Int}, Vector{Float64}}()
    a2_psd_phase = Dict{Tuple{Int, Int}, Vector{Float64}}()
    for T in [1, 2]
        for n in [19, 20]

            dt = T/n
            t = (0:n-1).*dt
            p = apth_for_nbs.(t)

            t_a2 = range(0, T, length=n) |> collect # This needs to be an array, since we'll eventually be passing it to C/Fortran via ccall.
            if mod(n, 2) == 0
                p_a2 = p
            else
                p_a2 = apth_for_nbs.(t_a2)
            end
            freq_a2, psd_msp_a2, psd_phase_a2 = ANOPP2.a2jl_aa_psd(ANOPP2.a2_aa_pa, ANOPP2.a2_aa_pa, t_a2, p_a2)
            a2_psd_freq[T, n] = freq_a2
            a2_psd_amp[T, n] = psd_msp_a2
            a2_psd_phase[T, n] = psd_phase_a2
        end
    end
    return Dict("a2_psd_freq"=>a2_psd_freq,
                "a2_psd_amp"=>a2_psd_amp,
                "a2_psd_phase"=>a2_psd_phase)
end

function gen_pbs()
    # Need a PSD to pass to the routine.
    freq0 = 1000.0
    T = 20/freq0
    t0 = 0.13
    n = 128

    dt = T/n
    t = (0:n-1).*dt

    t_a2 = range(0, T, length=n) |> collect # This needs to be an array, since we'll eventually be passing it to C/Fortran via ccall.
    if mod(n, 2) == 0
        p_a2 = apth_for_pbs.(freq0, t)
    else
        p_a2 = apth_for_pbs.(freq0, t_a2)
    end

    freq_a2, psd_msp_a2, psd_phase_a2 = ANOPP2.a2jl_aa_psd(ANOPP2.a2_aa_pa, ANOPP2.a2_aa_pa, t_a2, p_a2)
    @show freq_a2
    @show psd_msp_a2

    pbs_freq, pbs = ANOPP2.a2jl_aa_pbs(ANOPP2.a2_aa_psd, ANOPP2.a2_aa_msp, freq_a2, psd_msp_a2, 3.0, ANOPP2.a2_aa_exact)

    return Dict("a2_pbs_freq"=>pbs_freq, "a2_pbs"=>pbs)
end

function gen_pbs()
    # Need a PSD to pass to the routine.
    freq0 = 1000.0
    T = 20/freq0
    t0 = 0.13
    n = 128

    dt = T/n
    t = (0:n-1).*dt

    t_a2 = range(0, T, length=n) |> collect # This needs to be an array, since we'll eventually be passing it to C/Fortran via ccall.
    if mod(n, 2) == 0
        p_a2 = apth_for_pbs.(freq0, t)
    else
        p_a2 = apth_for_pbs.(freq0, t_a2)
    end

    freq_a2, psd_msp_a2, psd_phase_a2 = ANOPP2.a2jl_aa_psd(ANOPP2.a2_aa_pa, ANOPP2.a2_aa_pa, t_a2, p_a2)
    @show freq_a2
    @show psd_msp_a2

    pbs_freq, pbs = ANOPP2.a2jl_aa_pbs(ANOPP2.a2_aa_psd, ANOPP2.a2_aa_msp, freq_a2, psd_msp_a2, 3.0, ANOPP2.a2_aa_exact)

    return Dict("a2_pbs_freq"=>pbs_freq, "a2_pbs"=>pbs)
end

function gen_pbs2()
    n_freq = 2232
    psd_freq = 45.0 .+ 5 .* (0:n_freq-1)
    df = psd_freq[2] - psd_freq[1]
    msp_amp = 20 .+ 10 .* (1:n_freq)./n_freq
    # psd_amp = msp_amp ./ df
    freq_a2 = psd_freq |> collect
    # psd_msp_a2 = psd_amp |> collect
    msp_amp_a2 = msp_amp |> collect

    pbs_freq, pbs = ANOPP2.a2jl_aa_pbs(ANOPP2.a2_aa_nbs, ANOPP2.a2_aa_msp, freq_a2, msp_amp_a2, 3.0, ANOPP2.a2_aa_exact)

    return Dict("a2_pbs_freq"=>pbs_freq, "a2_pbs"=>pbs)
end

function main()
    nbs_data = gen_nbs()
    save(joinpath(@__DIR__, "nbs-new.jld2"), nbs_data)
    psd_data = gen_psd()
    save(joinpath(@__DIR__, "psd-new.jld2"), psd_data)
    pbs_data = gen_pbs()
    save(joinpath(@__DIR__, "pbs-new.jld2"), pbs_data)
    return nothing
end

end # module
