# car_ui — OBD2 テレメトリ + エンジン音

ELM327(BLE)で車両の対応 PID を自動検出して表示・記録するテレメトリアプリ。5 タブ: ダッシュボード/データ(センサー+チャート統合)/ドライブ/エンジン音/ツール。エンジン音タブは enjine-sim 由来のプロシージャル合成を実測 RPM で駆動(2026-07-12 移植、`EngineSoundController.swift`)。README なし。

## 基本情報
- scheme / target: `car_ui`(単一)
- iOS 26.0+ / bundle id `Sena.car-ui`
- ソース: `car_ui/` 直下(フォルダ同期 — .swift は置くだけでビルド対象)
- SPM: GoogleMobileAds(全タブ共通バナーのみ)。エンジン音の全プリセット(F1 V10 含む)は無料・ロックなし(2026-07-13〜)
- Info.plist はリポジトリ直下(同期フォルダ内に置くとビルド衝突するため)+ GENERATE_INFOPLIST_FILE 併用

## ビルド
```sh
xcodebuild -project car_ui.xcodeproj -scheme car_ui \
  -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -20
```

## 知見メモ
<!-- `- YYYY-MM-DD: 事実 → 対処` で追記。2〜3 回使った知見は上のセクションへ昇格 -->
- 2026-07-12: SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor のため、オーディオスレッド等 main 外から呼ぶ型は `nonisolated` 宣言が必須(HarmonicGenerator/EngineSoundState/EngineParameters で対応済み)。
- 2026-07-12: AdMob ID はルート `Info.plist`(アプリ ID)と `AdBannerView.swift` の AdConfig(ユニット ID)の 2 箇所。
- 2026-07-13: `PrivacyInfo.xcprivacy` の `NSPrivacyAccessedAPITypes` に UserDefaults(理由 `CA92.1`)を宣言済み。新たに file timestamp/system boot time/disk space API を使うコードを追加したら追記が必要。
- 2026-08-06: AdMob ID ねじれ(コンソール登録先と実装が別ID)で公開以来バナー未配信の疑い→ App ID `~9182984317`・バナー `/2711542365` に修正(旧 `~8945778220`・`/1160611372` は破棄)。リワードユニットIDはコード上に存在しない(2026-07-13 の Pro課金統合でリワード解放機能が StoreKit 買い切りに置き換わり未使用化した形跡、`straightPipe` フラグのみ残存)。
- 2026-08-06: `AdBannerView` が広告未ロード時にコンテナ高さを 0 に畳む実装は、`banner.load()` 呼び出し時点でビュー高さが 0 になり SDK が「Invalid ad width or height」でクライアント側失敗する原因だった(2026-07-16 に「高さ0 collapse で隙間も出ない」と記録したのは逆効果だったので撤回)。修正: `AdLoadState`(pending/loaded/failed)を導入し、結果が判明するまでは 50pt を確保、失敗確定時のみ 0 に畳む。
