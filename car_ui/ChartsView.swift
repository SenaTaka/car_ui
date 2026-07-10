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

    @State private var selectedChannels: Set<String> = []
    @State private var windowMinutes = 5
    @State private var normalized = false

    private let windowOptions = [1, 5, 15, 60]

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

            if chartSeries.allSatisfy({ $0.points.isEmpty }) {
                Text("選択したチャンネルの直近データがありません")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 200)
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

            HStack {
                ShareLink(
                    item: TelemetryCSV(channelIDs: exportChannels),
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
        guard selectedChannels.isEmpty else { return }
        let preferred = ["obd.0C", "obd.0D", "gps.speed"].filter { recorder.channelIDs.contains($0) }
        if !preferred.isEmpty {
            selectedChannels = Set(preferred)
        } else if let first = recorder.channelIDs.first {
            selectedChannels = [first]
        }
    }
}
