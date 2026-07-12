import Foundation
import SwiftUI

/// Analog tachometer-style RPM gauge view.
struct RPMGaugeView: View {
    let currentRpm: Double
    let maxRpm: Double
    let redlineRpm: Double
    let idleRpm: Double
    var size: CGFloat = 200

    // Classic JDM cluster sweep: the needle rests at ~7 o'clock and swings
    // ~300° clockwise to ~5 o'clock (angles are y-down: 90° = 6 o'clock).
    private let startAngle = 120.0
    private let endAngle = 420.0

    var body: some View {
        ZStack {
            dialFace
            redlineBand
            tickMarks
            numberLabels
            needle
            hub
            centerLabel
        }
        .frame(width: size, height: size)
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

    private var redlineBand: some View {
        GaugeArc(startAngle: angle(for: redlineRpm), endAngle: endAngle)
            .stroke(Color.red.opacity(0.82), style: StrokeStyle(lineWidth: size * 0.055, lineCap: .butt))
            .padding(size * 0.055)
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
            // Thousands-only labels (the "x1000" center caption carries the
            // unit), stepping by 2 on very-high-rev dials so nothing collides.
            ForEach(Array(stride(from: labelStep, through: maxThousands, by: labelStep)), id: \.self) { value in
                Text("\(value)")
                    .font(.system(size: size * 0.066, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(Double(value * 1000) >= redlineRpm ? .red.opacity(0.9) : .white.opacity(0.86))
                    .position(labelPosition(for: Double(value) * 1000.0))
            }
        }
    }

    private var labelStep: Int {
        maxThousands > 12 ? 2 : 1
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
                .animation(.linear(duration: 0.05), value: currentRpm)

            Rectangle()
                .fill(Color.white.opacity(0.35))
                .frame(width: size * 0.008, height: size * 0.18)
                .offset(y: size * 0.09)
                .rotationEffect(.degrees(needleAngle + 90))
                .animation(.linear(duration: 0.05), value: currentRpm)
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
            Text("RPM")
                .font(.system(size: size * 0.055, weight: .bold))
                .tracking(1.1)
            Text("x1000")
                .font(.system(size: size * 0.045, weight: .medium))
        }
        .foregroundColor(.white.opacity(0.62))
        .offset(y: size * 0.2)
    }

    private var maxThousands: Int {
        // One extra thousand of dial beyond the mechanical limit, like a real
        // tach that reads past the redline.
        max(1, Int(ceil(maxRpm / 1000.0)) + 1)
    }

    private var dialMaxRpm: Double {
        Double(maxThousands) * 1000.0
    }

    private var minorTickCount: Int {
        maxThousands * 2
    }

    private var minorTickStep: Double {
        (endAngle - startAngle) / Double(minorTickCount)
    }

    private var needleAngle: Double {
        angle(for: currentRpm)
    }

    private func angle(for rpm: Double) -> Double {
        let clampedRpm = min(max(0, rpm), dialMaxRpm)
        let fraction = dialMaxRpm > 0 ? clampedRpm / dialMaxRpm : 0
        return startAngle + (endAngle - startAngle) * fraction
    }

    private func labelPosition(for rpm: Double) -> CGPoint {
        let radians = CGFloat(angle(for: rpm) * .pi / 180)
        let radius = size * 0.305
        return CGPoint(
            x: size / 2 + cos(radians) * radius,
            y: size / 2 + sin(radians) * radius
        )
    }
}

private struct GaugeArc: Shape {
    let startAngle: Double
    let endAngle: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = min(rect.width, rect.height) / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(startAngle),
            endAngle: .degrees(endAngle),
            clockwise: false
        )
        return path
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        RPMGaugeView(
            currentRpm: 4500,
            maxRpm: 7000,
            redlineRpm: 6500,
            idleRpm: 800
        )
    }
}
