//
//  Components.swift
//  car_ui
//
//  タブ間で共有する UI 部品。
//

import SwiftUI

// MARK: - 接続状態ピル

struct StatusPill: View {
    let phase: OBDConnectionPhase

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(LocalizedStringKey(label))
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.12), in: Capsule())
        .foregroundStyle(color)
    }

    private var label: String {
        switch phase {
        case .connected:
            return "接続"
        case .scanning:
            return "検索"
        case .connecting, .discovering, .initializing, .waitingForBluetooth:
            return "処理中"
        case .failed, .unavailable:
            return "注意"
        case .idle, .disconnected:
            return "待機"
        }
    }

    private var color: Color {
        switch phase {
        case .connected:
            return .green
        case .scanning, .connecting, .discovering, .initializing, .waitingForBluetooth:
            return .blue
        case .failed, .unavailable:
            return .red
        case .idle, .disconnected:
            return .secondary
        }
    }
}

// MARK: - 数値タイル(ミニゲージ付き)

struct MetricTile: View {
    let title: String
    let value: String
    let unit: String
    let systemImage: String
    let tint: Color
    var progress: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 0)
            }

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)

                Text(unit)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let progress {
                ProgressView(value: min(max(progress, 0), 1))
                    .progressViewStyle(.linear)
                    .tint(tint)
                    .scaleEffect(x: 1, y: 0.7, anchor: .center)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
        // レビュー 3-5: 意味を持たない装飾半透明円を削除(データUIのノイズ)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: DS.Radius.control))
    }
}

// MARK: - ラベル+値の小型表示

struct InfoItem: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                // LocalizedStringKey 化: 呼び出し側の日本語リテラルをカタログで解決する
                // (未登録の動的文字列はそのまま表示される)
                Text(LocalizedStringKey(title))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - デバイス行

struct DeviceRow: View {
    let device: OBDPeripheral
    let connect: () -> Void

    var body: some View {
        Button(action: connect) {
            HStack(spacing: 12) {
                Image(systemName: device.isLikelyAdapter ? "checkmark.seal.fill" : "dot.radiowaves.left.and.right")
                    .foregroundStyle(device.isLikelyAdapter ? .green : .secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 3) {
                    Text(device.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(serviceText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Text("\(device.rssi) dBm")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var serviceText: String {
        if device.isLikelyAdapter {
            return "ELM327 候補"
        }

        if device.serviceUUIDs.isEmpty {
            return "BLE デバイス"
        }

        return device.serviceUUIDs.prefix(2).joined(separator: ", ")
    }
}

// MARK: - スパークライン(直近の推移を小さく描画)

struct Sparkline: View {
    let samples: [TelemetrySample]
    let tint: Color

    var body: some View {
        Canvas { context, size in
            guard samples.count >= 2 else { return }

            let values = samples.map(\.value)
            guard let minValue = values.min(), let maxValue = values.max() else { return }
            let span = max(maxValue - minValue, 0.0001)

            let startTime = samples.first!.time.timeIntervalSinceReferenceDate
            let endTime = samples.last!.time.timeIntervalSinceReferenceDate
            let timeSpan = max(endTime - startTime, 0.0001)

            var path = Path()
            for (index, sample) in samples.enumerated() {
                let x = (sample.time.timeIntervalSinceReferenceDate - startTime) / timeSpan * size.width
                let y = size.height - (sample.value - minValue) / span * size.height
                if index == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }

            context.stroke(path, with: .color(tint), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - 故障コードなどのフローレイアウト

struct FlowLayout<Data: RandomAccessCollection, Content: View>: View where Data.Element: Hashable {
    let items: Data
    let content: (Data.Element) -> Content

    init(items: Data, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.items = items
        self.content = content
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(Array(items), id: \.self) { item in
                content(item)
            }
        }
    }
}

// MARK: - パネル装飾

extension View {
    func panelStyle() -> some View {
        self
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - 数値フォーマット

func metricText(_ value: Double?, digits: Int) -> String {
    guard let value else { return "--" }
    return String(format: "%.\(digits)f", value)
}

// MARK: - 接続シート(スキャン・接続・デモモード)

struct ConnectionSheet: View {
    @EnvironmentObject private var obd: ELM327BluetoothModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "car.front.waves.up")
                            .font(.title2)
                            .foregroundStyle(.blue)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("ELM327 BLE")
                                .font(.headline)
                            Text(obd.phase.title)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        StatusPill(phase: obd.phase)
                    }
                    .padding(.vertical, 2)

                    Text("iPhone では BLE 型 ELM327 アダプタを使用します。Bluetooth Classic SPP 型は iOS の公開 API では接続できません。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    if obd.phase.isConnected {
                        Button(role: .destructive) {
                            obd.disconnect()
                        } label: {
                            Label(obd.isDemo ? "デモモード終了" : "切断", systemImage: "xmark.circle")
                        }
                    } else {
                        Button {
                            obd.startScan()
                        } label: {
                            Label("アダプタを検索", systemImage: "magnifyingglass")
                        }
                        .disabled(!obd.canScan)

                        if case .scanning = obd.phase {
                            Button {
                                obd.stopScan()
                            } label: {
                                Label("検索を停止", systemImage: "stop.fill")
                            }
                        }

                        Button {
                            obd.startDemoMode()
                        } label: {
                            Label("デモモードで試す(アダプタ不要)", systemImage: "play.rectangle")
                        }
                    }
                }

                if !obd.discoveredPeripherals.isEmpty {
                    Section("検出したデバイス") {
                        ForEach(obd.discoveredPeripherals) { device in
                            DeviceRow(device: device) {
                                obd.connect(to: device)
                            }
                            .disabled(!obd.canConnect)
                        }
                    }
                } else if case .scanning = obd.phase {
                    Section {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("周辺の BLE デバイスを検索中")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("接続")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
            .onChange(of: obd.phase.isConnected) { _, isConnected in
                if isConnected { dismiss() }
            }
        }
    }
}
