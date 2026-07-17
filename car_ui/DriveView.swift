//
//  DriveView.swift
//  car_ui
//
//  ドライブ計測: G ボール(加速度計)+ GPS + 0-100 km/h 加速計測。
//

import SwiftUI

struct DriveView: View {
    @EnvironmentObject private var obd: ELM327BluetoothModel
    @EnvironmentObject private var location: LocationModel
    @EnvironmentObject private var motion: MotionModel
    @Environment(ProStore.self) private var proStore
    @StateObject private var accelTest = AccelTestModel()
    @State private var recordStore = DriveRecordStore()
    @State private var showingPaywall = false
    @State private var showingSaveConfirmation = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // レビュー 1-3: 走行タブ上部に常設のセッションバー
                SessionBar()

                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Space.cardGap) {
                        TripPanel()
                        gForcePanel
                        accelTestPanel
                        gpsPanel
                    }
                    .padding()
                    // タブバー被り回避(レビュー 2-2)
                    .padding(.bottom, 72)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("走行")
            .toolbar {
                NavigationLink {
                    DriveRecordsView(store: recordStore)
                } label: {
                    Label("保存済み記録", systemImage: "list.bullet.clipboard")
                }
            }
            .onAppear {
                motion.start()
                location.start()
            }
            // 監査 REL-012: ドライブセッション(OBD 接続)中でなければ、タブを離れた時点で
            // GPS を停止する(以前はタブを一度開くと他タブでも最高精度 GPS が回り続けた)。
            // 接続中は走行マップ・トリップの記録を継続するため止めない。
            // データタブのセンサートグルからいつでも手動で制御できる。
            .onDisappear {
                if !obd.phase.isConnected {
                    location.stop()
                }
            }
            .onReceive(obd.$liveValues) { values in
                if let speed = values[0x0D] {
                    accelTest.update(speedKPH: speed)
                }
            }
            .onReceive(location.$speedKPH) { speed in
                // OBD 車速があるときは OBD を優先
                guard obd.liveValues[0x0D] == nil, let speed else { return }
                accelTest.update(speedKPH: speed)
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
            }
            .alert("記録を保存しました", isPresented: $showingSaveConfirmation) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("保存済み記録: \(recordStore.records.count) 件")
            }
        }
    }

    // MARK: - G ボール

    private var gForcePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("G フォース", systemImage: "circle.dotted.circle")
                    .font(.headline)

                Spacer()

                Button("ピーク解除") {
                    motion.resetPeak()
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            HStack(spacing: 18) {
                gBall
                    .frame(width: 170, height: 170)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("G フォース")
                    .accessibilityValue("横 \(metricText(motion.lateralG, digits: 2)) G、前後 \(metricText(motion.longitudinalG, digits: 2)) G")

                VStack(alignment: .leading, spacing: 10) {
                    gValueRow(label: "横 G", value: motion.lateralG, tint: .pink)
                    gValueRow(label: "前後 G", value: motion.longitudinalG, tint: .orange)
                    gValueRow(label: "合成 G", value: motion.magnitudeG, tint: .purple)
                    gValueRow(label: "ピーク", value: motion.peakG, tint: .red)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !motion.isActive {
                Text("加速度計が停止しています(センサータブで有効化)")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                Text("端末の取り付け角度に依存せず、水平面の G を表示します。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .panelStyle()
    }

    private var gBall: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            // 外周 = 1.0 G
            let scale = side / 2

            ZStack {
                ForEach([1.0, 0.5], id: \.self) { ring in
                    Circle()
                        .stroke(Color(.systemFill), lineWidth: 1)
                        .frame(width: side * ring, height: side * ring)
                        .position(center)
                }

                Path { path in
                    path.move(to: CGPoint(x: center.x - scale, y: center.y))
                    path.addLine(to: CGPoint(x: center.x + scale, y: center.y))
                    path.move(to: CGPoint(x: center.x, y: center.y - scale))
                    path.addLine(to: CGPoint(x: center.x, y: center.y + scale))
                }
                .stroke(Color(.systemFill), lineWidth: 1)

                Circle()
                    .fill(.purple)
                    .frame(width: 16, height: 16)
                    .position(
                        x: center.x + min(max(motion.lateralG, -1), 1) * scale,
                        y: center.y - min(max(motion.longitudinalG, -1), 1) * scale
                    )
                    .shadow(color: .purple.opacity(0.5), radius: 5)
                    .animation(.linear(duration: 0.1), value: motion.lateralG)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func gValueRow(label: String, value: Double, tint: Color) -> some View {
        HStack {
            Text(LocalizedStringKey(label))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Text("\(metricText(value, digits: 2)) G")
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(tint)
        }
    }

    // MARK: - 0-100 km/h 計測

    private var accelTestPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("0-100 km/h 加速計測", systemImage: "flag.checkered")
                    .font(.headline)

                Spacer()

                Text(accelStateText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accelStateColor)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                MetricValue(value: accelTest.elapsed, unit: "秒", digits: 2,
                            valueFont: .system(size: 44, weight: .heavy, design: .rounded))

                Spacer()

                // レビュー 9-3: 自動モードは走行直前のタップを要求しない
                Toggle(isOn: autoStartTiming) {
                    Text("自動")
                        .font(.caption.weight(.semibold))
                }
                .toggleStyle(.button)

                if accelTest.isMeasuring {
                    Button(role: .destructive) {
                        accelTest.cancel()
                    } label: {
                        Label("中止", systemImage: "xmark")
                    }
                    .buttonStyle(.bordered)
                } else if !accelTest.autoStart {
                    Button {
                        accelTest.arm()
                    } label: {
                        Label("計測開始", systemImage: "flag")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(speedSourceUnavailable)
                }
            }

            // 自動モードの状態説明(停止検出→発進で自動開始)
            if accelTest.autoStart, !accelTest.isMeasuring {
                Text(speedSourceUnavailable
                     ? "車速ソースがありません。OBD 接続かデモモード、または GPS を有効にしてください。"
                     : "完全停止すると自動で待機し、発進で計測を開始します。")
                    .font(.caption)
                    .foregroundStyle(speedSourceUnavailable ? .orange : .secondary)
            }

            // GPS のみで計測する場合、精度が低いと信頼できない(レビュー 9-4)
            if obd.liveValues[0x0D] == nil, location.isActive, !location.quality.allowsAccelTiming {
                Text("GPS 精度が低いため、加速計測の値は参考値です。")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if speedSourceUnavailable, !accelTest.autoStart {
                Text("車速ソースがありません。OBD 接続(またはデモモード)か GPS を有効にしてください。")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if !accelTest.splits.isEmpty {
                VStack(spacing: 6) {
                    ForEach(accelTest.splits) { split in
                        HStack {
                            Text("0-\(split.targetKPH) km/h")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(metricText(split.seconds, digits: 2)) 秒")
                                .font(.subheadline.weight(.bold).monospacedDigit())
                        }
                    }
                }

                if case .finished = accelTest.state {
                    HStack {
                        Button {
                            saveRecord()
                        } label: {
                            Label(
                                proStore.isPro ? String(localized: "記録を保存") : String(localized: "記録を保存 (Pro)"),
                                systemImage: proStore.isPro ? "square.and.arrow.down" : "lock.fill"
                            )
                        }
                        .buttonStyle(.bordered)

                        Spacer()

                        if !recordStore.records.isEmpty {
                            NavigationLink {
                                DriveRecordsView(store: recordStore)
                            } label: {
                                Text("保存済み \(recordStore.records.count) 件")
                                    .font(.caption)
                            }
                        }
                    }
                }
            }
        }
        .panelStyle()
    }

    private func saveRecord() {
        guard proStore.isPro else {
            showingPaywall = true
            return
        }
        recordStore.save(splits: accelTest.splits, peakG: motion.peakG)
        showingSaveConfirmation = true
    }

    private var autoStartTiming: Binding<Bool> {
        Binding(get: { accelTest.autoStart }, set: { accelTest.setAutoStart($0) })
    }

    private var speedSourceUnavailable: Bool {
        obd.liveValues[0x0D] == nil && location.speedKPH == nil
    }

    private var accelStateText: String {
        switch accelTest.state {
        case .idle:
            return String(localized: "待機")
        case .armed:
            return String(localized: "停止状態から発進してください")
        case .running:
            return String(localized: "計測中")
        case .finished:
            return String(localized: "計測完了")
        }
    }

    private var accelStateColor: Color {
        switch accelTest.state {
        case .idle:
            return .secondary
        case .armed:
            return .blue
        case .running:
            return .orange
        case .finished:
            return .green
        }
    }

    // MARK: - GPS

    private var gpsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("GPS", systemImage: "location")
                    .font(.headline)

                Spacer()

                Button("距離リセット") {
                    location.resetDistance()
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 12)], spacing: 12) {
                InfoItem(title: "車速 (GPS)", value: location.speedKPH.map { "\(metricText($0, digits: 1)) km/h" } ?? "--", systemImage: "location.fill")
                InfoItem(title: "高度", value: location.altitudeM.map { "\(metricText($0, digits: 1)) m" } ?? "--", systemImage: "mountain.2")
                InfoItem(title: "方位", value: location.courseDegrees.map { "\(metricText($0, digits: 0))°" } ?? "--", systemImage: "safari")
                InfoItem(title: "走行距離", value: "\(metricText(location.totalDistanceKm, digits: 2)) km", systemImage: "road.lanes")
                InfoItem(title: "水平精度", value: location.horizontalAccuracyM.map { "±\(metricText($0, digits: 0)) m" } ?? "--", systemImage: "scope")
            }

            // レビュー 9-4: GPS 精度を数値だけでなく品質として言語化
            HStack(spacing: 6) {
                Circle().fill(location.quality.color).frame(width: 8, height: 8)
                Text("GPS 品質: ")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                + Text(location.quality.label)
                    .font(.caption.weight(.semibold))
            }

            if let obdSpeed = obd.liveValues[0x0D], let gpsSpeed = location.speedKPH {
                let diff = obdSpeed - gpsSpeed
                Text("OBD と GPS の車速差: \(metricText(diff, digits: 1)) km/h(メーター誤差の目安)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if location.isDenied {
                Text("位置情報が拒否されています。設定アプリから許可してください。")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .panelStyle()
    }
}
