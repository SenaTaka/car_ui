//
//  DriveSession.swift
//  car_ui
//
//  走行セッション(レビュー 1-3・13章)。このアプリの中心概念は
//  「走行を記録して分析すること」だが、記録中か・記録時間・距離・
//  各種状態が常時見えなかった。薄い層として明示的なセッションを足す。
//
//  既存の常時記録(接続で自動 record)は壊さない。セッションは記録の
//  「開始/停止」区間を明示し、UI に状態を集約表示するためのもの。
//

import Combine
import Foundation

@MainActor
final class DriveSessionManager: ObservableObject {
    static let shared = DriveSessionManager()

    @Published private(set) var isRecording = false
    @Published private(set) var startedAt: Date?
    /// セッション開始時点の積算距離(差分でセッション距離を出す)
    private var startDistanceKm: Double = 0
    private var currentDistanceKm: Double = 0

    private init() {}

    /// 記録開始。`distanceKm` は LocationModel の現在の積算距離。
    func start(distanceKm: Double) {
        startedAt = Date()
        startDistanceKm = distanceKm
        currentDistanceKm = distanceKm
        isRecording = true
    }

    func stop() {
        isRecording = false
    }

    /// 積算距離の更新(LocationModel から供給)。
    func updateDistance(_ distanceKm: Double) {
        currentDistanceKm = distanceKm
    }

    /// セッション経過秒(未記録なら 0)
    func elapsed(now: Date = Date()) -> TimeInterval {
        guard let startedAt else { return 0 }
        return now.timeIntervalSince(startedAt)
    }

    /// セッション走行距離(km)
    var sessionDistanceKm: Double {
        max(0, currentDistanceKm - startDistanceKm)
    }

    /// `H:MM:SS` / `MM:SS` 形式の経過時間
    func elapsedText(now: Date = Date()) -> String {
        let total = Int(elapsed(now: now))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
