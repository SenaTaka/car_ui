//
//  FreezeFramePanel.swift
//  car_ui
//
//  フリーズフレーム(Mode 02)の表示パネル。ToolsView に配置。
//

import SwiftUI

// 2026-07-16 リリース品質監査(REL-001〜004)により診断系を無効化。再有効化には RELEASE_QUALITY_AUDIT.md の合格条件を満たすこと
/*
struct FreezeFramePanel: View {
    @EnvironmentObject private var obd: ELM327BluetoothModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("フリーズフレーム", systemImage: "camera.viewfinder")
                    .font(.headline)

                Spacer()

                Text(obd.freezeFrameStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button {
                    obd.readFreezeFrame()
                } label: {
                    Label("取得", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!obd.phase.isConnected || obd.isReadingFreezeFrame)

                if obd.isReadingFreezeFrame {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let frame = obd.freezeFrame {
                if let dtc = frame.triggeringDTC {
                    HStack(spacing: 8) {
                        Text(dtc)
                            .font(.system(.body, design: .monospaced).weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                            .foregroundStyle(.red)

                        Text("発生時の車両状態")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 130), spacing: 12)],
                    alignment: .leading,
                    spacing: 12
                ) {
                    ForEach(frame.entries) { entry in
                        if let definition = PIDCatalog.byPID[entry.pid] {
                            InfoItem(
                                title: definition.name,
                                value: "\(metricText(entry.value, digits: definition.fractionDigits)) \(definition.unit)",
                                systemImage: definition.icon
                            )
                        }
                    }
                }
            } else {
                Text("故障コード確定時に ECU が保存した車両状態(RPM・車速・水温など)を読み取ります。保存がない車両や非対応の車両では取得できません。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .panelStyle()
    }
}
*/
