//
//  ToolsView.swift
//  car_ui
//
//  アダプタ情報・通信ログ。
//

import SwiftUI

struct ToolsView: View {
    @EnvironmentObject private var obd: ELM327BluetoothModel
    @EnvironmentObject private var recorder: TelemetryRecorder
    @Environment(ProStore.self) private var proStore
    // 2026-07-16 リリース品質監査(REL-001〜004)により診断系を無効化。再有効化には RELEASE_QUALITY_AUDIT.md の合格条件を満たすこと
    // @State private var manualCommand = "010C"
    @State private var showingPaywall = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    proPanel
                    adapterPanel
                    // 2026-07-16 リリース品質監査(REL-001〜004)により診断系を無効化。再有効化には RELEASE_QUALITY_AUDIT.md の合格条件を満たすこと
                    // diagnosticsPanel
                    // ReadinessPanel()
                    // FreezeFramePanel()
                    // commandPanel
                    logPanel
                    settingsPanel
                    privacyPanel
                }
                .padding()
                .padding(.bottom, 72)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("その他")
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
            }
        }
    }

    private var proPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("car_ui Pro", systemImage: proStore.isPro ? "checkmark.seal.fill" : "star.fill")
                    .font(.headline)
                    .foregroundStyle(proStore.isPro ? .green : .orange)

                Spacer()

                if proStore.isPro {
                    Text("Pro 有効")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                } else {
                    Button("Pro にアップグレード") {
                        showingPaywall = true
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }

            if !proStore.isPro {
                Text(proStore.isAdFree
                     ? "広告除去は購入済み。Pro で CSV 無制限・記録保存も使えます"
                     : "広告除去・CSV 無制限・記録保存")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("購入を復元") {
                    Task { await proStore.restore() }
                }
                .font(.caption.weight(.semibold))
                .disabled(proStore.isPurchasing)
            }
        }
        .panelStyle()
    }

    private var adapterPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("アダプタ", systemImage: "cpu")
                    .font(.headline)

                Spacer()

                StatusPill(phase: obd.phase)

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
                    .controlSize(.small)
                    .disabled(obd.isDemo)
                }
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 130), spacing: 12)],
                alignment: .leading,
                spacing: 12
            ) {
                InfoItem(title: "Adapter", value: obd.adapterInfo, systemImage: "cpu")
                InfoItem(title: "Protocol", value: obd.protocolDescription, systemImage: "point.3.connected.trianglepath.dotted")
                InfoItem(title: "Mode 01", value: supportedPIDText, systemImage: "checklist")
                // 「点」を直書きすると英語 UI に日本語が残る(2026-08-17 US 実機確認で発覚)
                InfoItem(title: "記録",
                         value: String(localized: "\(recorder.totalSampleCount) 点 / \(recorder.channelIDs.count) ch"),
                         systemImage: "internaldrive")
            }
        }
        .panelStyle()
    }

    // 2026-07-16 リリース品質監査(REL-001〜004)により診断系を無効化。再有効化には RELEASE_QUALITY_AUDIT.md の合格条件を満たすこと
    /*
    private var diagnosticsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("故障コード (DTC)", systemImage: "stethoscope")
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
                .disabled(!obd.phase.isConnected || obd.isReadingDiagnostics || obd.isDemo)

                Button(role: .destructive) {
                    if proStore.isPro {
                        obd.clearDiagnosticTroubleCodes()
                    } else {
                        showingPaywall = true
                    }
                } label: {
                    Label("DTC 消去", systemImage: proStore.isPro ? "trash" : "lock.fill")
                }
                .buttonStyle(.bordered)
                .disabled(!obd.phase.isConnected || obd.isReadingDiagnostics || obd.isDemo)

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
            Label("手動コマンド", systemImage: "chevron.left.forwardslash.chevron.right")
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
                .disabled(!obd.phase.isConnected || obd.isSendingManualCommand || obd.isDemo)
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
    */

    private var logPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("通信ログ", systemImage: "terminal")
                .font(.headline)

            if obd.logLines.isEmpty {
                Text("ログはまだありません")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(obd.logLines.suffix(12), id: \.self) { line in
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

    // 監査 REL-012: スリープ防止のユーザー制御
    @AppStorage("display.keepAwakeWhileConnected") private var keepAwakeWhileConnected = true
    /// 起動時に復元する保存データの範囲(分)。0 = 読み込まない / -1 = すべて
    @AppStorage("data.restoreWindowMinutes") private var restoreWindowMinutes = 30
    /// アプリ内の言語上書き("" = システムに従う)。AppleLanguages 経由で次回起動時に反映
    @AppStorage("app.languageOverride") private var languageOverride = ""

    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("設定", systemImage: "gearshape")
                .font(.headline)

            unitsRow

            Divider()

            vehicleRows

            Divider()

            Toggle("接続中は画面をスリープさせない", isOn: $keepAwakeWhileConnected)
                .font(.subheadline)

            Text("オンの場合、OBD 接続中(デモ含む)だけ画面を常時点灯します。未接続時は通常どおりスリープします。")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            // 2026-08-02 フィードバック: デモモードの入口を接続シートからここへ移動
            Button {
                if obd.isDemo {
                    obd.disconnect()
                } else {
                    obd.startDemoMode()
                }
            } label: {
                Label(obd.isDemo ? "デモモードを終了" : "デモモードを開始(アダプタ不要)",
                      systemImage: obd.isDemo ? "stop.rectangle" : "play.rectangle")
            }
            .font(.subheadline)

            Text("擬似データで全機能を試せます。")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            // ラベルが見えるよう HStack で明記(メニュー式ピッカーは選択値しか表示されない)
            HStack {
                Label("起動時に読み込む保存データ", systemImage: "internaldrive")
                    .font(.subheadline)
                Spacer()
                Picker("起動時に読み込む保存データ", selection: $restoreWindowMinutes) {
                    Text("読み込まない").tag(0)
                    Text("直近30分").tag(30)
                    Text("直近2時間").tag(120)
                    Text("すべて").tag(-1)
                }
                .labelsHidden()
            }

            Text("記録・軌跡の復元範囲。少ないほど起動後の動作が軽くなります(次回起動から反映)。")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            HStack {
                Label("言語設定", systemImage: "globe")
                    .font(.subheadline)
                Spacer()
                Picker("言語設定", selection: $languageOverride) {
                    Text(verbatim: "システムに従う / System").tag("")
                    Text(verbatim: "日本語").tag("ja")
                    Text(verbatim: "English").tag("en")
                    Text(verbatim: "简体中文").tag("zh-Hans")
                    Text(verbatim: "Español").tag("es")
                    Text(verbatim: "Deutsch").tag("de")
                    Text(verbatim: "Français").tag("fr")
                }
                .labelsHidden()
            }
            .onChange(of: languageOverride) { _, code in
                applyLanguageOverride(code)
            }

            Text("変更はアプリの再起動後に反映されます。")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Button {
                NotificationCenter.default.post(name: .carUIShowOnboarding, object: nil)
            } label: {
                Label("はじめかたをもう一度見る", systemImage: "sparkles.rectangle.stack")
            }
            .font(.subheadline)
        }
        .panelStyle()
    }

    /// 監査 A-1: 単位系(既定は端末の地域から自動判定)。
    @ViewBuilder
    private var unitsRow: some View {
        @Bindable var units = UnitSettings.shared

        HStack {
            Label("単位系", systemImage: "ruler")
                .font(.subheadline)
            Spacer()
            Picker("単位系", selection: $units.preference) {
                ForEach(UnitSystemPreference.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .labelsHidden()
        }

        Text("速度・温度・圧力・燃費の表示単位です。CSV 書き出しもこの単位に従います(単位は列見出しに入ります)。")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    /// 監査 A-3・B-5: 車両プロファイル(タコメーターの目盛りと燃費推定に使う)。
    @ViewBuilder
    private var vehicleRows: some View {
        @Bindable var vehicle = VehicleProfile.shared

        HStack {
            Label("タコメーター上限", systemImage: "gauge.with.needle")
                .font(.subheadline)
            Spacer()
            Picker("タコメーター上限", selection: $vehicle.maxRpm) {
                ForEach(VehicleProfile.selectableMaxRpm, id: \.self) { rpm in
                    Text(verbatim: "\(Int(rpm)) rpm").tag(rpm)
                }
            }
            .labelsHidden()
            .onChange(of: vehicle.maxRpm) { _, _ in vehicle.clampRedline() }
        }

        HStack {
            Label("レッドライン", systemImage: "exclamationmark.triangle")
                .font(.subheadline)
            Spacer()
            Text(verbatim: "\(Int(vehicle.redlineRpm)) rpm")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }

        Slider(value: $vehicle.redlineRpm, in: 2000...vehicle.maxRpm, step: 100)
            .accessibilityLabel("レッドライン")
            .accessibilityValue(Text(verbatim: "\(Int(vehicle.redlineRpm)) rpm"))

        HStack {
            Label("燃料", systemImage: "fuelpump")
                .font(.subheadline)
            Spacer()
            Picker("燃料", selection: $vehicle.fuelType) {
                ForEach(FuelType.allCases) { fuel in
                    Text(fuel.label).tag(fuel)
                }
            }
            .labelsHidden()
        }

        Text("メーターの目盛りと、燃料流量 (0x5E) 非対応車での燃費推定に使います。")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    /// AppleLanguages を上書きしてアプリ内言語を切り替える(反映は次回起動時)。
    /// 空文字はシステム設定に戻す。
    private func applyLanguageOverride(_ code: String) {
        if code.isEmpty {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([code], forKey: "AppleLanguages")
        }
    }

    /// 監査 REL-007: UMP プライバシーオプション(広告同意の再設定)入口。
    /// 同意フォームが必須の地域でのみ表示される。
    @ViewBuilder
    private var privacyPanel: some View {
        if AdConsentManager.shared.isPrivacyOptionsRequired {
            VStack(alignment: .leading, spacing: 10) {
                Label("プライバシー", systemImage: "hand.raised")
                    .font(.headline)

                Button("広告プライバシー設定を変更") {
                    Task {
                        await AdConsentManager.shared.presentPrivacyOptions()
                    }
                }

                Text("広告表示に関する同意内容をいつでも変更できます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .panelStyle()
        }
    }

    private var supportedPIDText: String {
        obd.supportedMode01PIDCount > 0
            ? String(localized: "\(obd.supportedMode01PIDCount) 件対応")
            : String(localized: "未取得")
    }
}
