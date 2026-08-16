//
//  ToolsView.swift
//  car_ui
//
//  「その他」タブ: 課金・車両・表示・データ・言語・サポート・プライバシーの設定。
//  技術情報と通信ログは AdapterDetailView(1 階層下)へ。
//

import SwiftUI

struct ToolsView: View {
    @EnvironmentObject private var obd: ELM327BluetoothModel
    @EnvironmentObject private var recorder: TelemetryRecorder
    @Environment(ProStore.self) private var proStore
    // 2026-07-16 リリース品質監査(REL-001〜004)により診断系を無効化。再有効化には RELEASE_QUALITY_AUDIT.md の合格条件を満たすこと
    // @State private var manualCommand = "010C"
    @State private var showingPaywall = false

    /// 監査 D-1: ScrollView + 自作パネルの縦積みをやめ、iOS 標準の Form / Section に戻す。
    /// 課金・車両・表示・データ・サポートが同じ視覚階層に並んでいて、
    /// どれが設定でどれが情報なのか区別できなかった。
    var body: some View {
        NavigationStack {
            Form {
                proSection
                vehicleSection
                displaySection
                dataSection
                languageSection
                supportSection
                privacySection
            }
            .navigationTitle("その他")
            // 監査 F-3: タブバーとバナーの下に最後のセクションが潜り込まないようにする
            .contentMargins(.bottom, DS.Space.tabBarClearance, for: .scrollContent)
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
            }
        }
    }

    // MARK: - Pro

    @ViewBuilder
    private var proSection: some View {
        Section {
            if proStore.isPro {
                HStack {
                    Label("car_ui Pro", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(DS.Role.ok)
                    Spacer()
                    Text("有効")
                        .foregroundStyle(.secondary)
                }
            } else {
                Button {
                    showingPaywall = true
                } label: {
                    HStack {
                        Label("car_ui Pro にアップグレード", systemImage: "star.fill")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }

                Button("購入を復元") {
                    Task { await proStore.restore() }
                }
                .disabled(proStore.isPurchasing)
            }
        } footer: {
            if !proStore.isPro {
                Text(proStore.isAdFree
                     ? "広告除去は購入済み。Pro で CSV 無制限・記録保存も使えます"
                     : "広告除去・CSV 無制限・記録保存")
            }
        }
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

    // MARK: - サポート(接続情報・通信ログ)

    /// 監査 D-2: 生の通信ログを一般ユーザーの設定画面に常設していたのをやめ、
    /// アダプタの技術情報とまとめて 1 階層下へ退避する。
    @ViewBuilder
    private var supportSection: some View {
        Section {
            Button {
                NotificationCenter.default.post(name: .carUIShowOnboarding, object: nil)
            } label: {
                Label("はじめかたをもう一度見る", systemImage: "sparkles.rectangle.stack")
            }

            NavigationLink {
                AdapterDetailView()
            } label: {
                Label("接続とアダプタの情報", systemImage: "cpu")
            }
        } header: {
            Text("ヘルプとサポート")
        } footer: {
            Text("うまく動かないときは「接続とアダプタの情報」の内容をお問い合わせに添えてください。")
        }
    }

    // 監査 REL-012: スリープ防止のユーザー制御
    @AppStorage("display.keepAwakeWhileConnected") private var keepAwakeWhileConnected = true
    /// 起動時に復元する保存データの範囲(分)。0 = 読み込まない / -1 = すべて
    @AppStorage("data.restoreWindowMinutes") private var restoreWindowMinutes = 30
    // 旧 `app.languageOverride`(AppleLanguages 直書き)は監査 D-4 で廃止。
    // 残存データは car_uiApp.migrateLegacyLanguageOverride() が一度だけ消す。

    // MARK: - 車両(監査 A-3・B-5)

    @ViewBuilder
    private var vehicleSection: some View {
        @Bindable var vehicle = VehicleProfile.shared

        Section {
            Picker(selection: $vehicle.maxRpm) {
                ForEach(VehicleProfile.selectableMaxRpm, id: \.self) { rpm in
                    Text(verbatim: "\(Int(rpm)) rpm").tag(rpm)
                }
            } label: {
                Label("タコメーター上限", systemImage: "gauge.with.needle")
            }
            .onChange(of: vehicle.maxRpm) { _, _ in vehicle.clampRedline() }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Label("レッドライン", systemImage: "exclamationmark.triangle")
                    Spacer()
                    Text(verbatim: "\(Int(vehicle.redlineRpm)) rpm")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(value: $vehicle.redlineRpm, in: 2000...vehicle.maxRpm, step: 100)
                    .accessibilityLabel("レッドライン")
                    .accessibilityValue(Text(verbatim: "\(Int(vehicle.redlineRpm)) rpm"))
            }

            Picker(selection: $vehicle.fuelType) {
                ForEach(FuelType.allCases) { fuel in
                    Text(fuel.label).tag(fuel)
                }
            } label: {
                Label("燃料", systemImage: "fuelpump")
            }
        } header: {
            Text("車両")
        } footer: {
            Text("メーターの目盛りと、燃料流量 (0x5E) 非対応車での燃費推定に使います。")
        }
    }

    // MARK: - 表示(監査 A-1)

    @ViewBuilder
    private var displaySection: some View {
        @Bindable var units = UnitSettings.shared

        Section {
            Picker(selection: $units.preference) {
                ForEach(UnitSystemPreference.allCases) { option in
                    Text(option.label).tag(option)
                }
            } label: {
                Label("単位系", systemImage: "ruler")
            }

            Toggle(isOn: $keepAwakeWhileConnected) {
                Label("接続中は画面をスリープさせない", systemImage: "sun.max")
            }
        } header: {
            Text("表示")
        } footer: {
            Text("速度・温度・圧力・燃費の表示単位です。CSV 書き出しもこの単位に従います(単位は列見出しに入ります)。")
        }
    }

    // MARK: - データ

    @ViewBuilder
    private var dataSection: some View {
        Section {
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

            Picker(selection: $restoreWindowMinutes) {
                Text("読み込まない").tag(0)
                Text("直近30分").tag(30)
                Text("直近2時間").tag(120)
                Text("すべて").tag(-1)
            } label: {
                Label("起動時に読み込む保存データ", systemImage: "internaldrive")
            }
        } header: {
            Text("データ")
        } footer: {
            Text("デモモードは擬似データで全機能を試せます。保存データの復元範囲は少ないほど起動後の動作が軽くなります(次回起動から反映)。")
        }
    }

    // MARK: - 言語(監査 D-4)

    /// 以前は `AppleLanguages` を直接書き換えるピッカーを自前で持っていたが、
    /// 選んでも何も起きず「再起動後に反映」と告げるだけの行き止まりだった。
    /// iOS 標準の App 別言語設定へ誘導する(即時に切り替わり、システムと二重にならない)。
    @ViewBuilder
    private var languageSection: some View {
        Section {
            Button {
                openAppSettings()
            } label: {
                HStack {
                    Label("アプリの言語を変更", systemImage: "globe")
                    Spacer()
                    Image(systemName: "arrow.up.forward.app")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        } footer: {
            Text("iOS の設定アプリが開きます。「言語」から日本語・English・简体中文・Español・Deutsch・Français を選べます。")
        }
    }

    // MARK: - プライバシー

    /// 監査 REL-007: UMP プライバシーオプション(広告同意の再設定)入口。
    /// 同意フォームが必須の地域でのみ表示される。
    @ViewBuilder
    private var privacySection: some View {
        if AdConsentManager.shared.isPrivacyOptionsRequired {
            Section {
                Button {
                    Task { await AdConsentManager.shared.presentPrivacyOptions() }
                } label: {
                    Label("広告プライバシー設定を変更", systemImage: "hand.raised")
                }
            } header: {
                Text("プライバシー")
            } footer: {
                Text("広告表示に関する同意内容をいつでも変更できます。")
            }
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - 接続とアダプタの情報(監査 D-2・D-3)

/// 技術的な情報と生の通信ログをまとめた 1 階層下の画面。
/// 以前は設定タブの本体に生ログが常設され、設定と同じ視覚階層に並んでいた。
private struct AdapterDetailView: View {
    @EnvironmentObject private var obd: ELM327BluetoothModel
    @EnvironmentObject private var recorder: TelemetryRecorder

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    StatusPill(phase: obd.phase)
                } label: {
                    Text("状態")
                }

                if obd.phase.isConnected {
                    Button {
                        if obd.isPolling { obd.stopPolling() } else { obd.startPolling() }
                    } label: {
                        Label(obd.isPolling ? "データ取得を一時停止" : "データ取得を再開",
                              systemImage: obd.isPolling ? "pause.fill" : "play.fill")
                    }
                    .disabled(obd.isDemo)
                }
            } header: {
                Text("接続")
            }

            Section {
                // 監査 D-3: "Adapter" / "Protocol" / "Mode 01" と英語のままだったので
                // 日本語ラベルにし、"Mode 01" は意味の分かる言い方に置き換えた
                LabeledContent(String(localized: "アダプタ"), value: obd.adapterInfo)
                LabeledContent(String(localized: "通信プロトコル"), value: obd.protocolDescription)
                LabeledContent(String(localized: "対応している項目"), value: supportedPIDText)
                LabeledContent(String(localized: "記録済みのデータ"),
                               value: String(localized: "\(recorder.totalSampleCount) 点 / \(recorder.channelIDs.count) ch"))
            } header: {
                Text("アダプタ")
            }

            Section {
                if obd.logLines.isEmpty {
                    Text("ログはまだありません")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(obd.logLines.suffix(40).reversed(), id: \.self) { line in
                        Text(line)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            } header: {
                Text("通信ログ")
            } footer: {
                Text("新しいものが上に並びます。長押しでコピーできます。")
            }
        }
        .navigationTitle("接続とアダプタの情報")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var supportedPIDText: String {
        obd.supportedMode01PIDCount > 0
            ? String(localized: "\(obd.supportedMode01PIDCount) 件対応")
            : String(localized: "未取得")
    }
}
