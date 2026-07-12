# car_ui — OBD2 テレメトリ + エンジン音

ELM327(BLE)で車両の対応 PID を自動検出して表示・記録するテレメトリアプリ。5 タブ: ダッシュボード/データ(センサー+チャート統合)/ドライブ/エンジン音/ツール。エンジン音タブは enjine-sim 由来のプロシージャル合成を実測 RPM で駆動(2026-07-12 移植、`EngineSoundController.swift`)。README なし。

## 基本情報
- scheme / target: `car_ui`(単一)
- iOS 26.0+ / bundle id `Sena.car-ui`
- ソース: `car_ui/` 直下(フォルダ同期 — .swift は置くだけでビルド対象)
- SPM: GoogleMobileAds(全タブ共通バナー + リワードで F1 プリセット 24h 解錠)
- Info.plist はリポジトリ直下(同期フォルダ内に置くとビルド衝突するため)+ GENERATE_INFOPLIST_FILE 併用

## ビルド
```sh
xcodebuild -project car_ui.xcodeproj -scheme car_ui \
  -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -20
```

## 知見メモ
<!-- `- YYYY-MM-DD: 事実 → 対処` で追記。2〜3 回使った知見は上のセクションへ昇格 -->
- 2026-07-12: SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor のため、オーディオスレッド等 main 外から呼ぶ型は `nonisolated` 宣言が必須(HarmonicGenerator/EngineSoundState/EngineParameters で対応済み)。
- 2026-07-12: AdMob ID はルート `Info.plist`(アプリ ID)と `AdBannerView.swift` の AdConfig(ユニット ID)の 2 箇所。`PrivacyInfo.xcprivacy` は広告導入前の「収集なし」宣言のまま → 提出前に要更新。
