import Foundation
import SwiftUI

/// Analog speedometer, styled to pair with RPMGaugeView (same face, same
/// 7-o'clock → 5-o'clock sweep). The dial range adapts to the preset's
/// mechanical top speed so every engine "fills" its own dial.
struct SpeedometerView: View {
    let currentSpeed: Double  // km/h
    let topSpeed: Double      // km/h at maxRpm in top gear
    var size: CGFloat = 200

    private let startAngle = 120.0
    private let endAngle = 420.0

    var body: some View {
        ZStack {
            dialFace
            tickMarks
            numberLabels
            needle
            hub
            centerLabel
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("車速")
        .accessibilityValue("\(Int(currentSpeed)) km/h")
    }

    private var dialFace: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.18, green: 0.19, blue: 0.21),
                            Color(red: 0.035, green: 0.037, blue: 0.043)
                        ],
                        center: .center,
                        startRadius: size * 0.08,
                        endRadius: size * 0.55
                    )
                )

            Circle()
                .stroke(Color.white.opacity(0.16), lineWidth: 2)
                .padding(size * 0.025)

            Circle()
                .stroke(Color.black.opacity(0.75), lineWidth: size * 0.055)
                .padding(size * 0.008)
        }
    }

    private var tickMarks: some View {
        ZStack {
            ForEach(0...minorTickCount, id: \.self) { index in
                let isMajor = index.isMultiple(of: 2)
                Rectangle()
                    .fill(isMajor ? Color.white.opacity(0.88) : Color.white.opacity(0.42))
                    .frame(width: isMajor ? 2.2 : 1.2, height: isMajor ? size * 0.086 : size * 0.048)
                    .offset(y: -(size * 0.405))
                    .rotationEffect(.degrees(startAngle + Double(index) * minorTickStep + 90))
            }
        }
    }

    private var numberLabels: some View {
        ZStack {
            ForEach(Array(stride(from: 0, through: dialMax, by: labelEvery)), id: \.self) { value in
                Text("\(value)")
                    .font(.system(size: size * 0.06, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white.opacity(0.86))
                    .position(labelPosition(for: Double(value)))
            }
        }
    }

    private var needle: some View {
        ZStack {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.red, Color(red: 1.0, green: 0.72, blue: 0.52)],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .frame(width: size * 0.018, height: size * 0.36)
                .offset(y: -(size * 0.18))
                .rotationEffect(.degrees(needleAngle + 90))
                .animation(.linear(duration: 0.05), value: currentSpeed)

            Rectangle()
                .fill(Color.white.opacity(0.35))
                .frame(width: size * 0.008, height: size * 0.18)
                .offset(y: size * 0.09)
                .rotationEffect(.degrees(needleAngle + 90))
                .animation(.linear(duration: 0.05), value: currentSpeed)
        }
    }

    private var hub: some View {
        ZStack {
            Circle()
                .fill(Color.black)
                .frame(width: size * 0.18, height: size * 0.18)
            Circle()
                .stroke(Color.white.opacity(0.28), lineWidth: 1)
                .frame(width: size * 0.18, height: size * 0.18)
            Circle()
                .fill(Color.white.opacity(0.12))
                .frame(width: size * 0.07, height: size * 0.07)
        }
    }

    private var centerLabel: some View {
        VStack(spacing: 1) {
            Text("SPEED")
                .font(.system(size: size * 0.055, weight: .bold))
                .tracking(1.1)
            Text("km/h")
                .font(.system(size: size * 0.045, weight: .medium))
        }
        .foregroundColor(.white.opacity(0.62))
        .offset(y: size * 0.2)
    }

    /// Dial ceiling: the mechanical top speed rounded up to the next 20 km/h,
    /// like a 180 km/h dial on a car that tops out around 175.
    private var dialMax: Int {
        max(60, Int(ceil(topSpeed / 20.0)) * 20)
    }

    private var labelEvery: Int {
        dialMax > 220 ? 40 : 20
    }

    private var minorTickCount: Int {
        dialMax / 10
    }

    private var minorTickStep: Double {
        (endAngle - startAngle) / Double(minorTickCount)
    }

    private var needleAngle: Double {
        angle(for: currentSpeed)
    }

    private func angle(for speed: Double) -> Double {
        let clamped = min(max(0, speed), Double(dialMax))
        let fraction = dialMax > 0 ? clamped / Double(dialMax) : 0
        return startAngle + (endAngle - startAngle) * fraction
    }

    private func labelPosition(for speed: Double) -> CGPoint {
        let radians = CGFloat(angle(for: speed) * .pi / 180)
        let radius = size * 0.305
        return CGPoint(
            x: size / 2 + cos(radians) * radius,
            y: size / 2 + sin(radians) * radius
        )
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        SpeedometerView(currentSpeed: 96, topSpeed: 178)
    }
}
