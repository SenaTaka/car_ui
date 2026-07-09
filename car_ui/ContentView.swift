//
//  ContentView.swift
//  car_ui
//
//  Created by Sena Takasawa on 2026/2/20.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var obd = ELM327BluetoothModel()
    @State private var manualCommand = "010C"

    private let metricColumns = [
        GridItem(.adaptive(minimum: 150), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    connectionPanel
                    vehicleMetrics
                    diagnosticsPanel
                    commandPanel
                    logPanel
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("OBD2 Monitor")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if obd.phase.isConnected {
                        Button {
                            obd.disconnect()
                        } label: {
                            Label("切断", systemImage: "xmark.circle")
                        }
                    } else {
                        Button {
                            obd.startScan()
                        } label: {
                            Label("検索", systemImage: "antenna.radiowaves.left.and.right")
                        }
                        .disabled(!obd.canScan)
                    }
                }
            }
        }
    }

    private var connectionPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
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

            Text("iPhone では BLE 型 ELM327 アダプタを使用します。Bluetooth Classic SPP 型は iOS の公開 API では接続できません。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button {
                    obd.startScan()
                } label: {
                    Label("検索", systemImage: "magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!obd.canScan || obd.phase.isConnected)

                Button {
                    obd.stopScan()
                } label: {
                    Label("停止", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)

                Spacer()

                if obd.phase.isConnected {
                    Button {
                        if obd.isPolling {
                            obd.stopPolling()
                        } else {
                            obd.startPolling()
                        }
                    } label: {
                        Label(obd.isPolling ? "一時停止" : "再開", systemImage: obd.isPolling ? "pause.fill" : "play.fill")
                    }
                    .buttonStyle(.bordered)
                }
            }

            if !obd.discoveredPeripherals.isEmpty {
                VStack(spacing: 8) {
                    ForEach(obd.discoveredPeripherals) { device in
                        DeviceRow(device: device) {
                            obd.connect(to: device)
                        }
                        .disabled(!obd.canConnect)
                    }
                }
            } else if case .scanning = obd.phase {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("周辺の BLE デバイスを検索中")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }

            Divider()

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 130), spacing: 12)],
                alignment: .leading,
                spacing: 12
            ) {
                InfoItem(title: "Adapter", value: obd.adapterInfo, systemImage: "cpu")
                InfoItem(title: "Protocol", value: obd.protocolDescription, systemImage: "point.3.connected.trianglepath.dotted")
                InfoItem(title: "Mode 01", value: supportedPIDText, systemImage: "checklist")
            }
        }
        .panelStyle()
    }

    private var vehicleMetrics: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Live Data", systemImage: "gauge.with.dots.needle.67percent")
                    .font(.headline)

                Spacer()

                Text(lastUpdatedText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: metricColumns, spacing: 12) {
                MetricTile(
                    title: "RPM",
                    value: intText(obd.telemetry.rpm),
                    unit: "rpm",
                    systemImage: "tachometer",
                    tint: .orange
                )

                MetricTile(
                    title: "Speed",
                    value: intText(obd.telemetry.speedKPH),
                    unit: "km/h",
                    systemImage: "speedometer",
                    tint: .blue
                )

                MetricTile(
                    title: "Coolant",
                    value: intText(obd.telemetry.coolantTempC),
                    unit: "C",
                    systemImage: "thermometer.medium",
                    tint: .red
                )

                MetricTile(
                    title: "Throttle",
                    value: decimalText(obd.telemetry.throttlePercent),
                    unit: "%",
                    systemImage: "pedal.accelerator",
                    tint: .green
                )

                MetricTile(
                    title: "Load",
                    value: decimalText(obd.telemetry.engineLoadPercent),
                    unit: "%",
                    systemImage: "engine.combustion",
                    tint: .purple
                )

                MetricTile(
                    title: "Intake",
                    value: intText(obd.telemetry.intakeTempC),
                    unit: "C",
                    systemImage: "wind",
                    tint: .teal
                )

                MetricTile(
                    title: "MAF",
                    value: decimalText(obd.telemetry.mafGramsPerSecond),
                    unit: "g/s",
                    systemImage: "waveform.path.ecg",
                    tint: .indigo
                )

                MetricTile(
                    title: "Voltage",
                    value: decimalText(obd.telemetry.moduleVoltage, fractionDigits: 2),
                    unit: "V",
                    systemImage: "bolt.fill",
                    tint: .yellow
                )
            }
        }
        .panelStyle()
    }

    private var diagnosticsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Diagnostics", systemImage: "stethoscope")
                    .font(.headline)

                Spacer()

                Text(obd.diagnosticStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button {
                    obd.readDiagnosticTroubleCodes()
                } label: {
                    Label("DTC 読取", systemImage: "list.bullet.rectangle")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!obd.phase.isConnected || obd.isReadingDiagnostics)

                if obd.isReadingDiagnostics {
                    ProgressView()
                }
            }

            if obd.diagnosticCodes.isEmpty {
                Text("表示する故障コードはありません")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                FlowLayout(items: obd.diagnosticCodes) { code in
                    Text(code)
                        .font(.system(.body, design: .monospaced).weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                        .foregroundStyle(.red)
                }
            }
        }
        .panelStyle()
    }

    private var commandPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Command", systemImage: "chevron.left.forwardslash.chevron.right")
                .font(.headline)

            HStack(spacing: 10) {
                TextField("ATZ / 010C", text: $manualCommand)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.roundedBorder)

                Button {
                    obd.sendManualCommand(manualCommand)
                } label: {
                    Label("送信", systemImage: "paperplane.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!obd.phase.isConnected || obd.isSendingManualCommand)
            }

            HStack(alignment: .top, spacing: 8) {
                if obd.isSendingManualCommand {
                    ProgressView()
                        .controlSize(.small)
                }

                Text(obd.manualCommandResponse)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .panelStyle()
    }

    private var logPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Log", systemImage: "terminal")
                .font(.headline)

            if obd.logLines.isEmpty {
                Text("ログはまだありません")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(obd.logLines.suffix(10), id: \.self) { line in
                        Text(line)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .panelStyle()
    }

    private var lastUpdatedText: String {
        guard let lastUpdated = obd.telemetry.lastUpdated else {
            return "未更新"
        }

        return lastUpdated.formatted(date: .omitted, time: .standard)
    }

    private func intText(_ value: Int?) -> String {
        value.map(String.init) ?? "--"
    }

    private func decimalText(_ value: Double?, fractionDigits: Int = 1) -> String {
        guard let value else { return "--" }
        return value.formatted(.number.precision(.fractionLength(fractionDigits)))
    }

    private var supportedPIDText: String {
        obd.supportedMode01PIDCount > 0 ? "\(obd.supportedMode01PIDCount) 件対応" : "未取得"
    }
}

private struct StatusPill: View {
    let phase: OBDConnectionPhase

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
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

private struct DeviceRow: View {
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
            .padding(10)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
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

private struct InfoItem: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
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

private struct MetricTile: View {
    let title: String
    let value: String
    let unit: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)

                Text(unit)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(tint.opacity(0.16))
                .frame(width: 44, height: 44)
                .offset(x: 14, y: -14)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct FlowLayout<Data: RandomAccessCollection, Content: View>: View where Data.Element: Hashable {
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

private extension View {
    func panelStyle() -> some View {
        self
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(.separator).opacity(0.25), lineWidth: 1)
            )
    }
}

#Preview {
    ContentView()
}
