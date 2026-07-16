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
