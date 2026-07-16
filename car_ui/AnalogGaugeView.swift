//
//  AnalogGaugeView.swift
//  car_ui
//
//  任意の PID 値を表示する汎用アナログメーター(270° スイープ・針式)。
//  ダッシュボードのウィジェットとして使う。
//

import SwiftUI

struct AnalogGaugeView: View {
    let title: String
    let value: Double?
    let range: ClosedRange<Double>
    let unit: String
    let tint: Color
    let fractionDigits: Int

    // 7時位置(135°)から5時位置(405°)まで 270° スイープ(y-down 座標)
    private let startAngle = 135.0
    private let sweep = 270.0
    private let majorTickCount = 8

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            ZStack {
                track(size: size)
                progressArc(size: size)
                ticks(size: size)
                needle(size: size)
                hub(size: size)
                labels(size: size)
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func track(size: CGFloat) -> some View {
        AnalogGaugeArc(startAngle: startAngle, endAngle: startAngle + sweep)
            .stroke(Color(.systemFill), style: StrokeStyle(lineWidth: size * 0.06, lineCap: .round))
            .padding(size * 0.07)
    }

    private func progressArc(size: CGFloat) -> some View {
        AnalogGaugeArc(startAngle: startAngle, endAngle: needleAngle)
            .stroke(tint.opacity(0.85), style: StrokeStyle(lineWidth: size * 0.06, lineCap: .round))
            .padding(size * 0.07)
            .animation(.linear(duration: 0.15), value: value)
    }

    private func ticks(size: CGFloat) -> some View {
        ForEach(0...majorTickCount, id: \.self) { index in
            Rectangle()
                .fill(Color.secondary.opacity(0.55))
                .frame(width: 1.6, height: size * 0.05)
                .offset(y: -(size * 0.36))
                .rotationEffect(.degrees(startAngle + sweep * Double(index) / Double(majorTickCount) + 90))
        }
    }

    private func needle(size: CGFloat) -> some View {
        Rectangle()
            .fill(tint)
            .frame(width: size * 0.02, height: size * 0.30)
            .offset(y: -(size * 0.15))
            .rotationEffect(.degrees(needleAngle + 90))
            .animation(.linear(duration: 0.15), value: value)
    }

    private func hub(size: CGFloat) -> some View {
        Circle()
            .fill(tint.opacity(0.9))
            .frame(width: size * 0.07, height: size * 0.07)
    }

    private func labels(size: CGFloat) -> some View {
        VStack(spacing: 0) {
            Spacer()

            Text(metricText(value, digits: fractionDigits))
                .font(.system(size: size * 0.16, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(unit)
                .font(.system(size: size * 0.07, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.system(size: size * 0.075, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.top, size * 0.015)
                .padding(.bottom, size * 0.04)
        }
        .frame(width: size * 0.8)
    }

    private var needleAngle: Double {
        let clamped = min(max(value ?? range.lowerBound, range.lowerBound), range.upperBound)
        let fraction = (clamped - range.lowerBound) / (range.upperBound - range.lowerBound)
        return startAngle + sweep * fraction
    }
}

private struct AnalogGaugeArc: Shape {
    let startAngle: Double
    let endAngle: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY),
            radius: min(rect.width, rect.height) / 2,
            startAngle: .degrees(startAngle),
            endAngle: .degrees(endAngle),
            clockwise: false
        )
        return path
    }
}

#Preview {
    AnalogGaugeView(
        title: "冷却水温",
        value: 88,
        range: 40...130,
        unit: "°C",
        tint: .red,
        fractionDigits: 0
    )
    .frame(width: 180, height: 180)
}
