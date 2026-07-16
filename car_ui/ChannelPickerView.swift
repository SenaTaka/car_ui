//
//  ChannelPickerView.swift
//  car_ui
//
//  チャンネル選択(レビュー 6章・8章・4-4)。従来のチップ(3列で名称が切れる・
//  拡張性が低い)を廃し、検索可能なカテゴリ別リストへ。選択済みを上部固定、
//  日英名+単位を表示、チェックマークで状態を明示、最大選択数を提示する。
//

import SwiftUI

struct ChannelPickerView: View {
    /// 選択対象の全チャンネルID
    let channelIDs: [String]
    @Binding var selected: Set<String>
    /// 最大選択数(超過時は追加不可)。nil で無制限。
    var maxSelection: Int? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                if !selected.isEmpty {
                    Section("選択中 \(selectionCountText)") {
                        ForEach(sortedSelected, id: \.self) { id in
                            row(id)
                        }
                    }
                }

                ForEach(PIDCategory.allCases) { category in
                    let ids = filtered(in: category)
                    if !ids.isEmpty {
                        Section {
                            ForEach(ids, id: \.self) { id in
                                row(id)
                            }
                        } header: {
                            Text(category.label)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $query, prompt: "チャンネルを検索")
            .navigationTitle("チャンネル選択")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }
                }
                ToolbarItem(placement: .cancellationAction) {
                    if !selected.isEmpty {
                        Button("全解除") { selected.removeAll() }
                    }
                }
            }
        }
    }

    private func row(_ id: String) -> some View {
        let info = ChannelInfo.info(for: id)
        let isSelected = selected.contains(id)
        let atLimit = !isSelected && limitReached

        return Button {
            toggle(id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: info.icon)
                    .foregroundStyle(info.tint)
                    .frame(width: 26)

                VStack(alignment: .leading, spacing: 2) {
                    Text(info.name)
                        .foregroundStyle(atLimit ? .secondary : .primary)
                    if !info.unit.isEmpty {
                        Text(info.unit)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? DS.Role.accent : Color(.tertiaryLabel))
                    .font(.title3)
            }
            .contentShape(Rectangle())
            .frame(minHeight: DS.minTapTarget)
        }
        .buttonStyle(.plain)
        .disabled(atLimit)
    }

    // MARK: - ロジック

    private var limitReached: Bool {
        if let maxSelection { return selected.count >= maxSelection }
        return false
    }

    private var selectionCountText: String {
        if let maxSelection {
            return String(localized: "\(selected.count) / 最大 \(maxSelection)")
        }
        return String(localized: "\(selected.count) 件")
    }

    private var sortedSelected: [String] {
        selected.sorted()
    }

    private func filtered(in category: PIDCategory) -> [String] {
        channelIDs.filter { id in
            let info = ChannelInfo.info(for: id)
            guard info.category == category else { return false }
            guard !query.isEmpty else { return true }
            return info.name.localizedCaseInsensitiveContains(query) || id.localizedCaseInsensitiveContains(query)
        }
    }

    private func toggle(_ id: String) {
        if selected.contains(id) {
            selected.remove(id)
        } else if !limitReached {
            selected.insert(id)
        }
    }
}
