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
- `xcodebuild -destination 'generic/platform=iOS Simulator' build` 成功(未コミット)
