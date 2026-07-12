import AVFoundation
import Foundation

// MARK: - Biquad filter

/// Transposed Direct-Form II biquad. Used to build the resonant formant bank that
/// gives the engine its "box" / exhaust character. Real engine timbre comes from
/// the exhaust and body cavities ringing when each combustion pulse hits them, so
/// resonators with a real Q are what make this sound like an engine rather than a
/// buzzer.
nonisolated struct Biquad {
    var b0: Double = 1, b1: Double = 0, b2: Double = 0
    var a1: Double = 0, a2: Double = 0
    private var z1: Double = 0, z2: Double = 0

    @inline(__always)
    mutating func process(_ x: Double) -> Double {
        let y = b0 * x + z1
        z1 = b1 * x - a1 * y + z2
        z2 = b2 * x - a2 * y
        return y
    }

    mutating func reset() { z1 = 0; z2 = 0 }

    /// Constant-skirt-gain band-pass (peak gain ≈ Q at center).
    mutating func setBandpass(freq: Double, q: Double, sampleRate: Double) {
        let f = min(max(freq, 20.0), sampleRate * 0.45)
        let qq = max(0.3, q)
        let w0 = 2.0 * .pi * f / sampleRate
        let cs = cos(w0), sn = sin(w0)
        let alpha = sn / (2.0 * qq)
        let a0 = 1.0 + alpha
        b0 = (sn / 2.0) / a0
        b1 = 0.0
        b2 = -(sn / 2.0) / a0
        a1 = (-2.0 * cs) / a0
        a2 = (1.0 - alpha) / a0
    }

    /// Peaking EQ (boost/cut around a center frequency).
    mutating func setPeaking(freq: Double, q: Double, gainDB: Double, sampleRate: Double) {
        let f = min(max(freq, 20.0), sampleRate * 0.45)
        let qq = max(0.3, q)
        let A = pow(10.0, gainDB / 40.0)
        let w0 = 2.0 * .pi * f / sampleRate
        let cs = cos(w0), sn = sin(w0)
        let alpha = sn / (2.0 * qq)
        let a0 = 1.0 + alpha / A
        b0 = (1.0 + alpha * A) / a0
        b1 = (-2.0 * cs) / a0
        b2 = (1.0 - alpha * A) / a0
        a1 = (-2.0 * cs) / a0
        a2 = (1.0 - alpha / A) / a0
    }

    /// One-pole low-pass (used inline where a full biquad is unnecessary).
    mutating func setLowpass(freq: Double, sampleRate: Double) {
        let f = min(max(freq, 20.0), sampleRate * 0.45)
        let w0 = 2.0 * .pi * f / sampleRate
        let cs = cos(w0), sn = sin(w0)
        let alpha = sn / (2.0 * 0.7071)
        let a0 = 1.0 + alpha
        let cos1 = (1.0 - cs) / 2.0
        b0 = cos1 / a0
        b1 = (1.0 - cs) / a0
        b2 = cos1 / a0
        a1 = (-2.0 * cs) / a0
        a2 = (1.0 - alpha) / a0
    }
}

// MARK: - Deterministic RNG

/// Small deterministic PRNG so per-cylinder / per-harmonic character is stable
/// across launches (a real engine sounds the same every time you start it).
private nonisolated struct SeededRNG {
    var state: UInt64
    @inline(__always) mutating func nextUInt() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
    /// Uniform in [0, 1).
    @inline(__always) mutating func nextUnit() -> Double {
        Double(nextUInt() >> 11) * (1.0 / 9007199254740992.0)
    }
    /// Uniform in [-1, 1).
    @inline(__always) mutating func nextBipolar() -> Double {
        nextUnit() * 2.0 - 1.0
    }
}

// MARK: - Tuning constants
//
// Every "how strong / how fast / at what frequency" knob for the recorded-engine
// character lives here so the sound can be re-balanced without hunting through
// the DSP graph.
private nonisolated enum Tuning {
    // Cycle-to-cycle combustion variation (CoV of IMEP) driving per-event
    // amplitude scatter: ~2% base for a warm loaded engine, rising with RPM
    // (measured: ~3% @3000 → ~13% @5000) and toward idle, falling with load.
    // The AR(1) memory correlates each cylinder's scatter across cycles, which
    // is what puts the energy at the half-order instead of broadband hiss.
    static let covBase = 0.02
    static let covRpmGain = 0.14
    static let covIdleGain = 0.13
    static let covLoadCut = 0.06
    static let covMin = 0.015
    static let covMax = 0.18
    static let covAr1Keep = 0.72

    // Per-event ignition timing jitter, as a fraction of ONE firing interval
    // (interval-relative, so many-cylinder engines stay coherent at high rpm).
    static let timingJitterIntervalAtIdle = 0.080
    static let timingJitterIntervalAtLoad = 0.024

    // Half-order-locked roughness AM for single-collector engines (dual-bank
    // engines get their rumble from uneven per-bank firing instead). Depth
    // stays far below the ~30% annoyance threshold.
    static let roughnessDepthBase = 0.05
    static let roughnessDepthScav = 0.07

    // Chance (0...1) that any single cylinder event misfires, scaled by idle
    // proximity. Misfired events get their amplitude crushed, not silenced.
    static let misfireChanceMax = 0.012
    static let misfireAmpFloor = 0.10

    // Combustion pulse shape: quick attack, exponential-ish decay tail.
    static let pulseAttackFrac = 0.18
    static let pulseDecayRate = 4.4

    // Per-firing combustion noise burst (2-5 ms class) injected alongside the
    // pressure pulse — this is what keeps the exhaust from sounding like a tone.
    static let combNoiseBurstMs = 3.2
    static let combNoiseBurstGain = 0.55

    // Exhaust pipe waveguide (short feedback delay / comb resonance).
    static let pipeDelayMsAtIdle = 5.4
    static let pipeDelayMsAtHighRpm = 2.4
    static let pipeFeedbackBase = 0.55
    static let pipeFeedbackThrottleCut = 0.18
    static let pipeLoopDamping = 0.35

    // Dual exhaust-bank routing. Bank A leans left, bank B leans right; the
    // cross-bleed is the acoustic mixing between the two tailpipes and the
    // makeup gain keeps dual-bank presets at the single-collector loudness.
    // Bank B runs a slightly longer pipe (unequal-length headers).
    static let bankCrossBleed = 0.45
    static let bankMakeupGain = 1.15
    static let bankPipeRatioV = 1.03
    static let bankPipeRatioBoxer = 1.07

    // Anti-aliasing: minimum combustion pulse width in samples. Keeps the
    // pulse spectrum band-limited when firing rate gets high (V12 near redline).
    static let minPulseWidthSamples = 11.0

    // Formant bank stereo detune (applied to every resonant band).
    static let bandDetuneL = 0.985
    static let bandDetuneR = 1.015

    // Turbo whistle: band-passed noise, not a sine tone.
    static let turboFreqBase = 4000.0
    static let turboFreqSpoolRange = 5000.0
    static let turboQBase = 9.0
    static let turboQSpoolRange = 6.0
    static let turboGain = 0.32

    // Blow-off valve (throttle-lift) burst.
    static let bovThrottleHighWatermark = 0.45
    static let bovThrottleLowWatermark = 0.15
    static let bovMinRpmFactor = 1.4     // relative to idleRpm
    static let bovDecaySeconds = 0.20
    static let bovGain = 0.5

    // Overrun / afterfire pop scheduling (Poisson-ish exponential interval).
    static let overrunPopMeanMsEnabled = 95.0
    static let overrunPopMeanMsDisabled = 240.0
    static let overrunPopBigChance = 0.08
    static let overrunPopBigChanceDisabled = 0.02
    static let overrunPopAmpDisabledScale = 0.12
    static let popDecayMsMin = 10.0
    static let popDecayMsMax = 30.0

    // Starter motor.
    static let starterFreqL = 340.0
    static let starterFreqR = 360.0
    static let starterHarmonicMul = 2.05
    static let starterGain = 0.35
    static let starterHarmonicGain = 0.16

    // Cranking excitation shaping (weak, muffled combustion-less pulses).
    static let crankExcitationCut = 0.65
    static let crankBodyBoost = 0.25
    static let crankExhaustCut = 0.92

    // Shift-cut ignition mute depth.
    static let shiftCutMuteDepth = 0.90
    static let fuelCutMuteDepth = 0.96

    // Speed-dependent road and air noise. Kept subtle so it adds motion without
    // masking the engine note.
    static let roadNoiseGain = 0.065
    static let roadNoiseMaxKmh = 230.0

    // Short stereo reflection to keep the output from sounding like a perfectly
    // dry oscillator. This is a synthetic cabin/phone-speaker ambience hook; real
    // impulse-response samples can be mixed at the same point later.
    static let cabinReflectionGain = 0.075
    static let cabinDelayMsL = 17.0
    static let cabinDelayMsR = 23.0

    // Small-speaker compensation. The built-in speaker reproduces almost
    // nothing below ~250 Hz, so while it is the active route the sub-250 Hz
    // combustion energy is folded into 2nd/3rd-harmonic midrange the speaker
    // CAN play (missing-fundamental effect: the brain restores the lows).
    static let speakerBassLowpassK = 0.031   // ≈ 220 Hz source band (one-pole)
    static let speakerHarmDcK = 0.026        // ≈ 185 Hz — strips DC + original fundamental
    static let speakerHarmMidK = 0.18        // ≈ 1.4 kHz — smooths the generated harmonics
    static let speakerHarmGain = 1.4
}

// MARK: - Engine synthesizer

/// Physically-motivated engine synthesizer aimed at recorded-engine realism
/// rather than clean synth tones.
///
/// Signal chain (per sample):
///   1. Combustion excitation — one shaped pressure pulse per cylinder firing,
///      asymmetric (fast attack / exponential decay) rather than a symmetric
///      raised-cosine "buzzer" bump. Each firing event independently jitters its
///      amplitude and the timing of its *next* occurrence, and can rarely
///      misfire — this is what breaks up mechanical periodicity.
///   2. A short feedback delay ("exhaust pipe waveguide") colors the excitation
///      with the comb resonance of a real header/pipe before it hits the formant
///      bank.
///   3. Formant / resonance bank — five parallel biquads per channel (body +
///      four exhaust formants), independently detuned left/right for natural
///      stereo width, modelling the exhaust pipe resonances and body cavity.
///   4. Aspiration + mechanical noise beds, turbo whistle (band-passed noise,
///      not a tone), blow-off valve bursts, starter motor whine, overrun/afterfire
///      pops and shift/limiter pops are layered on top, all envelope-driven.
///   5. Soft saturation + master, bounded by tanh so it can never hard-clip, with
///      DC blocking on both the excitation and the final per-channel output.
///
/// All continuous parameters (RPM, throttle, load) are smoothed per sample, so
/// the output stays glitch-free no matter how coarse the control-rate updates are.
nonisolated final class HarmonicGenerator {
    private let sampleRate: Double

    // --- Control targets (written from the main/display-link thread) ---
    private var targetRpm: Double = 0
    private var targetThrottle: Double = 0
    private var targetLoad: Double = 0
    private var targetSpeed: Double = 0
    private var targetClutchPedal: Double = 0
    private var running: Bool = false
    private var cranking: Bool = false
    private var shiftCutTarget: Bool = false
    private var fuelCutTarget: Bool = false
    private var decelFuelCutTarget: Bool = false
    private var overrunTarget: Bool = false
    private var popsEnabled: Bool = true
    private var gear: Int = 0
    private var cylinders: Int = 4
    private var exhaustBankPattern: UInt16 = 0
    private var exhaustBankCount: Int = 1
    private var idleRpm: Double = 800
    private var redlineRpm: Double = 7000
    private var harmonicRichness: Double = 0.4
    private var exhaustScavengingFactor: Double = 0.7
    private var intakeHarmonicFactor: Double = 0.3
    private var intakeEfficiency: Double = 0.85
    private var exhaustEfficiency: Double = 0.90
    private var frictionFactor: Double = 0.15
    private var vtecMode = false
    private var boxerMode = false
    private var turboMode = false
    private var smallSpeakerTarget = false
    private var straightPipeTarget = false

    // Edge-detection state for control-rate events (compared each `update`).
    private var previousTargetThrottle: Double = 0
    private var previousShiftCut: Bool = false
    private var previousFuelCut: Bool = false
    private var previousDecelFuelCut: Bool = false

    // Cross-thread trigger counters. Written on the main thread inside
    // `update`, consumed on the audio thread at the top of `renderStereo`.
    // Plain Int increments (no allocation, no lock) — worst case a trigger is
    // coalesced with the next one, which is inaudible for a one-shot pop.
    private var bovTriggerCount: Int = 0
    private var lastHandledBovTrigger: Int = 0
    private var shiftPopTriggerCount: Int = 0
    private var lastHandledShiftPopTrigger: Int = 0
    private var fuelCutPopTriggerCount: Int = 0
    private var lastHandledFuelCutPopTrigger: Int = 0
    private var refirePopTriggerCount: Int = 0
    private var lastHandledRefirePopTrigger: Int = 0
    private var driveShockTargetCount: Int = 0
    private var lastHandledDriveShock: Int = 0
    private var driveShockMagnitude: Double = 0

    // --- Smoothed audio-rate state ---
    private var rpm: Double = 0
    private var throttle: Double = 0
    private var load: Double = 0
    private var speed: Double = 0
    private var clutchPedal: Double = 0
    private var gate: Double = 0          // 0 = engine off, 1 = running (fades in/out)
    private var crankGate: Double = 0     // 0 = normal running, 1 = cranking
    private var shiftGate: Double = 0     // 0 = normal, 1 = shift-cut fully engaged
    private var fuelCutGate: Double = 0   // 0 = normal, 1 = limiter fuel cut
    private var dfcoGate: Double = 0      // 0 = fuel on, 1 = decel fuel cut fully engaged
    private var overrunGate: Double = 0   // 0 = normal, 1 = overrun fully engaged
    private var speakerGate: Double = 0   // 0 = flat mix, 1 = small-speaker compensation
    private var pipeOpenGate: Double = 0  // 0 = stock muffler, 1 = straight pipe

    // --- Small-speaker bass-folding filter states ---
    private var spkLowL: Double = 0, spkLowR: Double = 0
    private var spkDcL: Double = 0, spkDcR: Double = 0
    private var spkMidL: Double = 0, spkMidR: Double = 0
    // --- Small-speaker loudness: sub-band strip ahead of the limiter ---
    private var spkCutL: Double = 0, spkCutR: Double = 0

    // --- Oscillator / cycle phases ---
    private var cyclePhase: Double = 0    // 0..1 across one full 4-stroke cycle (2 revs)
    private var limiterPhase: Double = 0
    private var limiterWasCut: Bool = false
    private var starterGearPhase: Double = 0

    // --- Per-cylinder combustion state ---
    // Fixed capacity (max 16 cylinders) so preset changes never reallocate
    // while the audio thread is reading — `cylinders` is updated last.
    private var firingAngle = [Double](repeating: 0, count: 16)
    private var firingAngleJitter = [Double](repeating: 0, count: 16)  // timing offset for the next firing
    private var cylinderAmp = [Double](repeating: 1, count: 16)
    private var pulseAmpJitter = [Double](repeating: 1, count: 16)     // amplitude multiplier for the current firing
    private var wasInPulse = [Bool](repeating: false, count: 16)
    private var firingBank = [Int](repeating: 0, count: 16)            // exhaust bank of each firing event
    private var covSlow = [Double](repeating: 0, count: 16)            // AR(1) per-cylinder combustion drift

    // --- Exhaust pipe waveguides (short feedback delay / comb resonance),
    // one per exhaust bank. Bank B is only processed for dual-bank engines. ---
    private var pipeDelayBuffer: [Double] = []
    private var pipeDelayBufferB: [Double] = []
    private var pipeDelayCapacity: Int = 0
    private var pipeDelayWriteIdx: Int = 0
    private var pipeDelayWriteIdxB: Int = 0
    private var pipeDelayLP: Double = 0
    private var pipeDelayLPB: Double = 0

    // --- Resonance bank: body + 4 exhaust formants, independent L/R detune ---
    private var bodyResL = Biquad(), bodyResR = Biquad()
    private var exhaust1L = Biquad(), exhaust1R = Biquad()
    private var exhaust2L = Biquad(), exhaust2R = Biquad()
    private var exhaust3L = Biquad(), exhaust3R = Biquad()
    private var exhaust4L = Biquad(), exhaust4R = Biquad()

    // --- Tailpipe quarter-wave resonance (fixed per preset) + variable
    // exhaust low-pass (throttle opens the system up, DFCO muffles it) ---
    private var tailpipeHz: Double = 120
    private var lastTailpipeHz: Double = -1
    private var tailPeakL = Biquad(), tailPeakR = Biquad()
    private var exhaustLpL: Double = 0, exhaustLpR: Double = 0

    // --- Combustion noise-burst envelope (shared, injected into excitation) ---
    private var combNoiseEnv: Double = 0

    // --- Overrun / afterfire / shift / limiter pop envelope (shared) ---
    private var popEnv: Double = 0
    private var popDecayCoef: Double = 0.99
    private var popCountdownSamples: Int = 2000

    // --- Turbo whistle (band-passed noise) ---
    private var turboResL = Biquad(), turboResR = Biquad()
    private var lastTurboSpool: Double = -1

    // --- Blow-off valve burst ---
    private var bovEnv: Double = 0
    private var bovHpL: Double = 0, bovHpR: Double = 0

    // --- Starter motor whine (fundamental + harmonic, per channel) ---
    private var starterResL = Biquad(), starterResR = Biquad()
    private var starterRes2L = Biquad(), starterRes2R = Biquad()

    // --- DC blockers (per-bank excitation + per-channel output) ---
    private var dcX: Double = 0
    private var dcY: Double = 0
    private var dcXB: Double = 0
    private var dcYB: Double = 0
    private var outDcXL: Double = 0, outDcYL: Double = 0
    private var outDcXR: Double = 0, outDcYR: Double = 0

    // --- Noise filter states (per channel for stereo decorrelation) ---
    private var intakeLpL: Double = 0, intakeLpR: Double = 0
    private var mechHpL: Double = 0,  mechHpR: Double = 0
    private var mechBandL: Double = 0, mechBandR: Double = 0
    private var roadLpL: Double = 0, roadLpR: Double = 0

    // --- Short cabin/space reflection ---
    private var cabinDelayL: [Double] = []
    private var cabinDelayR: [Double] = []
    private var cabinDelayCapacity: Int = 0
    private var cabinDelayWriteIdx: Int = 0
    private var cabinDelaySamplesL: Int = 1
    private var cabinDelaySamplesR: Int = 1

    // --- RNG ---
    private var rng = SeededRNG(state: 0x9E3779B97F4A7C15)

    // Cached RPM used for the last coefficient update (avoids recomputing biquads
    // every sample; the formant centers move slowly).
    private var lastCoeffRpm: Double = -1

    init(sampleRate: Double = 44100) {
        self.sampleRate = sampleRate
        pipeDelayCapacity = Int(sampleRate * 0.010) + 8
        pipeDelayBuffer = Array(repeating: 0.0, count: pipeDelayCapacity)
        pipeDelayBufferB = Array(repeating: 0.0, count: pipeDelayCapacity)
        cabinDelayCapacity = Int(sampleRate * 0.040) + 8
        cabinDelayL = Array(repeating: 0.0, count: cabinDelayCapacity)
        cabinDelayR = Array(repeating: 0.0, count: cabinDelayCapacity)
        cabinDelaySamplesL = max(1, Int(Tuning.cabinDelayMsL * 0.001 * sampleRate))
        cabinDelaySamplesR = max(1, Int(Tuning.cabinDelayMsR * 0.001 * sampleRate))
        configureCylinders(4)
        configureStaticFilters()
    }

    // MARK: Configuration

    /// Rebuild per-cylinder firing angles, exhaust-bank routing and amplitude
    /// variation. Called whenever the cylinder count / bank layout changes.
    /// Writes happen in place into fixed-capacity arrays, and `cylinders` is
    /// assigned last, so the audio thread can never index past valid data.
    private func configureCylinders(_ count: Int) {
        let n = max(1, min(16, count))

        // Deterministic per-cylinder variation seeded by cylinder count so each
        // engine has a consistent personality.
        var seed = SeededRNG(state: 0xD1B54A32D192ED03 &+ UInt64(n) &* 0x100000001B3)

        for i in 0..<n {
            // Even firing: cylinders equally spaced across the 4-stroke cycle.
            // (Real even-firing engines are exactly this; the bank routing below
            // is what makes the per-bank exhaust rhythm uneven.)
            var angle = Double(i) / Double(n)

            // Boxer: unequal-length headers also shift pulse arrival slightly.
            if boxerMode {
                angle += (i % 2 == 0 ? -1.0 : 1.0) * 0.010
            }
            firingAngle[i] = (angle + 1.0).truncatingRemainder(dividingBy: 1.0)
            firingBank[i] = exhaustBankCount == 2 ? Int((exhaustBankPattern >> UInt16(i)) & 1) : 0

            // Slight combustion strength variation (±8%).
            cylinderAmp[i] = 0.92 + 0.16 * seed.nextUnit()
            firingAngleJitter[i] = 0
            pulseAmpJitter[i] = 1.0
            wasInPulse[i] = false
        }
        cylinders = n
        lastCoeffRpm = -1
    }

    /// One-time setup for filters whose tuning doesn't depend on RPM.
    private func configureStaticFilters() {
        starterResL.setBandpass(freq: Tuning.starterFreqL, q: 5.5, sampleRate: sampleRate)
        starterResR.setBandpass(freq: Tuning.starterFreqR, q: 5.5, sampleRate: sampleRate)
        starterRes2L.setBandpass(freq: Tuning.starterFreqL * Tuning.starterHarmonicMul, q: 6.0, sampleRate: sampleRate)
        starterRes2R.setBandpass(freq: Tuning.starterFreqR * Tuning.starterHarmonicMul, q: 6.0, sampleRate: sampleRate)
    }

    // MARK: Parameter updates (main thread)

    /// Push the latest simulation state. Cheap; safe to call every display-link tick.
    func update(_ state: EngineSoundState) {
        if state.cylinders != self.cylinders || state.boxerMode != self.boxerMode
            || state.exhaustBankPattern != self.exhaustBankPattern
            || state.exhaustBankCount != self.exhaustBankCount {
            self.boxerMode = state.boxerMode
            self.exhaustBankPattern = state.exhaustBankPattern
            self.exhaustBankCount = state.exhaustBankCount
            configureCylinders(state.cylinders)
        }
        self.targetRpm = state.rpm
        self.targetThrottle = state.throttle
        self.targetLoad = state.load
        self.targetSpeed = state.speed
        self.targetClutchPedal = state.clutchPedal
        self.running = state.running
        self.cranking = state.cranking
        self.idleRpm = state.idleRpm
        self.redlineRpm = state.redlineRpm
        self.gear = state.gear
        self.harmonicRichness = max(0.0, min(1.0, Double(state.harmonicCount - 12) / 14.0))
        self.exhaustScavengingFactor = max(0.0, min(1.2, state.exhaustScavengingFactor))
        self.intakeHarmonicFactor = max(0.0, min(1.2, state.intakeHarmonicFactor))
        self.intakeEfficiency = max(0.0, min(1.2, state.intakeEfficiency))
        self.exhaustEfficiency = max(0.0, min(1.2, state.exhaustEfficiency))
        self.frictionFactor = max(0.0, min(0.7, state.frictionFactor))
        self.vtecMode = state.vtecMode
        self.turboMode = state.turboMode
        self.popsEnabled = state.popsEnabled
        self.straightPipeTarget = state.straightPipe
        self.overrunTarget = state.overrun
        self.smallSpeakerTarget = state.smallSpeaker
        self.tailpipeHz = state.tailpipeResonanceHz
        self.driveShockMagnitude = state.driveShockMagnitude
        self.driveShockTargetCount = state.driveShockCount

        // Blow-off valve: detect a sharp throttle lift while boosted.
        if state.turboMode
            && previousTargetThrottle > Tuning.bovThrottleHighWatermark
            && state.throttle < Tuning.bovThrottleLowWatermark
            && state.rpm > self.idleRpm * Tuning.bovMinRpmFactor {
            bovTriggerCount &+= 1
        }

        // Shift-cut recovery: fires a small pop the instant the cut releases.
        if previousShiftCut && !state.shiftCut {
            shiftPopTriggerCount &+= 1
        }
        self.shiftCutTarget = state.shiftCut

        if previousFuelCut && !state.fuelCut {
            fuelCutPopTriggerCount &+= 1
        }
        self.fuelCutTarget = state.fuelCut

        // DFCO ending near idle = fuel refire, a soft single pop.
        if previousDecelFuelCut && !state.decelFuelCut {
            refirePopTriggerCount &+= 1
        }
        self.decelFuelCutTarget = state.decelFuelCut

        previousTargetThrottle = state.throttle
        previousShiftCut = state.shiftCut
        previousFuelCut = state.fuelCut
        previousDecelFuelCut = state.decelFuelCut
    }

    // MARK: Coefficient update (control rate)

    private func updateResonatorCoefficients() {
        // Exhaust formants drift slightly upward with RPM (gas velocity), giving a
        // sense of the pipe "opening up". Body resonance stays low. Every band is
        // independently detuned left/right so the stereo image doesn't come purely
        // from decorrelated noise.
        let r = rpm
        let dl = Tuning.bandDetuneL, dr = Tuning.bandDetuneR

        let layoutShift = (boxerMode ? 0.93 : 1.0) * (turboMode ? 1.03 : 1.0)
        let pipeShift = (0.94 + 0.12 * exhaustEfficiency) * layoutShift
        let brightShift = 0.98 + 0.10 * harmonicRichness

        let f0 = (95.0 + r * 0.004) * (0.96 + 0.08 * frictionFactor)
        let f1 = (180.0 + r * 0.010) * pipeShift
        let f2 = (430.0 + r * 0.024) * pipeShift
        let f3 = (950.0 + r * 0.048) * pipeShift * brightShift
        let f4 = (1900.0 + r * 0.075) * pipeShift * brightShift

        let exhaustQ = 2.7 + 0.9 * exhaustScavengingFactor
        bodyResL.setBandpass(freq: f0 * dl, q: 1.55 + 0.35 * frictionFactor, sampleRate: sampleRate)
        bodyResR.setBandpass(freq: f0 * dr, q: 1.55 + 0.35 * frictionFactor, sampleRate: sampleRate)
        exhaust1L.setBandpass(freq: f1 * dl, q: exhaustQ, sampleRate: sampleRate)
        exhaust1R.setBandpass(freq: f1 * dr, q: exhaustQ, sampleRate: sampleRate)
        exhaust2L.setBandpass(freq: f2 * dl, q: exhaustQ + 0.35, sampleRate: sampleRate)
        exhaust2R.setBandpass(freq: f2 * dr, q: exhaustQ + 0.35, sampleRate: sampleRate)
        exhaust3L.setBandpass(freq: f3 * dl, q: 2.5 + 0.7 * harmonicRichness, sampleRate: sampleRate)
        exhaust3R.setBandpass(freq: f3 * dr, q: 2.5 + 0.7 * harmonicRichness, sampleRate: sampleRate)
        exhaust4L.setBandpass(freq: f4 * dl, q: 2.0 + 0.5 * harmonicRichness, sampleRate: sampleRate)
        exhaust4R.setBandpass(freq: f4 * dr, q: 2.0 + 0.5 * harmonicRichness, sampleRate: sampleRate)
        lastCoeffRpm = r
    }

    // MARK: Render (audio thread)

    /// Fill the supplied buffer list (mono or stereo) with `frameCount` samples.
    func render(frameCount: Int, bufferList: UnsafeMutableAudioBufferListPointer) {
        let channelCount = bufferList.count
        let out0 = bufferList[0].mData?.assumingMemoryBound(to: Float.self)
        let out1 = channelCount > 1 ? bufferList[1].mData?.assumingMemoryBound(to: Float.self) : nil
        renderStereo(frameCount: frameCount, left: out0, right: out1)
    }

    /// Pointer-based stereo render core. Kept separate from the AudioBufferList
    /// entry point so the DSP can be exercised offline in tests.
    func renderStereo(frameCount: Int,
                      left out0: UnsafeMutablePointer<Float>?,
                      right out1: UnsafeMutablePointer<Float>?) {
        // Per-sample smoothing coefficients (one-pole toward target).
        let kRpm = 1.0 - exp(-1.0 / (sampleRate * 0.035))     // ~35 ms
        let kThr = 1.0 - exp(-1.0 / (sampleRate * 0.020))     // ~20 ms
        let kGate = 1.0 - exp(-1.0 / (sampleRate * 0.050))
        let kCrank = 1.0 - exp(-1.0 / (sampleRate * 0.080))   // ~80 ms crank<->run blend
        let kShift = 1.0 - exp(-1.0 / (sampleRate * 0.015))   // ~15 ms shift-cut mute
        let kFuelCut = 1.0 - exp(-1.0 / (sampleRate * 0.010)) // ~10 ms limiter cut edge
        let kDfco = 1.0 - exp(-1.0 / (sampleRate * 0.040))    // ~40 ms fuel cut/refire blend
        let kOverrun = 1.0 - exp(-1.0 / (sampleRate * 0.120)) // ~120 ms overrun engage
        let kSpeaker = 1.0 - exp(-1.0 / (sampleRate * 0.150)) // ~150 ms route crossfade
        let kSlow = 1.0 - exp(-1.0 / (sampleRate * 0.090))
        let combNoiseDecay = exp(-1.0 / (sampleRate * Tuning.combNoiseBurstMs / 1000.0))
        let bovDecayCoef = exp(-1.0 / (sampleRate * Tuning.bovDecaySeconds))

        // Refresh resonator tuning if RPM moved meaningfully since last render.
        if abs(rpm - lastCoeffRpm) > 40.0 || lastCoeffRpm < 0 {
            updateResonatorCoefficients()
        }
        // Tailpipe resonance only changes on preset switch.
        if abs(tailpipeHz - lastTailpipeHz) > 0.5 {
            tailPeakL.setPeaking(freq: tailpipeHz * Tuning.bandDetuneL, q: 4.0, gainDB: 4.0, sampleRate: sampleRate)
            tailPeakR.setPeaking(freq: tailpipeHz * Tuning.bandDetuneR, q: 4.0, gainDB: 4.0, sampleRate: sampleRate)
            lastTailpipeHz = tailpipeHz
        }
        // Variable exhaust low-pass: throttle opens the system up, DFCO
        // muffles it, a straight pipe removes most of the muffler damping.
        // Block-rate values (≤ ~12 ms) are smooth enough for filter cutoffs.
        let kPipeBlock = 1.0 - exp(-Double(frameCount) / (sampleRate * 0.080))  // ~80 ms blend
        pipeOpenGate += ((straightPipeTarget ? 1.0 : 0.0) - pipeOpenGate) * kPipeBlock
        let stockCutoff = min(2600.0, max(850.0, 1200.0 + 1300.0 * throttle - 150.0 * dfcoGate))
        let exhaustLpCutoff = stockCutoff * (1.0 + 2.2 * pipeOpenGate)
        let kExhaustLp = 1.0 - exp(-2.0 * .pi * exhaustLpCutoff / sampleRate)

        // Consume cross-thread event triggers once per render callback.
        if bovTriggerCount != lastHandledBovTrigger {
            bovEnv = 1.0
            lastHandledBovTrigger = bovTriggerCount
        }
        if shiftPopTriggerCount != lastHandledShiftPopTrigger {
            triggerPop(baseAmplitude: 0.6 + 0.3 * rng.nextUnit(), decayMsMin: 8, decayMsMax: 16)
            lastHandledShiftPopTrigger = shiftPopTriggerCount
        }
        if fuelCutPopTriggerCount != lastHandledFuelCutPopTrigger {
            triggerPop(baseAmplitude: 0.55 + 0.35 * rng.nextUnit(), decayMsMin: 7, decayMsMax: 14)
            lastHandledFuelCutPopTrigger = fuelCutPopTriggerCount
        }
        if refirePopTriggerCount != lastHandledRefirePopTrigger {
            triggerPop(baseAmplitude: 0.25, decayMsMin: 8, decayMsMax: 14)
            lastHandledRefirePopTrigger = refirePopTriggerCount
        }
        if driveShockTargetCount != lastHandledDriveShock {
            // Clunky shift: a longer, lower driveline "thump" through the
            // same exhaust resonance, scaled by the rev mismatch.
            triggerPop(baseAmplitude: 0.25 + 0.55 * driveShockMagnitude, decayMsMin: 18, decayMsMax: 32)
            lastHandledDriveShock = driveShockTargetCount
        }

        for n in 0..<frameCount {
            // --- Smooth control parameters ---
            rpm += (targetRpm - rpm) * kRpm
            throttle += (targetThrottle - throttle) * kThr
            load += (targetLoad - load) * kThr
            speed += (targetSpeed - speed) * kSlow
            clutchPedal += (targetClutchPedal - clutchPedal) * kThr
            let gateTarget = running ? 1.0 : 0.0
            gate += (gateTarget - gate) * kGate
            crankGate += ((cranking ? 1.0 : 0.0) - crankGate) * kCrank
            shiftGate += ((shiftCutTarget ? 1.0 : 0.0) - shiftGate) * kShift
            fuelCutGate += ((fuelCutTarget ? 1.0 : 0.0) - fuelCutGate) * kFuelCut
            dfcoGate += ((decelFuelCutTarget ? 1.0 : 0.0) - dfcoGate) * kDfco
            overrunGate += ((overrunTarget ? 1.0 : 0.0) - overrunGate) * kOverrun

            if gate < 0.0005 && !running {
                if let o = out0 { o[n] = 0 }
                if let o = out1 { o[n] = 0 }
                continue
            }

            let rpmNorm = min(1.0, rpm / 8000.0)
            let inGear = gear > 0 ? 1.0 : 0.0
            let clutchOpen = min(1.0, max(0.0, clutchPedal))
            let drivetrainCoupling = inGear * (1.0 - clutchOpen)
            let roadSpeedNorm = min(1.0, max(0.0, speed / Tuning.roadNoiseMaxKmh))
            let gearLoad = drivetrainCoupling * (0.25 + 0.75 * load)
            let loadStress = min(1.0, load * (0.35 + 0.65 * throttle) + gearLoad * 0.22)

            // VTEC crossover blend (smoothstep around ~5600 RPM).
            var vtecBlend = 0.0
            if vtecMode {
                let x = max(0.0, min(1.0, (rpm - 5150.0) / 900.0))
                vtecBlend = x * x * (3.0 - 2.0 * x)
            }

            // How close we are to idle — drives jitter/roughness amount. 1 at
            // idle, fades to 0 by ~1.3x idle RPM.
            let idleSpan = max(50.0, idleRpm * 0.3)
            let idleProximity = min(1.0, max(0.0, 1.0 - (rpm - idleRpm) / idleSpan))

            // --- Per-sample noise sources (decorrelated per channel + one mono) ---
            let noiseMono = rng.nextBipolar()
            let wl = rng.nextBipolar()
            let wr = rng.nextBipolar()

            // --- Firing geometry ---
            let cycleFreq = rpm / 120.0                 // full 4-stroke cycle (2 revs), Hz
            cyclePhase += cycleFreq / sampleRate
            if cyclePhase >= 1.0 { cyclePhase -= 1.0 }

            // Pulse width as a fraction of the cylinder spacing. Narrower pulses =
            // sharper/brighter/raspier. Load, throttle, RPM and VTEC all sharpen it.
            // The absolute-sample floor keeps the pulse band-limited at high
            // firing rates (anti-aliasing; V12 near redline would otherwise
            // degenerate into single-sample impulses).
            let spacing = 1.0 / Double(cylinders)
            let sharpen = 0.55 - 0.18 * throttle - 0.12 * rpmNorm - 0.10 * vtecBlend - 0.06 * harmonicRichness + 0.04 * frictionFactor + 0.10 * dfcoGate - 0.07 * pipeOpenGate
            let minFrac = min(0.5, Tuning.minPulseWidthSamples * cycleFreq * Double(cylinders) / sampleRate)
            let duty = spacing * max(minFrac, max(0.16, sharpen))

            // Cycle-to-cycle combustion variation (CoV of IMEP): rises with RPM
            // and toward idle, falls with load — measured SI-engine behavior.
            let rpmCov = Tuning.covRpmGain * pow(max(0.0, rpmNorm - 0.35) / 0.65, 1.6)
            let cov = min(Tuning.covMax, max(Tuning.covMin,
                Tuning.covBase + rpmCov + Tuning.covIdleGain * idleProximity - Tuning.covLoadCut * loadStress))
            let timingJitterAmt = (Tuning.timingJitterIntervalAtLoad
                + (Tuning.timingJitterIntervalAtIdle - Tuning.timingJitterIntervalAtLoad) * idleProximity) * spacing
            let misfireChance = Tuning.misfireChanceMax * idleProximity * idleProximity

            // --- Combustion excitation: sum shaped pulses over all cylinders,
            // routed into their exhaust bank (A leans left, B leans right). ---
            let twoBanks = exhaustBankCount == 2
            var excA = 0.0
            var excB = 0.0
            for i in 0..<cylinders {
                let angle = firingAngle[i] + firingAngleJitter[i]
                var q = cyclePhase - angle
                if q < 0 { q += 1.0 }
                let inPulse = q < duty

                if inPulse && !wasInPulse[i] {
                    // New firing event: slow per-cylinder drift (AR(1), cycle-
                    // correlated → half-order energy) plus fresh per-event
                    // scatter, and a rare misfire.
                    covSlow[i] = Tuning.covAr1Keep * covSlow[i] + (1.0 - Tuning.covAr1Keep) * cov * rng.nextBipolar()
                    var amp = 1.0 + covSlow[i] + 0.6 * cov * rng.nextBipolar()
                    if rng.nextUnit() < misfireChance {
                        amp *= Tuning.misfireAmpFloor + 0.10 * rng.nextUnit()
                    }
                    pulseAmpJitter[i] = amp

                    // Combustion noise burst, scaled with this event's intensity.
                    combNoiseEnv += Tuning.combNoiseBurstGain * amp * (0.4 + 0.9 * throttle + 0.5 * loadStress) * (0.82 + 0.32 * exhaustEfficiency)

                    // Timing jitter for this cylinder's *next* firing.
                    firingAngleJitter[i] = timingJitterAmt * rng.nextBipolar()
                }
                wasInPulse[i] = inPulse

                if inPulse {
                    let u = q / duty
                    let shaped: Double
                    if u < Tuning.pulseAttackFrac {
                        let a = u / Tuning.pulseAttackFrac
                        shaped = a * a
                    } else {
                        let d = (u - Tuning.pulseAttackFrac) / (1.0 - Tuning.pulseAttackFrac)
                        shaped = exp(-d * Tuning.pulseDecayRate)
                    }
                    let contribution = cylinderAmp[i] * pulseAmpJitter[i] * shaped
                    if firingBank[i] == 0 {
                        excA += contribution
                    } else {
                        excB += contribution
                    }
                }
            }

            // Combustion intensity grows with throttle & load. DFCO cuts the
            // fuel but the engine keeps pumping air through the exhaust, so
            // the pulsation only drops ~5 dB and darkens — the overrun drone
            // you hear engine-braking downhill. (Deeper cuts proved near-
            // silent on a phone speaker: "the sound died" after downshifts.)
            let neutralLightness = 0.78 + 0.22 * drivetrainCoupling
            let excGain = (0.55 + 0.95 * throttle + 0.45 * loadStress) * neutralLightness
                * (0.86 + 0.22 * exhaustEfficiency)
                * (1.0 - 0.45 * dfcoGate)
                * (1.0 + 0.35 * pipeOpenGate)

            // Inject the shared combustion-noise burst and any pending
            // overrun/afterfire/shift/limiter pop into the same excitation path
            // so they ring through the same exhaust resonance as real pulses.
            // Cranking: no real ignition yet — weak, muffled compression pulses.
            let injected = combNoiseEnv * noiseMono + popEnv * noiseMono * 0.9
            combNoiseEnv *= combNoiseDecay
            popEnv *= popDecayCoef

            let crankExcitationLevel = 1.0 - Tuning.crankExcitationCut * crankGate
            if twoBanks {
                excA = (excA * excGain + injected * 0.5) * crankExcitationLevel
                excB = (excB * excGain + injected * 0.5) * crankExcitationLevel
            } else {
                excA = (excA * excGain + injected) * crankExcitationLevel
            }

            // --- Overrun / afterfire pop scheduling (Poisson-ish). Unburned
            // fuel igniting in the hot exhaust — DFCO overrun is when real
            // pops & bangs happen. ---
            if (overrunGate > 0.4 || dfcoGate > 0.4) && crankGate < 0.5 && gate > 0.5 {
                popCountdownSamples -= 1
                if popCountdownSamples <= 0 {
                    // A straight pipe crackles more often and more violently.
                    let openPipe = pipeOpenGate > 0.5
                    let bigChance = (popsEnabled ? Tuning.overrunPopBigChance : Tuning.overrunPopBigChanceDisabled)
                        + (openPipe ? 0.12 : 0.0)
                    let big = rng.nextUnit() < bigChance
                    let ampScale = popsEnabled ? 1.0 : Tuning.overrunPopAmpDisabledScale
                    let base = (0.5 + 0.5 * rng.nextUnit()) * (big ? 2.6 : 1.0) * ampScale * (openPipe ? 1.3 : 1.0)
                    triggerPop(baseAmplitude: base, decayMsMin: Tuning.popDecayMsMin, decayMsMax: Tuning.popDecayMsMax)

                    let u = max(1e-6, rng.nextUnit())
                    let meanMs = (popsEnabled ? Tuning.overrunPopMeanMsEnabled : Tuning.overrunPopMeanMsDisabled)
                        * (openPipe ? 0.40 : 1.0)
                    let intervalMs = min(max(-log(u) * meanMs, 25.0), 420.0)
                    popCountdownSamples = Int(intervalMs * 0.001 * sampleRate)
                }
            }

            // DC-block each bank's pulse train (asymmetric pulses carry DC).
            let dcOutA = excA - dcX + 0.9975 * dcY
            dcX = excA
            dcY = dcOutA
            var dcOutB = 0.0
            if twoBanks {
                dcOutB = excB - dcXB + 0.9975 * dcYB
                dcXB = excB
                dcYB = dcOutB
            }

            // --- Exhaust pipe waveguides: short feedback delay per bank ahead
            // of the formant bank, giving each pipe its own comb resonance. ---
            let delayMs = Tuning.pipeDelayMsAtHighRpm
                + (Tuning.pipeDelayMsAtIdle - Tuning.pipeDelayMsAtHighRpm) * (1.0 - rpmNorm)
            let feedback = Tuning.pipeFeedbackBase
                + 0.10 * exhaustScavengingFactor
                + 0.05 * drivetrainCoupling
                + 0.10 * pipeOpenGate
                - Tuning.pipeFeedbackThrottleCut * throttle

            let delaySamples = min(pipeDelayCapacity - 1, max(1, Int(delayMs * 0.001 * sampleRate)))
            let readIdx = (pipeDelayWriteIdx - delaySamples + pipeDelayCapacity) % pipeDelayCapacity
            let delayed = pipeDelayBuffer[readIdx]
            pipeDelayLP += Tuning.pipeLoopDamping * (delayed - pipeDelayLP)
            let pipedA = dcOutA + pipeDelayLP * feedback
            pipeDelayBuffer[pipeDelayWriteIdx] = pipedA
            pipeDelayWriteIdx += 1
            if pipeDelayWriteIdx >= pipeDelayCapacity { pipeDelayWriteIdx = 0 }

            var pipedB = 0.0
            if twoBanks {
                // Bank B: unequal-length header — slightly longer pipe.
                let ratio = boxerMode ? Tuning.bankPipeRatioBoxer : Tuning.bankPipeRatioV
                let delaySamplesB = min(pipeDelayCapacity - 1, max(1, Int(delayMs * ratio * 0.001 * sampleRate)))
                let readIdxB = (pipeDelayWriteIdxB - delaySamplesB + pipeDelayCapacity) % pipeDelayCapacity
                let delayedB = pipeDelayBufferB[readIdxB]
                pipeDelayLPB += Tuning.pipeLoopDamping * (delayedB - pipeDelayLPB)
                pipedB = dcOutB + pipeDelayLPB * feedback
                pipeDelayBufferB[pipeDelayWriteIdxB] = pipedB
                pipeDelayWriteIdxB += 1
                if pipeDelayWriteIdxB >= pipeDelayCapacity { pipeDelayWriteIdxB = 0 }
            }

            // Bank routing: A leans left, B leans right; cross-bleed models the
            // acoustic mixing between tailpipes. Single-collector engines feed
            // both channels identically (stereo comes from formant detune).
            let mixL: Double, mixR: Double
            let directL: Double, directR: Double
            if twoBanks {
                mixL = (pipedA + Tuning.bankCrossBleed * pipedB) * Tuning.bankMakeupGain
                mixR = (pipedB + Tuning.bankCrossBleed * pipedA) * Tuning.bankMakeupGain
                directL = (dcOutA + Tuning.bankCrossBleed * dcOutB) * Tuning.bankMakeupGain
                directR = (dcOutB + Tuning.bankCrossBleed * dcOutA) * Tuning.bankMakeupGain
            } else {
                mixL = pipedA
                mixR = pipedA
                directL = dcOutA
                directR = dcOutA
            }

            // --- Resonance / formant bank (independent L/R for stereo width) ---
            let bodyL = bodyResL.process(mixL), bodyR = bodyResR.process(mixR)
            let e1L = exhaust1L.process(mixL), e1R = exhaust1R.process(mixR)
            let e2L = exhaust2L.process(mixL), e2R = exhaust2R.process(mixR)
            let e3L = exhaust3L.process(mixL), e3R = exhaust3R.process(mixR)
            let e4L = exhaust4L.process(mixL), e4R = exhaust4R.process(mixR)

            // VTEC lifts the upper formants when engaged; fuel-cut overrun
            // darkens the top end (no combustion energy to excite it); an open
            // straight pipe lets the rasp through.
            let dfcoDarken = 1.0 - 0.30 * dfcoGate
            let pipeBright = 1.0 + 0.90 * pipeOpenGate
            let e3GainDyn = (0.28 + 0.30 * vtecBlend) * dfcoDarken * pipeBright
            let e4GainDyn = (0.20 + 0.34 * vtecBlend) * dfcoDarken * pipeBright

            // Cranking reshapes the mix toward a low, muffled thump (no exhaust
            // formants yet — there's no real exhaust pulse until ignition fires).
            let bodyWeight = (0.78 + 0.22 * drivetrainCoupling + Tuning.crankBodyBoost * crankGate)
            let exhaustWeight = (1.0 - Tuning.crankExhaustCut * crankGate) * (0.78 + 0.30 * exhaustEfficiency)

            let directGain = (0.10 + 0.26 * throttle + 0.16 * rpmNorm + 0.14 * loadStress)
                * exhaustWeight
                * (0.84 + 0.32 * harmonicRichness)
                * (1.0 - 0.35 * dfcoGate)

            // Half-order-locked roughness AM (20-70 Hz modulation band through
            // the usable rev range) for single-collector engines; dual-bank
            // engines generate this physically from uneven per-bank firing.
            var roughnessAM = 1.0
            if !twoBanks {
                let depth = (Tuning.roughnessDepthBase + Tuning.roughnessDepthScav * min(1.0, exhaustScavengingFactor))
                    * min(1.0, rpm / 2500.0)
                roughnessAM = 1.0 + depth * sin(2.0 * .pi * cyclePhase)
            }

            var combustionL = bodyWeight * bodyL
                + exhaustWeight * roughnessAM * (0.65 * e1L + 0.62 * e2L + e3GainDyn * e3L + e4GainDyn * e4L)
                + directGain * directL
            var combustionR = bodyWeight * bodyR
                + exhaustWeight * roughnessAM * (0.65 * e1R + 0.62 * e2R + e3GainDyn * e3R + e4GainDyn * e4R)
                + directGain * directR

            // --- Rev limiter (fuel-cut stutter), with a small pop each time it
            // re-opens so recovery reads as "bap-bap-bap" rather than a mute. ---
            var limiterMute = 1.0
            if fuelCutGate > 0.08 || rpm > redlineRpm * 0.985 {
                limiterPhase += (22.0 + 6.0 * fuelCutGate) / sampleRate
                if limiterPhase >= 1.0 { limiterPhase -= 1.0 }
                let cutNow = limiterPhase < (0.40 + 0.18 * fuelCutGate)
                if limiterWasCut && !cutNow {
                    triggerPop(baseAmplitude: 0.45 + 0.25 * rng.nextUnit(), decayMsMin: 6, decayMsMax: 12)
                }
                limiterWasCut = cutNow
                limiterMute = cutNow ? (1.0 - Tuning.fuelCutMuteDepth) : 1.0
            } else {
                limiterPhase = 0
                limiterWasCut = false
            }

            // Shift-cut: ignition mostly muted while the cut is engaged.
            let shiftMute = 1.0 - Tuning.shiftCutMuteDepth * shiftGate

            let combustionMute = limiterMute * shiftMute
            combustionL *= combustionMute
            combustionR *= combustionMute

            // Tailpipe quarter-wave resonance + variable exhaust low-pass.
            combustionL = tailPeakL.process(combustionL)
            combustionR = tailPeakR.process(combustionR)
            exhaustLpL += kExhaustLp * (combustionL - exhaustLpL)
            exhaustLpR += kExhaustLp * (combustionR - exhaustLpR)
            combustionL = exhaustLpL
            combustionR = exhaustLpR

            // Small-speaker compensation: fold the sub-250 Hz energy the phone
            // speaker cannot move into 2nd/3rd-harmonic midrange it can.
            // |x| doubles the frequency, x·|x| adds the 3rd; the DC/fundamental
            // is stripped and the result smoothed to ≤ ~1.4 kHz.
            speakerGate += ((smallSpeakerTarget ? 1.0 : 0.0) - speakerGate) * kSpeaker
            if speakerGate > 0.001 {
                spkLowL += Tuning.speakerBassLowpassK * (combustionL - spkLowL)
                spkLowR += Tuning.speakerBassLowpassK * (combustionR - spkLowR)
                let rawL = abs(spkLowL) * 1.6 + spkLowL * abs(spkLowL) * 1.2
                let rawR = abs(spkLowR) * 1.6 + spkLowR * abs(spkLowR) * 1.2
                spkDcL += Tuning.speakerHarmDcK * (rawL - spkDcL)
                spkDcR += Tuning.speakerHarmDcK * (rawR - spkDcR)
                spkMidL += Tuning.speakerHarmMidK * ((rawL - spkDcL) - spkMidL)
                spkMidR += Tuning.speakerHarmMidK * ((rawR - spkDcR) - spkMidR)
                combustionL += spkMidL * Tuning.speakerHarmGain * speakerGate
                combustionR += spkMidR * Tuning.speakerHarmGain * speakerGate
            }

            // --- Turbo whistle: band-passed noise whose center rises with
            // spool, not a sine tone. ---
            var turboL = 0.0, turboR = 0.0
            if turboMode {
                let spool = max(0.0, throttle - 0.15) * min(1.0, rpm / 6500.0)
                if abs(spool - lastTurboSpool) > 0.006 {
                    let centerHz = Tuning.turboFreqBase + Tuning.turboFreqSpoolRange * spool
                    let q = Tuning.turboQBase + Tuning.turboQSpoolRange * spool
                    turboResL.setBandpass(freq: centerHz * 0.99, q: q, sampleRate: sampleRate)
                    turboResR.setBandpass(freq: centerHz * 1.01, q: q, sampleRate: sampleRate)
                    lastTurboSpool = spool
                }
                if spool > 0.0008 {
                    turboL = turboResL.process(wl) * spool * Tuning.turboGain
                    turboR = turboResR.process(wr) * spool * Tuning.turboGain
                } else {
                    _ = turboResL.process(0)
                    _ = turboResR.process(0)
                }
            }

            // --- Blow-off valve burst: broadband, high-passed noise. ---
            var bovL = 0.0, bovR = 0.0
            if bovEnv > 0.0005 {
                bovHpL += 0.25 * (wl - bovHpL)
                bovHpR += 0.25 * (wr - bovHpR)
                let hpL = wl - bovHpL
                let hpR = wr - bovHpR
                bovL = hpL * bovEnv * Tuning.bovGain
                bovR = hpR * bovEnv * Tuning.bovGain
                bovEnv *= bovDecayCoef
            }

            // --- Starter motor: gear whine (fundamental + harmonic), amplitude
            // modulated in sync with cranking RPM, fading in/out with crankGate. ---
            var starterL = 0.0, starterR = 0.0
            if crankGate > 0.001 {
                starterGearPhase += (rpm / 60.0 * 6.0) / sampleRate
                if starterGearPhase >= 1.0 { starterGearPhase -= 1.0 }
                let gearAM = 0.7 + 0.3 * sin(2.0 * .pi * starterGearPhase)
                let baseL = starterResL.process(wl) * Tuning.starterGain
                let baseR = starterResR.process(wr) * Tuning.starterGain
                let harmL = starterRes2L.process(wl) * Tuning.starterHarmonicGain
                let harmR = starterRes2R.process(wr) * Tuning.starterHarmonicGain
                starterL = (baseL + harmL) * gearAM * crankGate
                starterR = (baseR + harmR) * gearAM * crankGate
            } else {
                _ = starterResL.process(0); _ = starterResR.process(0)
                _ = starterRes2L.process(0); _ = starterRes2R.process(0)
            }

            var coreL = combustionL + turboL + bovL + starterL
            var coreR = combustionR + turboR + bovR + starterR

            coreL *= gate
            coreR *= gate

            // --- Per-channel noise beds (decorrelated for stereo width) ---
            // Intake noise follows the throttle plate: idle bleed stays, but a
            // closed throttle at speed (overrun) passes almost no intake air.
            // Mechanical noise is BAND-limited (~3.4-6 kHz "clatter"), not raw
            // high-passed white — full-bandwidth hiss dominates on a phone
            // speaker, whose response starts where the engine tone ends.
            let intakeAmt = (0.02 + 0.08 * idleProximity + 0.44 * throttle + 0.20 * loadStress) * (0.75 + 0.45 * intakeEfficiency) * (0.78 + 0.42 * intakeHarmonicFactor)
            let mechAmt   = (0.03 + 0.13 * rpmNorm + 0.09 * loadStress) * (0.75 + 1.20 * frictionFactor)
            let roadAmt = roadSpeedNorm * roadSpeedNorm * Tuning.roadNoiseGain * (0.45 + 0.55 * drivetrainCoupling)
            let lpK = 0.05 + 0.10 * throttle

            // Left channel
            intakeLpL += lpK * (wl - intakeLpL)
            let mechHpL_out = wl - mechHpL; mechHpL += 0.4 * (wl - mechHpL)
            mechBandL += 0.55 * (mechHpL_out - mechBandL)
            roadLpL += 0.035 * (wl - roadLpL)
            let roadL = (wl - roadLpL) * roadAmt
            let noiseL = (intakeLpL * intakeAmt + mechBandL * mechAmt + roadL) * gate

            // Right channel
            intakeLpR += lpK * (wr - intakeLpR)
            let mechHpR_out = wr - mechHpR; mechHpR += 0.4 * (wr - mechHpR)
            mechBandR += 0.55 * (mechHpR_out - mechBandR)
            roadLpR += 0.035 * (wr - roadLpR)
            let roadR = (wr - roadLpR) * roadAmt
            let noiseR = (intakeLpR * intakeAmt + mechBandR * mechAmt + roadR) * gate

            // --- Saturation + master ---
            // Gentle drive: warms and hardens under load without crushing the
            // crest factor into a square wave.
            let drive = 1.0 + 0.7 * throttle + 0.3 * loadStress + 0.3 * vtecBlend + 0.35 * pipeOpenGate

            // Small-speaker loudness: the sub-band the speaker cannot move
            // only eats limiter headroom, so strip it and push the level.
            // The straight pipe gets an extra shove so its difference is
            // unmistakable on the phone speaker too.
            var preL = coreL + noiseL
            var preR = coreR + noiseR
            if speakerGate > 0.001 {
                spkCutL += 0.032 * (preL - spkCutL)   // ~230 Hz
                spkCutR += 0.032 * (preR - spkCutR)
                preL -= spkCutL * 0.8 * speakerGate
                preR -= spkCutR * 0.8 * speakerGate
            }
            let master = 0.55 * (1.0 + 0.45 * speakerGate + 0.18 * speakerGate * pipeOpenGate)

            var left  = tanh(drive * preL) * master
            var right = tanh(drive * preR) * master

            let cabinReadIdxL = (cabinDelayWriteIdx - cabinDelaySamplesL + cabinDelayCapacity) % cabinDelayCapacity
            let cabinReadIdxR = (cabinDelayWriteIdx - cabinDelaySamplesR + cabinDelayCapacity) % cabinDelayCapacity
            let reflectionL = cabinDelayL[cabinReadIdxL]
            let reflectionR = cabinDelayR[cabinReadIdxR]
            cabinDelayL[cabinDelayWriteIdx] = left
            cabinDelayR[cabinDelayWriteIdx] = right
            cabinDelayWriteIdx += 1
            if cabinDelayWriteIdx >= cabinDelayCapacity { cabinDelayWriteIdx = 0 }

            let cabinGain = Tuning.cabinReflectionGain * (0.55 + 0.25 * roadSpeedNorm + 0.20 * drivetrainCoupling)
            left += reflectionR * cabinGain
            right += reflectionL * cabinGain

            // Remove the DC that asymmetric excitation + tanh introduce (prevents
            // speaker offset and start/stop thumps).
            let dl = left - outDcXL + 0.9995 * outDcYL
            outDcXL = left; outDcYL = dl; left = dl
            let dr = right - outDcXR + 0.9995 * outDcYR
            outDcXR = right; outDcYR = dr; right = dr

            if let o = out0 { o[n] = Float(left) }
            if let o = out1 { o[n] = Float(right) }
        }
    }

    // MARK: Shared pop envelope

    /// Retrigger the shared pop envelope (overrun/afterfire, shift-cut recovery,
    /// rev-limiter recovery all route through this so they ring through the same
    /// exhaust resonance as everything else). Additive so overlapping triggers
    /// don't erase each other; clamped so it can never blow up the resonators —
    /// final output is bounded by tanh regardless.
    @inline(__always)
    private func triggerPop(baseAmplitude: Double, decayMsMin: Double, decayMsMax: Double) {
        popEnv += baseAmplitude
        if popEnv > 4.0 { popEnv = 4.0 }
        let ms = decayMsMin + (decayMsMax - decayMsMin) * rng.nextUnit()
        popDecayCoef = exp(-1.0 / (sampleRate * ms / 1000.0))
    }

    // MARK: Lifecycle

    func reset() {
        rpm = 0; throttle = 0; load = 0; speed = 0; clutchPedal = 0; gate = 0
        crankGate = 0; shiftGate = 0; fuelCutGate = 0; dfcoGate = 0; overrunGate = 0
        speakerGate = 0
        pipeOpenGate = 0
        spkLowL = 0; spkLowR = 0; spkDcL = 0; spkDcR = 0; spkMidL = 0; spkMidR = 0
        spkCutL = 0; spkCutR = 0
        cyclePhase = 0; limiterPhase = 0; limiterWasCut = false
        starterGearPhase = 0
        dcX = 0; dcY = 0; dcXB = 0; dcYB = 0
        outDcXL = 0; outDcYL = 0; outDcXR = 0; outDcYR = 0
        intakeLpL = 0; intakeLpR = 0
        mechHpL = 0; mechHpR = 0
        mechBandL = 0; mechBandR = 0
        roadLpL = 0; roadLpR = 0
        bodyResL.reset(); bodyResR.reset()
        exhaust1L.reset(); exhaust1R.reset()
        exhaust2L.reset(); exhaust2R.reset()
        exhaust3L.reset(); exhaust3R.reset()
        exhaust4L.reset(); exhaust4R.reset()
        turboResL.reset(); turboResR.reset()
        starterResL.reset(); starterResR.reset()
        starterRes2L.reset(); starterRes2R.reset()
        tailPeakL.reset(); tailPeakR.reset()
        exhaustLpL = 0; exhaustLpR = 0
        lastCoeffRpm = -1
        lastTurboSpool = -1
        lastTailpipeHz = -1

        combNoiseEnv = 0
        popEnv = 0
        popCountdownSamples = 2000
        bovEnv = 0
        bovHpL = 0; bovHpR = 0

        for i in 0..<pipeDelayBuffer.count { pipeDelayBuffer[i] = 0 }
        for i in 0..<pipeDelayBufferB.count { pipeDelayBufferB[i] = 0 }
        pipeDelayWriteIdx = 0
        pipeDelayWriteIdxB = 0
        pipeDelayLP = 0
        pipeDelayLPB = 0
        for i in 0..<cabinDelayL.count { cabinDelayL[i] = 0 }
        for i in 0..<cabinDelayR.count { cabinDelayR[i] = 0 }
        cabinDelayWriteIdx = 0

        for i in 0..<firingAngleJitter.count { firingAngleJitter[i] = 0 }
        for i in 0..<pulseAmpJitter.count { pulseAmpJitter[i] = 1.0 }
        for i in 0..<wasInPulse.count { wasInPulse[i] = false }
        for i in 0..<covSlow.count { covSlow[i] = 0 }

        // Avoid replaying stale cross-thread triggers that happened before reset.
        lastHandledBovTrigger = bovTriggerCount
        lastHandledShiftPopTrigger = shiftPopTriggerCount
        lastHandledFuelCutPopTrigger = fuelCutPopTriggerCount
        lastHandledRefirePopTrigger = refirePopTriggerCount
        lastHandledDriveShock = driveShockTargetCount
    }
}
