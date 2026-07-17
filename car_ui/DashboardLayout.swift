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
            case .tile: return String(localized: "デジタル")
            case .gauge: return String(localized: "アナログメーター")
            case .chart: return String(localized: "チャート")
            case .map: return String(localized: "走行マップ")
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

/// ダッシュボードの用途別プリセット(レビュー 5章)
enum DashboardPreset: String, CaseIterable, Identifiable {
    case simple   // シンプル: 最小限の運転計器
    case sport    // スポーツ: 回転・ブースト・油温など走り重視
    case eco      // エコ: 燃費・スロットル重視
    case custom   // カスタム: 既定(自由編集)

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .simple: return "シンプル"
        case .sport: return "スポーツ"
        case .eco: return "エコ"
        case .custom: return "カスタム"
        }
    }

    var icon: String {
        switch self {
        case .simple: return "gauge.with.dots.needle.33percent"
        case .sport: return "flag.checkered"
        case .eco: return "leaf"
        case .custom: return "slider.horizontal.3"
        }
    }

    var widgets: [DashboardWidget] {
        switch self {
        case .simple:
            return [
                DashboardWidget(kind: .gauge, pid: 0x0C),  // 回転数
                DashboardWidget(kind: .gauge, pid: 0x0D),  // 車速
                DashboardWidget(kind: .tile, pid: 0x05),   // 冷却水温
                DashboardWidget(kind: .tile, pid: 0x2F),   // 燃料残量
            ]
        case .sport:
            return [
                DashboardWidget(kind: .gauge, pid: 0x0C),  // 回転数
                DashboardWidget(kind: .gauge, pid: 0x0D),  // 車速
                DashboardWidget(kind: .tile, pid: 0x0B),   // 吸気圧(ブースト)
                DashboardWidget(kind: .tile, pid: 0x11),   // スロットル
                DashboardWidget(kind: .tile, pid: 0x5C),   // 油温
                DashboardWidget(kind: .tile, pid: 0x04),   // 負荷
                DashboardWidget(kind: .map, pid: nil),
            ]
        case .eco:
            return [
                DashboardWidget(kind: .tile, pid: 0x5E),   // 燃料流量(瞬間燃費源)
                DashboardWidget(kind: .tile, pid: 0x2F),   // 燃料残量
                DashboardWidget(kind: .tile, pid: 0x11),   // スロットル
                DashboardWidget(kind: .tile, pid: 0x05),   // 冷却水温
                DashboardWidget(kind: .chart, pid: 0x5E),  // 燃料流量の推移
            ]
        case .custom:
            return DashboardLayoutStore.defaultPIDs.map { DashboardWidget(kind: .tile, pid: $0) }
        }
    }
}

@MainActor
@Observable
final class DashboardLayoutStore {
    private(set) var widgets: [DashboardWidget] = []

    private static let storageKey = "dashboardLayout.v1"
    /// 旧タイル選択(hex CSV)からの移行元キー
    private static let legacyKey = "dashboardPIDs.v1"

    /// 従来ハードコードされていた既定の表示順(デジタルタイルとして採用)
    nonisolated static let defaultPIDs: [UInt8] = [
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

    /// レビュー 5章: 用途別の表示プリセットを適用する。
    func apply(preset: DashboardPreset) {
        widgets = preset.widgets
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
