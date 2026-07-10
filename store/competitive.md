# car_ui 競合分析(OBD2 アプリ / iOS)

調査日: 2026-07-10

## 主要競合

| アプリ | 価格 | 強み | 弱み |
|---|---|---|---|
| Car Scanner ELM OBD2 | 無料+Pro(約$5〜) | カスタムダッシュボード、HUD、0-100 計測、GPS トリップ地図、DTC データベース、車種別プロファイル、デモモード | ゲージは手動設定が必要。日本語ローカライズが弱い。UI が古め |
| OBD Fusion | $9.99+車種パック($10/系) | 車種別拡張診断(ABS/エアバッグ)、CarPlay、CSV ログ | 有料前提。ライブ表示のセットアップが手間 |
| Torque Pro | Android のみ | ダッシュボード・ログの定番 | iOS 非対応(= iOS では競合外) |
| BlueDriver | 専用機 | 整備レポート | 専用アダプタ必須・高価 |

## car_ui の差別化ポイント(本日実装)

1. **データ量 — 設定ゼロで全部見える**: ECU の対応 PID(Mode 01 ビットマスク)を自動検出し、対応する全 PID(カタログ約 50 種)+GPS 4ch+加速度計 3ch を自動で一覧表示。競合はゲージを 1 個ずつ手動追加。
2. **時系列 — 全チャンネル常時自動記録**: 選択不要で全チャンネルをリングバッファに記録。任意の複数チャンネルを重ね描き(単位が違っても正規化表示可)+CSV 共有。
3. **GPS 連携**: GPS 車速/高度/方位/積算距離をセンサーとして統合。OBD 車速との差分(メーター誤差)表示。
4. **加速度計連携**: 重力補正済み水平面 G(取り付け角度不問)の G ボール、ピーク G、0-100 km/h 加速計測(20/40/60/80/100 スプリット)。
5. **UX**: 完全日本語 UI。アダプタなしで全機能を試せるデモモード(審査・スクショにも有効)。

## 出典
- https://obdadvisor.com/car-scanner-elm-obd2-review/
- https://obdadvisor.com/obd-fusion-app-review/
- https://www.carscanner.info/coding/
- https://apps.apple.com/us/app/car-scanner-elm-obd2/id1259933623
- https://www.obdsoftware.net/software/obdfusion
