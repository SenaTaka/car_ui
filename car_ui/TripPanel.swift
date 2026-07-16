//
//  TripPanel.swift
//  car_ui
//
//  トリップコンピュータの表示パネル。DriveView に配置。
//

import SwiftUI

struct TripPanel: View {
    @EnvironmentObject private var trip: TripComputerModel
    @State private var showingResetConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("トリップ", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    .font(.headline)

                Spacer()

                Button("リセット") {
                    showingResetConfirmation = true
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!trip.hasData)
            }

            instantFuelRow

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 12)], spacing: 12) {
                InfoItem(
                    title: "走行距離",
                    value: "\(metricText(trip.distanceKM, digits: 2)) km",
                    systemImage: "road.lanes"
                )
                InfoItem(
                    title: "走行時間",
                    value: elapsedText,
                    systemImage: "clock"
                )
                InfoItem(
                    title: "平均速度",
                    value: trip.averageSpeedKPH.map { "\(metricText($0, digits: 1)) km/h" } ?? "--",
                    systemImage: "gauge.with.needle"
                )
                InfoItem(
                    title: "平均燃費",
                    value: trip.averageKPL.map { "\(metricText($0, digits: 1)) km/L" } ?? "--",
                    systemImage: "leaf"
                )
                InfoItem(
                    title: "消費燃料",
                    value: "\(metricText(trip.fuelUsedLiters, digits: 2)) L",
                    systemImage: "fuelpump"
                )
            }

            if trip.isFuelEstimated {
                Text("* 燃費は吸入空気量(MAF)からの推定値です")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .panelStyle()
        .alert("トリップをリセットしますか?", isPresented: $showingResetConfirmation) {
            Button("リセット", role: .destructive) {
                trip.reset()
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("距離・時間・燃費の積算をゼロに戻します。")
        }
    }

    private var instantFuelRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let kpl = trip.instantKPL {
                Text(metricText(kpl, digits: 1))
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                Text("km/L")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            } else if let lph = trip.instantLPH {
                Text(metricText(lph, digits: 1))
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                Text("L/h(停車中)")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            } else {
                Text("--")
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                Text("km/L")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("瞬間燃費")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var elapsedText: String {
        let total = Int(trip.elapsedSeconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}
