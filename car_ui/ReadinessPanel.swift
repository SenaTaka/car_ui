//
//  ReadinessPanel.swift
//  car_ui
//
//  レディネスモニタ(Mode 01 PID 01)の表示パネル。ToolsView に配置。
//

import SwiftUI

// 2026-07-16 リリース品質監査(REL-001〜004)により診断系を無効化。再有効化には RELEASE_QUALITY_AUDIT.md の合格条件を満たすこと
/*
struct ReadinessPanel: View {
    @EnvironmentObject private var obd: ELM327BluetoothModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("レディネスモニタ", systemImage: "checkmark.shield")
                    .font(.headline)

                Spacer()

                Button {
                    obd.readReadinessStatus()
                } label: {
                    Label("更新", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!obd.phase.isConnected || obd.isReadingReadiness)

                if obd.isReadingReadiness {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let readiness = obd.readiness {
                milRow(readiness)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 150), spacing: 8)],
                    alignment: .leading,
                    spacing: 8
                ) {
                    ForEach(readiness.monitors) { monitor in
                        monitorRow(monitor)
                    }
                }
            } else {
                Text(obd.phase.isConnected
                     ? "「更新」でモニタ状態を取得します"
                     : "接続するとエンジン警告灯と各モニタの完了状態を確認できます")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text("車検・排ガス検査前のチェックに。全モニタ Ready なら検査準備完了です。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .panelStyle()
    }

    private func milRow(_ readiness: ReadinessStatus) -> some View {
        HStack(spacing: 10) {
            Image(systemName: readiness.milOn ? "engine.combustion.badge.exclamationmark.fill" : "checkmark.circle.fill")
                .foregroundStyle(readiness.milOn ? .red : .green)

            Text(readiness.milOn
                 ? "エンジン警告灯 点灯中(DTC \(readiness.dtcCount) 件)"
                 : "エンジン警告灯 消灯(DTC \(readiness.dtcCount) 件)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(readiness.milOn ? .red : .primary)

            Spacer()

            if readiness.isCompressionIgnition {
                Text("ディーゼル")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.blue.opacity(0.12), in: Capsule())
                    .foregroundStyle(.blue)
            }
        }
    }

    private func monitorRow(_ monitor: ReadinessStatus.Monitor) -> some View {
        HStack(spacing: 6) {
            Image(systemName: statusIcon(monitor))
                .foregroundStyle(statusColor(monitor))
                .font(.caption)

            Text(monitor.name)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 0)

            Text(statusText(monitor))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(statusColor(monitor))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(statusColor(monitor).opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private func statusText(_ monitor: ReadinessStatus.Monitor) -> String {
        guard monitor.supported else { return "非対応" }
        return monitor.ready ? "Ready" : "Not Ready"
    }

    private func statusIcon(_ monitor: ReadinessStatus.Monitor) -> String {
        guard monitor.supported else { return "minus.circle" }
        return monitor.ready ? "checkmark.circle.fill" : "xmark.circle.fill"
    }

    private func statusColor(_ monitor: ReadinessStatus.Monitor) -> Color {
        guard monitor.supported else { return .secondary }
        return monitor.ready ? .green : .orange
    }
}
*/
