//
//  ReviewPromptPolicy.swift
//  car_ui
//
//  App Store レビュー依頼(requestReview)を出すかどうかの純粋な判定ロジック。
//  副作用(StoreKit 呼び出し・永続化)は ContentView 側が担い、ここでは
//  「いつ出していいか」だけを扱う。運転中に絶対出さないことが最優先の要件。
//

import Foundation

enum ReviewPromptPolicy {
    /// 依頼可否を判定するために必要な永続状態。
    struct State: Equatable {
        /// 実接続(デモ除く)でライブデータ受信が累計3分以上あったセッションの回数
        var qualifyingSessionCount: Int = 0
        /// 最後にレビュー依頼を出したアプリバージョン(未依頼なら nil)
        var lastRequestedVersion: String?
        /// セッション終了直後で、安全な文脈になり次第チェックすべきフラグ
        var pendingCheck: Bool = false
    }

    /// 条件を満たすセッション回数のしきい値(2回目のセッション終了時に依頼)
    static let requiredSessionCount = 2
    /// 「ライブデータ受信あり」とみなす累計接続時間
    static let requiredLiveDataDuration: TimeInterval = 180

    /// 接続セッションが終了したときに呼ぶ。デモモードは対象外。
    /// 3分以上のライブデータ受信があった場合のみカウントし、以後チェック対象にする。
    static func sessionEnded(isDemo: Bool, liveDuration: TimeInterval, state: State) -> State {
        var next = state
        guard !isDemo, liveDuration >= requiredLiveDataDuration else { return next }
        next.qualifyingSessionCount += 1
        next.pendingCheck = true
        return next
    }

    /// レビュー依頼を出してよい文脈か。接続中・HUD 表示中・走行タブ・非フォアグラウンドは常に false。
    static func isSafeContext(
        isConnected: Bool,
        isHUDPresented: Bool,
        isOnDriveTab: Bool,
        isForeground: Bool
    ) -> Bool {
        isForeground && !isConnected && !isHUDPresented && !isOnDriveTab
    }

    /// 依頼を実行すべきかを判定し、更新後の state を返す。
    /// pendingCheck が立っていない、または安全な文脈でなければ何もしない(state はそのまま)。
    /// 安全な文脈でチェックした場合は pendingCheck を必ず倒す(条件未達でも延々と聞き続けない)。
    static func shouldRequestReview(
        state: State,
        currentVersion: String,
        isSafeContext: Bool
    ) -> (shouldRequest: Bool, nextState: State) {
        guard state.pendingCheck, isSafeContext else {
            return (false, state)
        }
        var next = state
        next.pendingCheck = false
        guard state.qualifyingSessionCount >= requiredSessionCount,
              state.lastRequestedVersion != currentVersion else {
            return (false, next)
        }
        next.lastRequestedVersion = currentVersion
        return (true, next)
    }
}
