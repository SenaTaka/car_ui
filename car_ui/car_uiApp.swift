//
//  car_uiApp.swift
//  car_ui
//
//  Created by Sena Takasawa on 2026/2/20.
//

import SwiftUI

@main
struct car_uiApp: App {
    // 2026-07-16 監査 REL-007 対応: Mobile Ads SDK の開始は UMP 同意確定後に
    // AdConsentManager が行う(ContentView の .task から起動ごとに更新)。

    init() {
        Self.migrateLegacyLanguageOverride()
    }

    /// 監査 D-4: アプリ内の言語ピッカー(`AppleLanguages` 直書き + 再起動待ち)を廃止し、
    /// iOS 標準の App 別言語設定へ寄せた。旧設定を残したままだと UI から変更できない
    /// 言語に固定されてしまうため、一度だけ消してシステム設定に主導権を戻す。
    private static func migrateLegacyLanguageOverride() {
        let defaults = UserDefaults.standard
        let legacyKey = "app.languageOverride"
        guard let override = defaults.string(forKey: legacyKey), !override.isEmpty else { return }
        defaults.removeObject(forKey: "AppleLanguages")
        defaults.removeObject(forKey: legacyKey)
    }

    var body: some Scene {
        WindowGroup {
            // ユニットテスト実行時はアプリ UI を起動しない(SwiftUI の再構築で
            // MainActor 既定分離クラスの isolated deinit がテストホストを
            // 落とすランタイム問題の回避 + テスト安定化)
            if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
                ContentView()
            }
        }
    }
}
