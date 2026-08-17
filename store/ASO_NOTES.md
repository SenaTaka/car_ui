# ASO_NOTES — car_ui (OBD2 + エンジン音)

正本は store/metadata/。競合・価格の詳細調査は STRATEGY.md 決定ログ 2026-07-13(2) と strategist レポート。

## ポジショニング(2026-07-13 strategist)
- 一文: ELM327 BLE で車のデータを「見て・聴く」。サブスクなしの買い切りで、無料アプリより滑らかな UI と唯一無二のエンジン音を届ける。
- 競合の穴: サブスク嫌悪(Auto Doctor/Carista で実証)/UI 古い(DashCommand)/エンジン音は競合皆無/日本語 OBD が薄い(空白地帯)。
- 価格: 海外 $4.99 / 日本 ¥730(EngineLink $5.99 未満、DashCommand $14.99 の 1/3 以下)。

## キーワード設計(2026-07-13)
- ヘッド語 EN: OBD2 scanner / ELM327 app / engine sound / OBD2 no subscription
- ヘッド語 JA: OBD2 診断 / ELM327 アプリ / エンジン音 / OBD2 サブスクなし
- name/subtitle に OBD2・ELM327・エンジン音・サブスクなし を配置済み(keywords 欄からは重複排除)。
- 「engine sound」「エンジン音」は競合が持たない独自語 → 検索で必ず 1 位取れる想定。

検索順位の記録は末尾の表(リリース後 4 週ごとに手動測定)。

## 2026-07-16 スクショ刷新(v2: 5枚構成)
- ユーザーフィードバック反映: ①診断系(レディネス/フリーズフレーム/ツール)は**実車未検証のためプロモーションから除外**(スクショ7→5枚、説明文からも車検セクション・promotional の故障コード消去を削除。Pro 特典リストの DTC 消去は事実記載として残置)②マップ見出しは「速度、回転数を地図上に表示」③「計器」→「見たい情報」
- 自然さの改善: GPS ルートは**実在道路に沿わせる**(大阪・御堂筋 = 直線大通りなので simctl の直線補間でも路上に乗る。東京の斜め直線ルートは公園横断で不自然だった)。接続表示は `-uiDemoName "ELM327 v2.3"` フックで「デモモード」表記を回避(UI は実機能・データはデモ)
- 構成(CVR は先頭2枚が勝負): 01 自分用ダッシュボード → 02 地図コンター → 03 HUD → 04 エンジン音 → 05 データ記録。全枚 navy 系グラデで統一(ブランド一貫性、コラージュ感の回避)

## 2026-08-17 「OBD2 日本語」を取りに行く(ja メタデータ更新)
- 発端: 米国から初の Pro 課金(2026-08-15、$4.99 / proceeds $4.24)。同時に ja 側の検索対策が未着手なことが判明。
- 判明した事実: **`obd2 日本語` は App Store の実サジェスト語**(需要あり)だが、ja の name / subtitle / keywords のどこにも「日本語」が無く、**構造的にヒットしない**状態だった。keywords 欄も 100 字中 49 字しか使っていなかった。2026-07-13 のポジショニングで「日本語 OBD が薄い(空白地帯)」と穴を特定済みだったのに、メタデータへ落とし込まれていなかった。
- 変更:
  - subtitle: `ELM327メーター・買い切り・サブスクなし`(22字) → `日本語のELM327メーター・買い切り・サブスクなし`(26字)。既存語を捨てずに「日本語」を追加。name の `OBD2` と組み合わさって `OBD2 日本語` が引ける想定。
  - keywords: 49字 → 69字。追加 `対応`(「日本語対応」組み合わせ用) / `記録`,`csv`(Pro の実際の売り = CSV無制限・記録保存をストア側でも検証する枠) / `タコメーター` / `油温`。(当初 `obd` も入れたが、name の `OBD2` と重複で lint NG のため同日削除)
  - `日本語` は subtitle に置いたので keywords 側では重複排除(2026-07-13 の方針を踏襲)。
- 見送り: 「診断」「故障」「エラーコード」系語(2026-08-09 の分析どおり、DTC は実車未検証+2.3.7 リジェクト前例のため継続して不採用)。
- 制約: name/subtitle/keywords は新バージョンを作らないと編集できない(随時変更可なのは promotional text のみ)。App Store 公開版は 1.0.1 のままで ASC に 1.0.2 のレコードが無い(build 39 は VALID で待機)。**この ASO 変更は 1.0.2 の提出に相乗りさせる**。

## 検索順位の記録(リリース後 4 週ごとに JP/US の App Store アプリで手動検索)
| 日付 | ストア | 検索語 | 順位 | メモ |
|---|---|---|---|---|
| 2026-08-17 | JP | OBD2 日本語 | **圏外(実測)** | 変更前ベースライン。App Store アプリで手動検索し car_ui は表示されずを確認。「日本語」が name/subtitle/keywords のどこにも無いという説明と一致。1.0.2 反映後に同じ手順で再測定 |

## 2026-08-17 en-US スクショ全面撮り直し(単位系対応+日本語 UI の解消)
- **判明した重大な問題**: 従来の en-US スクショは**見出しだけ英語で、中の端末画面は全部日本語 UI** だった(「ダッシュボード」「冷却水温」「サウンド開始」がそのまま写っていた)。最大市場である US のストアで日本語アプリに見えていた。2026-07-16 監査の 10.1 で指摘されていたが、アプリの多言語化(完了済み)だけ行われスクショは放置されていた。
- 撮り直し: iPhone 15 Pro Max / iOS 26.0 / 地域 en_US。英語 UI + mph・°F・psi・mpg。見出し・キャプションは既存 5 枚から復元してそのまま踏襲(方針 A)。
- **1 本だけ変更**: 05 の見出し `Trip economy and 0-100 timing` → `Trip economy and acceleration timing`。単位系対応で本体表示が「0-62 mph Timer」になり、旧見出しは事実と食い違うため(2.3.7 で一度リジェクトされた前例があるカテゴリ)。
- keywords: lint 指摘により `obd` を削除(name の `OBD2` と重複=枠の無駄)。代わりに `油温` を追加(`水温` はあったが油温は未カバー)。69/100 字。
- 残る lint NG 2 件(`description` の「無料」「free」)は 1.0.1 から存在し、root CLAUDE.md の「価格は description のみ可」に沿った意図的なもの。lint 側が過剰。

## 2026-08-17 description の car_ui 除去 / en-US keywords 再配分 / ロケール追加(zh-Hans・de-DE・fr-FR・es-MX・es-ES)
- description(ja/en-US)の開発コード名 "car_ui" を「このアプリ/the app」に置換(各1箇所)。訴求内容は不変。
- en-US **subtitle は変更を見送り**(意図的な決定・確度【実践知】): obd2_analysis の案「Live gauges + engine sound, no sub」は name.txt が既に "Engine Sound" を含み、ASO_PLAYBOOK 2章の「subtitle は name と単語重複禁止」に反する(過去に "obd" 重複で lint NG になった前例と同種)。ELM327/gauges/no sub は現行のまま維持し、代わりに **keywords 側で再配分**(83→96字、`obdii`,`torque` を追加)。iTunes サジェスト API(US)で両語とも実需要を確認済み(`instrument`/`cluster`/`dash`/`car` は無関係ジャンルが大半を占め死に枠と判定し不採用)。
- 新規ロケール 5 件(name/subtitle/keywords は iTunes サジェスト API の実サジェストで検証。DE/FR/ES/CN でも英語 "OBD2 Scanner" 自体が現地サジェストに出た=name は全ロケール共通のまま維持)。zh-Hans のみ現地化名(`OBD2扫描仪 · 引擎声音`、`仪表盘` の強い実需要を subtitle に反映)。ASC へ反映済み(appStoreVersionLocalization 作成+appInfoLocalization 更新+supportUrl/marketingUrl を ja/en-US から PATCH で補完 — 新ロケールは継承されない既知の罠)。

### 撮影レシピ(次回そのまま使える)
- 撮影専用シミュレータを新規 create し、**アプリを一度も起動しないうちに** `simctl privacy grant location` する(起動後だと iOS 26 ではダイアログが消えずタップできない → `_AI_AGENT_NOTES/simulator-device.md`)。
- 地図は `simctl location set 34.6700,135.5014`(御堂筋)+ `track.json` をコンテナへ seed。位置を設定せずに起動するとアプリが Cupertino の点を軌跡に追記し、地図が太平洋まで引きになる。
- 起動引数: `-uiDemo 1 -uiDemoName "ELM327 v2.3" -uiTab N`。分析タブのセグメントは `-analysisSection N`(@AppStorage を NSArgumentDomain で上書き)。
- 広告バナーは生スクショの下端に写るので、合成前に**上端基準で** 2450px に切る。`sips -c` は `--cropOffset 0 0` を付けても中央基準で切ってしまい、ステータスバーが落ちてバナーが残る。
