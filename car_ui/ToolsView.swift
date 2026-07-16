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
                    privacyPanel
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("ツール")
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
                InfoItem(title: "記録", value: "\(recorder.totalSampleCount) 点 / \(recorder.channelIDs.count) ch", systemImage: "internaldrive")
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
        obd.supportedMode01PIDCount > 0 ? "\(obd.supportedMode01PIDCount) 件対応" : "未取得"
    }
}
