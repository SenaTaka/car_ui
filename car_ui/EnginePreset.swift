import Foundation

/// Predefined engine configurations
struct EnginePreset: Identifiable {
    let id = UUID()
    let name: String
    let description: String
    let parameters: EngineParameters

    static let presets: [EnginePreset] = [
        EnginePreset(
            name: "Inline 4 Economy",
            description: "1.6L 4-cylinder economy engine",
            parameters: EngineParameters(
                cylinders: 4,
                displacement: 1.6,
                bore: 76.0,
                stroke: 88.0,
                compressionRatio: 10.5,
                firingOrder: [1, 3, 4, 2],
                idleRpm: 750,
                redlineRpm: 6000,
                maxRpm: 6500
            )
        ),

        EnginePreset(
            name: "Inline 4 Sport",
            description: "2.0L turbocharged 4-cylinder",
            parameters: EngineParameters(
                cylinders: 4,
                displacement: 2.0,
                bore: 86.0,
                stroke: 86.0,
                compressionRatio: 9.5,
                firingOrder: [1, 3, 4, 2],
                idleRpm: 800,
                redlineRpm: 7000,
                maxRpm: 7500,
                turboMode: true
            )
        ),

        EnginePreset(
            name: "V6 Grand Tourer",
            description: "3.5L V6 smooth cruiser",
            parameters: EngineParameters(
                cylinders: 6,
                displacement: 3.5,
                bore: 94.0,
                stroke: 84.0,
                compressionRatio: 11.0,
                firingOrder: [1, 4, 2, 5, 3, 6],
                idleRpm: 650,
                redlineRpm: 6500,
                maxRpm: 7000
            )
        ),

        EnginePreset(
            name: "V8 American Muscle",
            description: "5.0L V8 performance engine",
            parameters: EngineParameters(
                cylinders: 8,
                displacement: 5.0,
                bore: 92.2,
                stroke: 93.0,
                compressionRatio: 11.0,
                firingOrder: [1, 8, 4, 3, 6, 5, 7, 2],
                idleRpm: 750,
                redlineRpm: 7500,
                maxRpm: 8000,
                harmonicCount: 20
            )
        ),

        EnginePreset(
            name: "V12 Exotic",
            description: "6.5L V12 supercar engine",
            parameters: EngineParameters(
                cylinders: 12,
                displacement: 6.5,
                bore: 95.0,
                stroke: 76.4,
                compressionRatio: 11.5,
                firingOrder: [1, 7, 5, 11, 3, 9, 6, 12, 2, 8, 4, 10],
                idleRpm: 900,
                redlineRpm: 8500,
                maxRpm: 9000,
                harmonicCount: 24
            )
        ),

        EnginePreset(
            name: "Flat 6 Sports Car",
            description: "3.0L horizontally opposed 6-cylinder",
            parameters: EngineParameters(
                cylinders: 6,
                displacement: 3.0,
                bore: 102.0,
                stroke: 61.0,
                compressionRatio: 12.0,
                firingOrder: [1, 6, 2, 4, 3, 5],
                idleRpm: 850,
                redlineRpm: 9000,
                maxRpm: 9500,
                harmonicCount: 18
            )
        ),

        EnginePreset(
            name: "Inline 6 Legend",
            description: "3.2L naturally aspirated straight-six",
            parameters: EngineParameters(
                cylinders: 6,
                displacement: 3.2,
                bore: 87.0,
                stroke: 91.0,
                compressionRatio: 11.3,
                firingOrder: [1, 5, 3, 6, 2, 4],
                idleRpm: 700,
                redlineRpm: 7900,
                maxRpm: 8300,
                harmonicCount: 18
            )
        ),

        EnginePreset(
            name: "V10 Symphony",
            description: "5.2L high-revving V10",
            parameters: EngineParameters(
                cylinders: 10,
                displacement: 5.2,
                bore: 88.0,
                stroke: 79.0,
                compressionRatio: 12.0,
                firingOrder: [1, 6, 5, 10, 2, 7, 3, 8, 4, 9],
                idleRpm: 850,
                redlineRpm: 8700,
                maxRpm: 9000,
                harmonicCount: 22
            )
        ),

        EnginePreset(
            name: "Kei Turbo 660",
            description: "0.66L 3-cylinder turbo kei car",
            parameters: EngineParameters(
                cylinders: 3,
                displacement: 0.66,
                bore: 64.0,
                stroke: 68.2,
                compressionRatio: 9.2,
                firingOrder: [1, 2, 3],
                idleRpm: 850,
                redlineRpm: 7200,
                maxRpm: 7700,
                harmonicCount: 14,
                turboMode: true
            )
        ),

        EnginePreset(
            name: "F1 V10 Legend",
            description: "3.0L V10 — the 19,000 rpm championship scream",
            parameters: EngineParameters(
                cylinders: 10,
                displacement: 3.0,
                bore: 96.0,
                stroke: 41.4,
                compressionRatio: 13.5,
                firingOrder: [1, 6, 5, 10, 2, 7, 3, 8, 4, 9],
                idleRpm: 2400,
                redlineRpm: 19000,
                maxRpm: 20000,
                harmonicCount: 26,
                exhaustScavengingFactor: 1.1,
                intakeHarmonicFactor: 0.9,
                intakeEfficiency: 1.1,
                exhaustEfficiency: 1.15,
                frictionFactor: 0.06
            )
        )
    ]
}
