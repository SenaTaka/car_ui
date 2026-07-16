//
//  DashboardWidgetViews.swift
//  car_ui
//
//  ダッシュボードに置けるウィジェットの描画: チャート / 走行マップ。
//  (デジタルタイル = MetricTile、アナログ = AnalogGaugeView を流用)
//

import Charts
import MapKit
import SwiftUI

/// PID 1 チャンネルのミニ時系列チャート(直近 5 分)。
struct ChartWidgetView: View {
    let pid: UInt8
    @EnvironmentObject private var obd: ELM327BluetoothModel
    @EnvironmentObject private var recorder: TelemetryRecorder

    var body: some View {
        let definition = PIDCatalog.byPID[pid]
        let samples = definition.map { recorder.samples($0.channelID, since: Date().addingTimeInterval(-300)) } ?? []

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: definition?.icon ?? "chart.xyaxis.line")
                    .font(.caption)
                    .foregroundStyle(definition?.tint ?? .gray)

                Text(definition?.name ?? String(format: "PID %02X", pid))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                if let definition, let value = obd.liveValues[pid] {
                    Text("\(metricText(value, digits: definition.fractionDigits)) \(definition.unit)")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(definition.tint)
                }
            }

            if samples.count >= 2 {
                Chart(samples) { sample in
                    LineMark(
                        x: .value("時刻", sample.time),
                        y: .value(definition?.name ?? "", sample.value)
                    )
                    .foregroundStyle(definition?.tint ?? .blue)
                    .interpolationMethod(.monotone)
                }
                .chartXAxis(.hidden)
                .frame(height: 110)
            } else {
                Text("データ待ち…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 110)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
        // recorder の revision 更新で再描画
        .onChange(of: recorder.revision) { _, _ in }
    }
}

/// 走行軌跡ミニマップ(タップで拡大表示)。色分け・地図スタイルは走行マップと設定共有。
struct MapWidgetView: View {
    @ObservedObject private var track = TrackStore.shared
    @AppStorage("trackMap.colorSource") private var colorSourceRaw = TrackColorSource.speed.rawValue
    @AppStorage("trackMap.style") private var mapStyleRaw = TrackMapStyleOption.standard.rawValue
    @State private var showingExpanded = false

    private var colorSource: TrackColorSource {
        TrackColorSource(rawValue: colorSourceRaw) ?? .speed
    }

    private var styleOption: TrackMapStyleOption {
        TrackMapStyleOption(rawValue: mapStyleRaw) ?? .standard
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("走行マップ", systemImage: "map")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if track.points.count < 2 {
                VStack(spacing: 6) {
                    Image(systemName: "location.magnifyingglass")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text("走行すると軌跡が描かれます")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                Map(initialPosition: .automatic, interactionModes: []) {
                    TrackMapContent(points: track.points, colorSource: colorSource)
                }
                .mapStyle(styleOption.mapStyle)
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .id(track.points.count / 10)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onTapGesture { showingExpanded = true }
        .fullScreenCover(isPresented: $showingExpanded) {
            TrackMapExpandedView()
        }
    }
}

/// アナログメーターのグリッドセル(タイトル・レンジは PIDCatalog から解決)。
struct GaugeWidgetView: View {
    let pid: UInt8
    @EnvironmentObject private var obd: ELM327BluetoothModel

    var body: some View {
        Group {
            if let definition = PIDCatalog.byPID[pid] {
                AnalogGaugeView(
                    title: definition.name,
                    value: obd.liveValues[pid],
                    range: definition.gaugeRange,
                    unit: definition.unit,
                    tint: definition.tint,
                    fractionDigits: definition.fractionDigits
                )
                .padding(8)
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
    }
}
