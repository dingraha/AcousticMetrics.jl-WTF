using AcousticMetrics: p_ref
using AcousticMetrics: r2rfftfreq, rfft, rfft!, irfft, irfft!, RFFTCache, dft_r2hc, dft_hc2r
using AcousticMetrics: PressureTimeHistory
using AcousticMetrics: PressureSpectrumAmplitude, PressureSpectrumPhase, MSPSpectrumAmplitude, MSPSpectrumPhase, PowerSpectralDensityAmplitude, PowerSpectralDensityPhase
using AcousticMetrics: starttime, timestep, time, pressure, frequency, halfcomplex, OASPL
using AcousticMetrics: band_start, band_end
using AcousticMetrics: ExactOctaveCenterBands, ExactOctaveLowerBands, ExactOctaveUpperBands
using AcousticMetrics: ExactThirdOctaveCenterBands, ExactThirdOctaveLowerBands, ExactThirdOctaveUpperBands
using AcousticMetrics: ExactProportionalBands, lower_bands, center_bands, upper_bands
using AcousticMetrics: ProportionalBandSpectrum, ExactThirdOctaveSpectrum
using AcousticMetrics: ApproximateOctaveBands, ApproximateOctaveCenterBands, ApproximateOctaveLowerBands, ApproximateOctaveUpperBands
using AcousticMetrics: ApproximateThirdOctaveBands, ApproximateThirdOctaveCenterBands, ApproximateThirdOctaveLowerBands, ApproximateThirdOctaveUpperBands
using AcousticMetrics: W_A
using ForwardDiff
using JLD2
using Polynomials: Polynomials
using Random
using Test

include(joinpath(@__DIR__, "gen_anopp2_data", "test_functions.jl"))


@testset "Fourier transforms" begin

    @testset "FFTW compared to a function with a known Fourier transform" begin
        for T in [1.0, 2.0]
            f(t) = 6 + 8*cos(1*2*pi/T*t + 0.2) + 2.5*cos(2*2*pi/T*t - 3.0) + 9*cos(3*2*pi/T*t + 3.1) + 0.5*cos(4*2*pi/T*t - 1.1) + 3*cos(5*2*pi/T*t + 0.2)
            for n in [10, 11]
                dt = T/n
                t = (0:n-1).*dt
                p = f.(t)
                p_fft = rfft(p)./n
                p_fft_expected = similar(p_fft)
                p_fft_expected[1] = 6.0
                p_fft_expected[2] = 0.5*8*cos(0.2)
                p_fft_expected[end] = 0.5*8*sin(0.2)
                p_fft_expected[3] = 0.5*2.5*cos(-3.0)
                p_fft_expected[end-1] = 0.5*2.5*sin(-3.0)
                p_fft_expected[4] = 0.5*9*cos(3.1)
                p_fft_expected[end-2] = 0.5*9*sin(3.1)
                p_fft_expected[5] = 0.5*0.5*cos(-1.1)
                p_fft_expected[end-3] = 0.5*0.5*sin(-1.1)
                if n == 10
                    p_fft_expected[6] = 3*cos(0.2)
                else
                    p_fft_expected[6] = 0.5*3*cos(0.2)
                    p_fft_expected[end-4] = 0.5*3*sin(0.2)
                end
                @test all(isapprox.(p_fft, p_fft_expected, atol=1e-12))
            end
        end
    end

    @testset "FFTW vs ad-hoc discrete Fourier transform" begin
        # Should check both even- and odd-length inputs, since the definition of the
        # discrete Fourier transform output depends slightly on that.
        for n in [64, 65]
            x = rand(n)
            y_fft = similar(x)
            rfft!(y_fft, x)
            y_dft = dft_r2hc(x)
            @test all(y_dft .≈ y_fft)

            y_ifft = similar(x)
            irfft!(y_ifft, x)
            y_idft = dft_hc2r(x)
            @test all(y_idft .≈ y_ifft)
        end
    end

    # Now check derivatives.
    @testset "FFTW derivatives" begin
        @testset "basic" begin
            for n in [64, 65]
                x = rand(n)
                y = similar(x)
                dy_dx_fft = ForwardDiff.jacobian(rfft!, y, x)
                dy_dx_dft = ForwardDiff.jacobian(dft_r2hc, x)
                @test all(isapprox.(dy_dx_fft, dy_dx_dft, atol=1e-13))

                dy_dx_ifft = ForwardDiff.jacobian(irfft!, y, x)
                dy_dx_idft = ForwardDiff.jacobian(dft_hc2r, x)
                @test all(isapprox.(dy_dx_ifft, dy_dx_idft, atol=1e-13))
            end
        end

        @testset "as intermediate function" begin
            function f1_fft(t)
                x = range(t[begin], t[end], length=8)
                x = @. 2*x^2 + 3*x + 5
                y = similar(x)
                rfft!(y, x)
                return y
            end
            function f1_dft(t)
                x = range(t[begin], t[end], length=8)
                x = @. 2*x^2 + 3*x + 5
                y = dft_r2hc(x)
                return y
            end
            dy_dx_fft = ForwardDiff.jacobian(f1_fft, [1.1, 3.5])
            dy_dx_dft = ForwardDiff.jacobian(f1_dft, [1.1, 3.5])
            @test all(isapprox.(dy_dx_fft, dy_dx_dft, atol=1e-13))

            function f1_ifft(t)
                x = range(t[begin], t[end], length=8)
                x = @. 2*x^2 + 3*x + 5
                y = similar(x)
                irfft!(y, x)
                return y
            end
            function f1_idft(t)
                x = range(t[begin], t[end], length=8)
                x = @. 2*x^2 + 3*x + 5
                y = dft_hc2r(x)
                return y
            end
            dy_dx_ifft = ForwardDiff.jacobian(f1_ifft, [1.1, 3.5])
            dy_dx_idft = ForwardDiff.jacobian(f1_idft, [1.1, 3.5])
            @test all(isapprox.(dy_dx_ifft, dy_dx_idft, atol=1e-13))
        end

        @testset "with user-supplied cache" begin
            nx = 8
            nt = 5
            cache = RFFTCache(Float64, nx, nt)
            function f2_fft(t)
                xstart = sum(t)
                xend = xstart + 2
                x = range(xstart, xend, length=nx)
                x = @. 2*x^2 + 3*x + 5
                y = similar(x)
                rfft!(y, x, cache)
                return y
            end
            function f2_dft(t)
                xstart = sum(t)
                xend = xstart + 2
                x = range(xstart, xend, length=nx)
                x = @. 2*x^2 + 3*x + 5
                y = dft_r2hc(x)
                return y
            end
            t = rand(nt)
            dy_dx_fft = ForwardDiff.jacobian(f2_fft, t)
            dy_dx_dft = ForwardDiff.jacobian(f2_dft, t)
            @test all(isapprox.(dy_dx_fft, dy_dx_dft, atol=1e-13))

            function f2_ifft(t)
                xstart = sum(t)
                xend = xstart + 2
                x = range(xstart, xend, length=nx)
                x = @. 2*x^2 + 3*x + 5
                y = similar(x)
                irfft!(y, x, cache)
                return y
            end
            function f2_idft(t)
                xstart = sum(t)
                xend = xstart + 2
                x = range(xstart, xend, length=nx)
                x = @. 2*x^2 + 3*x + 5
                y = dft_hc2r(x)
                return y
            end
            t = rand(nt)
            dy_dx_ifft = ForwardDiff.jacobian(f2_ifft, t)
            dy_dx_idft = ForwardDiff.jacobian(f2_idft, t)
            @test all(isapprox.(dy_dx_ifft, dy_dx_idft, atol=1e-13))
        end
    end
end

@testset "Pressure Spectrum" begin
    @testset "t0 == 0" begin
        for T in [1.0, 2.0]
            f(t) = 6 + 8*cos(1*2*pi/T*t + 0.2) + 2.5*cos(2*2*pi/T*t - 3.0) + 9*cos(3*2*pi/T*t + 3.1) + 0.5*cos(4*2*pi/T*t - 1.1) + 3*cos(5*2*pi/T*t + 0.2)
            for n in [10, 11]
                dt = T/n
                t = (0:n-1).*dt
                p = f.(t)
                ap = PressureTimeHistory(p, dt)
                @test all(isapprox.(time(ap), t))
                @test timestep(ap) ≈ dt
                @test starttime(ap) ≈ 0.0
                # ps = PressureSpectrum(ap)
                # amp = amplitude(ps)
                amp = PressureSpectrumAmplitude(ap)
                phase = PressureSpectrumPhase(ap)
                freq_expected = [0.0, 1/T, 2/T, 3/T, 4/T, 5/T]
                amp_expected = similar(amp)
                amp_expected[1] = 6
                amp_expected[2] = 8
                amp_expected[3] = 2.5
                amp_expected[4] = 9
                amp_expected[5] = 0.5
                phase_expected = similar(phase)
                phase_expected[1] = 0
                phase_expected[2] = 0.2
                phase_expected[3] = -3
                phase_expected[4] = 3.1
                phase_expected[5] = -1.1
                # Handle the Nyquist frequency (kinda tricky). There isn't really a
                # Nyquist frequency for the odd input length case.
                if n == 10
                    amp_expected[6] = 3*cos(0.2)
                    phase_expected[6] = 0
                else
                    amp_expected[6] = 3
                    phase_expected[6] = 0.2
                end
                @test all(isapprox.(frequency(amp), freq_expected; atol=1e-12))
                @test all(isapprox.(frequency(phase), freq_expected; atol=1e-12))
                @test all(isapprox.(amp, amp_expected; atol=1e-12))
                @test all(isapprox.(phase.*amp, phase_expected.*amp_expected; atol=1e-12))

                # Make sure I can go from a PressureSpectrum to an PressureTimeHistory.
                ap_from_ps = PressureTimeHistory(amp)
                @test timestep(ap_from_ps) ≈ timestep(ap)
                @test starttime(ap_from_ps) ≈ starttime(ap)
                @test all(isapprox.(pressure(ap_from_ps), pressure(ap)))
            end
        end
        @testset "negative amplitudes" begin
            for T in [1.0, 2.0]
                f(t) = -6 - 8*cos(1*2*pi/T*t + 0.2) - 2.5*cos(2*2*pi/T*t - 3.0) + 9*cos(3*2*pi/T*t + 3.1) + 0.5*cos(4*2*pi/T*t - 1.1) + 3*cos(5*2*pi/T*t + 0.2)
                for n in [10, 11]
                    dt = T/n
                    t = (0:n-1).*dt
                    p = f.(t)
                    ap = PressureTimeHistory(p, dt)
                    # ps = PressureSpectrum(ap)
                    amp = PressureSpectrumAmplitude(ap)
                    phase = PressureSpectrumPhase(ap)
                    freq_expected = [0.0, 1/T, 2/T, 3/T, 4/T, 5/T]
                    amp_expected = similar(amp)
                    amp_expected[1] = 6
                    amp_expected[2] = 8
                    amp_expected[3] = 2.5
                    amp_expected[4] = 9
                    amp_expected[5] = 0.5
                    phase_expected = similar(phase)
                    phase_expected[1] = pi
                    phase_expected[2] = -pi + 0.2
                    phase_expected[3] = pi - 3
                    phase_expected[4] = 3.1
                    phase_expected[5] = -1.1
                    # Handle the Nyquist frequency (kinda tricky). There isn't really a
                    # Nyquist frequency for the odd input length case.
                    if n == 10
                        amp_expected[6] = 3*cos(0.2)
                        phase_expected[6] = 0
                    else
                        amp_expected[6] = 3
                        phase_expected[6] = 0.2
                    end
                    @test all(isapprox.(frequency(amp), freq_expected; atol=1e-12))
                    @test all(isapprox.(frequency(phase), freq_expected; atol=1e-12))
                    @test all(isapprox.(amp, amp_expected; atol=1e-12))
                    @test all(isapprox.(phase.*amp, phase_expected.*amp_expected; atol=1e-12))

                    # Make sure I can go from a PressureSpectrum to an PressureTimeHistory.
                    ap_from_ps = PressureTimeHistory(amp)
                    @test timestep(ap_from_ps) ≈ timestep(ap)
                    @test starttime(ap_from_ps) ≈ starttime(ap)
                    @test all(isapprox.(pressure(ap_from_ps), pressure(ap)))
                end
            end
        end
    end

    @testset "t0 !== 0" begin
        for T in [1.0, 2.0]
            t0 = 0.13
            f(t) = 6 + 8*cos(1*2*pi/T*t + 0.2) + 2.5*cos(2*2*pi/T*t - 3.0) + 9*cos(3*2*pi/T*t + 3.1) + 0.5*cos(4*2*pi/T*t - 1.1) + 3*cos(5*2*pi/T*t + 0.2)
            for n in [10, 11]
                dt = T/n
                t = t0 .+ (0:n-1).*dt
                p = f.(t)
                ap = PressureTimeHistory(p, dt, t0)
                @test all(isapprox.(time(ap), t))
                @test timestep(ap) ≈ dt
                @test starttime(ap) ≈ t0
                # ps = PressureSpectrum(ap)
                amp = PressureSpectrumAmplitude(ap)
                phase = PressureSpectrumPhase(ap)
                freq_expected = [0.0, 1/T, 2/T, 3/T, 4/T, 5/T]
                amp_expected = similar(amp)
                amp_expected[1] = 6
                amp_expected[2] = 8
                amp_expected[3] = 2.5
                amp_expected[4] = 9
                amp_expected[5] = 0.5
                phase_expected = similar(phase)
                phase_expected[1] = 0
                phase_expected[2] = 0.2
                phase_expected[3] = -3
                phase_expected[4] = 3.1
                phase_expected[5] = -1.1
                # Handle the Nyquist frequency (kinda tricky). There isn't really a
                # Nyquist frequency for the odd input length case.
                if n == 10
                    amp_expected[6] = abs(3*cos(5*2*pi/T*t0 + 0.2))
                    phase_expected[6] = rem2pi(pi - 5*2*pi/T*t0, RoundNearest)
                else
                    amp_expected[6] = 3
                    phase_expected[6] = 0.2
                end
                @test all(isapprox.(frequency(amp), freq_expected; atol=1e-12))
                @test all(isapprox.(frequency(phase), freq_expected; atol=1e-12))
                @test all(isapprox.(amp, amp_expected; atol=1e-12))
                @test all(isapprox.(phase, phase_expected; atol=1e-12))

                # Make sure I can go from a PressureSpectrum to an PressureTimeHistory.
                ap_from_ps = PressureTimeHistory(amp)
                @test timestep(ap_from_ps) ≈ timestep(ap)
                @test starttime(ap_from_ps) ≈ starttime(ap)
                @test all(isapprox.(pressure(ap_from_ps), pressure(ap)))
            end
        end
    end
end

@testset "Mean-squared Pressure Spectrum" begin
    @testset "t0 == 0" begin
        for T in [1.0, 2.0]
            f(t) = 6 + 8*cos(1*2*pi/T*t + 0.2) + 2.5*cos(2*2*pi/T*t - 3.0) + 9*cos(3*2*pi/T*t + 3.1) + 0.5*cos(4*2*pi/T*t - 1.1) + 3*cos(5*2*pi/T*t + 0.2)
            for n in [10, 11]
                dt = T/n
                t = (0:n-1).*dt
                p = f.(t)
                ap = PressureTimeHistory(p, dt)
                amp = MSPSpectrumAmplitude(ap)
                phase = MSPSpectrumPhase(ap)
                freq_expected = [0.0, 1/T, 2/T, 3/T, 4/T, 5/T]
                amp_expected = similar(amp)
                amp_expected[1] = 6^2
                amp_expected[2] = 0.5*8^2
                amp_expected[3] = 0.5*2.5^2
                amp_expected[4] = 0.5*9^2
                amp_expected[5] = 0.5*0.5^2
                phase_expected = similar(phase)
                phase_expected[1] = 0
                phase_expected[2] = 0.2
                phase_expected[3] = -3
                phase_expected[4] = 3.1
                phase_expected[5] = -1.1
                # Handle the Nyquist frequency (kinda tricky). There isn't really a
                # Nyquist frequency for the odd input length case.
                if n == 10
                    amp_expected[6] = (3*cos(0.2))^2
                    phase_expected[6] = 0
                else
                    amp_expected[6] = 0.5*3^2
                    phase_expected[6] = 0.2
                end
                @test all(isapprox.(frequency(amp), freq_expected; atol=1e-12))
                @test all(isapprox.(frequency(phase), freq_expected; atol=1e-12))
                @test all(isapprox.(amp, amp_expected; atol=1e-12))
                @test all(isapprox.(phase.*amp, phase_expected.*amp_expected; atol=1e-12))

                # Make sure I can convert a mean-squared pressure to a pressure spectrum.
                psamp = PressureSpectrumAmplitude(amp)
                amp_expected = similar(amp)
                amp_expected[1] = 6
                amp_expected[2] = 8
                amp_expected[3] = 2.5
                amp_expected[4] = 9
                amp_expected[5] = 0.5
                # Handle the Nyquist frequency (kinda tricky). There isn't really a
                # Nyquist frequency for the odd input length case.
                if n == 10
                    amp_expected[6] = 3*cos(0.2)
                else
                    amp_expected[6] = 3
                end
                @test all(isapprox.(frequency(psamp), freq_expected; atol=1e-12))
                @test all(isapprox.(psamp, amp_expected; atol=1e-12))

                # Make sure I can convert a mean-squared pressure to the acoustic pressure.
                ap_from_msp = PressureTimeHistory(amp)
                @test timestep(ap_from_msp) ≈ timestep(ap)
                @test starttime(ap_from_msp) ≈ starttime(ap)
                @test all(isapprox.(pressure(ap_from_msp), pressure(ap)))
            end
        end
    end

    @testset "t0 !== 0" begin
        for T in [1.0, 2.0]
            t0 = 0.13
            f(t) = 6 + 8*cos(1*2*pi/T*t + 0.2) + 2.5*cos(2*2*pi/T*t - 3.0) + 9*cos(3*2*pi/T*t + 3.1) + 0.5*cos(4*2*pi/T*t - 1.1) + 3*cos(5*2*pi/T*t + 0.2)
            for n in [10, 11]
                dt = T/n
                t = t0 .+ (0:n-1).*dt
                p = f.(t)
                ap = PressureTimeHistory(p, dt, t0)
                amp = MSPSpectrumAmplitude(ap)
                phase = MSPSpectrumPhase(ap)
                freq_expected = [0.0, 1/T, 2/T, 3/T, 4/T, 5/T]
                amp_expected = similar(amp)
                amp_expected[1] = 6^2
                amp_expected[2] = 0.5*8^2
                amp_expected[3] = 0.5*2.5^2
                amp_expected[4] = 0.5*9^2
                amp_expected[5] = 0.5*0.5^2
                phase_expected = similar(phase)
                phase_expected[1] = 0
                phase_expected[2] = 0.2
                phase_expected[3] = -3
                phase_expected[4] = 3.1
                phase_expected[5] = -1.1
                # Handle the Nyquist frequency (kinda tricky). There isn't really a
                # Nyquist frequency for the odd input length case.
                if n == 10
                    # amp_expected[6] = (3*cos(5*2*pi/T*t0 + 0.2))^2
                    # phase_expected[6] = rem2pi(-5*2*pi/T*t0, RoundNearest)
                    amp_expected[6] = (3*cos(5*2*pi/T*t0 + 0.2))^2
                    phase_expected[6] = rem2pi(pi - 5*2*pi/T*t0, RoundNearest)
                else
                    amp_expected[6] = 0.5*3^2
                    phase_expected[6] = 0.2
                end
                @test all(isapprox.(frequency(amp), freq_expected; atol=1e-12))
                @test all(isapprox.(frequency(phase), freq_expected; atol=1e-12))
                @test all(isapprox.(amp, amp_expected; atol=1e-12))
                @test all(isapprox.(phase, phase_expected; atol=1e-12))

                # Make sure I can convert a mean-squared pressure to a pressure spectrum.
                psamp = PressureSpectrumAmplitude(amp)
                amp_expected = similar(psamp)
                amp_expected[1] = 6
                amp_expected[2] = 8
                amp_expected[3] = 2.5
                amp_expected[4] = 9
                amp_expected[5] = 0.5
                # Handle the Nyquist frequency (kinda tricky). There isn't really a
                # Nyquist frequency for the odd input length case.
                if n == 10
                    # The `t0` term pushes the cosine below zero, which messes
                    # up the test. Hmm... what's the right thing to do here?
                    # Well, what should the phase and amplitude be?
                    # amp_expected[6] = 3*cos(5*2*pi/T*t0 + 0.2)
                    amp_expected[6] = abs(3*cos(5*2*pi/T*t0 + 0.2))
                else
                    amp_expected[6] = 3
                end
                @test all(isapprox.(frequency(psamp), freq_expected; atol=1e-12))
                @test all(isapprox.(psamp, amp_expected; atol=1e-12))

                # Make sure I can convert a mean-squared pressure to the acoustic pressure.
                ap_from_msp = PressureTimeHistory(amp)
                @test timestep(ap_from_msp) ≈ timestep(ap)
                @test starttime(ap_from_msp) ≈ starttime(ap)
                @test all(isapprox.(pressure(ap_from_msp), pressure(ap)))
            end
        end
    end

    @testset "ANOPP2 comparison" begin
        a2_data = load(joinpath(@__DIR__, "gen_anopp2_data", "nbs.jld2"))
        freq_a2 = a2_data["a2_nbs_freq"]
        nbs_msp_a2 = a2_data["a2_nbs_amp"]
        nbs_phase_a2 = a2_data["a2_nbs_phase"]
        for T in [1, 2]
            for n in [19, 20]
                dt = T/n
                t = (0:n-1).*dt
                p = apth_for_nbs.(t)
                ap = PressureTimeHistory(p, dt)
                amp = MSPSpectrumAmplitude(ap)
                phase = MSPSpectrumPhase(ap)
                @test all(isapprox.(frequency(amp), freq_a2[(T,n)], atol=1e-12))
                @test all(isapprox.(frequency(phase), freq_a2[(T,n)], atol=1e-12))
                @test all(isapprox.(amp, nbs_msp_a2[(T,n)], atol=1e-12))
                # Checking the phase is tricky, since it involves the ratio of
                # the imaginary component to the real component of the MSP
                # spectrum (definition is phase = atan(imag(fft(p)),
                # real(fft(p)))). For the components of the spectrum that have
                # zero amplitude that ratio ends up being very noisy. So scale
                # the phase by the amplitude to remove the problematic
                # zero-amplitude components.
                @test all(isapprox.(phase.*amp, nbs_phase_a2[T, n].*nbs_msp_a2[T, n], atol=1e-12))
            end
        end
    end
end

@testset "Power Spectral Density" begin
    @testset "t0 == 0" begin
        for T in [1.0, 2.0]
            f(t) = 6 + 8*cos(1*2*pi/T*t + 0.2) + 2.5*cos(2*2*pi/T*t - 3.0) + 9*cos(3*2*pi/T*t + 3.1) + 0.5*cos(4*2*pi/T*t - 1.1) + 3*cos(5*2*pi/T*t + 0.2)
            for n in [10, 11]
                dt = T/n
                df = 1/T
                t = (0:n-1).*dt
                p = f.(t)
                ap = PressureTimeHistory(p, dt)
                amp = PowerSpectralDensityAmplitude(ap)
                phase = PowerSpectralDensityPhase(ap)
                freq_expected = [0.0, 1/T, 2/T, 3/T, 4/T, 5/T]
                amp_expected = similar(amp)
                amp_expected[1] = 6^2/df
                amp_expected[2] = 0.5*8^2/df
                amp_expected[3] = 0.5*2.5^2/df
                amp_expected[4] = 0.5*9^2/df
                amp_expected[5] = 0.5*0.5^2/df
                phase_expected = similar(phase)
                phase_expected[1] = 0
                phase_expected[2] = 0.2
                phase_expected[3] = -3
                phase_expected[4] = 3.1
                phase_expected[5] = -1.1
                # Handle the Nyquist frequency (kinda tricky). There isn't really a
                # Nyquist frequency for the odd input length case.
                if n == 10
                    amp_expected[6] = (3*cos(0.2))^2/df
                    phase_expected[6] = 0
                else
                    amp_expected[6] = 0.5*3^2/df
                    phase_expected[6] = 0.2
                end
                @test all(isapprox.(frequency(amp), freq_expected; atol=1e-12))
                @test all(isapprox.(frequency(phase), freq_expected; atol=1e-12))
                @test all(isapprox.(amp, amp_expected; atol=1e-12))
                @test all(isapprox.(phase.*amp, phase_expected.*amp_expected; atol=1e-12))

                # Make sure I can convert a PSD to a pressure spectrum.
                psamp = PressureSpectrumAmplitude(amp)
                amp_expected = similar(psamp)
                amp_expected[1] = 6
                amp_expected[2] = 8
                amp_expected[3] = 2.5
                amp_expected[4] = 9
                amp_expected[5] = 0.5
                # Handle the Nyquist frequency (kinda tricky). There isn't really a
                # Nyquist frequency for the odd input length case.
                if n == 10
                    amp_expected[6] = 3*cos(0.2)
                else
                    amp_expected[6] = 3
                end
                @test all(isapprox.(frequency(psamp), freq_expected; atol=1e-12))
                @test all(isapprox.(psamp, amp_expected; atol=1e-12))

                # Make sure I can convert a PSD to the acoustic pressure.
                ap_from_psd = PressureTimeHistory(amp)
                @test timestep(ap_from_psd) ≈ timestep(ap)
                @test starttime(ap_from_psd) ≈ starttime(ap)
                @test all(isapprox.(pressure(ap_from_psd), pressure(ap)))
            end
        end
    end

    @testset "t0 !== 0" begin
        for T in [1.0, 2.0]
            t0 = 0.13
            f(t) = 6 + 8*cos(1*2*pi/T*t + 0.2) + 2.5*cos(2*2*pi/T*t - 3.0) + 9*cos(3*2*pi/T*t + 3.1) + 0.5*cos(4*2*pi/T*t - 1.1) + 3*cos(5*2*pi/T*t + 0.2)
            for n in [10, 11]
                dt = T/n
                df = 1/T
                t = t0 .+ (0:n-1).*dt
                p = f.(t)
                ap = PressureTimeHistory(p, dt, t0)
                amp = PowerSpectralDensityAmplitude(ap)
                phase = PowerSpectralDensityPhase(ap)
                freq_expected = [0.0, 1/T, 2/T, 3/T, 4/T, 5/T]
                amp_expected = similar(amp)
                amp_expected[1] = 6^2/df
                amp_expected[2] = 0.5*8^2/df
                amp_expected[3] = 0.5*2.5^2/df
                amp_expected[4] = 0.5*9^2/df
                amp_expected[5] = 0.5*0.5^2/df
                phase_expected = similar(phase)
                phase_expected[1] = 0
                phase_expected[2] = 0.2
                phase_expected[3] = -3
                phase_expected[4] = 3.1
                phase_expected[5] = -1.1
                # Handle the Nyquist frequency (kinda tricky). There isn't really a
                # Nyquist frequency for the odd input length case.
                if n == 10
                    # amp_expected[6] = (3*cos(5*2*pi/T*t0 + 0.2))^2
                    # phase_expected[6] = rem2pi(-5*2*pi/T*t0, RoundNearest)
                    amp_expected[6] = (3*cos(5*2*pi/T*t0 + 0.2))^2/df
                    phase_expected[6] = rem2pi(pi - 5*2*pi/T*t0, RoundNearest)
                else
                    amp_expected[6] = 0.5*3^2/df
                    phase_expected[6] = 0.2
                end
                @test all(isapprox.(frequency(amp), freq_expected; atol=1e-12))
                @test all(isapprox.(frequency(phase), freq_expected; atol=1e-12))
                @test all(isapprox.(amp, amp_expected; atol=1e-12))
                @test all(isapprox.(phase, phase_expected; atol=1e-12))

                # Make sure I can convert a PSD to a pressure spectrum.
                psamp = PressureSpectrumAmplitude(amp)
                amp_expected = similar(psamp)
                amp_expected[1] = 6
                amp_expected[2] = 8
                amp_expected[3] = 2.5
                amp_expected[4] = 9
                amp_expected[5] = 0.5
                # Handle the Nyquist frequency (kinda tricky). There isn't really a
                # Nyquist frequency for the odd input length case.
                if n == 10
                    # The `t0` term pushes the cosine below zero, which messes
                    # up the test. Hmm... what's the right thing to do here?
                    # Well, what should the phase and amplitude be?
                    # amp_expected[6] = 3*cos(5*2*pi/T*t0 + 0.2)
                    amp_expected[6] = abs(3*cos(5*2*pi/T*t0 + 0.2))
                else
                    amp_expected[6] = 3
                end
                @test all(isapprox.(frequency(psamp), freq_expected; atol=1e-12))
                @test all(isapprox.(psamp, amp_expected; atol=1e-12))

                # Make sure I can convert a PSD to the acoustic pressure.
                ap_from_psd = PressureTimeHistory(amp)
                @test timestep(ap_from_psd) ≈ timestep(ap)
                @test starttime(ap_from_psd) ≈ starttime(ap)
                @test all(isapprox.(pressure(ap_from_psd), pressure(ap)))
            end
        end
    end

    @testset "ANOPP2 comparison" begin
        a2_data = load(joinpath(@__DIR__, "gen_anopp2_data", "psd.jld2"))
        freq_a2 = a2_data["a2_psd_freq"]
        psd_msp_a2 = a2_data["a2_psd_amp"]
        psd_phase_a2 = a2_data["a2_psd_phase"]
        for T in [1, 2]
            for n in [19, 20]
                dt = T/n
                t = (0:n-1).*dt
                p = apth_for_nbs.(t)
                ap = PressureTimeHistory(p, dt)
                amp = PowerSpectralDensityAmplitude(ap)
                phase = PowerSpectralDensityPhase(ap)
                @test all(isapprox.(frequency(amp), freq_a2[(T,n)], atol=1e-12))
                @test all(isapprox.(frequency(phase), freq_a2[(T,n)], atol=1e-12))
                @test all(isapprox.(amp, psd_msp_a2[(T,n)], atol=1e-12))
                # Checking the phase is tricky, since it involves the ratio of
                # the imaginary component to the real component of the MSP
                # spectrum (definition is phase = atan(imag(fft(p)),
                # real(fft(p)))). For the components of the spectrum that have
                # zero amplitude that ratio ends up being very noisy. So scale
                # the phase by the amplitude to remove the problematic
                # zero-amplitude components.
                @test all(isapprox.(phase.*amp, psd_phase_a2[T, n].*psd_msp_a2[T, n], atol=1e-12))
            end
        end
    end
end

@testset "Proportional Band Spectrum" begin
    @testset "exact octave" begin
        bands = ExactOctaveCenterBands(6, 16)
        bands_expected = [62.5, 125.0, 250.0, 500.0, 1000.0, 2000.0, 4000.0, 8000.0, 16000.0, 32000.0, 64000.0]
        @test all(isapprox.(bands, bands_expected))

        @test_throws BoundsError bands[0]
        @test_throws BoundsError bands[12]

        bands_9_to_11 = ExactOctaveCenterBands(9, 11)
        @test all(isapprox.(bands_9_to_11, bands_expected[4:6]))

        @test_throws BoundsError bands_9_to_11[0]
        @test_throws BoundsError bands_9_to_11[4]

        @test_throws ArgumentError ExactOctaveCenterBands(5, 4)

        lbands = ExactOctaveLowerBands(6, 16)
        @test all((log2.(bands) .- log2.(lbands)) .≈ 1/2)

        ubands = ExactOctaveUpperBands(6, 16)
        @test all((log2.(ubands) .- log2.(bands)) .≈ 1/2)

        @test all((log2.(ubands) .- log2.(lbands)) .≈ 1)

        cbands = ExactOctaveCenterBands(700.0, 22000.0)
        @test cbands.bstart == 9
        @test cbands.bend == 14

        lbands = ExactOctaveLowerBands(700.0, 22000.0)
        @test lbands.bstart == 9
        @test lbands.bend == 14

        ubands = ExactOctaveUpperBands(700.0, 22000.0)
        @test ubands.bstart == 9
        @test ubands.bend == 14

    end

    @testset "exact 1/3-octave" begin
        bands = ExactThirdOctaveCenterBands(17, 40)
        # These are just from the ANOPP2 manual.
        bands_expected_all = [49.61, 62.50, 78.75, 99.21, 125.00, 157.49, 198.43, 250.00, 314.98, 396.85, 500.00, 629.96, 793.70, 1000.0, 1259.92, 1587.40, 2000.00, 2519.84, 3174.80, 4000.00, 5039.68, 6349.60, 8000.00, 10079.37]
        @test all(isapprox.(bands, bands_expected_all; atol=0.005))

        @test_throws BoundsError bands[0]
        @test_throws BoundsError bands[25]

        bands_30_to_38 = ExactThirdOctaveCenterBands(30, 38)
        @test all(isapprox.(bands_30_to_38, bands_expected_all[14:end-2]; atol=0.005))

        @test_throws BoundsError bands_30_to_38[0]
        @test_throws BoundsError bands_30_to_38[10]

        @test_throws ArgumentError ExactThirdOctaveCenterBands(5, 4)

        lbands = ExactThirdOctaveLowerBands(17, 40)
        @test all((log2.(bands) .- log2.(lbands)) .≈ 1/(2*3))

        ubands = ExactThirdOctaveUpperBands(17, 40)
        @test all((log2.(ubands) .- log2.(bands)) .≈ 1/(2*3))

        @test all((log2.(ubands) .- log2.(lbands)) .≈ 1/3)

        cbands = ExactThirdOctaveCenterBands(332.0, 7150.0)
        @test cbands.bstart == 25
        @test cbands.bend == 39

        lbands = ExactThirdOctaveLowerBands(332.0, 7150.0)
        @test lbands.bstart == 25
        @test lbands.bend == 39

        ubands = ExactThirdOctaveUpperBands(332.0, 7150.0)
        @test ubands.bstart == 25
        @test ubands.bend == 39

        @testset "not-so-narrow narrowband spectrum" begin
            T = 1/1000.0
            t0 = 0.13
            f(t) = 6 + 8*cos(1*2*pi/T*t + 0.2) + 2.5*cos(2*2*pi/T*t - 3.0) + 9*cos(3*2*pi/T*t + 3.1) + 0.5*cos(4*2*pi/T*t - 1.1) + 3*cos(5*2*pi/T*t + 0.2)

            n = 10
            dt = T/n
            df = 1/T
            t = t0 .+ (0:n-1).*dt
            p = f.(t)
            ap = PressureTimeHistory(p, dt)
            psd = PowerSpectralDensityAmplitude(ap)
            pbs = ProportionalBandSpectrum(ExactProportionalBands{3}, psd)
            # So, this should have non-zero stuff at 1000 Hz, 2000 Hz, 3000 Hz, 4000 Hz, 5000 Hz.
            # And that means that, say, the 1000 Hz signal will exend from 500
            # Hz to 1500 Hz.
            # So then it will show up in a bunch of bands:
            #
            #   * 445 to 561
            #   * 561 to 707
            #   * 707 to 890
            #   * 890 to 1122
            #   * 1122 to 1414
            #   * 1414 to 1781
            # 
            # And that means the signal at 2000 will also show up at that last frequency.
            # So did I code this up properly?
            # I think so.
            # Here are all the bands that should be active:
            #
            # 1: 445.44935907016963, 561.2310241546866
            # 2: 561.2310241546866, 707.1067811865476
            # 3: 707.1067811865476, 890.8987181403395
            # 4: 890.8987181403393, 1122.4620483093731
            # 5: 1122.4620483093731, 1414.213562373095
            # 6: 1414.2135623730949, 1781.7974362806785
            # 7: 1781.7974362806785, 2244.9240966187463
            # 8: 2244.9240966187463, 2828.42712474619
            # 9: 2828.42712474619, 3563.594872561358
            # 10: 3563.594872561357, 4489.8481932374925
            # 11: 4489.8481932374925, 5656.85424949238
            lbands = lower_bands(pbs)
            ubands = upper_bands(pbs)
            @test pbs[1] ≈ 0.5*8^2/df*(ubands[1] - 500)
            @test pbs[2] ≈ 0.5*8^2/df*(ubands[2] - lbands[2])
            @test pbs[3] ≈ 0.5*8^2/df*(ubands[3] - lbands[3])
            @test pbs[4] ≈ 0.5*8^2/df*(ubands[4] - lbands[4])
            @test pbs[5] ≈ 0.5*8^2/df*(ubands[5] - lbands[5])
            @test pbs[6] ≈ 0.5*8^2/df*(1500 - lbands[6]) + 0.5*2.5^2/df*(ubands[6] - 1500)
            @test pbs[7] ≈ 0.5*2.5^2/df*(ubands[7] - lbands[7])
            @test pbs[8] ≈ 0.5*2.5^2/df*(2500 - lbands[8]) + 0.5*9^2/df*(ubands[8] - 2500)
            @test pbs[9] ≈ 0.5*9^2/df*(3500 - lbands[9]) + 0.5*0.5^2/df*(ubands[9] - 3500)
            @test pbs[10] ≈ 0.5*0.5^2/df*(ubands[10] - lbands[10])
            # Last one is wierd because of the Nyquist frequency.
            @test pbs[11] ≈ 0.5*0.5^2/df*(4500 - lbands[11]) + (3*cos(0.2))^2/df*(5500 - 4500)
        end

        @testset "narrowband spectrum, one narrowband per proportional band" begin
            freq0 = 1000.0
            T = 20/freq0
            t0 = 0.13
            f(t) = 6 + 8*cos(1*2*pi*freq0*t + 0.2) + 2.5*cos(2*2*pi*freq0*t - 3.0) + 9*cos(3*2*pi*freq0*t + 3.1)

            n = 128
            dt = T/n
            df = 1/T
            t = t0 .+ (0:n-1).*dt
            p = f.(t)
            ap = PressureTimeHistory(p, dt)
            psd = PowerSpectralDensityAmplitude(ap)
            pbs = ProportionalBandSpectrum(ExactProportionalBands{3}, psd)
            lbands = lower_bands(pbs)
            ubands = upper_bands(pbs)
            psd_freq = frequency(psd)
            @test psd_freq[21] ≈ freq0
            @test pbs[17] ≈ psd[21]*df
            @test psd_freq[41] ≈ 2*freq0
            @test pbs[20] ≈ psd[41]*df
            @test psd_freq[61] ≈ 3*freq0
            @test pbs[22] ≈ psd[61]*df
            # Make sure all the other PBS entries are zero.
            for (i, amp) in enumerate(pbs)
                if i ∉ [17, 20, 22]
                    @test isapprox(amp, 0.0; atol=1e-12)
                end
            end

            a2_data = load(joinpath(@__DIR__, "gen_anopp2_data", "pbs.jld2"))
            a2_freq = a2_data["a2_pbs_freq"]
            a2_pbs = a2_data["a2_pbs"]
            pbs_level = @. 10*log10(pbs/p_ref^2)
            # For some reason ANOPP2 doesn't give me the first four proportional
            # bands that I'd expect, but they're all zero anyway, so maybe
            # that's not important. But it also doesn't give me the last band I
            # expect, which is not zero. :-( The rest look good, though.
            for i in 1:length(a2_freq)
                @test center_bands(pbs)[i + 4] ≈ a2_freq[i]
                if a2_pbs[i] > 0
                    @test pbs_level[i + 4] ≈ a2_pbs[i]
                end
            end

        end

        @testset "narrowband spectrum, many narrowbands per proportional band" begin
            nfreq_nb = 800
            freq_min_nb = 55.0
            freq_max_nb = 1950.0
            df_nb = (freq_max_nb - freq_min_nb)/(nfreq_nb - 1)
            f_nb = freq_min_nb .+ (0:(nfreq_nb-1)).*df_nb
            psd = psd_func.(f_nb)
            pbs = ProportionalBandSpectrum(ExactProportionalBands{3}, freq_min_nb, df_nb, psd)
            cbands = center_bands(pbs)
            pbs_level = @. 10*log10(pbs/p_ref^2)

            a2_data = load(joinpath(@__DIR__, "gen_anopp2_data", "pbs3.jld2"))
            a2_pbs_freq = a2_data["a2_pbs_freq"]
            a2_pbs = a2_data["a2_pbs"]
            for i in 1:length(a2_pbs)
                # I'm not sure why ANOPP2 doesn't include all of the proportional bands I think it should.
                j = i + 1
                @test cbands[j] ≈ a2_pbs_freq[i]
                @test isapprox(pbs_level[j], a2_pbs[i]; atol=1e-2)
            end

        end

        # @testset "ANOPP2 docs example" begin
        #     n_freq = 2232
        #     psd_freq = 45.0 .+ 5 .* (0:n_freq-1)
        #     df = psd_freq[2] - psd_freq[1]
        #     msp_amp = 20 .+ 10 .* (1:n_freq)./n_freq
        #     psd_amp = msp_amp ./ df
        #     # pbs = ExactProportionalBandSpectrum{3}(first(psd_freq), df, psd_amp)
        #     pbs = ProportionalBandSpectrum(ExactProportionalBands{3}, first(psd_freq), df, psd_amp)
        #     cbands = center_bands(pbs)
        #     lbands = lower_bands(pbs)
        #     ubands = upper_bands(pbs)

        #     pbs_level = @. 10*log10(pbs/p_ref^2)
        #     # @show cbands pbs_level
        #     # @show length(cbands) length(pbs_level)
        # end

        @testset "convergence test" begin

            @testset "one band" begin
                freq_min, freq_max = 50.0, 2000.0
                lbands = ExactThirdOctaveLowerBands(freq_min, freq_max)
                cbands = ExactThirdOctaveCenterBands(freq_min, freq_max)
                ubands = ExactThirdOctaveUpperBands(freq_min, freq_max)
                for b in 1:length(cbands)
                    pbs_b_exact = psd_func_int(lbands[b], ubands[b])
                    errs = Vector{Float64}()
                    nfreqs = Vector{Int}()
                    for nfreq in 200:10:300
                        # df_nb = (freq_max - freq_min)/(nfreq - 1)
                        # f = freq_min .+ (0:nfreq-1).*df_nb
                        df_nb = (ubands[b] - lbands[b])/nfreq
                        f0 = lbands[b] + 0.5*df_nb
                        f1 = ubands[b] - 0.5*df_nb
                        f = f0 .+ (0:nfreq-1).*df_nb
                        psd = psd_func.(f)
                        pbs = ExactThirdOctaveSpectrum(f0, df_nb, psd)
                        if length(pbs) > 1
                            # We tried above to construct the narrowand frequencies
                            # to only cover the current 1/3-octave proportional
                            # band, i.e., the one that starts at lbands[b] and ends
                            # at ubands[b]. But because of floating point errors, we
                            # might end up with a tiny bit of the narrowband in the
                            # next proportional band. But only in the next one, so
                            # check that we only have two:
                            @test length(pbs) == 2
                            # And the amount of energy we have in the next band
                            # should be very small.
                            @test isapprox(pbs[2], 0; atol=1e-10)
                        end
                        @test center_bands(pbs)[1] ≈ cbands[b]
                        push!(nfreqs, nfreq)
                        push!(errs, abs(pbs[1] - pbs_b_exact))
                    end
                    # So here we're assuming that 
                    #
                    #       err ≈ 1/(nfreq^p)
                    #
                    # We want to find `p`.
                    # If we take the error for two different values of `nfreq` and find their ratio:
                    #
                    #       err2/err1 = nfreq1^p/nfreq2^p
                    #       log(err2/err1) = p*log(nfreq1/nfreq2)
                    #       p = log(err2/err1)/log(nfreq1/nfreq2)
                    #
                    # p = log.(errs[2:end]./errs[1:end-1])./log.(nfreqs[1:end-1]./nfreqs[2:end])
                    # @show b errs p
                    # 
                    # But here we'll just use the Polynomials package to fit a line though the error as a function of nfreq on a log-log plot.
                    l = Polynomials.fit(log.(nfreqs), log.(errs), 1)
                    # @show l.coeffs[2]
                    @test isapprox(l.coeffs[2], -2; atol=1e-5)
                end
            end

            @testset "many bands" begin
                freq_min, freq_max = 50.0, 2000.0
                lbands = ExactThirdOctaveLowerBands(freq_min, freq_max)
                cbands = ExactThirdOctaveCenterBands(freq_min, freq_max)
                ubands = ExactThirdOctaveUpperBands(freq_min, freq_max)
                for b in 1:length(cbands)
                    pbs_b_exact = psd_func_int(lbands[b], ubands[b])
                    errs = Vector{Float64}()
                    nfreqs_b = Vector{Int}()
                    for nfreq_b in 200:10:300
                        # OK, I want to decide on a frequency spacing that will
                        # fit nicely in the current band.
                        df_nb = (ubands[b] - lbands[b])/nfreq_b

                        # This is where I want the narrowband frequencies to start in the current band `b`.
                        f0 = lbands[b] + 0.5*df_nb
                        f1 = ubands[b] - 0.5*df_nb

                        # But now I want the actual narrowband frequency to cover freq_min and freq_max.
                        # So I need to figure out how many bins I need before f0 and after f1.
                        n_before_f0 = Int(floor((f0 - (lbands[1] + 0.5*df_nb)) / df_nb))
                        n_after_f1 = Int(floor(((ubands[end] - 0.5*df_nb) - f1) / df_nb))

                        # So now I should be able to get the narrowband frequencies.
                        f = f0 .+ (-n_before_f0 : (nfreq_b-1)+n_after_f1).*df_nb

                        # Now the PSD for the entire narrowband range.
                        psd = psd_func.(f)

                        # And the PBS
                        # pbs = ExactProportionalBandSpectrum{3}(f[1], df_nb, psd)
                        pbs = ExactThirdOctaveSpectrum(f[1], df_nb, psd)

                        # We created a narrowband range that should cover from freq_min to freq_max, so the sizes should be the same.
                        @test length(pbs) == length(cbands)
                        @test pbs.cbands.bstart == cbands.bstart
                        @test pbs.cbands.bend == cbands.bend
                        push!(nfreqs_b, nfreq_b)
                        # We only want to check the error for the current band.
                        push!(errs, abs(pbs[b] - pbs_b_exact))
                    end
                    # So here we're assuming that 
                    #
                    #       err ≈ 1/(nfreq^p)
                    #
                    # We want to find `p`.
                    # If we take the error for two different values of `nfreq` and find their ratio:
                    #
                    #       err2/err1 = nfreq1^p/nfreq2^p
                    #       log(err2/err1) = p*log(nfreq1/nfreq2)
                    #       p = log(err2/err1)/log(nfreq1/nfreq2)
                    #
                    # p = log.(errs[2:end]./errs[1:end-1])./log.(nfreqs_b[1:end-1]./nfreqs_b[2:end])
                    # @show b errs p
                    # 
                    # But here we'll just use the Polynomials package to fit a line though the error as a function of nfreq on a log-log plot.
                    l = Polynomials.fit(log.(nfreqs_b), log.(errs), 1)
                    # @show l.coeffs[2]
                    @test isapprox(l.coeffs[2], -2; atol=1e-5)
                end
            end
        end
    end

    @testset "approximate octave" begin
        cbands = ApproximateOctaveCenterBands(0, 20)
        cbands_expected = [1.0, 2.0, 4.0, 8.0, 16.0, 31.5, 63, 125.0, 250.0, 500.0, 1000.0, 2000.0, 4000.0, 8000.0, 16e3, 31.5e3, 63e3, 125e3, 250e3, 500e3, 1000e3]
        @test all(cbands .≈ cbands_expected)

        lbands = ApproximateOctaveLowerBands(0, 20)
        lbands_expected = [0.71, 1.42, 2.84, 5.68, 11.0, 22.0, 44.0, 88.0, 177.0, 355.0, 0.71e3, 1.42e3, 2.84e3, 5.68e3, 11.0e3, 22e3, 44e3, 88e3, 177e3, 355e3, 0.71e6]
        @test all(lbands .≈ lbands_expected)

        ubands = ApproximateOctaveUpperBands(0, 20)
        ubands_expected = [1.42, 2.84, 5.68, 11.0, 22.0, 44.0, 88.0, 177.0, 355.0, 0.71e3, 1.42e3, 2.84e3, 5.68e3, 11.0e3, 22e3, 44e3, 88e3, 177e3, 355e3, 0.71e6, 1.42e6]
        @test all(ubands .≈ ubands_expected)

        cbands = ApproximateOctaveCenterBands(-20, 0)
        cbands_expected = [1.0e-6, 2.0e-6, 4.0e-6, 8.0e-6, 16.0e-6, 31.5e-6, 63e-6, 125.0e-6, 250.0e-6, 500.0e-6, 1000.0e-6, 2000.0e-6, 4000.0e-6, 8000.0e-6, 16e-3, 31.5e-3, 63e-3, 125e-3, 250e-3, 500e-3, 1000e-3]
        @test all(cbands .≈ cbands_expected)

        lbands = ApproximateOctaveLowerBands(-20, 0)
        lbands_expected = [0.71e-6, 1.42e-6, 2.84e-6, 5.68e-6, 11.0e-6, 22.0e-6, 44.0e-6, 88.0e-6, 177.0e-6, 355.0e-6, 0.71e-3, 1.42e-3, 2.84e-3, 5.68e-3, 11.0e-3, 22e-3, 44e-3, 88e-3, 177e-3, 355e-3, 0.71]
        @test all(lbands .≈ lbands_expected)

        ubands = ApproximateOctaveUpperBands(-20, 0)
        ubands_expected = [1.42e-6, 2.84e-6, 5.68e-6, 11.0e-6, 22.0e-6, 44.0e-6, 88.0e-6, 177.0e-6, 355.0e-6, 0.71e-3, 1.42e-3, 2.84e-3, 5.68e-3, 11.0e-3, 22e-3, 44e-3, 88e-3, 177e-3, 355e-3, 0.71, 1.42]
        @test all(ubands .≈ ubands_expected)

        cbands = ApproximateOctaveCenterBands(2.2, 30.5e3)
        @test cbands.bstart == 1
        @test cbands.bend == 15

        lbands = ApproximateOctaveLowerBands(2.2, 30.5e3)
        @test lbands.bstart == 1
        @test lbands.bend == 15

        ubands = ApproximateOctaveUpperBands(2.2, 30.5e3)
        @test ubands.bstart == 1
        @test ubands.bend == 15

        cbands = ApproximateOctaveCenterBands(23.0e-6, 2.8e-3)
        @test cbands.bstart == -15
        @test cbands.bend == -9

        lbands = ApproximateOctaveLowerBands(23.0e-6, 2.8e-3)
        @test lbands.bstart == -15
        @test lbands.bend == -9

        ubands = ApproximateOctaveUpperBands(23.0e-6, 2.8e-3)
        @test ubands.bstart == -15
        @test ubands.bend == -9

        @testset "spectrum, normal case" begin
            freq_min_nb = 55.0
            freq_max_nb = 1950.0
            df_nb = 2.0
            f_nb = freq_min_nb:df_nb:freq_max_nb
            psd = psd_func.(f_nb)
            pbs = ProportionalBandSpectrum(ApproximateOctaveBands, freq_min_nb, df_nb, psd)
            lbands = lower_bands(pbs)
            cbands = center_bands(pbs)
            ubands = upper_bands(pbs)
            # So, the narrowband frequency range is from 55 - 0.5*2 = 54 to 1950 + 0.5*2 = 1951.0
            # So we should be using bands 6 to 11.
            @test band_start(cbands) == 6
            @test band_end(cbands) == 11
            # Now, let's add up what each band's answer should be.
            # Do I need to worry about the min and max stuff?
            # I know that I've picked bands that fully cover the input PSD frequency.
            # But, say, for the first band, it is possible that the lower edge of the first band is much lower than the lower edge of the first proportional band.
            # So I do need to do that.
            # Similar for the last band.
            # But I don't think it's necessary for the inner ones.
            for (lband, uband, pbs_b) in zip(lbands, ubands, pbs)
                istart = searchsortedfirst(f_nb .+ 0.5*df_nb, lband)
                res_first = psd[istart]*(min(uband, f_nb[istart] + 0.5*df_nb) - max(lband, f_nb[istart] - 0.5*df_nb))
                iend = searchsortedfirst(f_nb .+ 0.5*df_nb, uband)
                if iend > lastindex(f_nb)
                    iend = lastindex(f_nb)
                end
                if iend == istart
                    res_last = zero(eltype(psd))
                else
                    res_last = psd[iend]*(min(uband, f_nb[iend] + 0.5*df_nb) - max(lband, f_nb[iend] - 0.5*df_nb))
                end
                res = res_first + sum(psd[istart+1:iend-1].*df_nb) + res_last
                @test pbs_b ≈ res
            end
        end

        @testset "spectrum, lowest narrowband on a right edge" begin
            freq_min_nb = 87.0
            freq_max_nb = 1950.0
            df_nb = 2.0
            f_nb = freq_min_nb:df_nb:freq_max_nb
            psd = psd_func.(f_nb)
            pbs = ProportionalBandSpectrum(ApproximateOctaveBands, freq_min_nb, df_nb, psd)
            lbands = lower_bands(pbs)
            cbands = center_bands(pbs)
            ubands = upper_bands(pbs)
            # So, the narrowband frequency range is from 87 - 0.5*2 = 86 to 1950 + 0.5*2 = 1951.0
            # So we should be using bands 6 to 11.
            @test band_start(cbands) == 6
            @test band_end(cbands) == 11
            @test ubands[1] ≈ freq_min_nb + 0.5*df_nb
            for (lband, uband, pbs_b) in zip(lbands, ubands, pbs)
                istart = searchsortedfirst(f_nb .+ 0.5*df_nb, lband)
                res_first = psd[istart]*(min(uband, f_nb[istart] + 0.5*df_nb) - max(lband, f_nb[istart] - 0.5*df_nb))
                iend = searchsortedfirst(f_nb .+ 0.5*df_nb, uband)
                if iend > lastindex(f_nb)
                    iend = lastindex(f_nb)
                end
                if iend == istart
                    res_last = zero(eltype(psd))
                else
                    res_last = psd[iend]*(min(uband, f_nb[iend] + 0.5*df_nb) - max(lband, f_nb[iend] - 0.5*df_nb))
                end
                res = res_first + sum(psd[istart+1:iend-1].*df_nb) + res_last
                @test pbs_b ≈ res
            end
        end

        @testset "spectrum, lowest narrowband on a left edge" begin
            freq_min_nb = 89.0
            freq_max_nb = 1950.0
            df_nb = 2.0
            f_nb = freq_min_nb:df_nb:freq_max_nb
            psd = psd_func.(f_nb)
            pbs = ProportionalBandSpectrum(ApproximateOctaveBands, freq_min_nb, df_nb, psd)
            lbands = lower_bands(pbs)
            cbands = center_bands(pbs)
            ubands = upper_bands(pbs)
            # So, the narrowband frequency range is from 89 - 0.5*2 = 88 to 1950 + 0.5*2 = 1951.0
            # So we should be using bands 7 to 11.
            # But because of floating point roundoff, the code actually picks 6 as the starting band.
            @test band_start(cbands) == 6
            @test band_end(cbands) == 11
            @test lbands[2] ≈ freq_min_nb - 0.5*df_nb
            for (lband, uband, pbs_b) in zip(lbands, ubands, pbs)
                istart = searchsortedfirst(f_nb .+ 0.5*df_nb, lband)
                res_first = psd[istart]*(min(uband, f_nb[istart] + 0.5*df_nb) - max(lband, f_nb[istart] - 0.5*df_nb))
                iend = searchsortedfirst(f_nb .+ 0.5*df_nb, uband)
                if iend > lastindex(f_nb)
                    iend = lastindex(f_nb)
                end
                if iend == istart
                    res_last = zero(eltype(psd))
                else
                    res_last = psd[iend]*(min(uband, f_nb[iend] + 0.5*df_nb) - max(lband, f_nb[iend] - 0.5*df_nb))
                end
                res = res_first + sum(psd[istart+1:iend-1].*df_nb) + res_last
                @test pbs_b ≈ res
            end
        end

        @testset "spectrum, highest narrowband on a left edge" begin
            freq_min_nb = 55.0
            freq_max_nb = 1421.0
            df_nb = 2.0
            f_nb = freq_min_nb:df_nb:freq_max_nb
            psd = psd_func.(f_nb)
            pbs = ProportionalBandSpectrum(ApproximateOctaveBands, freq_min_nb, df_nb, psd)
            lbands = lower_bands(pbs)
            cbands = center_bands(pbs)
            ubands = upper_bands(pbs)
            # So, the narrowband frequency range is from 55 - 0.5*2 = 54 to 1421.0 + 0.5*2 = 1422.0
            # So we should be using bands 6 to 11.
            @test band_start(cbands) == 6
            @test band_end(cbands) == 11
            @test lbands[end] ≈ freq_max_nb - 0.5*df_nb
            # Now, let's add up what each band's answer should be.
            # Do I need to worry about the min and max stuff?
            # I know that I've picked bands that fully cover the input PSD frequency.
            # But, say, for the first band, it is possible that the lower edge of the first band is much lower than the lower edge of the first proportional band.
            # So I do need to do that.
            # Similar for the last band.
            # But I don't think it's necessary for the inner ones.
            for (lband, uband, pbs_b) in zip(lbands, ubands, pbs)
                istart = searchsortedfirst(f_nb .+ 0.5*df_nb, lband)
                res_first = psd[istart]*(min(uband, f_nb[istart] + 0.5*df_nb) - max(lband, f_nb[istart] - 0.5*df_nb))
                iend = searchsortedfirst(f_nb .+ 0.5*df_nb, uband)
                if iend > lastindex(f_nb)
                    iend = lastindex(f_nb)
                end
                if iend == istart
                    res_last = zero(eltype(psd))
                else
                    res_last = psd[iend]*(min(uband, f_nb[iend] + 0.5*df_nb) - max(lband, f_nb[iend] - 0.5*df_nb))
                end
                res = res_first + sum(psd[istart+1:iend-1].*df_nb) + res_last
                @test pbs_b ≈ res
            end
        end

        @testset "spectrum, highest narrowband on a right edge" begin
            freq_min_nb = 55.0
            freq_max_nb = 1419.0
            df_nb = 2.0
            f_nb = freq_min_nb:df_nb:freq_max_nb
            psd = psd_func.(f_nb)
            pbs = ProportionalBandSpectrum(ApproximateOctaveBands, freq_min_nb, df_nb, psd)
            lbands = lower_bands(pbs)
            cbands = center_bands(pbs)
            ubands = upper_bands(pbs)
            # So, the narrowband frequency range is from 55 - 0.5*2 = 54 to 1419.0 + 0.5*2 = 1420.0
            # So we should be using bands 6 to 10.
            @test band_start(cbands) == 6
            @test band_end(cbands) == 10
            @test ubands[end] ≈ freq_max_nb + 0.5*df_nb
            # Now, let's add up what each band's answer should be.
            # Do I need to worry about the min and max stuff?
            # I know that I've picked bands that fully cover the input PSD frequency.
            # But, say, for the first band, it is possible that the lower edge of the first band is much lower than the lower edge of the first proportional band.
            # So I do need to do that.
            # Similar for the last band.
            # But I don't think it's necessary for the inner ones.
            for (lband, uband, pbs_b) in zip(lbands, ubands, pbs)
                istart = searchsortedfirst(f_nb .+ 0.5*df_nb, lband)
                res_first = psd[istart]*(min(uband, f_nb[istart] + 0.5*df_nb) - max(lband, f_nb[istart] - 0.5*df_nb))
                iend = searchsortedfirst(f_nb .+ 0.5*df_nb, uband)
                if iend > lastindex(f_nb)
                    iend = lastindex(f_nb)
                end
                if iend == istart
                    res_last = zero(eltype(psd))
                else
                    res_last = psd[iend]*(min(uband, f_nb[iend] + 0.5*df_nb) - max(lband, f_nb[iend] - 0.5*df_nb))
                end
                res = res_first + sum(psd[istart+1:iend-1].*df_nb) + res_last
                @test pbs_b ≈ res
            end
        end
    end

    @testset "approximate 1/3rd octave" begin
        cbands = ApproximateThirdOctaveCenterBands(0, 30)
        cbands_expected = [1.0, 1.25, 1.6, 2.0, 2.5, 3.15, 4.0, 5.0, 6.3, 8.0, 1.0e1, 1.25e1, 1.6e1, 2.0e1, 2.5e1, 3.15e1, 4.0e1, 5.0e1, 6.3e1, 8.0e1, 1.0e2, 1.25e2, 1.6e2, 2.0e2, 2.5e2, 3.15e2, 4.0e2, 5.0e2, 6.3e2, 8.0e2, 1.0e3]
        @test all(cbands .≈ cbands_expected)

        lbands = ApproximateThirdOctaveLowerBands(0, 30)
        lbands_expected = [0.9, 1.12, 1.4, 1.8, 2.24, 2.8, 3.35, 4.5, 5.6, 7.1, 0.9e1, 1.12e1, 1.4e1, 1.8e1, 2.24e1, 2.8e1, 3.35e1, 4.5e1, 5.6e1, 7.1e1, 0.9e2, 1.12e2, 1.4e2, 1.8e2, 2.24e2, 2.8e2, 3.35e2, 4.5e2, 5.6e2, 7.1e2, 0.9e3]
        @test all(lbands .≈ lbands_expected)

        ubands = ApproximateThirdOctaveUpperBands(0, 30)
        ubands_expected = [1.12, 1.4, 1.8, 2.24, 2.8, 3.35, 4.5, 5.6, 7.1, 0.9e1, 1.12e1, 1.4e1, 1.8e1, 2.24e1, 2.8e1, 3.35e1, 4.5e1, 5.6e1, 7.1e1, 0.9e2, 1.12e2, 1.4e2, 1.8e2, 2.24e2, 2.8e2, 3.35e2, 4.5e2, 5.6e2, 7.1e2, 0.9e3, 1.12e3]
        @test all(ubands .≈ ubands_expected)

        cbands = ApproximateThirdOctaveCenterBands(-30, 0)
        cbands_expected = [1.0e-3, 1.25e-3, 1.6e-3, 2.0e-3, 2.5e-3, 3.15e-3, 4.0e-3, 5.0e-3, 6.3e-3, 8.0e-3, 1.0e-2, 1.25e-2, 1.6e-2, 2.0e-2, 2.5e-2, 3.15e-2, 4.0e-2, 5.0e-2, 6.3e-2, 8.0e-2, 1.0e-1, 1.25e-1, 1.6e-1, 2.0e-1, 2.5e-1, 3.15e-1, 4.0e-1, 5.0e-1, 6.3e-1, 8.0e-1, 1.0]
        @test all(cbands .≈ cbands_expected)

        lbands = ApproximateThirdOctaveLowerBands(-30, 0)
        lbands_expected = [0.9e-3, 1.12e-3, 1.4e-3, 1.8e-3, 2.24e-3, 2.8e-3, 3.35e-3, 4.5e-3, 5.6e-3, 7.1e-3, 0.9e-2, 1.12e-2, 1.4e-2, 1.8e-2, 2.24e-2, 2.8e-2, 3.35e-2, 4.5e-2, 5.6e-2, 7.1e-2, 0.9e-1, 1.12e-1, 1.4e-1, 1.8e-1, 2.24e-1, 2.8e-1, 3.35e-1, 4.5e-1, 5.6e-1, 7.1e-1, 0.9]
        @test all(lbands .≈ lbands_expected)

        ubands = ApproximateThirdOctaveUpperBands(-30, 0)
        ubands_expected = [1.12e-3, 1.4e-3, 1.8e-3, 2.24e-3, 2.8e-3, 3.35e-3, 4.5e-3, 5.6e-3, 7.1e-3, 0.9e-2, 1.12e-2, 1.4e-2, 1.8e-2, 2.24e-2, 2.8e-2, 3.35e-2, 4.5e-2, 5.6e-2, 7.1e-2, 0.9e-1, 1.12e-1, 1.4e-1, 1.8e-1, 2.24e-1, 2.8e-1, 3.35e-1, 4.5e-1, 5.6e-1, 7.1e-1, 0.9, 1.12]
        @test all(ubands .≈ ubands_expected)

        @testset "spectrum, normal case" begin
            freq_min_nb = 50.0
            freq_max_nb = 1950.0
            df_nb = 2.0
            f_nb = freq_min_nb:df_nb:freq_max_nb
            psd = psd_func.(f_nb)
            pbs = ProportionalBandSpectrum(ApproximateThirdOctaveBands, freq_min_nb, df_nb, psd)
            lbands = lower_bands(pbs)
            cbands = center_bands(pbs)
            ubands = upper_bands(pbs)
            # So, the narrowband frequency range is from 50 - 0.5*2 = 49 to 1950 + 0.5*2 = 1951.0
            # So we should be using bands 17 to 33.
            @test band_start(cbands) == 17
            @test band_end(cbands) == 33
            for (lband, uband, pbs_b) in zip(lbands, ubands, pbs)
                istart = searchsortedfirst(f_nb .+ 0.5*df_nb, lband)
                res_first = psd[istart]*(min(uband, f_nb[istart] + 0.5*df_nb) - max(lband, f_nb[istart] - 0.5*df_nb))
                iend = searchsortedfirst(f_nb .+ 0.5*df_nb, uband)
                if iend > lastindex(f_nb)
                    iend = lastindex(f_nb)
                end
                if iend == istart
                    res_last = zero(eltype(psd))
                else
                    res_last = psd[iend]*(min(uband, f_nb[iend] + 0.5*df_nb) - max(lband, f_nb[iend] - 0.5*df_nb))
                end
                res = res_first + sum(psd[istart+1:iend-1].*df_nb) + res_last
                @test pbs_b ≈ res
            end
        end

        @testset "spectrum, lowest narrowband on a right edge" begin
            freq_min_nb = 55.0
            freq_max_nb = 1950.0
            df_nb = 2.0
            f_nb = freq_min_nb:df_nb:freq_max_nb
            psd = psd_func.(f_nb)
            pbs = ProportionalBandSpectrum(ApproximateThirdOctaveBands, freq_min_nb, df_nb, psd)
            lbands = lower_bands(pbs)
            cbands = center_bands(pbs)
            ubands = upper_bands(pbs)
            # So, the narrowband frequency range is from 50 - 0.5*2 = 49 to 1950 + 0.5*2 = 1951.0
            # So we should be using bands 17 to 33.
            @test band_start(cbands) == 17
            @test band_end(cbands) == 33
            @test ubands[1] ≈ freq_min_nb + 0.5*df_nb
            # Now, let's add up what each band's answer should be.
            # Do I need to worry about the min and max stuff?
            # I know that I've picked bands that fully cover the input PSD frequency.
            # But, say, for the first band, it is possible that the lower edge of the first band is much lower than the lower edge of the first proportional band.
            # So I do need to do that.
            # Similar for the last band.
            # But I don't think it's necessary for the inner ones.
            #
            # Hmm... first PBS band isn't passing.
            # The first PBS band goes from 45 Hz to 56 Hz.
            # This PSD would have just one band there, centered on 55 Hz, extending from 54 to 56 Hz.
            # So, that bin width should be 2 Hz.
            # Looks like that's what I'm doing.
            # Oh, wait.
            # Maybe I'm adding it twice here?
            # Let's see...
            # `f_nb .+ 0.5*df_nb = [56, 57, 58, 59...]`
            # And the upper band edge for the first PBS is 56.
            # So is `iend` here 1, or 2?
            # `iend == 1`, same as `istart`.
            # So I bet that has something to do with it.
            # Yeah, looks like I'm adding this band twice, right?
            # Yep, so need to deal with that.
            # Fixed it.
            for (lband, uband, pbs_b) in zip(lbands, ubands, pbs)
                istart = searchsortedfirst(f_nb .+ 0.5*df_nb, lband)
                res_first = psd[istart]*(min(uband, f_nb[istart] + 0.5*df_nb) - max(lband, f_nb[istart] - 0.5*df_nb))
                iend = searchsortedfirst(f_nb .+ 0.5*df_nb, uband)
                if iend > lastindex(f_nb)
                    iend = lastindex(f_nb)
                end
                if iend == istart
                    res_last = zero(eltype(psd))
                else
                    res_last = psd[iend]*(min(uband, f_nb[iend] + 0.5*df_nb) - max(lband, f_nb[iend] - 0.5*df_nb))
                end
                res = res_first + sum(psd[istart+1:iend-1].*df_nb) + res_last
                @test pbs_b ≈ res
            end
        end

        @testset "spectrum, lowest narrowband on a left edge" begin
            freq_min_nb = 57.0
            freq_max_nb = 1950.0
            df_nb = 2.0
            f_nb = freq_min_nb:df_nb:freq_max_nb
            psd = psd_func.(f_nb)
            pbs = ProportionalBandSpectrum(ApproximateThirdOctaveBands, freq_min_nb, df_nb, psd)
            lbands = lower_bands(pbs)
            cbands = center_bands(pbs)
            ubands = upper_bands(pbs)
            # So, the narrowband frequency range is from 57 - 0.5*2 = 56 to 1950 + 0.5*2 = 1951.0
            # So we should be using bands 18 to 33.
            # But, actually, because of numerical roundoff stuff, the code picks 17.
            @test band_start(cbands) == 17
            @test band_end(cbands) == 33
            # Because of floating point inaccuracy stuff, the code picks one proportional band lower than I think it should.
            @test lbands[2] ≈ freq_min_nb - 0.5*df_nb
            for (lband, uband, pbs_b) in zip(lbands, ubands, pbs)
                istart = searchsortedfirst(f_nb .+ 0.5*df_nb, lband)
                res_first = psd[istart]*(min(uband, f_nb[istart] + 0.5*df_nb) - max(lband, f_nb[istart] - 0.5*df_nb))
                iend = searchsortedfirst(f_nb .+ 0.5*df_nb, uband)
                if iend > lastindex(f_nb)
                    iend = lastindex(f_nb)
                end
                if iend == istart
                    res_last = zero(eltype(psd))
                else
                    res_last = psd[iend]*(min(uband, f_nb[iend] + 0.5*df_nb) - max(lband, f_nb[iend] - 0.5*df_nb))
                end
                res = res_first + sum(psd[istart+1:iend-1].*df_nb) + res_last
                @test pbs_b ≈ res
            end
        end

        @testset "spectrum, highest narrowband on a right edge" begin
            freq_min_nb = 50.0
            freq_max_nb = 1799.0
            df_nb = 2.0
            f_nb = freq_min_nb:df_nb:freq_max_nb
            psd = psd_func.(f_nb)
            pbs = ProportionalBandSpectrum(ApproximateThirdOctaveBands, freq_min_nb, df_nb, psd)
            lbands = lower_bands(pbs)
            cbands = center_bands(pbs)
            ubands = upper_bands(pbs)
            # So, the narrowband frequency range is from 50 - 0.5*2 = 49 to 1799 + 0.5*2 = 1800.0
            # So we should be using bands 17 to 32.
            @test band_start(cbands) == 17
            @test band_end(cbands) == 32
            @test ubands[end] ≈ freq_max_nb + 0.5*df_nb
            for (lband, uband, pbs_b) in zip(lbands, ubands, pbs)
                istart = searchsortedfirst(f_nb .+ 0.5*df_nb, lband)
                res_first = psd[istart]*(min(uband, f_nb[istart] + 0.5*df_nb) - max(lband, f_nb[istart] - 0.5*df_nb))
                iend = searchsortedfirst(f_nb .+ 0.5*df_nb, uband)
                if iend > lastindex(f_nb)
                    iend = lastindex(f_nb)
                end
                if iend == istart
                    res_last = zero(eltype(psd))
                else
                    res_last = psd[iend]*(min(uband, f_nb[iend] + 0.5*df_nb) - max(lband, f_nb[iend] - 0.5*df_nb))
                end
                res = res_first + sum(psd[istart+1:iend-1].*df_nb) + res_last
                @test pbs_b ≈ res
            end
        end

        @testset "spectrum, highest narrowband on a left edge" begin
            freq_min_nb = 50.0
            freq_max_nb = 1801.0
            df_nb = 2.0
            f_nb = freq_min_nb:df_nb:freq_max_nb
            psd = psd_func.(f_nb)
            pbs = ProportionalBandSpectrum(ApproximateThirdOctaveBands, freq_min_nb, df_nb, psd)
            lbands = lower_bands(pbs)
            cbands = center_bands(pbs)
            ubands = upper_bands(pbs)
            # So, the narrowband frequency range is from 50 - 0.5*2 = 49 to 1801 + 0.5*2 = 1802.0
            # So we should be using bands 17 to 33.
            @test band_start(cbands) == 17
            @test band_end(cbands) == 33
            @test lbands[end] ≈ freq_max_nb - 0.5*df_nb
            for (lband, uband, pbs_b) in zip(lbands, ubands, pbs)
                istart = searchsortedfirst(f_nb .+ 0.5*df_nb, lband)
                res_first = psd[istart]*(min(uband, f_nb[istart] + 0.5*df_nb) - max(lband, f_nb[istart] - 0.5*df_nb))
                iend = searchsortedfirst(f_nb .+ 0.5*df_nb, uband)
                if iend > lastindex(f_nb)
                    iend = lastindex(f_nb)
                end
                if iend == istart
                    res_last = zero(eltype(psd))
                else
                    res_last = psd[iend]*(min(uband, f_nb[iend] + 0.5*df_nb) - max(lband, f_nb[iend] - 0.5*df_nb))
                end
                res = res_first + sum(psd[istart+1:iend-1].*df_nb) + res_last
                @test pbs_b ≈ res
            end
        end
    end
end

@testset "OASPL" begin
    @testset "Parseval's theorem" begin
        fr(t) = 2*cos(1*2*pi*t) + 4*cos(2*2*pi*t) + 6*cos(3*2*pi*t) + 8*cos(4*2*pi*t)
        fi(t) = 2*sin(1*2*pi*t) + 4*sin(2*2*pi*t) + 6*sin(3*2*pi*t) + 8*sin(4*2*pi*t)
        f(t) = fr(t) + fi(t)
        for T in [1.0, 2.0]
            for n in [19, 20]
                dt = T/n
                t = (0:n-1).*dt
                p = f.(t)
                ap = PressureTimeHistory(p, dt)
                amp = MSPSpectrumAmplitude(ap)
                oaspl_time_domain = OASPL(ap)
                oaspl_freq_domain = OASPL(amp)
                @test oaspl_freq_domain ≈ oaspl_time_domain
            end
        end
    end
    @testset "function with know mean squared pressure" begin
        f(t) = 4*cos(2*2*pi*t)
        # What's the mean-square of that function? I think the mean-square of
        # 
        #   f(t) = a*cos(2*pi*k*t) 
        # 
        # is a^2/2. So
        for T in [1.0, 2.0]
            for n in [19, 20]
                dt = T/n
                t = (0:n-1).*dt
                p = f.(t)
                msp_expected = 4^2/2
                oaspl_expected = 10*log10(msp_expected/p_ref^2)
                ap = PressureTimeHistory(p, dt)
                amp = MSPSpectrumAmplitude(ap)
                oaspl_time_domain = OASPL(ap)
                oaspl_freq_domain = OASPL(amp)
                @test oaspl_time_domain ≈ oaspl_expected
                @test oaspl_freq_domain ≈ oaspl_expected
            end
        end
    end
    @testset "ANOPP2 comparison" begin
        fr(t) = 2*cos(1*2*pi*t) + 4*cos(2*2*pi*t) + 6*cos(3*2*pi*t) + 8*cos(4*2*pi*t)
        fi(t) = 2*sin(1*2*pi*t) + 4*sin(2*2*pi*t) + 6*sin(3*2*pi*t) + 8*sin(4*2*pi*t)
        f(t) = fr(t) + fi(t)
        oaspl_a2 = 114.77121254719663
        for T in [1, 2]
            for n in [19, 20]
                dt = T/n
                t = (0:n-1).*dt
                p = f.(t)
                ap = PressureTimeHistory(p, dt)
                oaspl = OASPL(ap)
                @test isapprox(oaspl, oaspl_a2, atol=1e-12)
            end
        end
    end
end

@testset "A-weighting" begin
    @testset "ANOPP2 comparison" begin
        fr(t) = 2*cos(1e3*2*pi*t) + 4*cos(2e3*2*pi*t) + 6*cos(3e3*2*pi*t) + 8*cos(4e3*2*pi*t)
        fi(t) = 2*sin(1e3*2*pi*t) + 4*sin(2e3*2*pi*t) + 6*sin(3e3*2*pi*t) + 8*sin(4e3*2*pi*t)
        f(t) = fr(t) + fi(t)
        nbs_A_a2 = Dict(
          (1, 19)=>[0.0, 4.000002539852234, 21.098932320239594, 47.765983983028875, 79.89329612328712, 6.904751939255882e-29, 3.438658433244509e-29, 3.385314868430938e-29, 4.3828241499153937e-29, 3.334042101984942e-29],
          (1, 20)=>[0.0, 4.000002539852235, 21.09893232023959, 47.76598398302881, 79.89329612328707, 2.4807405180395723e-29, 3.319538256490389e-29, 1.1860147288201262e-29, 1.5894684286161776e-29, 9.168407004474984e-30, 1.4222371367588704e-31],
          (2, 19)=>[0.0, 4.137956256384954e-30, 4.00000253985224, 2.1118658029791977e-29, 21.098932320239633, 3.4572972532471526e-29, 47.765983983028924, 1.2630134771692395e-28, 79.89329612328716, 8.284388048614786e-29],
          (2, 20)=>[0.0, 1.2697180778261437e-30, 4.000002539852251, 4.666290179209354e-29, 21.098932320239584, 3.4300386105764425e-29, 47.76598398302884, 6.100255343320017e-29, 79.89329612328727, 1.801023480958872e-28, 6.029776808298499e-29],
        )
        for T_ms in [1, 2]
            for n in [19, 20]
                dt = T_ms*1e-3/n
                t = (0:n-1).*dt
                p = f.(t)
                ap = PressureTimeHistory(p, dt)
                nbs = MSPSpectrumAmplitude(ap)
                # nbs_A = W_A(nbs)
                # amp_A = W_A(nbs)
                amp_A = W_A.(frequency(nbs)).*nbs
                # ANOPP2.a2_aa_weight(ANOPP2.a2_aa_a_weight, ANOPP2.a2_aa_nbs_enum, ANOPP2.a2_aa_msp, freq, nbs_A_a2)
                # Wish I could get this to match more closely. But the weighting
                # function looks pretty nasty numerically (frequencies raised to the
                # 4th power, and one of the coefficients is about 2.24e16).
                # @show T_ms n amp_A nbs_A_a2[(T_ms, n)]
                @test all(isapprox.(amp_A, nbs_A_a2[(T_ms, n)], atol=1e-6))
            end
        end
    end

    @testset "1kHz check" begin
        # A 1kHz signal should be unaffected by A-weighting.
        fr(t) = 2*cos(1e3*2*pi*t)
        fi(t) = 2*sin(1e3*2*pi*t)
        f(t) = fr(t) + fi(t)
        for T_ms in [1, 2]
            for n in [19, 20]
                dt = T_ms*1e-3/n
                t = (0:n-1).*dt
                p = f.(t)
                ap = PressureTimeHistory(p, dt)
                nbs = MSPSpectrumAmplitude(ap)
                # amp = amplitude(nbs)
                # nbs_A = W_A(nbs)
                # amp_A = W_A(nbs)
                amp_A = W_A.(frequency(nbs)).*nbs
                # This is lame. Should be able to get this to match better,
                # right?
                @test all(isapprox.(amp_A, nbs, atol=1e-5))
            end
        end
    end
end
