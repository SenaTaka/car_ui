//
//  SensorsView.swift
//  car_ui
//
//  OBD / GPS / 加速度計の全チャンネルを一覧表示。各行にスパークライン付き。
//

import SwiftUI
import UIKit

struct SensorsView: View {
    @EnvironmentObject private var obd: ELM327BluetoothModel
    @EnvironmentObject private var location: LocationModel
    @EnvironmentObject private var motion: MotionModel
    @EnvironmentObject private var recorder: TelemetryRecorder

    var body: some View {
        NavigationStack {
            List {
                // レビュー 13章: 各種状態を明示するバナー
                bannerSection

                Section {
                    HStack {
                        Label("表示中のチャンネル", systemImage: "square.grid.3x3")
                            .font(.subheadline)
                        Spacer()
                        Text("\(channelCount) ch")
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(.blue)
                    }
                }

                Section("OBD-II") {
                    if sortedOBDPIDs.isEmpty {
                        Text(obd.phase.isConnected ? "データ受信待ち" : "未接続(接続すると対応 PID が自動で並びます)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(sortedOBDPIDs, id: \.self) { pid in
                            if let definition = PIDCatalog.byPID[pid] {
                                sensorRow(
                                    channelID: definition.channelID,
                                    name: definition.name,
                                    icon: definition.icon,
                                    tint: definition.tint,
                                    value: obd.liveValues[pid],
                                    unit: definition.unit,
                                    digits: definition.fractionDigits
                                )
                            }
                        }

                        if let voltage = obd.adapterVoltage {
                            sensorRow(
                                channelID: "meta.voltage",
                                name: "アダプタ電圧",
                                icon: "bolt.fill",
                                tint: .yellow,
                                value: voltage,
                                unit: "V",
                                digits: 2
                            )
                        }
                    }
                }

                Section {
                    Toggle(isOn: gpsBinding) {
                        Label("GPS を使用", systemImage: "location")
                    }

                    if location.isDenied {
                        Text("位置情報が拒否されています。設定アプリから許可してください。")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    if location.isActive {
                        sensorRow(channelID: "gps.speed", name: "車速 (GPS)", icon: "location.fill", tint: .blue, value: location.speedKPH, unit: "km/h", digits: 1)
                        sensorRow(channelID: "gps.altitude", name: "高度", icon: "mountain.2", tint: .brown, value: location.altitudeM, unit: "m", digits: 1)
                        sensorRow(channelID: "gps.course", name: "方位", icon: "safari", tint: .cyan, value: location.courseDegrees, unit: "°", digits: 0)
                        sensorRow(channelID: "gps.distance", name: "走行距離", icon: "road.lanes", tint: .green, value: location.totalDistanceKm, unit: "km", digits: 2)

                        HStack {
                            Label("水平精度", systemImage: "scope")
                                .font(.subheadline)
                            Spacer()
                            Text(location.horizontalAccuracyM.map { "±\(metricText($0, digits: 0)) m" } ?? "--")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("GPS")
                }

                Section {
                    Toggle(isOn: motionBinding) {
                        Label("加速度計を使用", systemImage: "gyroscope")
                    }

                    if !motion.isAvailable {
                        Text("この端末ではモーションセンサーを利用できません。")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    if motion.isActive {
                        sensorRow(channelID: "motion.gx", name: "横 G", icon: "arrow.left.and.right", tint: .pink, value: motion.lateralG, unit: "G", digits: 2)
                        sensorRow(channelID: "motion.gy", name: "前後 G", icon: "arrow.up.and.down", tint: .orange, value: motion.longitudinalG, unit: "G", digits: 2)
                        sensorRow(channelID: "motion.gmag", name: "合成 G", icon: "circle.dotted.circle", tint: .purple, value: motion.magnitudeG, unit: "G", digits: 2)
                    }
                } header: {
                    Text("加速度計")
                }
            }
            .navigationTitle("センサー")
        }
    }

    private var sortedOBDPIDs: [UInt8] {
        obd.liveValues.keys.sorted()
    }

    private var channelCount: Int {
        var count = sortedOBDPIDs.count
        if obd.adapterVoltage != nil { count += 1 }
        if location.isActive { count += 4 }
        if motion.isActive { count += 3 }
        return count
    }

    private var gpsBinding: Binding<Bool> {
        Binding(
            get: { location.isActive },
            set: { $0 ? location.start() : location.stop() }
        )
    }

    private var motionBinding: Binding<Bool> {
        Binding(
            get: { motion.isActive },
            set: { $0 ? motion.start() : motion.stop() }
        )
    }

    private struct BannerConfig {
        let level: StatusBanner.Level
        let title: LocalizedStringKey
        let message: LocalizedStringKey?
        var showSettings = false
    }

    @ViewBuilder
    private var bannerSection: some View {
        if let banner = bannerConfig {
            let settingsTitle: LocalizedStringKey? = banner.showSettings ? "設定" : nil
            let settingsAction: (() -> Void)? = banner.showSettings ? { openSettings() } : nil
            Section {
                StatusBanner(level: banner.level, title: banner.title,
                             message: banner.message,
                             actionTitle: settingsTitle,
                             action: settingsAction)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
        }
    }

    /// 現在の状態に応じたバナー(未接続 / BT無効 / 位置情報拒否 / GPS低精度)。
    private var bannerConfig: BannerConfig? {
        if case .unavailable(let message) = obd.phase {
            return BannerConfig(level: .error, title: "アダプタに接続できません",
                                message: LocalizedStringKey(message), showSettings: true)
        } else if location.isDenied {
            return BannerConfig(level: .warning, title: "位置情報が使用できません",
                                message: "GPS 速度・走行マップには位置情報が必要です。", showSettings: true)
        } else if location.isActive, location.quality == .low {
            return BannerConfig(level: .warning, title: "GPS 精度が低下しています",
                                message: "走行マップや加速計測の精度が下がる場合があります。")
        } else if !obd.phase.isConnected, !obd.isDemo {
            return BannerConfig(level: .info, title: "未接続",
                                message: "アダプタに接続するか、デモモードで試せます。")
        }
        return nil
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    private func sensorRow(
        channelID: String,
        name: String,
        icon: String,
        tint: Color,
        value: Double?,
        unit: String,
        digits: Int
    ) -> some View {
        // レビュー P0#10・13章: 未取得 / 古い値 / 現行値 を区別する
        let hasValue = value != nil
        let isStale = hasValue && recorder.isStale(channelID)
        _ = recorder.revision  // 鮮度の再評価トリガ

        return HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(isStale ? AnyShapeStyle(.secondary) : AnyShapeStyle(tint))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(LocalizedStringKey(name))
                    .font(.subheadline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if isStale {
                    Text("更新なし")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }

            Spacer(minLength: 8)

            // recorder.revision の更新でスパークラインが再描画される
            Sparkline(
                samples: recorder.samples(channelID, since: Date().addingTimeInterval(-120)),
                tint: isStale ? .secondary : tint
            )
            .frame(width: 64, height: 22)
            .id(recorder.revision)

            MetricValue(
                value: value,
                unit: unit,
                digits: digits,
                valueFont: .subheadline,
                color: hasValue ? (isStale ? Color.secondary : Color.primary) : Color(.tertiaryLabel)
            )
            .frame(minWidth: 72, alignment: .trailing)
        }
    }
}
