abstract type AbstractAcousticPressure end

@concrete struct AcousticPressure <: AbstractAcousticPressure
    p
    dt
    t0
end

AcousticPressure(p, dt) = AcousticPressure(p, dt, zero(typeof(dt)))

@inline pressure(ap::AbstractAcousticPressure) = ap.p
@inline timestep(ap::AbstractAcousticPressure) = ap.dt
@inline starttime(ap::AbstractAcousticPressure) = ap.t0

@inline function time(ap::AbstractAcousticPressure)
    n = length(pressure(ap))
    return starttime(ap) .+ (0:n-1) .* timestep(ap)
end

abstract type AbstractPressureSpectrum end

@concrete struct PressureSpectrum <: AbstractPressureSpectrum
    n
    fs
    amp
    ϕ
end

@inline inputlength(ps::AbstractPressureSpectrum) = ps.n
@inline samplerate(ps::AbstractPressureSpectrum) = ps.fs
@inline frequency(ps::AbstractPressureSpectrum) = rfftfreq(inputlength(ps), samplerate(ps))
@inline amplitude(ps::AbstractPressureSpectrum) = ps.amp
@inline phase(ps::AbstractPressureSpectrum) = ps.ϕ

function split_hc_real_imag(p_fft)
    n = length(p_fft)
    n_real = n >> 1 # number of real outputs, not counting the mean
    n_imag = ((n + 1) >> 1) - 1

    # The mean of the signal is in the first element of the output array.
    # Always real for a real-input FFT.
    p_fft_mean = p_fft[begin]
    # Then the real parts of the positive frequencies.
    p_fft_real = @view p_fft[begin+1:n_real+1]
    # Then the imaginary parts of the positive frequencies, which are "backwards."
    p_fft_imag = @view p_fft[end:-1:end-n_imag+1]

    return p_fft_mean, p_fft_real, p_fft_imag
end

function PressureSpectrum(ap::AbstractAcousticPressure)
    p = pressure(ap)
    n = length(p)

    # Get the FFT of the acoustic pressure. Divide by n since FFT computes an
    # "unnormalized" FFT.
    p_fft = rfft(p)./n

    # Split the FFT output in half-complex format into mean, real, and imaginary
    # components (returns views for the latter two).
    p_fft_mean, p_fft_real, p_fft_imag = split_hc_real_imag(p_fft)

    # output length.
    m = 1 + length(p_fft_real)

    # Now I want to get the amplitude and phase.
    amp = similar(p, m)
    phi = similar(p, m)
    # Set the amplitude and phase for the mean component.
    amp[begin] = p_fft_mean
    phi[begin] = zero(eltype(phi))  # imaginary component is zero, so atan(0) == 0.
    if mod(n, 2) == 0
        @. amp[begin+1:end-1] = 2*sqrt(p_fft_real[begin:end-1]^2 + p_fft_imag^2)
        amp[end] = p_fft_real[end]
        @. phi[begin+1:end-1] = atan(p_fft_imag, p_fft_real[begin:end-1])
        phi[end] = zero(eltype(phi))  # imaginary component is zero, so atan(0) == 0.
    else
        @. amp[begin+1:end] = 2*sqrt(p_fft_real^2 + p_fft_imag^2)
        @. phi[begin+1:end] = atan(p_fft_imag, p_fft_real)
    end

    # Find the sampling rate, which we can use later to find the frequency bins.
    fs = 1/timestep(ap)
    return PressureSpectrum(n, fs, amp, phi)
end

function AcousticPressure(ps::AbstractPressureSpectrum)
    amp = amplitude(ps)
    ϕ = phase(ps)
    n = inputlength(ps)
    T = promote_type(eltype(amp), eltype(ϕ))
    p_fft = Vector{T}(undef, n)
    _, p_fft_real, p_fft_imag = split_hc_real_imag(p_fft)

    p_fft[begin] = amp[begin]
    # Both amp and phi always have the same length, and it's always one more
    # than p_fft_real.
    if mod(n, 2) == 0
        # The length of p_fft_real is one greater than p_fft_imag.
        # So the length of amp and phi are two greater than p_fft_imag.
        @. p_fft_real[begin:end-1] = 0.5*amp[begin+1:end-1]*cos(ϕ[begin+1:end-1])
        p_fft_real[end] = amp[end]
        @. p_fft_imag = 0.5*amp[begin+1:end-1]*sin(ϕ[begin+1:end-1])
    else
        # The length of p_fft_real is the same as p_fft_imag.
        # So the length of amp and phi are one greater than p_fft_real and p_fft_imag.
        @. p_fft_real = 0.5*amp[begin+1:end]*cos(ϕ[begin+1:end])
        @. p_fft_imag = 0.5*amp[begin+1:end]*sin(ϕ[begin+1:end])
    end

    # So now let's do an inverse FFT.
    p = copy(p_fft)
    r2r!(p, HC2R)

    # Now we just have to figure out dt and t0.
    dt = 1/samplerate(ps)
    return AcousticPressure(p, dt)
end

abstract type AbstractNarrowbandSpectrum end

@concrete struct NarrowbandSpectrum <: AbstractNarrowbandSpectrum
    n
    fs
    amp
    ϕ
end

@inline inputlength(nbs::AbstractNarrowbandSpectrum) = nbs.n
@inline samplerate(nbs::AbstractNarrowbandSpectrum) = nbs.fs
@inline frequency(nbs::AbstractNarrowbandSpectrum) = rfftfreq(inputlength(nbs), samplerate(nbs))
@inline amplitude(nbs::AbstractNarrowbandSpectrum) = nbs.amp
@inline phase(nbs::AbstractNarrowbandSpectrum) = nbs.ϕ

function NarrowbandSpectrum(ap::AbstractAcousticPressure)
    p = pressure(ap)
    n = length(p)

    # Get the FFT of the acoustic pressure. Divide by n since FFT computes an
    # "unnormalized" FFT.
    p_fft = rfft(p)./n

    # Split the FFT output in half-complex format into mean, real, and imaginary
    # components (returns views for the latter two).
    p_fft_mean, p_fft_real, p_fft_imag = split_hc_real_imag(p_fft)

    # output length.
    m = 1 + length(p_fft_real)

    # Now I want to get the amplitude and phase.
    amp = similar(p, m)
    ϕ = similar(p, m)

    amp[begin] = p_fft_mean^2
    ϕ[begin] = zero(eltype(ϕ))
    if mod(n, 2) == 0
        @. amp[begin+1:end-1] = 2*(p_fft_real[begin:end-1]^2 + p_fft_imag^2)
        amp[end] = p_fft_real[end]^2
        @. ϕ[2:end-1] = atan(p_fft_imag, p_fft_real[begin:end-1])
        ϕ[end] = zero(eltype(ϕ))  # imaginary component is zero, so atan(0) == 0.
    else
        @. amp[begin+1:end] = 2*(p_fft_real^2 + p_fft_imag^2)
        @. ϕ[begin+1:end] = atan(p_fft_imag, p_fft_real)
    end

    # Find the sampling rate, which we can use later to find the frequency bins.
    fs = 1/timestep(ap)
    return NarrowbandSpectrum(n, fs, amp, ϕ)
end

function PressureSpectrum(nbs::AbstractNarrowbandSpectrum)
    # amplitude(nbs) = 2*(p_fft_real^2 + p_fft_imag^2)
    # amplitude(ps) = 2*sqrt(p_fft_real^2 + p_fft_imag^2)
    # amp = 2*sqrt(amplitude(nbs)/2)
    # amp = 2*sqrt(2)*sqrt(amplitude(nbs))/2
    # amp = sqrt(2)*sqrt(amplitude(nbs))
    #
    n = inputlength(nbs)

    # But for the mean component:
    # amplitude(nbs)[1] = p_fft_mean^2
    # amplitude(ps)[1] = p_fft_mean
    nbs_amp = amplitude(nbs)
    amp = similar(nbs_amp)

    amp[begin] = sqrt(nbs_amp[begin])
    if mod(n, 2) == 0
        @. amp[begin+1:end-1] = sqrt(2*nbs_amp[begin+1:end-1])
        amp[end] = sqrt(nbs_amp[end])
    else
        @. amp[begin+1:end] = sqrt(2*nbs_amp[begin+1:end])
    end

    phi = copy(phase(nbs))
    fs = samplerate(nbs)
    return PressureSpectrum(n, fs, amp, phi)
end

function AcousticPressure(nbs::AbstractNarrowbandSpectrum)
    amp = amplitude(nbs)
    ϕ = phase(nbs)
    n = inputlength(nbs)
    T = promote_type(eltype(amp), eltype(ϕ))
    p_fft = Vector{T}(undef, n)
    _, p_fft_real, p_fft_imag = split_hc_real_imag(p_fft)

    p_fft[begin] = sqrt(amp[begin])
    # Both amp and phi always have the same length, and it's always one more
    # than p_fft_real.
    if mod(n, 2) == 0
        # The length of p_fft_real is one greater than p_fft_imag.
        # So the length of amp and phi are two greater than p_fft_imag.
        @. p_fft_real[begin:end-1] = 0.5*sqrt(2*amp[begin+1:end-1])*cos(ϕ[begin+1:end-1])
        p_fft_real[end] = sqrt(amp[end])
        @. p_fft_imag = 0.5*sqrt(2*amp[begin+1:end-1])*sin(ϕ[begin+1:end-1])
    else
        # The length of p_fft_real is the same as p_fft_imag.
        # So the length of amp and phi are one greater than p_fft_real and p_fft_imag.
        @. p_fft_real = 0.5*sqrt(2*amp[begin+1:end])*cos(ϕ[begin+1:end])
        @. p_fft_imag = 0.5*sqrt(2*amp[begin+1:end])*sin(ϕ[begin+1:end])
    end

    # So now let's do an inverse FFT.
    p = copy(p_fft)
    r2r!(p, HC2R)

    # Now we just have to figure out dt and t0.
    dt = 1/samplerate(nbs)
    return AcousticPressure(p, dt)
end

function OASPL(ap::AbstractAcousticPressure)
    p = pressure(ap)
    n = length(p)
    p_mean = sum(p)/n
    msp = sum((p .- p_mean).^2)/n
    return 10*log10(msp/p_ref^2)
end

function OASPL(nbs::AbstractNarrowbandSpectrum)
    amp = amplitude(nbs)
    msp = sum(amp[begin+1:end])
    return 10*log10(msp/p_ref^2)
end
