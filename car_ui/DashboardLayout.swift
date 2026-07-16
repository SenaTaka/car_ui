//
//  DashboardLayout.swift
//  car_ui
//
//  自分用ダッシュボードのウィジェット構成(種類 + 対象 PID)と永続化。
//  デジタルタイル / アナログメーター / チャート / 走行マップ を自由に並べられる。
//

import Foundation
import Observation
import SwiftUI

struct DashboardWidget: Identifiable, Codable, Equatable {
    enum Kind: String, Codable, CaseIterable {
        case tile
        case gauge
        case chart
        case map

        var displayName: String {
            switch self {
            case .tile: return "デジタル"
            case .gauge: return "アナログメーター"
            case .chart: return "チャート"
            case .map: return "走行マップ"
            }
        }

        var icon: String {
            switch self {
            case .tile: return "square.grid.2x2"
            case .gauge: return "gauge.with.needle"
            case .chart: return "chart.xyaxis.line"
            case .map: return "map"
            }
        }

        /// PID を対象にするウィジェットか(map のみ対象なし)
        var needsPID: Bool { self != .map }
    }

    var id = UUID()
    var kind: Kind
    /// kind.needsPID のとき必須
    var pid: UInt8?
}

@MainActor
@Observable
final class DashboardLayoutStore {
    private(set) var widgets: [DashboardWidget] = []

    private static let storageKey = "dashboardLayout.v1"
    /// 旧タイル選択(hex CSV)からの移行元キー
    private static let legacyKey = "dashboardPIDs.v1"

    /// 従来ハードコードされていた既定の表示順(デジタルタイルとして採用)
    static let defaultPIDs: [UInt8] = [
        0x05, 0x11, 0x04, 0x0B, 0x10, 0x0F, 0x5C, 0x2F, 0x0E, 0x5E, 0x46, 0x62
    ]

    init() {
        widgets = Self.load()
    }

    func move(fromOffsets: IndexSet, toOffset: Int) {
        widgets.move(fromOffsets: fromOffsets, toOffset: toOffset)
        save()
    }

    func remove(atOffsets offsets: IndexSet) {
        widgets.remove(atOffsets: offsets)
        save()
    }

    func remove(id: UUID) {
        widgets.removeAll { $0.id == id }
        save()
    }

    func append(_ widget: DashboardWidget) {
        widgets.append(widget)
        save()
    }

    func changeKind(id: UUID, to kind: DashboardWidget.Kind) {
        guard let index = widgets.firstIndex(where: { $0.id == id }) else { return }
        guard kind.needsPID, widgets[index].pid != nil else { return }
        widgets[index].kind = kind
        save()
    }

    func resetToDefault() {
        widgets = Self.defaultLayout()
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(widgets) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    private static func load() -> [DashboardWidget] {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let widgets = try? JSONDecoder().decode([DashboardWidget].self, from: data) {
            return widgets
        }

        // 旧「タイル PID 選択」からの移行(hex CSV。"-" は全非表示の明示値)
        if let legacy = UserDefaults.standard.string(forKey: legacyKey), !legacy.isEmpty {
            if legacy == "-" { return [] }
            let pids = legacy
                .split(separator: ",")
                .compactMap { UInt8($0.trimmingCharacters(in: .whitespaces), radix: 16) }
                .filter { PIDCatalog.byPID[$0] != nil }
            if !pids.isEmpty {
                return pids.map { DashboardWidget(kind: .tile, pid: $0) }
            }
        }

        return defaultLayout()
    }

    private static func defaultLayout() -> [DashboardWidget] {
        defaultPIDs.map { DashboardWidget(kind: .tile, pid: $0) }
    }
}
