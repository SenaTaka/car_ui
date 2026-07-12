import Foundation

/// Engine configuration parameters
nonisolated struct EngineParameters {
    // Engine characteristics
    var cylinders: Int
    var displacement: Double  // in liters
    var bore: Double  // in mm
    var stroke: Double  // in mm
    var compressionRatio: Double
    var firingOrder: [Int]

    // RPM limits
    var idleRpm: Double
    var redlineRpm: Double
    var maxRpm: Double

    // Audio synthesis parameters
    var harmonicCount: Int
    var exhaustScavengingFactor: Double
    var intakeHarmonicFactor: Double

    // Engine-specific modes (from sound.md)
    var vtecMode: Bool
    var boxerMode: Bool
    var turboMode: Bool

    // Performance characteristics
    var intakeEfficiency: Double
    var exhaustEfficiency: Double
    var frictionFactor: Double

    init(cylinders: Int = 4,
         displacement: Double = 2.0,
         bore: Double = 86.0,
         stroke: Double = 86.0,
         compressionRatio: Double = 10.0,
         firingOrder: [Int] = [1, 3, 4, 2],
         idleRpm: Double = 800,
         redlineRpm: Double = 6500,
         maxRpm: Double = 7000,
         harmonicCount: Int = 16,
         exhaustScavengingFactor: Double = 0.7,
         intakeHarmonicFactor: Double = 0.3,
         vtecMode: Bool = false,
         boxerMode: Bool = false,
         turboMode: Bool = false,
         intakeEfficiency: Double = 0.85,
         exhaustEfficiency: Double = 0.90,
         frictionFactor: Double = 0.15) {
        self.cylinders = cylinders
        self.displacement = displacement
        self.bore = bore
        self.stroke = stroke
        self.compressionRatio = compressionRatio
        self.firingOrder = firingOrder
        self.idleRpm = idleRpm
        self.redlineRpm = redlineRpm
        self.maxRpm = maxRpm
        self.harmonicCount = harmonicCount
        self.exhaustScavengingFactor = exhaustScavengingFactor
        self.intakeHarmonicFactor = intakeHarmonicFactor
        self.vtecMode = vtecMode
        self.boxerMode = boxerMode
        self.turboMode = turboMode
        self.intakeEfficiency = intakeEfficiency
        self.exhaustEfficiency = exhaustEfficiency
        self.frictionFactor = frictionFactor
    }
}

nonisolated extension EngineParameters {
    /// Exhaust-bank assignment for each firing event, derived from the firing
    /// order. Bit i of `pattern` is the bank (0 = A, 1 = B) of the i-th firing
    /// event in the 720° cycle. Per-bank firing becomes UNEVEN exactly where
    /// real engines are uneven — a cross-plane V8 yields 270-180-90-180° within
    /// one bank, which is the physical source of its burble. Singles/triples
    /// and malformed firing orders collapse to one bank.
    var exhaustBankInfo: (pattern: UInt16, bankCount: Int) {
        let n = cylinders
        guard n <= 16, firingOrder.count == n,
              firingOrder.allSatisfy({ $0 >= 1 && $0 <= n }) else {
            return (0, 1)
        }

        let bankOfCylinder: (Int) -> Int
        switch (n, boxerMode) {
        case (8, _), (4, true):
            // Cross-plane V8 (SBC numbering: odd cylinders = left bank) and
            // boxer-4 (odd = left side). Both produce uneven per-bank rhythm.
            bankOfCylinder = { $0 % 2 == 1 ? 0 : 1 }
        case (6, _), (10, false), (12, false):
            // V6/V10/V12, inline-6 with split (3-2-1) manifold, flat-6:
            // front half vs rear half — evenly alternating per bank.
            bankOfCylinder = { $0 <= n / 2 ? 0 : 1 }
        case (4, false):
            // Inline-4 with 4-2-1 header pairing: 1&4 vs 2&3.
            bankOfCylinder = { ($0 == 1 || $0 == 4) ? 0 : 1 }
        default:
            return (0, 1)
        }

        var pattern: UInt16 = 0
        for (i, cyl) in firingOrder.enumerated() where bankOfCylinder(cyl) == 1 {
            pattern |= UInt16(1) << UInt16(i)
        }
        return (pattern, 2)
    }
}
