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

function gen_pbs3()
    nfreq = 800
    freq_min_nb = 55.0
    freq_max_nb = 1950.0
    df = (freq_max_nb - freq_min_nb)/(nfreq - 1)
    psd_freq = freq_min_nb .+ (0:nfreq-1).*df
    psd_amp = psd_func.(psd_freq)
    freq_a2 = psd_freq |> collect
    psd_amp_a2 = psd_amp |> collect

    pbs_freq, pbs = ANOPP2.a2jl_aa_pbs(ANOPP2.a2_aa_psd, ANOPP2.a2_aa_msp, freq_a2, psd_amp_a2, 3.0, ANOPP2.a2_aa_exact)

    return Dict("a2_pbs_freq"=>pbs_freq, "a2_pbs"=>pbs)
end

psd_func_pbs4(freq) = 3*freq/1e1 + (4e-1)*(freq/1e1)^2 + (5e-2)*(freq/1e1)^3 + (6e-3)*(freq/1e1)^4

psd_func_pbs5(freq) = 100*(sin(2*pi/(100)*freq) + 2)

function gen_pbs4()

    freq_min_nb = 1e-2
    freq_max_nb = 1e5
    # nfreq = 100000
    # df = (freq_max_nb - freq_min_nb)/(nfreq - 1)
    # psd_freq = freq_min_nb .+ (0:nfreq-1).*df
    df = 1e-3
    psd_freq = freq_min_nb:df:freq_max_nb
    @show psd_freq length(psd_freq)
    psd_amp = psd_func_pbs5.(psd_freq)
    freq_a2 = psd_freq |> collect
    psd_amp_a2 = psd_amp |> collect

    pbs_freq_exact, pbs_exact = ANOPP2.a2jl_aa_pbs(ANOPP2.a2_aa_psd, ANOPP2.a2_aa_msp, freq_a2, psd_amp_a2, 1.0, ANOPP2.a2_aa_exact)
    pbs_freq_approx, pbs_approx = ANOPP2.a2jl_aa_pbs(ANOPP2.a2_aa_psd, ANOPP2.a2_aa_msp, freq_a2, psd_amp_a2, 1.0, ANOPP2.a2_aa_approximate)
    pbs_freq_pref, pbs_pref = ANOPP2.a2jl_aa_pbs(ANOPP2.a2_aa_psd, ANOPP2.a2_aa_msp, freq_a2, psd_amp_a2, 1.0, ANOPP2.a2_aa_preferred)

    return Dict("a2_pbs_freq_exact"=>pbs_freq_exact, "a2_pbs_exact"=>pbs_exact,
                "a2_pbs_freq_approx"=>pbs_freq_approx, "a2_pbs_approx"=>pbs_approx,
                "a2_pbs_freq_pref"=>pbs_freq_pref, "a2_pbs_pref"=>pbs_pref)
end

function main()
    # nbs_data = gen_nbs()
    # save(joinpath(@__DIR__, "nbs-new.jld2"), nbs_data)
    # psd_data = gen_psd()
    # save(joinpath(@__DIR__, "psd-new.jld2"), psd_data)
    # pbs_data = gen_pbs()
    # save(joinpath(@__DIR__, "pbs-new.jld2"), pbs_data)
    # pbs3_data = gen_pbs3()
    # save(joinpath(@__DIR__, "pbs3-new.jld2"), pbs3_data)
    pbs4_data = gen_pbs4()
    @show pbs4_data
    save(joinpath(@__DIR__, "pbs4-new.jld2"), pbs4_data)
    return nothing
end

end # module
