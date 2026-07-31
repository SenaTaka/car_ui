# 引き継ぎ: 接続ボタン / Bluetooth アダプタ接続問題

対象ブランチ: `claude/connection-button-unresponsive-2kxelx`
最終コミット: `c7e314d 接続ボタンが押せない不具合を修正`

---

## 1. 現象

1. 「接続」ボタン（および接続シートの「アダプタを検索」ボタン）が**押せない**。
2. 「アダプタを検索」を押しても**反応がなく**、Bluetooth アダプタに**接続できない**。

---

## 2. 特定した根本原因（修正済み）

**鶏卵（chicken-and-egg）問題**

- `canScan = centralManager?.state == .poweredOn`（`ELM327BluetoothModel.swift:163`）
- しかし `centralManager` は `ensureCentralManager()` が呼ばれるまで `nil`
- `ensureCentralManager()` は `startScan()` の中でしか呼ばれない（`:169`）
- ところが `startScan()` を呼ぶ経路（`DashboardView.openConnection()` / 接続シートの検索ボタン `.disabled(!canScan)`）はどれも `canScan == true` が前提

→ `centralManager` が永久に生成されず `canScan` が永久に `false`。
検索ボタンは常時 `.disabled`、`phase` も `.waitingForBluetooth` のまま `.idle` に遷移しない。

### 権限は問題なし
`car_ui.xcodeproj/project.pbxproj:341` に
`INFOPLIST_KEY_NSBluetoothAlwaysUsageDescription` が定義済み（`GENERATE_INFOPLIST_FILE` 併用）。
ルート `Info.plist` 側には Bluetooth キーは無いが、ビルド設定側で補完されるため権限文字列は存在する。

---

## 3. 実施した修正（コミット `c7e314d` に含む）

### `car_ui/ELM327BluetoothModel.swift`
`canScan` の直前に公開メソッドを追加:

```swift
/// 接続シートを開いた等、ユーザーが接続意思を示した最初のタイミングで
/// CBCentralManager を生成する。これを呼ばないと centralManager が nil のままで
/// canScan/canConnect が永久に false になり、検索・接続ボタンが押せなくなる。
/// (権限ダイアログはこの生成時に初めて発火するため、起動直後には呼ばない。)
func prepareForConnection() {
    ensureCentralManager()
}
```

### `car_ui/Components.swift`（`ConnectionSheet`）
`.onChange(of: obd.phase.isConnected)` の直前に追加:

```swift
.onAppear {
    // シート表示 = 接続意思。ここで CBCentralManager を生成しないと
    // canScan が false のままで「アダプタを検索」ボタンが押せない。
    obd.prepareForConnection()
}
```

接続シートはダッシュボード右上ボタン・オンボーディング通知など全入口が経由するため、
1 箇所で全経路をカバーする。権限ダイアログの遅延方針（起動直後には出さない）も維持。

> 注: この環境に `xcodebuild` が無いためビルド検証は未実施。ローカルでビルド確認が必要。

---

## 4. ローカルでの取り込み

```sh
git fetch origin claude/connection-button-unresponsive-2kxelx
git checkout claude/connection-button-unresponsive-2kxelx   # 既にあれば git pull
```

ビルド:

```sh
xcodebuild -project car_ui.xcodeproj -scheme car_ui \
  -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -20
```

---

## 5. 「押しても反応しない／接続できない」の続き調査ポイント

修正後もボタンが無反応/接続不可なら、以下の段階で止まっている可能性が高い。
**ツールタブのログ（`logLines`）を実機で確認すると切り分けが速い。**

| 実機ログ | 原因箇所 | 対応の方向性 |
|---|---|---|
| 「Bluetooth が利用可能になるまで待機しています」 | `startScan()` の `guard canScan`（`:170`）— manager が `.poweredOn` でない。ボタンが有効に見えても**ログを残すだけで無反応**になる | 権限拒否/BTオフ時のバナー表示・状態遷移を確認 |
| スキャン開始後もデバイスが出ない | `updateDiscoveredPeripheral`（`:735`）の `guard isLikelyAdapter \|\| resolvedName != nil` — 名前を advertise せず既知マーカーにも当たらないアダプタは**一覧に出ない** | `likelyNameMarkers`/`likelyServiceUUIDs`（`:116-126`）に手持ちアダプタの広告名/サービスUUIDを追加 |
| 「UART 互換の BLE characteristic が見つかりません」（8秒後 `.failed`） | `discoverTransport`/`failIfTransportWasNotFound`（`:768-785`）— write/notify characteristic が `preferredWrite/NotifyUUIDs`（`:128-142`）に無い | 手持ちアダプタの characteristic UUID を追加 |
| 「接続に失敗しました」 | `didFailToConnect`（`:1123`） | エラー内容を確認 |

### 改善候補（未着手）
- **スキャンにタイムアウトが無い**（`startScan`）: デバイスが出ないと `.scanning` のまま無限スピナー。
  タイムアウト + 「見つかりません」フィードバックの追加を推奨。
- `startScan()` の `guard canScan` で return する際、ログだけでなく UI にも
  「Bluetooth を確認中/オフです」等のフィードバックを出すと「無反応」に見えなくなる。

---

## 6. 主要ファイル/行番号（参照用）

- `car_ui/ELM327BluetoothModel.swift`
  - `ensureCentralManager()` `:150` / `prepareForConnection()` `:159`
  - `canScan` `:163` / `canConnect` `:167`
  - `startScan()` `:168` / `connect(to:)` `:194` / `disconnect()` `:209`
  - `updateDiscoveredPeripheral` `:723` / `looksLikeOBDAdapter` `:761`
  - `discoverTransport` `:768` / `centralManagerDidUpdateState` `:1072`（現在は追加行ぶんずれる可能性あり）
- `car_ui/Components.swift`: `ConnectionSheet` `:263`（検索ボタン `:303`、`.disabled(!canScan)` 付近）
- `car_ui/DashboardView.swift`: `openConnection()` `:77`
