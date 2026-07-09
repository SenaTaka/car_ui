# car_ui — SwiftUI プロトタイプ(最小構成)

車系 UI の実験用プロトタイプ。現状は `car_uiApp.swift` + `ContentView.swift` の 2 ファイルのみ(2026-02 作成)。README なし。

## 基本情報
- scheme / target: `car_ui`(単一)
- iOS 26.0+ / bundle id `Sena.car-ui`
- ソース: `car_ui/` 直下

## ビルド
```sh
xcodebuild -project car_ui.xcodeproj -scheme car_ui \
  -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -20
```

## 知見メモ
<!-- `- YYYY-MM-DD: 事実 → 対処` で追記。2〜3 回使った知見は上のセクションへ昇格 -->
