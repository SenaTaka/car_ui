//
//  DashboardBuilderView.swift
//  car_ui
//
//  自分用ダッシュボードの編集: ウィジェット(デジタル/アナログ/チャート/マップ)の
//  追加・削除・並べ替え・種類変更。
//

import SwiftUI

struct DashboardBuilderView: View {
    @Bindable var store: DashboardLayoutStore
    @Environment(\.dismiss) private var dismiss
    @State private var pendingKind: DashboardWidget.Kind?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.widgets) { widget in
                        widgetRow(widget)
                    }
                    .onMove { indices, newOffset in
                        store.move(fromOffsets: indices, toOffset: newOffset)
                    }
                    .onDelete { offsets in
                        store.remove(atOffsets: offsets)
                    }
                } header: {
                    Text("ウィジェット(ドラッグで並べ替え)")
                } footer: {
                    if store.widgets.isEmpty {
                        Text("下の「追加」からウィジェットを置いてください。")
                    } else {
                        Text("デジタル/アナログは2列グリッド、チャート/マップは横幅いっぱいに表示されます。")
                    }
                }

                Section("追加") {
                    ForEach(DashboardWidget.Kind.allCases, id: \.self) { kind in
                        Button {
                            if kind.needsPID {
                                pendingKind = kind
                            } else {
                                store.append(DashboardWidget(kind: .map, pid: nil))
                            }
                        } label: {
                            HStack {
                                Label(kind.displayName, systemImage: kind.icon)
                                Spacer()
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("ダッシュボード編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("デフォルトに戻す") {
                        store.resetToDefault()
                    }
                    .font(.subheadline)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("完了") { dismiss() }
                        .font(.subheadline.weight(.semibold))
                }
            }
            .sheet(item: $pendingKind) { kind in
                PIDPickerView(title: "\(kind.displayName)を追加") { pid in
                    store.append(DashboardWidget(kind: kind, pid: pid))
                }
            }
        }
    }

    private func widgetRow(_ widget: DashboardWidget) -> some View {
        let definition = widget.pid.flatMap { PIDCatalog.byPID[$0] }

        return HStack(spacing: 12) {
            Image(systemName: definition?.icon ?? widget.kind.icon)
                .foregroundStyle(definition?.tint ?? .blue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(definition?.name ?? widget.kind.displayName)
                    .font(.subheadline.weight(.semibold))
                Text(widget.kind.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // PID ウィジェットは種類をあとから切替できる
            if widget.kind.needsPID {
                Menu {
                    ForEach(DashboardWidget.Kind.allCases.filter(\.needsPID), id: \.self) { kind in
                        Button {
                            store.changeKind(id: widget.id, to: kind)
                        } label: {
                            Label(kind.displayName, systemImage: kind.icon)
                        }
                    }
                } label: {
                    Image(systemName: widget.kind.icon)
                        .font(.subheadline)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(.systemFill), in: Capsule())
                }
            }
        }
    }
}

extension DashboardWidget.Kind: Identifiable {
    var id: String { rawValue }
}

/// ウィジェットの対象 PID を選ぶシート。
private struct PIDPickerView: View {
    let title: String
    let onSelect: (UInt8) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(PIDCatalog.all) { definition in
                Button {
                    onSelect(definition.pid)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: definition.icon)
                            .foregroundStyle(definition.tint)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(definition.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(definition.unit.isEmpty ? String(format: "PID %02X", definition.pid) : definition.unit)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("キャンセル") { dismiss() }
                }
            }
        }
    }
}
