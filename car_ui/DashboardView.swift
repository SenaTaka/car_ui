//
//  DashboardView.swift
//  car_ui
//
//  接続状態+主要メトリクスのゲージ表示。対応 PID は自動でタイルに追加される。
//

import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var obd: ELM327BluetoothModel
    @EnvironmentObject private var location: LocationModel
    @State private var showsConnectionSheet = false
    @State private var showsCustomizeSheet = false
    @State private var showsHUD = false
    // ダッシュボードに優先表示する PID(対応していれば自動で並ぶ)。空 = 既定の並び。
    @AppStorage("dashboardPIDs.v1") private var storedFeaturedPIDs = ""

    private let tileColumns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    private var featuredPIDs: [UInt8] {
        DashboardConfig.decode(storedFeaturedPIDs)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    statusHeader

                    if obd.phase.isConnected {
                        heroPanel
                        metricGrid
                    } else {
                        emptyState
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("ダッシュボード")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showsCustomizeSheet = true
                    } label: {
                        Label("タイルを編集", systemImage: "slider.horizontal.3")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        openConnection()
                    } label: {
                        Label(obd.phase.isConnected ? "接続済み" : "接続",
                              systemImage: obd.phase.isConnected ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                            .font(.callout.weight(.bold))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(obd.phase.isConnected ? .green : .blue)
                }
            }
            .sheet(isPresented: $showsConnectionSheet) {
                ConnectionSheet()
            }
            .fullScreenCover(isPresented: $showsHUD) {
                HUDView()
            }
            .sheet(isPresented: $showsCustomizeSheet) {
                DashboardCustomizeView(
                    selectedPIDs: Binding(
                        get: { DashboardConfig.decode(storedFeaturedPIDs) },
                        set: { storedFeaturedPIDs = DashboardConfig.encode($0) }
                    )
                )
            }
        }
    }

    /// 接続ボタンを押したら接続シートを開き、未接続なら即スキャンを開始する。
    private func openConnection() {
        if !obd.phase.isConnected, obd.canScan {
            if case .scanning = obd.phase {} else {
                obd.startScan()
            }
        }
        showsConnectionSheet = true
    }

    private var statusHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(obd.phase.title)
                    .font(.subheadline.weight(.semibold))
                Text(statusDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            StatusPill(phase: obd.phase)
        }
        .panelStyle()
    }

    private var statusDetail: String {
        guard obd.phase.isConnected else {
            return "右上のボタンからアダプタに接続、またはデモモード"
        }

        var parts: [String] = []
        if obd.supportedMode01PIDCount > 0 {
            parts.append("対応 PID \(obd.supportedMode01PIDCount) 件")
        }
        parts.append("受信 \(obd.liveValues.count) 項目")
        if let lastUpdated = obd.lastUpdated {
            parts.append("更新 \(lastUpdated.formatted(date: .omitted, time: .standard))")
        }
        return parts.joined(separator: " ・ ")
    }

    private var heroPanel: some View {
        VStack(spacing: 14) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(speedSourceLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Button {
                            showsHUD = true
                        } label: {
                            Label("HUD", systemImage: "windshield.front.and.heat.waves")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.green.opacity(0.12), in: Capsule())
                                .foregroundStyle(.green)
                        }
                        .buttonStyle(.plain)
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(metricText(currentSpeed, digits: 0))
                            .font(.system(size: 64, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)

                        Text("km/h")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                rpmDial
            }

            if let rpm = obd.liveValues[0x0C] {
                Gauge(value: min(max(rpm, 0), 8000), in: 0...8000) {
                    EmptyView()
                }
                .gaugeStyle(.linearCapacity)
                .tint(rpm > 6000 ? .red : .orange)
            }
        }
        .panelStyle()
    }

    private var rpmDial: some View {
        VStack(spacing: 2) {
            Text(metricText(obd.liveValues[0x0C], digits: 0))
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text("rpm")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(width: 108, height: 108)
        .background {
            Circle()
                .stroke(Color(.systemFill), lineWidth: 10)
            Circle()
                .trim(from: 0, to: min(max((obd.liveValues[0x0C] ?? 0) / 8000, 0), 1))
                .stroke(
                    (obd.liveValues[0x0C] ?? 0) > 6000 ? Color.red : Color.orange,
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
    }

    private var currentSpeed: Double? {
        obd.liveValues[0x0D] ?? location.speedKPH
    }

    private var speedSourceLabel: String {
        obd.liveValues[0x0D] != nil ? "車速 (OBD)" : "車速 (GPS)"
    }

    private var metricGrid: some View {
        LazyVGrid(columns: tileColumns, spacing: 12) {
            ForEach(featuredDefinitions) { definition in
                let value = obd.liveValues[definition.pid]
                MetricTile(
                    title: definition.name,
                    value: metricText(value, digits: definition.fractionDigits),
                    unit: definition.unit,
                    systemImage: definition.icon,
                    tint: definition.tint,
                    progress: value.map { progress($0, in: definition.gaugeRange) }
                )
            }

            if let voltage = obd.adapterVoltage {
                MetricTile(
                    title: "アダプタ電圧",
                    value: metricText(voltage, digits: 2),
                    unit: "V",
                    systemImage: "bolt.fill",
                    tint: .yellow,
                    progress: progress(voltage, in: 8...16)
                )
            }
        }
    }

    private var featuredDefinitions: [PIDDefinition] {
        featuredPIDs.compactMap { pid in
            guard obd.liveValues[pid] != nil else { return nil }
            return PIDCatalog.byPID[pid]
        }
    }

    private func progress(_ value: Double, in range: ClosedRange<Double>) -> Double {
        (value - range.lowerBound) / (range.upperBound - range.lowerBound)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "car.front.waves.up")
                .font(.system(size: 52))
                .foregroundStyle(.blue)

            Text("車両に接続してライブデータを表示")
                .font(.headline)

            Text("ECU が対応する全 PID を自動検出し、設定なしですべて表示・記録します。アダプタがなくてもデモモードで全機能を試せます。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                Button {
                    openConnection()
                } label: {
                    Label("接続してデバイスを検索", systemImage: "antenna.radiowaves.left.and.right")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    obd.startDemoMode()
                } label: {
                    Label("デモモード", systemImage: "play.rectangle")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 2)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .panelStyle()
    }
}
