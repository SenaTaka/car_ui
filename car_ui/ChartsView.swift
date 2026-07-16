//
//  ChartsView.swift
//  car_ui
//
//  任意のチャンネルを複数選択して時系列を重ね描き。正規化表示と CSV 書き出しに対応。
//

import Charts
import SwiftUI

struct ChartsView: View {
    @EnvironmentObject private var recorder: TelemetryRecorder
    @Environment(ProStore.self) private var proStore

    @State private var selectedChannels: Set<String> = []
    @State private var windowMinutes = 5
    @State private var normalized = false
    @State private var exportWideFormat = true
    @AppStorage("charts.separate") private var separateCharts = false

    private let windowOptions = [1, 5, 15, 60]

    /// エクスポート用チャンネルプリセット(存在するチャンネルだけ選択される)
    private let exportPresets: [(name: String, channels: [String])] = [
        ("ドライブ", ["gps.lat", "gps.lon", "obd.0D", "gps.speed", "obd.0C", "motion.gx", "motion.gy", "motion.gmag"]),
        ("エンジン", ["obd.0C", "obd.04", "obd.11", "obd.05", "obd.0B", "obd.10", "obd.0E"]),
        ("燃費", ["obd.0D", "obd.0C", "obd.10", "obd.5E", "obd.2F", "gps.distance"])
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if recorder.channelIDs.isEmpty {
                        emptyState
                    } else {
                        channelPicker
                        chartPanel
                        controlPanel
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("チャート")
            .onAppear(perform: selectDefaultChannels)
            // 起動直後にこのタブを開くと記録がまだ空でデフォルト選択が効かないため、
            // チャンネルが現れたタイミングでも選択し直す
            .onChange(of: recorder.channelIDs.count) { _, _ in
                selectDefaultChannels()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 44))
                .foregroundStyle(.blue)

            Text("記録されたデータがまだありません")
                .font(.headline)

            Text("接続またはデモモードを開始すると、全チャンネルの時系列が自動で記録されます。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .panelStyle()
    }

    private var channelPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("チャンネル選択", systemImage: "checklist")
                    .font(.headline)
                Spacer()
                Text("\(selectedChannels.count) / \(recorder.channelIDs.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            FlowLayout(items: recorder.channelIDs) { channelID in
                let info = ChannelInfo.info(for: channelID)
                let isSelected = selectedChannels.contains(channelID)

                Button {
                    if isSelected {
                        selectedChannels.remove(channelID)
                    } else {
                        selectedChannels.insert(channelID)
                    }
                } label: {
                    Text(info.name)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            isSelected ? info.tint.opacity(0.18) : Color(.systemFill).opacity(0.5),
                            in: Capsule()
                        )
                        .foregroundStyle(isSelected ? info.tint : .secondary)
                        .overlay(
                            Capsule().stroke(isSelected ? info.tint : .clear, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .panelStyle()
    }

    private var chartPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("時系列", systemImage: "chart.xyaxis.line")
                    .font(.headline)
                Spacer()
                Text("記録 \(recorder.totalSampleCount) 点")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Picker("表示", selection: $separateCharts) {
                Text("重ね表示").tag(false)
                Text("個別表示").tag(true)
            }
            .pickerStyle(.segmented)

            if chartSeries.allSatisfy({ $0.points.isEmpty }) {
                Text("選択したチャンネルの直近データがありません")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else if separateCharts {
                // チャンネルごとに独立した小チャートを縦に並べる(単位が違っても見やすい)
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(chartSeries.filter { !$0.points.isEmpty }) { series in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(series.tint)
                                    .frame(width: 8, height: 8)
                                Text(series.name)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)

                                Spacer()

                                if let lastValue = series.points.last?.value {
                                    Text(metricText(lastValue, digits: 1))
                                        .font(.caption.monospacedDigit().weight(.semibold))
                                        .foregroundStyle(series.tint)
                                }
                            }

                            Chart(series.points) { point in
                                LineMark(
                                    x: .value("時刻", point.time),
                                    y: .value(series.name, point.value)
                                )
                                .foregroundStyle(series.tint)
                                .interpolationMethod(.monotone)
                            }
                            .frame(height: 110)
                        }
                    }
                }
            } else {
                Chart {
                    ForEach(chartSeries) { series in
                        ForEach(series.points) { point in
                            LineMark(
                                x: .value("時刻", point.time),
                                y: .value(series.name, point.value),
                                series: .value("チャンネル", series.name)
                            )
                            .foregroundStyle(by: .value("チャンネル", series.name))
                            .interpolationMethod(.monotone)
                        }
                    }
                }
                .chartForegroundStyleScale(
                    domain: chartSeries.map(\.name),
                    range: chartSeries.map(\.tint)
                )
                .chartLegend(position: .bottom, alignment: .leading)
                .frame(height: 260)
            }
        }
        .panelStyle()
        // revision 更新で再描画
        .onChange(of: recorder.revision) { _, _ in }
    }

    private var controlPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("表示範囲", selection: $windowMinutes) {
                ForEach(windowOptions, id: \.self) { minutes in
                    Text(minutes >= 60 ? "\(minutes / 60)時間" : "\(minutes)分").tag(minutes)
                }
            }
            .pickerStyle(.segmented)

            Toggle(isOn: $normalized) {
                Label("正規化(単位の異なる系列を 0-1 で重ねる)", systemImage: "arrow.up.left.and.arrow.down.right")
                    .font(.subheadline)
            }

            HStack(spacing: 8) {
                Text("プリセット")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(exportPresets, id: \.name) { preset in
                    Button(preset.name) {
                        selectedChannels = Set(preset.channels.filter { recorder.channelIDs.contains($0) })
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Spacer()
            }

            Picker("CSV 形式", selection: $exportWideFormat) {
                Text("横持ち(1行=1時刻)").tag(true)
                Text("縦持ち(1行=1サンプル)").tag(false)
            }
            .pickerStyle(.segmented)

            HStack {
                ShareLink(
                    item: TelemetryCSV(
                        channelIDs: exportChannels,
                        isPro: proStore.isPro,
                        format: exportWideFormat ? .wide : .long
                    ),
                    preview: SharePreview("テレメトリ CSV", image: Image(systemName: "tablecells"))
                ) {
                    Label("CSV 書き出し", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
                .disabled(exportChannels.isEmpty)

                Spacer()

                Button(role: .destructive) {
                    recorder.clear()
                    selectedChannels = []
                } label: {
                    Label("記録を消去", systemImage: "trash")
                }
                .buttonStyle(.bordered)
            }

            Text(exportWideFormat
                 ? "横持ち: 時刻ごとに選択チャンネルを列で並べます(表計算向け)。"
                 : "縦持ち: channel,name,unit,time,value の生ログ形式。")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !proStore.isPro {
                Text("無料版は直近\(TelemetryRecorder.freeExportRowLimit)件(行)までエクスポート。Pro で無制限。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .panelStyle()
    }

    private var exportChannels: [String] {
        selectedChannels.isEmpty ? recorder.channelIDs : Array(selectedChannels).sorted()
    }

    private struct ChartSeries: Identifiable {
        let id: String
        let name: String
        let tint: Color
        let points: [TelemetrySample]
    }

    private var chartSeries: [ChartSeries] {
        let since = Date().addingTimeInterval(-Double(windowMinutes) * 60)

        return selectedChannels.sorted().map { channelID in
            let info = ChannelInfo.info(for: channelID)
            var points = recorder.samples(channelID, since: since)

            if normalized, let minValue = points.map(\.value).min(), let maxValue = points.map(\.value).max() {
                let span = max(maxValue - minValue, 0.0001)
                points = points.map { TelemetrySample(time: $0.time, value: ($0.value - minValue) / span) }
            }

            let displayName = info.unit.isEmpty ? info.name : "\(info.name) [\(info.unit)]"
            return ChartSeries(id: channelID, name: displayName, tint: info.tint, points: points)
        }
    }

    private func selectDefaultChannels() {
        let preferred = Set(["obd.0C", "obd.0D", "gps.speed"].filter { recorder.channelIDs.contains($0) })
        guard !preferred.isEmpty else { return }

        if selectedChannels.isEmpty {
            selectedChannels = preferred
        } else if selectedChannels.isStrictSubset(of: preferred) {
            // GPS が先に現れて OBD が後から登録されるケース。ユーザーが手動選択する前
            // (= 既定候補の部分集合のまま)なら、後から現れた既定チャンネルも足す
            selectedChannels = preferred
        }
    }
}
