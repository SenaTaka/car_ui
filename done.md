# done.md — car_ui 作業ログ

<!-- タスク完了時に追記(下に新しいエントリ)。形式: `## YYYY/MM/DD HH:MM` + 箇条書き(やったこと・コミット hash・ハマった点)。読むときは tail -n 40 -->

## 2026/07/08 22:04
- AI エージェント向け知見ファイル体制を導入: `CLAUDE.md` とこの `done.md`(作業ログ)を新規作成
- 共通ルールは `../CLAUDE.md`、運用詳細は `../AI_INSTRUCTIONS.md`

## 2026/07/09 12:37
- ELM327 BLE 接続用の `ELM327BluetoothModel.swift` を追加
- BLE スキャン、接続、ELM 初期化、Mode 01 ライブデータ、Mode 03 DTC 読取、通信ログを実装
- `ContentView.swift` を OBD2 モニター画面へ置換
- 生成 Info.plist に `NSBluetoothAlwaysUsageDescription` を追加
- `xcodebuild -project car_ui.xcodeproj -scheme car_ui -destination 'generic/platform=iOS Simulator' build` 成功

## 2026/07/09 15:25
- 接続初期化時に Mode 01 対応 PID を検出し、未対応 PID の定期ポーリングを避けるよう改善
- ELM327 のヘッダ付き/スペース有無の応答を拾いやすいよう OBD 応答パーサを強化
- 任意の AT/OBD コマンドを送って応答確認できる Command パネルを追加
- `xcodebuild -project car_ui.xcodeproj -scheme car_ui -destination 'generic/platform=iOS Simulator' build` 成功

## 2026/07/09 15:29
- 現在の ELM327 BLE/OBD2 読み取り機能を `doc/README.md` に整理
- 画面構成、対応 PID、ELM327 初期化、BLE 対応範囲、既知の制約を記載

## 2026/07/09 15:44
- `car_ui_2026-07-09_15-30-52.702.xcdistributionlogs` の配布エラーを確認
- App Store 検証で必須 App Icon 120x120 / 152x152 と `CFBundleIconName` が不足していたため、`AppIcon.appiconset` に必要サイズの PNG と Contents.json 定義を追加
- 生成 Info.plist に `INFOPLIST_KEY_CFBundleIconName = AppIcon;` を追加
- `xcodebuild -project car_ui.xcodeproj -scheme car_ui -destination 'generic/platform=iOS Simulator' build` 成功
- `xcodebuild -project car_ui.xcodeproj -scheme car_ui -destination 'generic/platform=iOS' -archivePath /private/tmp/car_ui_iconcheck.xcarchive archive` 成功

## 2026/07/10 21:15
- 競合調査(Car Scanner / OBD Fusion 等)→ `store/competitive.md` に整理
- PID カタログ実装(約50 PID の名称/単位/デコード式/ゲージ範囲): `PIDCatalog.swift`
- ELM327 モデルをカタログ駆動の動的ポーリングに変更(高速 4 PID 毎周+対応 PID ラウンドロビン)、デモモード追加
- 全チャンネル時系列レコーダ(`TelemetryRecorder.swift`、リングバッファ 3600 点/ch、CSV Transferable)
- GPS(`LocationModel.swift`: 速度/高度/方位/距離)・加速度計(`MotionModel.swift`: 重力補正水平 G、0-100 計測)追加
- UI を 5 タブに刷新: ダッシュボード/センサー(全 ch+スパークライン)/チャート(重ね描き+正規化+CSV)/ドライブ(G ボール+GPS+0-100)/ツール(DTC/コマンド/ログ)
- pbxproj に NSLocationWhenInUseUsageDescription / NSMotionUsageDescription 追加
- ハマった点: SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY 有効のため @Published に明示的 `import Combine` が必要
- `xcodebuild -destination 'generic/platform=iOS Simulator' build` 成功 → commit f4121c2 (push 済み)

## 2026/07/10 21:35
- Xcode Cloud 対応: 共有スキーム `xcshareddata/xcschemes/car_ui.xcscheme` を新規作成(自動スキームのみで共有化されていなかった)
- `ITSAppUsesNonExemptEncryption = NO` を追加(TestFlight 配信時の輸出コンプライアンス手動回答を回避)
- commit 8ea0e1d(push 済み)。ワークフロー作成は Xcode GUI での操作が必要(下記手順をユーザーに案内)

## 2026/07/11 01:27
- Agent: Codex
- App Store 審査必須の `PrivacyInfo.xcprivacy` を新規作成・追加
  - NSPrivacyTracking=false、NSPrivacyTrackingDomains=[]、NSPrivacyCollectedDataTypes=[]、NSPrivacyAccessedAPITypes=[]
  - 外部送信なし確認: rg で URLSession/HTTP/send の検索結果なし、UserDefaults 使用なし
  - Xcode 15 自動同期により pbxproj 手動登録不要、ビルド時に自動バンドル
- `xcodebuild -project car_ui.xcodeproj -scheme car_ui -destination 'generic/platform=iOS Simulator' build` 成功（BUILD SUCCEEDED）

## 2026/07/12 13:05
- エンジン音タブ追加(計画承認済み /plan 経由)。enjine-sim の音合成を移植し OBD2 実測 RPM で駆動
  - DSP 層コピー: HarmonicGenerator / EngineSoundState / EngineParameters / EnginePreset(10種) / RPMGaugeView / SpeedometerView
  - `EngineSoundController.swift` 新規: simulator 依存を除去し、liveValues(0x0C/0x0D/0x11/0x04)を CADisplayLink 30Hz で一次遅れ補間して合成へ。スロットル床学習(0x11 のアイドルオフセット自動較正)、オーバーラン/DFCO ヒューリスティック、AVAudioSession 割り込み復帰、RPM 2秒喪失でアイドルへ(未接続=アイドル試聴)
  - `EngineSoundView.swift`: enjine-sim 踏襲(暗背景+ツインダイヤル+プリセットシート+POPSトグル)。F1 V10 はリワード広告で24h解錠、プリセットは @AppStorage 永続化
  - タブ再編: センサー+チャート→「データ」(`DataView.swift`、セグメント切替)で 5 タブ維持。順序: ダッシュボード/データ/ドライブ/エンジン音/ツール
  - AdMob: GoogleMobileAds SPM(12.x)、全タブ共通の最下部バナー、`MobileAds.shared.start()`。Info.plist をリポジトリ直下に新設(GADApplicationIdentifier+SKAdNetworkItems)
- 検証: `generic/platform=iOS Simulator` ビルド成功 + iPhone Air(iOS 26.3.1)シミュレータで起動確認(5タブ表示・クラッシュなし)。音・デモモード連動・リワード解錠の実操作確認は未実施(要手動テスト)
- commit a726140
- ハマった点: SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor により DSP 型に `nonisolated` 必須 / iPhone 15 系シミュレータは iOS 26 未満で使えず iPhone Air を使用 / pbxproj への SPM 追記時、Frameworks 配線(PBXBuildFile)は Xcode が自動補完
- **残 TODO**: ①〜済(2026/07/12 本番 ID 反映)。②PrivacyInfo.xcprivacy が広告導入前の「収集なし」宣言のままなので提出前に要更新
- 残置ファイル(他レーン由来・未タッチ): `car_ui_2026-07-09_15-30-52.702.xcdistributionlogs/`
