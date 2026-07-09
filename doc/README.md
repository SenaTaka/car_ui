# car_ui 機能ドキュメント

## 概要

`car_ui` は iPhone から BLE 型 ELM327 OBD2 アダプタへ接続し、車両情報を読み取る SwiftUI プロトタイプです。

iOS の公開 API では Bluetooth Classic SPP 型 ELM327 へ直接接続できないため、現在の実装対象は BLE 型アダプタです。

## 画面

### 接続

- 周辺 BLE デバイスのスキャン
- ELM327 らしい名称または既知の UART サービス UUID を持つデバイスの優先表示
- デバイス名、RSSI、ELM327 候補表示
- 接続、切断、スキャン停止
- Bluetooth 状態と接続フェーズの表示

### アダプタ情報

- ELM327 初期化応答の表示
- OBD プロトコル表示
- Mode 01 対応 PID 数の表示

### ライブデータ

接続後、自動で定期ポーリングします。

- エンジン回転数: PID `010C`
- 車速: PID `010D`
- 冷却水温: PID `0105`
- スロットル開度: PID `0111`
- エンジン負荷: PID `0104`
- 吸気温: PID `010F`
- MAF 空気流量: PID `0110`
- アダプタ/車両電圧: `ATRV`

Mode 01 対応 PID を接続時に取得し、未対応と判断した PID は定期ポーリングしません。対応 PID が取得できない場合は、互換性優先で上記 PID を試行します。

### 故障コード

- Mode 03 `03` による DTC 読み取り
- DTC なし、または取得したコード数の表示
- 取得した DTC コードの一覧表示

### 手動コマンド

- 任意の AT/OBD コマンド送信
- 応答結果の表示
- 例: `ATZ`, `ATDP`, `ATRV`, `010C`, `010D`

実機検証時に、アダプタ固有の応答や車両側の対応 PID を確認するための機能です。

### 通信ログ

- BLE スキャン開始/停止
- 接続、切断、失敗理由
- 送信コマンド
- 受信応答
- タイムアウト

画面上では直近 10 件を表示し、内部では最大 80 件を保持します。

## ELM327 初期化

接続後、次の順で初期化します。

- `ATZ`: リセット
- `ATE0`: エコー無効
- `ATL0`: 改行無効
- `ATS0`: スペース無効
- `ATH0`: ヘッダ無効
- `ATAT1`: adaptive timing 有効
- `ATSP0`: プロトコル自動選択
- `ATDP`: 使用プロトコル取得
- `0100` 以降: Mode 01 対応 PID 取得
- `ATRV`: 電圧取得

## BLE 対応

現在の探索対象:

- サービス UUID: `FFE0`, `FFF0`, `18F0`, Nordic UART Service
- write characteristic: `FFE1`, `FFF1`, `FFF2`, `2AF1`, Nordic UART TX
- notify characteristic: `FFE1`, `FFF1`, `FFF2`, `2AF0`, Nordic UART RX

名称による候補判定:

- `OBD`
- `ELM`
- `V-LINK`
- `VLINK`
- `LELINK`
- `VEEPEAK`
- `VIECAR`
- `CARISTA`
- `KONNWEI`
- `KONNWEY`
- `VGATE`
- `IOS-VLINK`
- `OBDII`
- `OBD-II`

## 権限

生成 Info.plist に `NSBluetoothAlwaysUsageDescription` を設定しています。

表示文:

`ELM327 OBD2 アダプタに接続して車両情報を読み取るために Bluetooth を使用します。`

## 既知の制約

- Bluetooth Classic SPP 型 ELM327 は対象外
- シミュレータでは実車 BLE 通信を検証できない
- 現時点では読み取り専用で、DTC 消去コマンドは UI から提供していない
- 車種や ECU によって PID 応答がない項目は `--` 表示になる
- 実機接続は BLE 型 ELM327 と車両の組み合わせで追加検証が必要

## ビルド確認

確認済みコマンド:

```sh
xcodebuild -project car_ui.xcodeproj -scheme car_ui -destination 'generic/platform=iOS Simulator' build
```

最終確認時点ではビルド成功済みです。
