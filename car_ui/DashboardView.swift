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
    /// 監査 B-3: タイルの鮮度判定に使う
    @EnvironmentObject private var recorder: TelemetryRecorder
    @State private var showsConnectionSheet = false
    @State private var showsCustomizeSheet = false
    @State private var showsHUD = false
    // 自分用ダッシュボードのウィジェット構成(種類+PID、永続化)
    @State private var layout = DashboardLayoutStore()

    private let tileColumns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    // 監査 E-2: 主要な数字が固定 pt で Dynamic Type に追従していなかった。
    // 巨大表示の意図は保ちつつ、文字サイズ設定に合わせて拡縮させる。
    //
    // ただし上限は必要。速度はもともとこの画面で最大の文字で、AX5 まで素直に
    // 拡大するとパネルからあふれて字が欠ける(2026-08-17 実測)。これ以上大きく
    // しても可読性は上がらないので頭打ちにする。
    @ScaledMetric(relativeTo: .largeTitle) private var scaledHeroValueSize: CGFloat = 64
    @ScaledMetric(relativeTo: .title) private var scaledDialValueSize: CGFloat = 30
    @ScaledMetric(relativeTo: .title) private var scaledDialDiameter: CGFloat = 108

    private var heroValueSize: CGFloat { min(scaledHeroValueSize, 96) }
    private var dialValueSize: CGFloat { min(scaledDialValueSize, 44) }
    private var dialDiameter: CGFloat { min(scaledDialDiameter, 150) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if obd.phase.isConnected {
                        // 監査 C-4: 接続状態は上部セッションバーとツールバーのボタンが
                        // 既に示している。ここは重複しない情報(取得状況)だけに絞る。
                        statusDetailLine
                        heroPanel
                        widgetSections
                    } else {
                        // 未接続時は emptyState が状態と次の一手を説明するので見出しは出さない
                        emptyState
                    }
                }
                .padding()
                // 監査 F-3: 他タブにはあった下端の逃げがここだけ無く、
                // 最後のタイルがタブバーとバナーの下に潜り込んでいた
                .padding(.bottom, DS.Space.tabBarClearance)
            }
            .background(Color(.systemGroupedBackground))
            // 監査 C-1: タブ名と画面タイトルを一致させる(旧: タブ「メーター」→タイトル「ダッシュボード」)
            .navigationTitle("メーター")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showsCustomizeSheet = true
                    } label: {
                        // 監査 C-5: シート側のタイトルと語を揃える(旧: ボタン「タイルを編集」→シート「ダッシュボード編集」)
                        Label("表示項目を編集", systemImage: "slider.horizontal.3")
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
            // オンボーディングの「アダプタに接続する」から呼ばれる
            .onReceive(NotificationCenter.default.publisher(for: .carUIOpenConnectionSheet)) { _ in
                openConnection()
            }
            .fullScreenCover(isPresented: $showsHUD) {
                HUDView()
            }
            .sheet(isPresented: $showsCustomizeSheet) {
                DashboardBuilderView(store: layout)
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

    /// 接続中の取得状況だけを 1 行で出す(監査 C-4)。
    /// 以前はここにパネル + 状態名 + StatusPill が乗っていて、ツールバーの接続ボタンと
    /// 合わせて同じ情報が 3 重になり、画面最上部の一等地を状態表示が占有していた。
    private var statusDetailLine: some View {
        Text(statusDetail)
            .font(.caption)
            .foregroundStyle(.secondary)
            // 大きい文字サイズでは 1 行に収まらず末尾が切れるので折り返しを許す
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusDetail: String {
        guard obd.phase.isConnected else {
            return String(localized: "右上のボタンからアダプタに接続、またはデモモード")
        }

        var parts: [String] = []
        if obd.supportedMode01PIDCount > 0 {
            parts.append(String(localized: "対応 PID \(obd.supportedMode01PIDCount) 件"))
        }
        parts.append(String(localized: "受信 \(obd.liveValues.count) 項目"))
        if let lastUpdated = obd.lastUpdated {
            let time = lastUpdated.formatted(date: .omitted, time: .standard)
            parts.append(String(localized: "更新 \(time)"))
        }
        return parts.joined(separator: " ・ ")
    }

    private var heroPanel: some View {
        VStack(spacing: 14) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(LocalizedStringKey(speedSourceLabel))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            // 独語の長い語(Geschwindigkeit)が 1 文字ずつ縦に折り返して
                            // 速度の数字を画面外へ押し出していた(2026-08-17 実測)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)

                        Button {
                            showsHUD = true
                        } label: {
                            Label("HUD", systemImage: "windshield.front.and.heat.waves")
                                .font(.caption2.weight(.bold))
                                // 付けないと大きい文字サイズで H/U/D が縦に割れる
                                .lineLimit(1)
                                .fixedSize()
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.green.opacity(0.12), in: Capsule())
                                .foregroundStyle(.green)
                        }
                        .buttonStyle(.plain)
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(unitText(currentSpeed, kind: .speed, digits: 0))
                            .font(.system(size: heroValueSize, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)

                        Text(UnitKind.speed.symbol(UnitSettings.shared.system))
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                rpmDial
            }

            if let rpm = obd.liveValues[0x0C] {
                // 監査 B-5: 上限・レッドラインは車両プロファイル由来(旧: 8000/6000 固定)
                let vehicle = VehicleProfile.shared
                Gauge(value: min(max(rpm, 0), vehicle.maxRpm), in: 0...vehicle.maxRpm) {
                    EmptyView()
                }
                .gaugeStyle(.linearCapacity)
                .tint(vehicle.isOverRedline(rpm) ? .red : .orange)
            }
        }
        .panelStyle()
        // 監査 E-2: ここは計器(グラフィック)なので拡大幅に上限を設ける。
        // 数値は既に大きく、AX5 まで素直に伸ばすとラベルが縦に折り返して
        // 肝心の速度が画面外へ出てしまう。
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    private var rpmDial: some View {
        // 監査 B-5: 上限・レッドラインは車両プロファイル由来(旧: 8000/6000 固定)
        let vehicle = VehicleProfile.shared
        let rpm = obd.liveValues[0x0C]

        return VStack(spacing: 2) {
            Text(metricText(rpm, digits: 0))
                .font(.system(size: dialValueSize, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text("rpm")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(width: dialDiameter, height: dialDiameter)
        .background {
            Circle()
                .stroke(Color(.systemFill), lineWidth: 10)
            Circle()
                .trim(from: 0, to: vehicle.progress(rpm ?? 0))
                .stroke(
                    vehicle.isOverRedline(rpm ?? 0) ? Color.red : Color.orange,
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        // 監査 E-1: 自作ダイヤルは Circle + Text の重ね合わせで読み上げられなかった
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("エンジン回転数")
        .accessibilityValue(rpm == nil ? Text("未取得") : Text("\(metricText(rpm, digits: 0)) rpm"))
    }

    private var currentSpeed: Double? {
        obd.liveValues[0x0D] ?? location.speedKPH
    }

    private var speedSourceLabel: String {
        obd.liveValues[0x0D] != nil ? "車速 (OBD)" : "車速 (GPS)"
    }

    // MARK: - ウィジェット描画(タイル/メーターはグリッド、チャート/マップは全幅)

    private enum WidgetBlock: Identifiable {
        case grid([DashboardWidget])
        case full(DashboardWidget)

        var id: UUID {
            switch self {
            case .grid(let widgets): return widgets[0].id
            case .full(let widget): return widget.id
            }
        }
    }

    private var widgetBlocks: [WidgetBlock] {
        var blocks: [WidgetBlock] = []
        var gridRun: [DashboardWidget] = []

        for widget in layout.widgets {
            switch widget.kind {
            case .tile, .gauge:
                gridRun.append(widget)
            case .chart, .map:
                if !gridRun.isEmpty {
                    blocks.append(.grid(gridRun))
                    gridRun = []
                }
                blocks.append(.full(widget))
            }
        }
        if !gridRun.isEmpty {
            blocks.append(.grid(gridRun))
        }
        return blocks
    }

    private var widgetSections: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(widgetBlocks) { block in
                switch block {
                case .grid(let widgets):
                    LazyVGrid(columns: tileColumns, spacing: 12) {
                        ForEach(widgets) { widget in
                            gridCell(widget)
                        }
                    }
                case .full(let widget):
                    switch widget.kind {
                    case .chart:
                        if let pid = widget.pid {
                            ChartWidgetView(pid: pid)
                        }
                    case .map:
                        MapWidgetView()
                    default:
                        EmptyView()
                    }
                }
            }

            if let voltage = obd.adapterVoltage {
                LazyVGrid(columns: tileColumns, spacing: 12) {
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

            if layout.widgets.isEmpty {
                Text("表示項目がありません。左上の編集ボタンから追加できます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            }
        }
    }

    @ViewBuilder
    private func gridCell(_ widget: DashboardWidget) -> some View {
        if let pid = widget.pid, let definition = PIDCatalog.byPID[pid] {
            switch widget.kind {
            case .gauge:
                GaugeWidgetView(pid: pid)
            default:
                let value = obd.liveValues[pid]
                // 監査 B-3: 凍った値を生きた値と同じ見た目にしない
                let _ = recorder.revision  // 鮮度の再評価トリガ
                let isStale = value != nil && recorder.isStale(definition.channelID)
                MetricTile(
                    title: definition.name,
                    value: definition.displayText(value),
                    unit: definition.displayUnit,
                    systemImage: definition.icon,
                    tint: definition.tint,
                    progress: value.map { progress($0, in: definition.gaugeRange) },
                    isStale: isStale
                )
            }
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
