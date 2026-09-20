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
    @Environment(ProStore.self) private var proStore
    @Environment(\.dismiss) private var dismiss
    @State private var pendingKind: DashboardWidget.Kind?
    @State private var showingPaywall = false
    /// プリセット適用で手組みの構成を上書きする前の確認(5a §12-1)。nil でなければ確認アラートを出す。
    @State private var pendingPreset: DashboardPreset?

    /// 無料プランのウィジェット上限(レイアウトは元々 1 つしか無いので、上限はウィジェット枚数だけで足りる)。
    /// README §11(5a): 自由配置を課金の壁にしない方針で 4→6 に緩和。
    private static let freeWidgetLimit = 6

    private var canAddMoreWidgets: Bool {
        proStore.isPro || store.widgets.count < Self.freeWidgetLimit
    }

    /// 上限に達していたら追加せず Paywall を出す。追加可なら渡された処理を実行する。
    private func addWidgetIfAllowed(_ perform: () -> Void) {
        guard canAddMoreWidgets else {
            showingPaywall = true
            return
        }
        perform()
    }

    var body: some View {
        NavigationStack {
            List {
                // 2026-08-02 フィードバック: プリセットを最上段へ(まず構成を選び、次に微調整の流れ)
                Section {
                    ForEach(DashboardPreset.allCases) { preset in
                        Button {
                            applyPresetWithConfirmationIfNeeded(preset)
                        } label: {
                            HStack {
                                Label(preset.label, systemImage: preset.icon)
                                Spacer()
                                Image(systemName: "arrow.right.circle")
                                    .foregroundStyle(.blue)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("プリセット")
                } footer: {
                    Text("プリセットを選ぶと現在のウィジェット構成を置き換えます。")
                }

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
                            addWidgetIfAllowed {
                                if kind.needsPID {
                                    pendingKind = kind
                                } else {
                                    store.append(DashboardWidget(kind: .map, pid: nil))
                                }
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
            .navigationTitle("表示項目を編集")
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
                PIDPickerView(title: String(localized: "\(kind.displayName)を追加")) { pid in
                    addWidgetIfAllowed {
                        store.append(DashboardWidget(kind: kind, pid: pid))
                    }
                }
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
            }
            .alert(
                pendingPresetAlertTitle,
                isPresented: Binding(
                    get: { pendingPreset != nil },
                    set: { if !$0 { pendingPreset = nil } }
                )
            ) {
                Button("OK") {
                    if let preset = pendingPreset {
                        store.apply(preset: preset)
                    }
                    pendingPreset = nil
                }
                Button("キャンセル", role: .cancel) {
                    pendingPreset = nil
                }
            }
        }
    }

    /// 5a §12-1: 手組みの構成(空でない・選んだプリセットと内容が違う)を上書きする前に確認する。
    /// 空、またはプリセットと同一内容なら従来どおり即適用。
    private func applyPresetWithConfirmationIfNeeded(_ preset: DashboardPreset) {
        if store.widgets.isEmpty || Self.widgetContents(store.widgets, match: preset.widgets) {
            store.apply(preset: preset)
        } else {
            pendingPreset = preset
        }
    }

    /// DashboardWidget.id は毎回新規発行される(Equatable の既定比較には使えない)ため、
    /// 種類+対象 PID の並びだけで内容を比較する。
    private static func widgetContents(_ a: [DashboardWidget], match b: [DashboardWidget]) -> Bool {
        guard a.count == b.count else { return false }
        return zip(a, b).allSatisfy { $0.kind == $1.kind && $0.pid == $1.pid }
    }

    private var pendingPresetAlertTitle: Text {
        guard let pendingPreset else { return Text("") }
        return Text("現在の構成を「") + Text(pendingPreset.label) + Text("」に置き換えます")
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
