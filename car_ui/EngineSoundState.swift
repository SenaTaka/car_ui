import Foundation

/// Snapshot of everything the synthesizer needs for one control-rate update.
/// Built on the main thread by `EngineSoundController` and consumed by `HarmonicGenerator`.
nonisolated struct EngineSoundState {
    var rpm: Double = 0
    var throttle: Double = 0        // 0...1
    var load: Double = 0            // 0...1
    var running: Bool = false
    var cranking: Bool = false      // starter motor phase of the start sequence
    var shiftCut: Bool = false      // momentary ignition cut during an upshift
    var fuelCut: Bool = false       // rev limiter fuel cut is active
    var decelFuelCut: Bool = false  // DFCO: fuel off during closed-throttle overrun
    var overrun: Bool = false       // throttle closed while RPM is falling from high
    var popsEnabled: Bool = true    // user toggle: exhaust pops & crackles on overrun
    var straightPipe: Bool = false  // reward unlock: open exhaust, extra pops
    var gear: Int = 0               // 0 = neutral, 1...6 = in gear
    var speed: Double = 0           // km/h
    var driveShockCount: Int = 0    // increments once per clunky shift
    var driveShockMagnitude: Double = 0  // 0...1 severity of the last one
    var clutchPedal: Double = 0     // 0 released, 1 fully pressed

    var cylinders: Int = 4
    var exhaustBankPattern: UInt16 = 0  // bit i = bank of the i-th firing event
    var exhaustBankCount: Int = 1       // 1 = single collector, 2 = dual bank
    var tailpipeResonanceHz: Double = 120  // quarter-wave resonance f = c/(4L)
    var idleRpm: Double = 800
    var redlineRpm: Double = 7000
    var harmonicCount: Int = 16
    var exhaustScavengingFactor: Double = 0.7
    var intakeHarmonicFactor: Double = 0.3
    var intakeEfficiency: Double = 0.85
    var exhaustEfficiency: Double = 0.90
    var frictionFactor: Double = 0.15

    var vtecMode: Bool = false
    var boxerMode: Bool = false
    var turboMode: Bool = false
    var smallSpeaker: Bool = false  // output is the built-in phone speaker
}
