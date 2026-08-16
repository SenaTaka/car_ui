//
//  Components.swift
//  car_ui
//
//  タブ間で共有する UI 部品。
//

import CoreBluetooth
import SwiftUI
import UIKit

// MARK: - 接続状態ピル

struct StatusPill: View {
    let phase: OBDConnectionPhase

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(LocalizedStringKey(label))
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.12), in: Capsule())
        .foregroundStyle(color)
    }

    /// 監査 C-2: すべて「今どうなっているか」を表す状態語にする。
    /// 以前は接続済みを「接続」と表示していて、同じ画面のツールバーにある
    /// 「接続」ボタン(未接続時に押す**動作**)と同じ語が逆の意味で並んでいた。
    /// 「注意」も何が起きたか分からないので「失敗」に改めた。
    private var label: String {
        switch phase {
        case .connected:
            return "接続済み"
        case .scanning:
            return "検索中"
        case .connecting, .discovering, .initializing, .waitingForBluetooth:
            return "接続中"
        case .failed, .unavailable:
            return "失敗"
        case .idle, .disconnected:
            return "未接続"
        }
    }

    private var color: Color {
        switch phase {
        case .connected:
            return .green
        case .scanning, .connecting, .discovering, .initializing, .waitingForBluetooth:
            return .blue
        case .failed, .unavailable:
            return .red
        case .idle, .disconnected:
            return .secondary
        }
    }
}

// MARK: - 数値タイル(ミニゲージ付き)

struct MetricTile: View {
    let title: String
    let value: String
    let unit: String
    let systemImage: String
    let tint: Color
    var progress: Double?
    /// 監査 B-3: 値が更新されなくなった状態。以前はダッシュボードのタイルに
    /// この概念が無く、凍った値と生きた値が同じ見た目だった(センサー一覧だけが
    /// 区別していた)。ライブ計器としての信頼性に直結するので全面で揃える。
    var isStale: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 0)
            }

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .foregroundStyle(isStale ? Color.secondary : Color.primary)

                Text(unit)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isStale {
                // 止まった値の進捗バーは誤解を生むので、代わりに理由を出す
                Label("更新なし", systemImage: "clock.badge.exclamationmark")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(DS.Role.warn)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else if let progress {
                ProgressView(value: min(max(progress, 0), 1))
                    .progressViewStyle(.linear)
                    .tint(tint)
                    .scaleEffect(x: 1, y: 0.7, anchor: .center)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
        // レビュー 3-5: 意味を持たない装飾半透明円を削除(データUIのノイズ)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: DS.Radius.control))
        // 監査 E-1: タイルは 1 要素として値ごと読み上げる
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(LocalizedStringKey(title)))
        .accessibilityValue(isStale
                            ? Text("\(value) \(unit)、") + Text("更新なし")
                            : Text("\(value) \(unit)"))
    }
}

// MARK: - ラベル+値の小型表示

struct InfoItem: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                // LocalizedStringKey 化: 呼び出し側の日本語リテラルをカタログで解決する
                // (未登録の動的文字列はそのまま表示される)
                Text(LocalizedStringKey(title))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - デバイス行

struct DeviceRow: View {
    let device: OBDPeripheral
    let connect: () -> Void

    var body: some View {
        Button(action: connect) {
            HStack(spacing: 12) {
                Image(systemName: device.isLikelyAdapter ? "checkmark.seal.fill" : "dot.radiowaves.left.and.right")
                    .foregroundStyle(device.isLikelyAdapter ? .green : .secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 3) {
                    Text(device.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(serviceText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // 監査 B-1: 生の dBm は一般ユーザーに読めないので電波強度のバーで示す
                signalBars
                    .accessibilityLabel("電波強度")
                    .accessibilityValue(signalText)
            }
            .contentShape(Rectangle())
            .frame(minHeight: DS.minTapTarget)
        }
        .buttonStyle(.plain)
    }

    /// 監査 B-1: 生の serviceUUID を並べても意味が伝わらないため、
    /// 「使えそうかどうか」だけを言葉で示す。
    private var serviceText: String {
        device.isLikelyAdapter
            ? String(localized: "ELM327 アダプタの可能性が高い")
            : String(localized: "ELM327 ではないかもしれません")
    }

    /// RSSI の目安: -60 以上=強、-75 以上=中、それ未満=弱
    private var signalLevel: Int {
        switch device.rssi {
        case (-60)...: return 3
        case (-75)..<(-60): return 2
        default: return 1
        }
    }

    private var signalText: String {
        switch signalLevel {
        case 3: return String(localized: "強")
        case 2: return String(localized: "中")
        default: return String(localized: "弱")
        }
    }

    private var signalBars: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(1...3, id: \.self) { level in
                Capsule()
                    .fill(level <= signalLevel ? AnyShapeStyle(DS.Role.ok) : AnyShapeStyle(.quaternary))
                    .frame(width: 3, height: CGFloat(4 + level * 3))
            }
        }
        .accessibilityElement(children: .ignore)
    }
}

// MARK: - スパークライン(直近の推移を小さく描画)

struct Sparkline: View {
    let samples: [TelemetrySample]
    let tint: Color

    var body: some View {
        Canvas { context, size in
            guard samples.count >= 2 else { return }

            let values = samples.map(\.value)
            guard let minValue = values.min(), let maxValue = values.max() else { return }
            let span = max(maxValue - minValue, 0.0001)

            let startTime = samples.first!.time.timeIntervalSinceReferenceDate
            let endTime = samples.last!.time.timeIntervalSinceReferenceDate
            let timeSpan = max(endTime - startTime, 0.0001)

            var path = Path()
            for (index, sample) in samples.enumerated() {
                let x = (sample.time.timeIntervalSinceReferenceDate - startTime) / timeSpan * size.width
                let y = size.height - (sample.value - minValue) / span * size.height
                if index == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }

            context.stroke(path, with: .color(tint), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        // スパークラインは装飾。値は同じ行のテキストが読み上げるので VoiceOver からは隠す
        .accessibilityHidden(true)
    }
}

// MARK: - 故障コードなどのフローレイアウト

struct FlowLayout<Data: RandomAccessCollection, Content: View>: View where Data.Element: Hashable {
    let items: Data
    let content: (Data.Element) -> Content

    init(items: Data, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.items = items
        self.content = content
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(Array(items), id: \.self) { item in
                content(item)
            }
        }
    }
}

// MARK: - パネル装飾

extension View {
    func panelStyle() -> some View {
        self
            .padding(DS.Space.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: DS.Radius.card))
    }
}

// MARK: - 接続シート(スキャン・接続・デモモード)

struct ConnectionSheet: View {
    @EnvironmentObject private var obd: ELM327BluetoothModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "car.front.waves.up")
                            .font(.title2)
                            .foregroundStyle(.blue)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("ELM327 BLE")
                                .font(.headline)
                            Text(obd.phase.title)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        StatusPill(phase: obd.phase)
                    }
                    .padding(.vertical, 2)

                    Text("iPhone では BLE 型 ELM327 アダプタを使用します。Bluetooth Classic SPP 型は iOS の公開 API では接続できません。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                // 監査 B-1: 失敗したまま何も出ない状態を無くす(OBD アプリ最大の離脱点)
                troubleshootingSection

                Section {
                    if obd.phase.isConnected {
                        Button(role: .destructive) {
                            obd.disconnect()
                        } label: {
                            Label(obd.isDemo ? "デモモード終了" : "切断", systemImage: "xmark.circle")
                        }
                    } else {
                        Button {
                            obd.startScan()
                        } label: {
                            Label("アダプタを検索", systemImage: "magnifyingglass")
                        }
                        .disabled(!obd.canScan)

                        if case .scanning = obd.phase {
                            Button {
                                obd.stopScan()
                            } label: {
                                Label("検索を停止", systemImage: "stop.fill")
                            }
                        }
                        // デモモードの入口は設定(その他タブ)へ移動(2026-08-02 フィードバック)
                    }
                }

                if !obd.discoveredPeripherals.isEmpty {
                    Section("検出したデバイス") {
                        ForEach(obd.discoveredPeripherals) { device in
                            DeviceRow(device: device) {
                                obd.connect(to: device)
                            }
                            .disabled(!obd.canConnect)
                        }
                    }
                } else if case .scanning = obd.phase {
                    Section {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("周辺の BLE デバイスを検索中")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                adapterShopSection
            }
            .navigationTitle("接続")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
            .onAppear {
                // シート表示 = 接続意思。ここで CBCentralManager を生成しないと
                // canScan が false のままで「アダプタを検索」ボタンが押せない。
                obd.prepareForConnection()
            }
            .onChange(of: obd.phase.isConnected) { _, isConnected in
                if isConnected { dismiss() }
            }
        }
    }

    // MARK: - 失敗時の復旧導線(監査 B-1)

    /// 接続が失敗・切断・利用不可のときだけ出す。理由 → 対処 → 再試行 の順に並べる。
    /// 以前はシートが成功時に自動で閉じるだけで、失敗しても何の説明も出なかった。
    @ViewBuilder
    private var troubleshootingSection: some View {
        if obd.phase.isProblem {
            Section {
                Label {
                    Text(obd.phase.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(DS.Role.warn)
                }

                ForEach(recoverySteps, id: \.self) { step in
                    Label {
                        Text(step)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 5))
                            .foregroundStyle(.tertiary)
                    }
                }

                if obd.needsBluetoothSettings {
                    Button {
                        openSystemSettings()
                    } label: {
                        Label("設定アプリを開く", systemImage: "gear")
                    }
                } else if obd.bluetoothState != .unsupported {
                    // BLE 非対応端末では再検索しても永久に見つからないのでボタンを出さない
                    Button {
                        obd.startScan()
                    } label: {
                        Label("もう一度検索する", systemImage: "arrow.clockwise")
                    }
                    .disabled(!obd.canScan)
                }
            } header: {
                Text("接続できないとき")
            }
        }
    }

    /// 状態に応じた対処手順。Bluetooth 側の問題と、アダプタ側の問題を混ぜない。
    /// 見出し行(`phase.title`)が理由を述べるので、ここには**取るべき行動だけ**を書く
    /// (理由を繰り返すと同じ文が 2 度並ぶ)。
    private var recoverySteps: [String] {
        switch obd.bluetoothState {
        case .poweredOff:
            return [String(localized: "設定アプリで Bluetooth をオンにしてください。")]
        case .unauthorized:
            return [String(localized: "設定アプリ > プライバシーとセキュリティ > Bluetooth で、このアプリに許可を与えてください。")]
        case .unsupported:
            // 打てる手が無い状態。見出しの理由だけで十分なので何も足さない
            return []
        default:
            return [
                String(localized: "アダプタが「ELM327」かつ「BLE(Bluetooth 4.0 / LE)対応」と明記された製品か確認してください。Bluetooth Classic (SPP) 型は iOS では接続できません。"),
                String(localized: "車両のイグニッションを ON にしてください。アダプタは車両から給電されるため、電源が入っていないと検出されません。"),
                String(localized: "アダプタを OBD2 ポートから抜き差しして、LED が点灯することを確認してください。"),
                String(localized: "iOS の設定アプリ側で「ペアリング」する必要はありません。このアプリの検索から直接つなぎます。")
            ]
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - アダプタ購入導線(Amazon アソシエイト)

    /// Amazon アソシエイトのアプリ承認が下りたらトラッキング ID を入れる(例: "xxxx-22")。
    /// 空の間はセクションごと非表示(未承認でのアフィリエイトリンク掲出は規約違反のため)。
    private static let amazonAffiliateTag = ""

    /// アフィリエイトリンクは日本の Amazon アソシエイト前提。
    /// 他ストアフロントのユーザーには出さない(タグが無効なうえ、案内先として不適切)。
    private var showsAffiliateLink: Bool {
        !Self.amazonAffiliateTag.isEmpty && Locale.current.region?.identifier == "JP"
    }

    /// ELM327 BLE アダプタの Amazon 検索結果(アフィリエイトタグ付き)
    private var adapterSearchURL: URL? {
        var components = URLComponents(string: "https://www.amazon.co.jp/s")
        components?.queryItems = [
            URLQueryItem(name: "k", value: "ELM327 OBD2 Bluetooth BLE"),
            URLQueryItem(name: "tag", value: Self.amazonAffiliateTag)
        ]
        return components?.url
    }

    /// 監査 A-4: 以前はアフィリエイトタグが空だとセクションごと消えていたため、
    /// アダプタを持たないユーザー(特に海外)は「何を買えばいいか」をどこからも知れなかった。
    /// 購入リンクの有無に関わらず、選び方のガイドは常に出す。
    @ViewBuilder
    private var adapterShopSection: some View {
        if !obd.phase.isConnected {
            Section {
                Label {
                    Text("「ELM327」かつ「BLE / Bluetooth 4.0 / Bluetooth LE」対応と明記された製品")
                        .font(.footnote)
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(DS.Role.ok)
                }

                Label {
                    Text("「Bluetooth Classic」「SPP」「Wi-Fi 接続」の製品は iPhone では使えません")
                        .font(.footnote)
                } icon: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(DS.Role.danger)
                }

                if showsAffiliateLink, let url = adapterSearchURL {
                    Link(destination: url) {
                        HStack {
                            Label("対応アダプタを Amazon で見る", systemImage: "cart")
                            Spacer()
                            Image(systemName: "arrow.up.forward")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("アダプタをお持ちでない方へ")
            } footer: {
                if showsAffiliateLink {
                    // ステマ規制(景品表示法)対応として「PR」を明記する
                    Text("PR: リンクは Amazon アソシエイトのアフィリエイトリンクです。")
                } else {
                    Text("アダプタが無くても、その他タブのデモモードで全機能を試せます。")
                }
            }
        }
    }
}
