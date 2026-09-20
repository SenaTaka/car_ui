# ダッシュボード UI 調査 — 競合 OBD アプリ + レースゲーム HUD からの移植パターン

作成: 2026-09-20(strategist)。調査目的: car_ui の Pro 主価値「自由に作れるダッシュボード」の機能仕様を決めるための一次情報収集。**コードは書いていない。car_ui のソースは編集していない**(README.md §3 のみ参照)。

出典はすべて WebSearch/WebFetch 経由、取得日は明記がなければ 2026-09-20。断定できない項目は「未確認」、根拠のない推測は「推定」と明記する。

---

## §1 競合比較表

| アプリ | OS | カスタム項目(確認できた範囲) | 編集操作 | 無料/有料の線引き | 評価規模 | 出典 |
|---|---|---|---|---|---|---|
| **Car Scanner ELM OBD2** | iOS/Android | 自分でレイアウトを組む「User-Defined Display Builder」。ゲージ種別=デジタル/バー/グラフ/ゲージ(針)。黄色・赤のしきい値、データレンジ、色、警告音を自分で設定。「Add Page」で複数ダッシュボードページを追加。未接続のデモ状態でも配置・サイズ変更が可能 | 画面上で直接配置・リサイズ(ビルダー画面) | 無料でダッシュボード構築そのものは可能。Pro(概算 $5 買い切り)は広告除去+拡張グラフ・コーディング機能が中心 | 3.3万件以上、★4.8(App Store, 2026-09-20時点) | [Apple](https://apps.apple.com/us/app/car-scanner-elm-obd2/id1259933623), [MWM](https://mwm.ai/apps/car-scanner-elm-obd2/1259933623), [OBD2 Australia](https://obd2australia.com.au/car-scanner-elm-obd2-app-dashboard/) |
| **OBD Fusion** | iOS/Android | 複数の独立したカスタムダッシュボード画面を作成可能。ゲージスタイル(アナログ針/デジタル/バー)、サイズ・色・**針の描画深度(needle depth)** までゲージ単位で調整。CarPlay ではリスト表示対応 | 画面上で直接編集(スタイル選択+ビルトインテンプレートの併用) | **買い切り $9.99 のみでサブスクなし**。ダッシュボード編集機能自体に追加課金の壁は確認できず。車種別の拡張診断パック(ABS/エアバッグ等)が別売 $9.99/ファミリー | 未確認(App Store のレーティング件数は取得できず) | [OBDSoftware.net](https://www.obdsoftware.net/software/obdfusion), [obdadvisor レビュー](https://obdadvisor.com/obd-fusion-app-review/) |
| **Torque Pro** | **Android のみ、iOS 版は存在しない**(開発元が公式に否定。iOS の Classic Bluetooth SPP 制約が理由) | 画面長押し→「Add Display」でダイヤル/折れ線グラフ/デジタル/マップをドラッグ&ドロップ配置。派生ツール(AA-Torque)では保存レイアウトを最大10件 | ドラッグ&ドロップが業界の基準を作った元祖 | 未確認(価格は今回未取得。一般に無料版+Pro買い切りとされるが本調査では価格を検証できていない=未確認) | 未確認 | [obdadvisor](https://obdadvisor.com/torque-pro-review/), [theonegauge](https://www.theonegauge.com/pages/android-device-setup-torque-pro), [chevybolt.orgフォーラム](https://www.chevybolt.org/threads/recommended-obd2-adapter-for-ios-and-torque-pro.37162/) |
| **DashCommand** | iOS/Android | 「Skin Sets」という**プリセット済みダッシュボード集合**を切り替える方式(スキッドパッド、レーストラック、インクリノメーター等)。ゲージをタップして current/min/max を切り替え可能。個別ゲージの自由な色・サイズ変更は確認できず(未確認) | プリセット選択が主。自由配置の証拠は見つからず | 本体 $9.99 買い切り+一部 IAP | 2,100件、★4.2(App Store) | [Apple](https://apps.apple.com/us/app/dashcommand-obd-ii-gauges/id321293183) |
| **RaceChrono Pro** | iOS/Android | 「Gauges」ページでスロットにデータを割当、プリセットあり。App Store レビューで「もっとゲージのデザインの選択肢が欲しい」という声あり=自由度に上限を感じているユーザーがいる | ページ内の項目単位で割当 | **Pro 版 $19.99 買い切りのみ**(無料版はOBD/CAN計測不可) | 182件、★4.7(App Store、ニッチ) | [Apple](https://apps.apple.com/us/app/racechrono-pro/id1129429340) |
| **TrackAddict** | iOS/Android | ダッシュボード表示でメートル法/ヤードポンド法の切替は確認。個別ゲージの色・スタイル自由度は未確認 | 未確認 | 無料+Pro機能 $8.99 IAP | 514件、★4.5(App Store) | [Apple](https://apps.apple.com/us/app/trackaddict/id632355692) |
| **Harry's LapTimer** | iOS/Android | OBD オーバーレイで単一/2連ゲージ(油温・水温など)を切替可能。**開発方針として自由度を意図的に制限**(「アプリ本来の役割を超えないように」という趣旨の記述あり) | オーバーレイ設定ページ内での選択式 | 未確認(価格・レーティング未取得) | 未確認 | [GPS-LapTimer フォーラム](http://forum.gps-laptimer.de/viewtopic.php?t=231) |
| **Carly** | iOS/Android | ダッシュボードというより**ブランド別コーディング/診断ツール**。CarPlay でライブOBD2表示+メンテナンスリマインダー。自由配置のダッシュボードビルダーではない(別カテゴリの競合) | 該当なし | サブスク $68.89/年〜(Premium、車種による)。買い切りではなく年額課金が中心事業として成立している事例 | 未確認(件数不明) | [mycarly.com](https://www.mycarly.com/blog/carly/how-much-does-carly-actually-cost-2026-edition/) |
| **OBDLink アプリ**(公式アダプタ companion) | iOS/Android | 自分でPIDを選んでダッシュボードを作成、ゲージのスタイルを個別に指定可能(長押し→Style)。複数ダッシュボードを作成・並べ替え可能 | 画面上で長押し編集 | 無料(自社アダプタ購入者向け companion、ダッシュボード機能自体に追加課金なし) | iOS: 3,500件★4.7 / Android: 9,896件★4.1(ストアにより差) | [OBDLink サポート](https://support.obdlink.com/support/solutions/articles/43000678883-add-and-edit-dashboard-gauges) |
| **BimmerCode** | iOS専用(BMW/MINI コーディング特化) | 「カスタマイズ可能なゲージと HUD 表示」に言及があるが詳細な自由度は未確認 | 未確認 | 未確認(価格未取得) | 未確認 | [OBDLink紹介ページ](https://obdlink.nl/en/obd-apps/bimmercode) |

### §1 の要点
- **「自由配置+サイズ変更+色/しきい値のカスタム」は Car Scanner・OBD Fusion・OBDLink の 3 社が横並びで持つ"業界標準"**で、価格帯 $0(基本無料)〜$9.99 買い切りのどこでも提供されている。**car_ui の現状(4種ウィジェット固定・別画面リストで並べ替え)はこの標準より明確に低い**。
- 「複数ページ/複数ダッシュボード」を持つのは Car Scanner(Add Page)・OBD Fusion(multiple dashboards)・Torque系(最大10レイアウト)——**ページ複数化は競合の共通パターン**であり、car_ui README の T4(2つ目のレイアウトで課金)は妥当な線。
- DashCommand は「プリセット切替」型で自由度が低いぶん評価件数・評価が競合内で相対的に弱い(2,100件/★4.2)。**自由配置系(Car Scanner 3.3万件/★4.8)との差は無視できない**(推定: 因果関係は証明できないが相関として記録)。
- RaceChrono のレビューにある「もっとゲージデザインが欲しい」は、**Pro級ユーザーでも見た目カスタムへの欲求が上限に達していない**ことを示す一次証拠。

---

## §2 ゲーム UI から移植するパターン(最大10)

| # | パターン名 | 由来 | 実車アプリでの使いどころ | 実装難度 |
|---|---|---|---|---|
| 1 | 進行型シフトライト(RPM連動の連続LEDバー、緑→赤) | iRacing 系オーバーレイ(SimHub/RaceLab、8〜10灯のシフトライト) | タコメーターが redline に近づくとタイル上端に光の帯が点灯していく警告表現。`VehicleProfile` のレッドライン値をそのまま使える | 中 |
| 2 | レッドライン到達時の点滅(近づくほど速く点滅) | Forza HUD カスタム(「redline 突入で赤点滅、リミッターに近いほど速く」) | アナログメーター/デジタルタイルの共通演出として追加。既存のしきい値判定ロジックに乗せやすい | 小 |
| 3 | 円形ダイヤルに代わる「アーク型」RPMバー | Forza カスタムHUD(「advanced race HUD 由来のRPMアーク」) | コンパクトなタイル向けの新ウィジェットスタイル。狭いグリッドマスでも視認性を保てる | 中 |
| 4 | しきい値による色バンディング(青緑→黄→赤) | Gran Turismo(GT Sport/GT7)のタコメーター | 既存の「しきい値判定」を色帯として可視化。水温・油圧・回転数など全PIDに横展開できる基礎パターン | 小 |
| 5 | HUD要素ごとの表示ON/OFF・スケール・不透明度の個別設定 | F1 24 の OSD カスタマイズ(要素単位でトグル・拡大縮小・不透明度) | car_ui の「自由に作れる」を体現する編集モデルそのもの。ウィジェット単位の表示制御に直結 | 中 |
| 6 | テーマ/スキンパックの切替 | DashCommand の Skin Sets、RaceLab の「80+ウィジェット・複数テーマ」 | 生パラメータ(RGB値等)を見せず、Pro向けに数種のプリセット外装(ネオン/クラシック針/フラット数字)を売る型。ユーザー設定は"種類+強弱"原則と整合 | 中 |
| 7 | 未接続でも組めるフリー配置+リサイズのビルダー画面 | Car Scanner の User-Defined Display Builder(デモ状態でも構築可) | car_ui の最大のギャップ。接続前でもダッシュボードを試作できるようにすることで「自由に作れる」訴求の説得力が増す | 大 |
| 8 | デルタ/ベスト値との差分表示ウィジェット | シムレーシング標準の「ラップデルタ」「予測タイム」オーバーレイ | car_ui の 0-100加速記録・トリップ燃費に「前回比」「自己ベスト比」を出す派生ウィジェット | 中 |
| 9 | 大きく中央寄せしたギア数字表示 | GT7 の HUD(速度・ギアを高コントラストで併記) | 新ウィジェット候補。**car_ui が現在ギアを推定できる PID/ロジックを持つかは今回未確認**(README・CLAUDE.md に記載なし) | 未確認(前提PIDの有無次第で小〜中) |
| 10 | 意図的な抑制(自由度に上限を設ける設計思想) | Harry's LapTimer(「アプリ本来の役割を超えないように」自由度を制限) | 逆パターンとして§4に活用。全部盛りのピクセル単位カスタムより、プリセット+軽いパラメータの方が個人開発の工数とQAに見合う | — |

---

## §3 car_ui に入れるべき「自由に作れる」機能 — 収益(Pro転換)に効く順

| 順位 | 施策 | 無料/Pro | 期待効果 | 工数 | 根拠 |
|---|---|---|---|---|---|
| 1 | **複数レイアウト対応+ウィジェット上限解除**(README既存T4の実体化。1レイアウト4枚→無制限・複数ページ) | 無料=1レイアウト・4枚上限/**Pro=無制限** | 大。README で既に「2つ目のレイアウト/5枚目のウィジェット」をペイウォールの直接トリガーに設計済み。競合3社(Car Scanner・OBD Fusion・Torque系)が横並びで持つ標準機能なので、無いこと自体が離脱理由になり得る | 小(既存グリッドの上限値を外すだけ、1〜2日) | §1: Add Page / multiple dashboards / 最大10レイアウトが競合の共通仕様 |
| 2 | **自由配置+サイズ変更のビルダー画面**(別画面リストでの並べ替えを廃止し、ダッシュボード上で直接ドラッグ&リサイズ。未接続でも編集可) | 基本操作=無料、**保存できるカスタム配置の自由度(細かい位置・サイズ)はPro** | 大。「自由に作れる」という Pro の看板そのもの。これが無いと#1・#3の価値訴求も"自由"と言い切れない。競合の主要3社が全員この操作方式 | 大(5〜8日、レイアウトエンジンの刷新が必要) | §1: Car Scanner「デモでも構築可」、OBD Fusion「サイズ・色・needle depth」、Torqueの元祖ドラッグ&ドロップ |
| 3 | **見た目テーマ(スキンパック)の切替**(数値/バー/針の3スタイル+2〜3配色テーマ。生パラメータは見せない) | 無料=既定1テーマ、**Pro=3〜5テーマ+アクセントカラー** | 中〜大。DashCommand(プリセット型・2,100件/★4.2)より自由配置系(Car Scanner 3.3万件/★4.8)が支持されている相関から、自由度がストア評価に効く可能性が高い(推定) | 中(3〜5日、テーマ定義+描画分岐) | §1比較表の評価規模差(相関、推定)、§2パターン#6 |
| 4 | **しきい値の色バンディング+警告演出**(基本の黄/赤色表示は無料、しきい値の細かい編集・段階数・点滅ON/OFFはPro) | 無料=既定しきい値の色表示、**Pro=しきい値カスタム編集+点滅演出** | 中(間接)。直接の課金トリガーではないが、危険域が一目でわかることは実運転での定着に効き、削除率56%(現状最悪)の改善に寄与しうる(推定) | 小〜中(2〜3日) | §2パターン#1・#2・#4、CLAUDE.md既知の`VehicleProfile`レッドライン活用 |
| 5 | **横向き専用レイアウト**(車載ホルダー利用を想定した横持ち専用ダッシュボード) | **無料=縦のみ、Pro=横向き専用レイアウト** | 小〜中。ニッチだが車載常用のヘビーユーザー層(継続率に直結する層)への訴求。OBD Fusion/Carly がCarPlay/複数画面を売りにしている傾向と整合するが、car_ui での需要規模は未検証 | 中(3〜4日) | §1: OBD Fusion CarPlay対応、Carly CarPlay対応(間接根拠) |

**優先順位の考え方**: #1は既存README設計の実装コストがほぼゼロで即座に課金導線に乗るため最優先。#2は工数最大だが、これが無いと「自由に作れる」という Pro の売り文句自体が誇大表示に近くなる(競合比較で明確に見劣りする)ため、#1と並行/直後で着手すべき基盤投資。#3以降は差別化・定着施策として#1・#2の後に積む。

---

## §4 やらないこと

- **生パラメータを逐一見せるUI**(RGB値スライダー、ピクセル単位のフォントサイズ、針の描画深度を数値入力させる等)。OBD Fusionの「needle depth」調整のような細かいノブは個人開発のQAコストに見合わず、ユーザーメモリ原則(調整UIは種類+強弱に畳む)とも矛盾する。
- **メーカー名・車種名を冠したスキン**(「BMW風」「Porsche風」ゲージ等)。CLAUDE.md既存規約(メーカー特定語を入れない)に抵触し、商標・審査リスクがある。
- **SimHub/RaceLab的な外部プラグイン連携・多数ウィジェットのマーケットプレイス化**。シムレーシング特有の需要であり、実車OBDユーザーのニーズとして確認できていない(未確認)。個人開発1人+AIエージェントのスコープを超える。
- **Harry's LapTimerが意図的に避けている「無制限の自由度」の全部盛り**。RaceChronoのレビューでも要望は「もう少しデザインの選択肢」程度であり、ピクセル単位の無制限カスタムまでは需要の裏付けがない(未確認/推測を避けるため、テーマパック方式(§3 #3)に留める)。
- **他社アプリのゲージ意匠に酷似した派手なネオン演出のそのままの移植**(特にsimレーシングHUD特有の過剰演出)。Apple HIGは運転中の可読性・高コントラストを重視しており、ゲーム的な演出過多は審査でのUI品質指摘や実運転時の視認性低下につながるリスクがある。
- **速度計としての精度保証や法規順守を匂わせる文言・機能**(取締り回避的な訴求等)。これは今回の検索で直接の出典は得られていないため**推定**だが、OBD系アプリ全般に共通するグレーゾーンであり、car_uiのポジショニング(音+計器+履歴)から外れるため触れない。

---

## 出典一覧(取得日 2026-09-20)

1. [Car Scanner ELM OBD2 - App Store](https://apps.apple.com/us/app/car-scanner-elm-obd2/id1259933623)
2. [Car Scanner ELM OBD2 - MWM](https://mwm.ai/apps/car-scanner-elm-obd2/1259933623)
3. [Car Scanner ELM OBD2 App Dashboard – OBD2 Australia](https://obd2australia.com.au/car-scanner-elm-obd2-app-dashboard/)
4. [Best OBD2 Scanner Apps in 2026: Comparison Guide | OBDAssistant](https://www.obd2assistant.com/blog/best-obd2-apps-2026)
5. [Car Scanner ELM OBD2 Review (2026) | OBDadvisor](https://obdadvisor.com/car-scanner-elm-obd2-review/)
6. [OBD Fusion - OBDSoftware.net](https://www.obdsoftware.net/software/obdfusion)
7. [OBD Fusion Review | OBDadvisor](https://obdadvisor.com/obd-fusion-app-review/)
8. [DashCommand - OBD-II Gauges - App Store](https://apps.apple.com/us/app/dashcommand-obd-ii-gauges/id321293183)
9. [DashCommand Users Manual (Palmer Performance)](https://www.palmerperformance.com/download/docs/DashCommand_User_Manual.pdf)
10. [Torque Pro Review (2026) | OBDadvisor](https://obdadvisor.com/torque-pro-review/)
11. [OneGauge: Android Device Setup (Torque Pro)](https://www.theonegauge.com/pages/android-device-setup-torque-pro)
12. [Chevy Bolt EV Forum: iOS adapter for Torque Pro](https://www.chevybolt.org/threads/recommended-obd2-adapter-for-ios-and-torque-pro.37162/)
13. [RaceChrono Pro - App Store](https://apps.apple.com/us/app/racechrono-pro/id1129429340)
14. [RaceChrono Forum: Customized dashboard parameters](https://racechrono.com/forum/discussion/2320/customized-dashboard-parameters)
15. [TrackAddict - App Store](https://apps.apple.com/gb/app/trackaddict/id632355692)
16. [Harry's GPS Suite Forum: OBD/Gauge screen](http://forum.gps-laptimer.de/viewtopic.php?t=231)
17. [Carly OBD2 - App Store](https://apps.apple.com/us/app/carly-obd2-car-scanner/id467344155)
18. [How Much Does Carly Actually Cost? (2026) - Carly Blog](https://www.mycarly.com/blog/carly/how-much-does-carly-actually-cost-2026-edition/)
19. [OBDLink: Add and Edit Dashboard Gauges](https://support.obdlink.com/support/solutions/articles/43000678883-add-and-edit-dashboard-gauges)
20. [OBDLink公式サイト](https://www.obdlink.com/obd-apps/obdlink-app/)
21. [OBDLink.nl: BimmerCode紹介](https://obdlink.nl/en/obd-apps/bimmercode)
22. [Nexus Mods: HORIZON HUD (Forza Horizon 6)](https://www.nexusmods.com/forzahorizon6/mods/648)
23. [Forza Community Forum: Custom Shift Light](https://forums.forza.net/t/custom-shift-light/670286)
24. [Forza Community Forum: HUD item size and layout customization](https://forums.forza.net/t/hud-item-size-and-layout-customization/626905)
25. [Gran Turismo 7 Online Manual](https://www.gran-turismo.com/us/gt7/manual/race/02)
26. [GTPlanet: Anyone bothered by the new Tachometer in GTSport?](https://www.gtplanet.net/forum/threads/anyone-bothered-by-the-new-tachometer-in-gtsport.363900/)
27. [Track Impulse: ACC Overlays](https://track-impulse.com/acc-overlays)
28. [RaceLab公式](https://racelab.app/)
29. [Track Impulse: 無料iRacingオーバーレイ](https://track-impulse.com/overlays)
30. [Coach Dave Academy: How to Set Up Your HUD in iRacing](https://coachdaveacademy.com/tutorials/how-to-set-up-your-hud-in-iracing/)
31. [EA Forums: F1 24 HUD adjustment](https://forums.ea.com/discussions/f1-24-general-discussion-en/hud-adjustment/8382275)
32. [Apple Developer: CarPlay Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/carplay)
33. [Apple Developer: Activity rings](https://developer.apple.com/design/human-interface-guidelines/activity-rings)

未確認・未取得だった主要項目(参考): Torque Proの正確な価格とレーティング件数、DashCommand以外の一部アプリのレーティング件数、Harry's LapTimer/BimmerCodeの価格、car_uiが現在ギア推定PIDを持つか。
