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

## 2026/07/13
- StoreKit 2 買い切り Pro を実装(`Sena.car-ui.pro` 非消費型、¥730 ローカル仮価格)
  - 新規: `ProStore.swift`(@MainActor @Observable、商品ロード/購入/復元/Transaction.updates/currentEntitlements)
  - 新規: `PaywallView.swift`(価値訴求 5 項目+購入・復元ボタン、濃色ボタン面)
  - 新規: `Products.storekit`(ローカル StoreKit Config)。共有スキーム `car_ui.xcscheme` の LaunchAction に `StoreKitConfigurationFileReference`(相対パス `../../../car_ui/Products.storekit`)を追加
  - 新規: `DriveRecordStore.swift`(0-100/G ピークの保存記録、UserDefaults JSON、最大100件)
  - Pro ゲート4点: ①`ToolsView` DTC 消去(`ELM327BluetoothModel.clearDiagnosticTroubleCodes()` 新規 Mode04 追加、無料はロック→ペイウォール) ②`ChartsView` CSV 書き出し(無料は各ch直近500件、Pro無制限。`TelemetryRecorder.freeExportRowLimit`) ③`DriveView` 0-100完走後の「記録を保存」ボタン(無料はペイウォール誘導) ④`EngineSoundView` F1 V10(`proStore.isPro || rewardStore.isUnlocked`で恒久解錠、Pro時は「Pro で解錠済み」表示・リワード導線スキップ)
  - `ContentView.swift`: `.environment(proStore)` 追加、`AdBannerView()` を `!proStore.isPro` 時のみ表示
  - `ToolsView` 先頭に Pro 入口パネル追加(状態表示+アップグレードボタン)
- 検証: `xcodebuild ... generic/platform=iOS Simulator build` 成功。iPhone Air(iOS 26.3)実機シミュレータへ install+launch し起動確認(クラッシュなし、スクショ取得)。**未検証**: 購入/復元/価格表示の実操作(タップ自動化ツールがなく、Tools タブ→ペイウォールへの遷移・購入フローは手動 Xcode Run での確認が必要)
- DTC 消去は着手前は未実装(読取のみ)だったため Mode04 clear を新規実装。DriveView の「記録保存」も同様に無かったため `DriveRecordStore` を新規実装(いずれも決定ログの前提と実コードの差分。詳細は指揮官への報告参照)
- ハマった点: `ProStore` の `deinit { updatesTask?.cancel() }` は `main actor-isolated` エラー(deinit は既定で nonisolated)→ シングルトンで実質 deinit しないため削除して解消

## 2026/07/13 (指揮側検証・申し送り)
- Pro 実装(builder)を指揮側で検証: ビルド成功、商品 Sena.car-ui.pro/NonConsumable/¥730 定義OK、広告ゲート(ContentView で !isPro のみ AdBannerView)、F1 恒久解錠(isPro || reward)、ProStore は Transaction.updates + currentEntitlements 実装。無料/Pro 境界は決定(DTC消去/CSV無制限[無料=500行/ch]/記録保存/広告除去/F1)と一致。
- **要ユーザー検証(環境制約で自動化不可)**:
  1. Xcode で Run → ツールタブ→ペイウォールで **¥730 が表示されるか**。表示されなければ scheme の StoreKitConfigurationFileReference パス(現 `../../../car_ui/Products.storekit`)を Xcode の Edit Scheme→Run→Options で選び直す(GUI 記録が正)。購入・復元・Pro反映(広告消滅・DTC消去解禁)も Run で確認。
  2. **実車テスト**: DTC消去は今回新規実装(Mode04=実車のECUに書き込む実操作)。実車で読取→消去→再読取を要確認。ライブデータ品質(各PID)もクローンアダプタ差で要確認。
- 未了: PrivacyInfo.xcprivacy の広告SDK対応更新(提出前・CLAUDE.md 既知)、スクショ撮影、/appstore-check。commit/push は未実施。

## 2026/07/13 (スクショ用デモモードフック+撮影)
- `ContentView.swift`: `TabView(selection: $selectedTab)` 化(各タブに `.tag(0〜4)`)、`.onAppear` に `applyUITestLaunchArgumentsIfPresent()` 追加。起動引数 `-uiDemo 1` で `obd.startDemoMode()`、`-uiTab N`(0〜4)で初期表示タブを設定。引数なしなら無変化(本番挙動不変)。
- `ELM327BluetoothModel.swift`: `centralManagerDidUpdateState` に `guard !isDemo else { return }` を追加。既存バグ修正 — シミュレータでは BLE `.unsupported` の遅延コールバックが `phase` を上書きし、デモモードの `.connected` 状態を消していた(TabView が5タブ全て即時マウントするため `DashboardView.onAppear` が先に `startScan()` を呼ぶ競合)。
- 撮影ハマりポイント: 位置情報許可ダイアログが `simctl privacy grant location` 済みでも消えず毎回表示された → 一度アプリを許可未応答のまま複数回 launch/terminate していたため OS 側にプロンプトが滞留した可能性。`simctl erase` でシミュレータを完全初期化 → install → `privacy grant location`(初回 launch 前)の順で解消。
- iPhone 17 Pro Max (iOS 26, UDID B35FB639-CA7C-4514-A5B1-170C7A68EFD3) で ja ロケール+デモモードにて5タブ撮影、`store/raw/tab_0〜4.png`(1320×2868)。全タブとも中身表示・クラッシュなしを目視確認。
- ビルド: `xcodebuild ... generic/platform=iOS Simulator build` → BUILD SUCCEEDED。
- 未検証: 実機 BLE 接続時の `centralManagerDidUpdateState` 挙動(ガード追加が正常系に影響しないことは確認済みだが実機テストなし)。commit/push は未実施。

## 2026/07/13 (エンジン音全無料化 + PrivacyInfo 修正)
- ユーザー決定によりエンジン音のリワード解錠/Pro解錠を廃止、全10プリセット最初から無料に統一
  - `EnginePreset.swift`: `isRewardLocked` プロパティを撤去(F1 V10 含め常時利用可能)
  - `EngineSoundView.swift`: ロック判定・広告alert・トースト・`presentRewardedAd`・`RewardStore`/`RewardedAdManager` の参照を全削除。`restorePresetAndSync`/`loadPreset` を単純化。未使用になった `proStore` プロパティも削除
  - `RewardStore.swift` / `AdManager.swift`(RewardedAdManager)は完全に未参照になったため削除。`AdBannerView.swift` の `AdConfig.rewardedUnitID` も削除(バナー広告の `bannerUnitID` は現状維持)
  - `PaywallView.swift` / `ToolsView.swift`: Pro 特典リストから「F1 V10 恒久解錠」を削除(Pro特典は広告除去・DTC消去・CSV無制限・記録保存の4つに)
- `PrivacyInfo.xcprivacy`: `NSPrivacyAccessedAPITypes` が空のまま(ITMS-91053 リスク)だったのを修正。rg で監査した結果、Required Reason API 該当は `UserDefaults`(`DriveRecordStore.swift`・`@AppStorage` 等)のみ(file timestamp/system boot time/disk space API は不使用)→ `NSPrivacyAccessedAPICategoryUserDefaults` + 理由コード `CA92.1`(自アプリ内のみ・App Group不使用)を追加。`NSPrivacyTracking`/`NSPrivacyCollectedDataTypes` は変更なし
- 検証: `xcodebuild ... generic/platform=iOS Simulator build` → BUILD SUCCEEDED(複数回、最終状態でも確認)。iPhone 17 Pro Max (B35FB639-...) に install+launch(`-uiDemo 1 -uiTab 3` ja)し、エンジン音タブとプリセットピッカーをスクショ確認。ピッカー撮影のため `showingPresets` の初期値を一時的に `true` に変えて再ビルド→撮影→`false` に戻して再ビルドし直した(コミットなし・最終ファイルは `false` のまま)
- 確認できたこと: プリセット一覧(Inline 4 Economy 〜 Inline 6 Legend まで表示範囲)に鍵アイコン・広告バッジは一切なし。grep で `isRewardLocked`/`RewardStore`/`RewardedAdManager`/`rewardedUnitID` の残存参照ゼロを確認済み(F1 V10 含め全プリセットがロックなしで選択可能なことをコードレベルで担保)
- 未解決: F1 V10 Legend 自体(リスト末尾)が実機スクショの可視範囲外(UI自動タップ環境なし・スクロール手段なし)。ロック判定コードが条件分岐なしで全プリセット共通に削除されている(行単位の分岐ではなく preset ループ全体からロジックごと除去)ため、コード監査で担保。commit/push は未実施。

## 2026/07/13 20:14 (車載向け: スリープ防止 + BG再生/データ + 駐車オートオフ)
- 要望: ①車載中に画面が暗転しない ②エンジン音を他アプリ表示中もBG再生 ③OBDデータもBG継続 ④(懸念対応)OBD負荷/バッテリーリスク
- `ContentView.swift`: `import UIKit`。scenePhase 連動で前面のみ `UIApplication.shared.isIdleTimerDisabled=true`(背面で解放)。BG遷移時の `engineSound.stop()` を削除しBG再生を許可。`obd.setBackgrounded(_:)` で前面/背面を通知
- `Info.plist`: `UIBackgroundModes=[audio, bluetooth-central]` を追加(音声+BLEのBG継続)
- `ELM327BluetoothModel.swift`: 駐車検知オートオフを実装。条件B=「電圧<13.0V」かつ「エンジン非稼働(直近5秒以内のRPMが300以上でない)」が背面で120秒継続→`disconnect()`。`lastRpmUpdate`(0x0C取得時に記録)で鮮度判定し、停止後に古いRPMが残る/スマート充電で走行中に電圧が13Vを割る車の誤切断を回避。`setBackgrounded`/`evaluateParkedAutoDisconnect` 追加、リセット時に鮮度・停止タイマーをクリア
- 安全確認: 車へ送るコマンドは全て読み取り専用(01XXライブ・03故障コード読出・ATxxドングル設定)。Mode 04/08 は自動送信なし(手入力 sendManualCommand 経由のみ)
- 調整可能定数: engineOffVoltage=13.0 / engineRunningRpm=300 / rpmFreshWindow=5 / parkedGracePeriod=120
- 検証: `xcodebuild ... generic/platform=iOS Simulator build` → BUILD SUCCEEDED。実機の電圧・BLE背面挙動は未検証(要実車確認)

## 2026/07/15 22:05
- App Store の `Car Scanner ELM OBD2`(iD `1259933623`) を調査し、`car_ui` との差分を整理
- `car_ui` 側で未実装/不足と判断した項目: フリーズフレーム、レディネス/モニタ状態、トリップ/燃費系、メーカー別プロファイル/拡張診断、HUD/ミラー表示、複数ページの柔軟なダッシュボード
- 既存実装で代替できる範囲: BLE 接続、PID 自動検出、DTC 読取/消去、手動コマンド、通信ログ、GPS/加速度、チャート/CSV、0-100 計測、エンジン音
- 参照: [`car_ui/doc/README.md`](doc/README.md), [`car_ui/DashboardView.swift`](car_ui/DashboardView.swift), [`car_ui/SensorsView.swift`](car_ui/SensorsView.swift), [`car_ui/ToolsView.swift`](car_ui/ToolsView.swift)

## 2026/07/16 (競合対抗5機能: フリーズフレーム/レディネス/トリップ燃費/ダッシュボード編集/HUD)
- Car Scanner ELM OBD2 との差分調査(07/15)に基づき、5機能を実装。全機能無料(既存 Pro 境界と整合、PaywallView 変更なし)。メーカー別拡張診断は PID DB 規模過大のため見送り
- **レディネスモニタ**: `ReadinessStatus.swift`(0101 の 4 バイトパース、バイトB bit3 でガソリン/ディーゼルのモニタ名切替)+ `ReadinessPanel.swift`。接続初期化後に自動読取、デモは EVAP のみ Not Ready の固定値
- **フリーズフレーム**: `FreezeFrameModel.swift` + `FreezeFramePanel.swift`。`readFreezeFrame()` は 020200 で発生 DTC 確認(00 00 = 未保存)→ 主要 9 PID を `02XX00` で逐次取得。**Mode 02 応答は PID 直後にフレーム番号 1 バイトが入るため `mode02Payload` で dropFirst 必須**。DTC 文字列化は `dtcString(high:low:)` に切り出して Mode 03 と共用
- **トリップ/燃費**: `TripComputerModel.swift`(距離/時間/平均速度/瞬間・平均燃費/消費燃料。0x5E 優先、なければ MAF から AFR14.7・密度740g/L で推定。dt>2秒はスキップ、瞬間値は EMA 平滑化)+ `TripPanel.swift`(DriveView 先頭)。ContentView の onReceive で ingest(EngineSound と同型)
- **ダッシュボード編集**: `featuredPIDs` を `@AppStorage("dashboardPIDs.v1")`(hex CSV)化。空文字=未設定→既定配列、"-"=全非表示(空文字と区別)。`DashboardCustomizeView.swift` で並べ替え/追加/削除/デフォルト復帰
- **HUD**: `HUDView.swift`(fullScreenCover、黒背景+緑の巨大速度+RPM バー、`hud.mirrored` でコンテンツのみ scaleEffect(x:-1)、操作ボタンは非反転)。起動はダッシュボード heroPanel の HUD バッジ
- 検証: 各ステップで xcodebuild BUILD SUCCEEDED。iPhone 17 Pro Max (B35FB639) デモモードで全画面スクショ確認(レディネス/トリップ積算/カスタマイズシート/HUD 通常+ミラー)。タップが必要な画面は初期値を一時変更して撮影→復元済み(`rg "TEMP: screenshot"` で残存ゼロ確認)。ミラー検証は `simctl spawn defaults write hud.mirrored` を利用
- **未検証(要実車)**: Mode 02 実応答(手動コマンド `020C00` で確認可)、0101 実応答、MAF 燃費推定の妥当性。ディーゼルでは燃費が過大推定(将来 readiness の点火方式フラグで AFR 切替可)

## 2026/07/16 (走行マップ・コンター表示 + CSV 横持ち + バナー隙間修正)
- **走行マップ**: `TrackStore.swift`(GPS 軌跡リングバッファ 7200 点・1 秒間引き。各点に OBD 車速優先の速度と RPM を紐付け、5 秒より古い OBD 値は不採用)+ `TrackMapPanel.swift`(DriveView に配置。MapKit の MapPolyline を色バケット単位でまとめて描画、速度/回転数の切替 Picker、青→赤ヒートマップ+凡例、60 秒超のギャップで線を分断、消去ボタン)。LocationModel から水平精度 <100m の点だけ送る
- **CSV 横持ち**: `TelemetryRecorder.csvWideData`(0.5 秒グリッドに時刻整列、各セルは直前サンプルを forward-fill、5 秒超の古い値は空欄、全列空の行はスキップ)。`TelemetryCSV` に format(.long/.wide)追加。`gps.lat`/`gps.lon` チャンネルを新設(LocationModel が記録、fractionDigits 6)。ChartsView にプリセット(ドライブ/エンジン/燃費)+ 横持ち/縦持ち切替を追加。無料版の 500 行制限は両形式に適用
- **バナー隙間修正(ユーザー指摘)**: AdBannerView が未ロードでも 50pt の白枠を常時確保していた → BannerViewDelegate で受信検知し、ロード完了まで高さ 0 に collapse。タブバー下の空白帯が解消
- 検証: xcodebuild BUILD SUCCEEDED。csvWideData は swiftc 単体テストで出力確認(時刻整列・空欄化・縦持ち互換)。地図は `simctl location start --speed=17 --distance=40 <5点>` で東京の実ルートを流し、速度コンター(青→赤)・凡例・現在位置マーカーをスクショ確認。CSV UI はパネル順を一時入替で撮影→復元(`rg "TEMP:"` 残存ゼロ)
- 注意: 軌跡・記録はメモリのみ(アプリ終了で消える)。地図の再構築は 10 点ごとに間引き(mapRefreshKey)。加速度計の前後 G 符号問題は未修正(別タスク、車速相関の自動キャリブレーション案を提示済み)

## 2026/07/16 (広告除去単品IAP + 走行マップ拡大/追従/航空写真 + タブバー切れ修正)
- **広告除去の有料モデル(2段構え)**: `Sena.car-ui.adfree`(¥300 買い切り・広告非表示のみ)を Products.storekit に追加。ProStore を 2 商品対応に(`isAdFree`、広告判定は `removesAds = isPro || isAdFree`)。PaywallView に「広告除去のみ」ボタン+購入済み表示、ToolsView の Pro パネル文言も対応。**要対応: App Store Connect に adfree 商品(¥300)の登録が必要**。scheme の StoreKit 構成での価格表示・購入・復元は Xcode Run で要確認(simctl 起動では構成が乗らない)
- **走行マップ改善(ユーザー要望)**: ①「拡大」ボタン+パネル地図タップでフルスクリーン表示(`TrackMapExpandedView`)。自由にパン/ズーム、「追従」ボタンで現在位置中心の固定表示(800m スパン、車載常時表示向け・画面スリープなしは既存対応)、「全体」で軌跡全体にフィット ②地図スタイル「標準/航空写真(hybrid)」切替(パネル・拡大共通の @AppStorage) ③コンター計算を `TrackContour` に共通化、パネル地図は `interactionModes: []` のプレビュー扱い
- **タブバー下端切れ修正(ユーザー指摘)**: バナーを VStack 下段 → `TabView.safeAreaInset(edge: .bottom)` に変更。TabView 圧縮でセーフエリアが失われタブバーが切れる問題を解消。広告ロード時はタブバーがバナーの上に正しく持ち上がる
- 検証: xcodebuild BUILD SUCCEEDED。simctl location の東京ルートで拡大マップ(航空写真+コンター+追従中/全体/凡例)をスクショ確認。ペイウォール 2 ボタン構成もスクショ確認(価格は StoreKit 構成が乗らないため未表示 = 既知の環境制約)。タブバーが下端まで表示されることを確認。一時変更(`TEMP:`)は復元済み・残存ゼロ
- 未検証: 実機での広告ロード時のタブバー持ち上がり、adfree 購入フロー(App Store Connect 登録後)
