//
//  DashboardCustomizeView.swift
//  car_ui
//
//  ダッシュボードのタイル(PID)の表示選択・並べ替え。
//  永続化はカンマ区切り hex 文字列(@AppStorage "dashboardPIDs.v1")。
//

import SwiftUI

/// ダッシュボード表示 PID の永続化形式の変換と既定値。
enum DashboardConfig {
    /// 従来ハードコードされていた既定の表示順
    static let defaultPIDs: [UInt8] = [
        0x05, 0x11, 0x04, 0x0B, 0x10, 0x0F, 0x5C, 0x2F, 0x0E, 0x5E, 0x46, 0x62
    ]

    /// "05,11,04" 形式をデコード。未設定(空文字)なら既定値、不正トークンは無視。
    /// "-" は「全タイル非表示」を明示する保存値(空文字=未設定と区別する)。
    static func decode(_ stored: String) -> [UInt8] {
        guard !stored.isEmpty else { return defaultPIDs }
        return stored
            .split(separator: ",")
            .compactMap { UInt8($0.trimmingCharacters(in: .whitespaces), radix: 16) }
            .filter { PIDCatalog.byPID[$0] != nil }
    }

    static func encode(_ pids: [UInt8]) -> String {
        guard !pids.isEmpty else { return "-" }
        return pids.map { String(format: "%02X", $0) }.joined(separator: ",")
    }
}

struct DashboardCustomizeView: View {
    @Binding var selectedPIDs: [UInt8]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(selectedDefinitions) { definition in
                        row(definition) {
                            Button {
                                selectedPIDs.removeAll { $0 == definition.pid }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .onMove { indices, newOffset in
                        selectedPIDs.move(fromOffsets: indices, toOffset: newOffset)
                    }
                } header: {
                    Text("表示中(ドラッグで並べ替え)")
                } footer: {
                    if selectedPIDs.isEmpty {
                        Text("すべて非表示です。下から追加してください。")
                    }
                }

                Section("非表示") {
                    ForEach(availableDefinitions) { definition in
                        row(definition) {
                            Button {
                                selectedPIDs.append(definition.pid)
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(.green)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("タイルを編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("デフォルトに戻す") {
                        selectedPIDs = DashboardConfig.defaultPIDs
                    }
                    .font(.subheadline)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("完了") { dismiss() }
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
    }

    private var selectedDefinitions: [PIDDefinition] {
        selectedPIDs.compactMap { PIDCatalog.byPID[$0] }
    }

    private var availableDefinitions: [PIDDefinition] {
        let selected = Set(selectedPIDs)
        return PIDCatalog.all.filter { !selected.contains($0.pid) }
    }

    private func row(_ definition: PIDDefinition, @ViewBuilder accessory: () -> some View) -> some View {
        HStack(spacing: 12) {
            Image(systemName: definition.icon)
                .foregroundStyle(definition.tint)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(definition.name)
                    .font(.subheadline.weight(.semibold))
                Text(definition.unit.isEmpty ? String(format: "PID %02X", definition.pid) : definition.unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            accessory()
        }
    }
}
