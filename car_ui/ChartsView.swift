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
    @State private var showingPaywall = false
    @State private var showingChannelPicker = false
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
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
            }
            .onAppear(perform: selectDefaultChannels)
            // 起動直後にこのタブを開くと記録がまだ空でデフォルト選択が効かないため、
            // チャンネルが現れたタイミングでも選択し直す
            .onChange(of: recorder.channelIDs.count) { _, _ in
                selectDefaultChannels()
            }
            .sheet(isPresented: $showingChannelPicker) {
                ChannelPickerView(channelIDs: recorder.channelIDs, selected: $selectedChannels)
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
                Button {
                    showingChannelPicker = true
                } label: {
                    Label("\(selectedChannels.count) 件を選択", systemImage: "slider.horizontal.3")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            // 選択中チャンネルを色チップで一覧(タップでピッカーを開く)
            if selectedChannels.isEmpty {
                Text("チャンネルが選択されていません")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                FlowLayout(items: selectedChannels.sorted()) { channelID in
                    let info = ChannelInfo.info(for: channelID)
                    HStack(spacing: 5) {
                        Circle().fill(info.tint).frame(width: 7, height: 7)
                        Text(info.name)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(info.tint.opacity(0.14), in: Capsule())
                    .foregroundStyle(info.tint)
                }
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
                // レビュー 7-8: 生の点数ではなく記録時間を表示(ユーザーに意味のある情報)
                Text(recordingDurationText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            // レビュー 7-7: 期間切替をチャート上部へ固定(下までスクロール不要)
            Picker("表示範囲", selection: $windowMinutes) {
                ForEach(windowOptions, id: \.self) { minutes in
                    Text(minutes >= 60 ? "\(minutes / 60)時間" : "\(minutes)分").tag(minutes)
                }
            }
            .pickerStyle(.segmented)

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

                                // レビュー 7-3: 現在値に「現在」+ 時刻ラベルを添える
                                if let last = series.points.last {
                                    VStack(alignment: .trailing, spacing: 0) {
                                        Text("現在 \(metricText(last.value, digits: 1))")
                                            .font(.caption.monospacedDigit().weight(.semibold))
                                            .foregroundStyle(series.tint)
                                        Text(last.time, format: .dateTime.hour().minute().second())
                                            .font(.caption2.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }

                            Chart(series.points) { point in
                                LineMark(
                                    x: .value("時刻", point.time),
                                    y: .value(series.name, point.value)
                                )
                                .foregroundStyle(series.tint)
                                .lineStyle(series.strokeStyle)
                                .interpolationMethod(.monotone)
                            }
                            .chartXAxis { sharedXAxis }
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
                            // レビュー 7-1: GPS 速度は破線にして OBD 速度と線種でも区別
                            .lineStyle(series.strokeStyle)
                            .interpolationMethod(.monotone)
                        }
                    }
                }
                .chartForegroundStyleScale(
                    domain: chartSeries.map(\.name),
                    range: chartSeries.map(\.tint)
                )
                .chartXAxis { sharedXAxis }
                .chartLegend(position: .bottom, alignment: .leading)
                .frame(height: 260)
            }
        }
        .panelStyle()
        // revision 更新で再描画
        .onChange(of: recorder.revision) { _, _ in }
    }

    /// レビュー 7-4: X軸ラベルの右端切れを防ぐ(本数を絞り時刻のみ・内側寄せ)
    private var sharedXAxis: some AxisContent {
        AxisMarks(preset: .aligned, values: .automatic(desiredCount: 4)) { value in
            AxisGridLine()
            AxisValueLabel(format: .dateTime.hour().minute(), anchor: .top)
        }
    }

    /// レビュー 7-8: 記録時間(生の点数ではなく意味のある情報)
    private var recordingDurationText: String {
        guard let start = recorder.startDate else { return "" }
        let secs = Int(Date().timeIntervalSince(start))
        let m = secs / 60, s = secs % 60
        return m > 0 ? String(localized: "記録 \(m)分\(s)秒") : String(localized: "記録 \(s)秒")
    }

    private var controlPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            // レビュー 7-6: 専門語「正規化」を平易な表現へ
            Toggle(isOn: $normalized) {
                VStack(alignment: .leading, spacing: 2) {
                    Label("変化を比較", systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(.subheadline)
                    Text("各データを 0〜100% に換算して重ねます")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
                if exportWillTruncate {
                    // 制限に実際に達している瞬間が最も購入意欲が高い(文脈導線)
                    Button {
                        showingPaywall = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text("記録が\(TelemetryRecorder.freeExportRowLimit)件を超えています。エクスポートは切り詰められます — Pro で無制限に")
                                .multilineTextAlignment(.leading)
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("無料版は直近\(TelemetryRecorder.freeExportRowLimit)件(行)までエクスポート。Pro で無制限。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .panelStyle()
    }

    private var exportChannels: [String] {
        selectedChannels.isEmpty ? recorder.channelIDs : Array(selectedChannels).sorted()
    }

    /// 無料版の切り詰めが実際に発生する記録量か
    private var exportWillTruncate: Bool {
        exportChannels.contains { recorder.samples($0).count > TelemetryRecorder.freeExportRowLimit }
    }

    private struct ChartSeries: Identifiable {
        let id: String
        let name: String
        let tint: Color
        let points: [TelemetrySample]
        /// GPS 系は破線にして OBD 系と線種でも区別する(レビュー 7-1)
        let dashed: Bool

        var strokeStyle: StrokeStyle {
            dashed ? StrokeStyle(lineWidth: 2, dash: [5, 3]) : StrokeStyle(lineWidth: 2)
        }
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
            return ChartSeries(id: channelID, name: displayName, tint: info.tint, points: points, dashed: channelID.hasPrefix("gps."))
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
