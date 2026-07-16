//
//  TrackMapPanel.swift
//  car_ui
//
//  GPS 走行軌跡を地図に描画し、速度または回転数で色分け(コンター)する。
//  DriveView のパネル表示と、拡大(フルスクリーン・追従固定)表示の両方を提供。
//

import CoreLocation
import MapKit
import SwiftUI

// MARK: - 色分けソース

enum TrackColorSource: String, CaseIterable, Identifiable {
    case speed = "速度"
    case rpm = "回転数"

    var id: String { rawValue }

    var unit: String {
        switch self {
        case .speed: return "km/h"
        case .rpm: return "rpm"
        }
    }

    func value(of point: TrackPoint) -> Double? {
        switch self {
        case .speed: return point.speedKPH
        case .rpm: return point.rpm
        }
    }

    /// 手動レンジ既定値(設定シートの初期値・自動レンジがない時のフォールバック)
    var defaultManualRange: ClosedRange<Double> {
        switch self {
        case .speed: return 0...120
        case .rpm: return 0...8000
        }
    }

    /// 手動レンジ調整のステップ幅
    var manualStep: Double {
        switch self {
        case .speed: return 10
        case .rpm: return 500
        }
    }
}

// MARK: - 地図スタイル

enum TrackMapStyleOption: String, CaseIterable, Identifiable {
    case standard = "標準"
    case imagery = "航空写真"

    var id: String { rawValue }

    var mapStyle: MapStyle {
        switch self {
        case .standard: return .standard
        case .imagery: return .hybrid  // 航空写真+道路名ラベル
        }
    }
}

// MARK: - コンター計算(パネル・拡大表示で共用)

enum TrackContour {
    /// コンターの色分け段数(段差を目立たせないため細かめ)
    static let bucketCount = 32
    /// 点間がこの秒数を超えたら別の走行として線を切る(トンネル・駐車)
    static let segmentGapSeconds: TimeInterval = 60

    struct ColoredSegment: Identifiable {
        let id: Int
        let coordinates: [CLLocationCoordinate2D]
        let color: Color
    }

    /// 実測値の自動レンジ(手動指定がないときのフォールバック)
    static func valueRange(_ points: [TrackPoint], source: TrackColorSource) -> ClosedRange<Double>? {
        let values = points.compactMap { source.value(of: $0) }
        guard let minValue = values.min(), let maxValue = values.max() else { return nil }
        return minValue...max(maxValue, minValue + 0.001)
    }

    /// 連続する点を色バケット単位でまとめ、Polyline の本数を抑える。
    /// `range` は呼び出し側で確定した実効レンジ(自動 or 手動)を渡す。
    static func segments(
        _ points: [TrackPoint],
        source: TrackColorSource,
        range: ClosedRange<Double>?
    ) -> [ColoredSegment] {
        guard points.count >= 2 else { return [] }

        var segments: [ColoredSegment] = []
        var currentCoords: [CLLocationCoordinate2D] = [points[0].coordinate]
        var currentBucket = bucket(for: points[0], source: source, range: range)
        var segmentID = 0

        func flush(bucket: Int?) {
            guard currentCoords.count >= 2 else { return }
            segmentID += 1
            let segmentColor: Color = bucket.map { color(forNormalized: Double($0) / Double(bucketCount - 1)) } ?? .gray
            segments.append(ColoredSegment(id: segmentID, coordinates: currentCoords, color: segmentColor))
        }

        for index in 1..<points.count {
            let point = points[index]
            let gap = point.time.timeIntervalSince(points[index - 1].time)

            if gap > segmentGapSeconds {
                flush(bucket: currentBucket)
                currentCoords = [point.coordinate]
                currentBucket = bucket(for: point, source: source, range: range)
                continue
            }

            let newBucket = bucket(for: point, source: source, range: range)
            if newBucket != currentBucket {
                currentCoords.append(point.coordinate)
                flush(bucket: currentBucket)
                currentCoords = [point.coordinate]
                currentBucket = newBucket
            } else {
                currentCoords.append(point.coordinate)
            }
        }

        flush(bucket: currentBucket)
        return segments
    }

    static func bucket(for point: TrackPoint, source: TrackColorSource, range: ClosedRange<Double>?) -> Int? {
        guard let range, let value = source.value(of: point) else { return nil }
        // 手動レンジ外の値はクランプ(0…1 に収める)
        let t = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        return min(bucketCount - 1, max(0, Int(min(max(t, 0), 0.999999) * Double(bucketCount))))
    }

    /// jet カラーマップ(0=濃青 → 青 → シアン → 緑 → 黄 → 赤 → 1=濃赤)。
    /// 区分線形の RGB 補間で滑らかに変化させる。
    static func color(forNormalized t: Double) -> Color {
        let x = min(max(t, 0), 1)
        // MATLAB jet に準拠したアンカー(位置, R, G, B)
        let stops: [(Double, Double, Double, Double)] = [
            (0.000, 0.00, 0.00, 0.50),
            (0.125, 0.00, 0.00, 1.00),
            (0.375, 0.00, 1.00, 1.00),
            (0.625, 1.00, 1.00, 0.00),
            (0.875, 1.00, 0.00, 0.00),
            (1.000, 0.50, 0.00, 0.00),
        ]
        for i in 1..<stops.count where x <= stops[i].0 {
            let (x0, r0, g0, b0) = stops[i - 1]
            let (x1, r1, g1, b1) = stops[i]
            let f = (x - x0) / (x1 - x0)
            return Color(
                red: r0 + (r1 - r0) * f,
                green: g0 + (g1 - g0) * f,
                blue: b0 + (b1 - b0) * f
            )
        }
        return Color(red: 0.5, green: 0, blue: 0)
    }

    /// 進行方位(度, 0=北 時計回り)。末尾から約 `minDistance` m 手前の点との
    /// 大円方位を返す。十分な移動がなければ nil(向きを更新しない)。
    static func bearingOfTravel(_ points: [TrackPoint], minDistance: CLLocationDistance = 15) -> Double? {
        guard let last = points.last else { return nil }
        let end = CLLocation(latitude: last.coordinate.latitude, longitude: last.coordinate.longitude)
        for point in points.reversed().dropFirst() {
            let start = CLLocation(latitude: point.coordinate.latitude, longitude: point.coordinate.longitude)
            if start.distance(from: end) >= minDistance {
                return bearing(from: point.coordinate, to: last.coordinate)
            }
        }
        return nil
    }

    private static func bearing(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let dLon = (to.longitude - from.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let deg = atan2(y, x) * 180 / .pi
        return (deg + 360).truncatingRemainder(dividingBy: 360)
    }
}

// MARK: - 共用の地図コンテンツ + 凡例

struct TrackMapContent: MapContent {
    let points: [TrackPoint]
    let colorSource: TrackColorSource
    let range: ClosedRange<Double>?
    var lineWidth: CGFloat = 8

    var body: some MapContent {
        ForEach(TrackContour.segments(points, source: colorSource, range: range)) { segment in
            MapPolyline(coordinates: segment.coordinates)
                .stroke(
                    segment.color,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                )
        }

        if let last = points.last {
            Annotation(String(localized: "現在"), coordinate: last.coordinate) {
                Circle()
                    .fill(.blue)
                    .stroke(.white, lineWidth: 2)
                    .frame(width: 14, height: 14)
            }
        }
    }
}

private struct TrackLegend: View {
    let range: ClosedRange<Double>?
    let unit: String

    var body: some View {
        HStack(spacing: 8) {
            Text(metricText(range?.lowerBound, digits: 0))
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.primary)

            LinearGradient(
                colors: (0..<TrackContour.bucketCount).map {
                    TrackContour.color(forNormalized: Double($0) / Double(TrackContour.bucketCount - 1))
                },
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 12)
            .clipShape(Capsule())

            Text(metricText(range?.upperBound, digits: 0))
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.primary)

            Text(unit)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - コンター範囲の設定(自動/手動)を AppStorage から解決する共通ロジック

/// パネル・拡大表示・設定シートで共有するコンター範囲の解決。
/// AppStorage を直接参照するため、各 View で同じキーを @AppStorage 宣言して使う。
enum TrackRangeResolver {
    static func effectiveRange(
        points: [TrackPoint],
        source: TrackColorSource,
        auto: Bool,
        speedMin: Double, speedMax: Double,
        rpmMin: Double, rpmMax: Double
    ) -> ClosedRange<Double>? {
        if auto {
            return TrackContour.valueRange(points, source: source)
        }
        let lower: Double
        let upper: Double
        switch source {
        case .speed: lower = speedMin; upper = speedMax
        case .rpm: lower = rpmMin; upper = rpmMax
        }
        guard upper > lower else { return lower...(lower + 0.001) }
        return lower...upper
    }
}

// MARK: - 範囲・地図の向き設定シート

struct TrackMapSettingsView: View {
    let source: TrackColorSource

    @Environment(\.dismiss) private var dismiss
    @AppStorage("trackMap.rangeAuto") private var rangeAuto = true
    @AppStorage("trackMap.speedMin") private var speedMin = 0.0
    @AppStorage("trackMap.speedMax") private var speedMax = 120.0
    @AppStorage("trackMap.rpmMin") private var rpmMin = 0.0
    @AppStorage("trackMap.rpmMax") private var rpmMax = 8000.0
    @AppStorage("trackMap.headingUp") private var headingUp = true

    var body: some View {
        NavigationStack {
            Form {
                Section("コンターの範囲") {
                    Toggle("自動(実測の最小〜最大)", isOn: $rangeAuto)

                    if !rangeAuto {
                        rangeStepper(title: String(localized: "最小 (\(source.unit))"), value: minBinding)
                        rangeStepper(title: String(localized: "最大 (\(source.unit))"), value: maxBinding)
                    }
                }

                Section {
                    Toggle("進行方向を上にする", isOn: $headingUp)
                } header: {
                    Text("地図の向き")
                } footer: {
                    Text("オフにすると常に北が上になります。")
                }
            }
            .navigationTitle("走行マップ設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }
                }
            }
        }
    }

    private func rangeStepper(title: String, value: Binding<Double>) -> some View {
        Stepper(value: value, in: 0...100_000, step: source.manualStep) {
            HStack {
                Text(verbatim: title)
                Spacer()
                Text(metricText(value.wrappedValue, digits: 0))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private var minBinding: Binding<Double> {
        switch source {
        case .speed: return $speedMin
        case .rpm: return $rpmMin
        }
    }

    private var maxBinding: Binding<Double> {
        switch source {
        case .speed: return $speedMax
        case .rpm: return $rpmMax
        }
    }
}

// MARK: - DriveView 内のパネル

struct TrackMapPanel: View {
    @ObservedObject private var track = TrackStore.shared
    @AppStorage("trackMap.colorSource") private var colorSourceRaw = TrackColorSource.speed.rawValue
    @AppStorage("trackMap.style") private var mapStyleRaw = TrackMapStyleOption.standard.rawValue
    @AppStorage("trackMap.rangeAuto") private var rangeAuto = true
    @AppStorage("trackMap.speedMin") private var speedMin = 0.0
    @AppStorage("trackMap.speedMax") private var speedMax = 120.0
    @AppStorage("trackMap.rpmMin") private var rpmMin = 0.0
    @AppStorage("trackMap.rpmMax") private var rpmMax = 8000.0
    @State private var showingExpanded = false
    @State private var showingClearConfirmation = false
    @State private var showingSettings = false

    private var colorSource: TrackColorSource {
        TrackColorSource(rawValue: colorSourceRaw) ?? .speed
    }

    private var styleOption: TrackMapStyleOption {
        TrackMapStyleOption(rawValue: mapStyleRaw) ?? .standard
    }

    private var effectiveRange: ClosedRange<Double>? {
        TrackRangeResolver.effectiveRange(
            points: track.points, source: colorSource, auto: rangeAuto,
            speedMin: speedMin, speedMax: speedMax, rpmMin: rpmMin, rpmMax: rpmMax
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("走行マップ", systemImage: "map")
                    .font(.headline)

                Spacer()

                Menu {
                    Picker("地図", selection: $mapStyleRaw) {
                        ForEach(TrackMapStyleOption.allCases) { option in
                            Text(LocalizedStringKey(option.rawValue)).tag(option.rawValue)
                        }
                    }
                } label: {
                    Label(LocalizedStringKey(styleOption.rawValue), systemImage: "globe.asia.australia")
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    showingSettings = true
                } label: {
                    Label("設定", systemImage: "gearshape")
                        .labelStyle(.iconOnly)
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    showingExpanded = true
                } label: {
                    Label("拡大", systemImage: "arrow.up.left.and.arrow.down.right")
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(track.points.count < 2)

                Button("消去") {
                    showingClearConfirmation = true
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(track.points.isEmpty)
            }

            Picker("色分け", selection: $colorSourceRaw) {
                ForEach(TrackColorSource.allCases) { source in
                    Text(LocalizedStringKey(source.rawValue)).tag(source.rawValue)
                }
            }
            .pickerStyle(.segmented)

            if track.points.count < 2 {
                VStack(spacing: 8) {
                    Image(systemName: "location.magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("走行するとここに軌跡が描かれます(GPS 必須)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                Map(initialPosition: .automatic, interactionModes: []) {
                    TrackMapContent(points: track.points, colorSource: colorSource, range: effectiveRange)
                }
                .mapStyle(styleOption.mapStyle)
                .frame(height: 280)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .id(mapRefreshKey)
                .overlay {
                    // パネルの小さい地図はプレビュー扱い。タップで拡大表示へ
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { showingExpanded = true }
                }

                TrackLegend(range: effectiveRange, unit: colorSource.unit)
            }
        }
        .panelStyle()
        .fullScreenCover(isPresented: $showingExpanded) {
            TrackMapExpandedView()
        }
        .sheet(isPresented: $showingSettings) {
            TrackMapSettingsView(source: colorSource)
        }
        .alert("軌跡を消去しますか?", isPresented: $showingClearConfirmation) {
            Button("消去", role: .destructive) {
                track.clear()
            }
            Button("キャンセル", role: .cancel) {}
        }
    }

    // プレビュー地図の再構築は点数の増分で間引く(全体表示のカメラを追従させるため)
    private var mapRefreshKey: Int {
        track.points.count / 10
    }
}

// MARK: - 拡大(フルスクリーン)表示

/// 走行マップの拡大表示。自由にパン/ズームでき、「追従」をオンにすると
/// 現在位置を中心に固定表示し続ける(車載での常時表示向け。画面は自動でスリープしない)。
struct TrackMapExpandedView: View {
    @ObservedObject private var track = TrackStore.shared
    @Environment(\.dismiss) private var dismiss
    @AppStorage("trackMap.colorSource") private var colorSourceRaw = TrackColorSource.speed.rawValue
    @AppStorage("trackMap.style") private var mapStyleRaw = TrackMapStyleOption.standard.rawValue
    @AppStorage("trackMap.follow") private var isFollowing = true
    @AppStorage("trackMap.headingUp") private var headingUp = true
    @AppStorage("trackMap.rangeAuto") private var rangeAuto = true
    @AppStorage("trackMap.speedMin") private var speedMin = 0.0
    @AppStorage("trackMap.speedMax") private var speedMax = 120.0
    @AppStorage("trackMap.rpmMin") private var rpmMin = 0.0
    @AppStorage("trackMap.rpmMax") private var rpmMax = 8000.0
    @State private var cameraPosition: MapCameraPosition = .automatic
    /// 追従中に維持するズーム距離(ユーザーのピンチ操作を記憶して上書きされないようにする)
    @State private var followDistance: CLLocationDistance = 1200
    @State private var showingSettings = false

    private var colorSource: TrackColorSource {
        TrackColorSource(rawValue: colorSourceRaw) ?? .speed
    }

    private var styleOption: TrackMapStyleOption {
        TrackMapStyleOption(rawValue: mapStyleRaw) ?? .standard
    }

    private var effectiveRange: ClosedRange<Double>? {
        TrackRangeResolver.effectiveRange(
            points: track.points, source: colorSource, auto: rangeAuto,
            speedMin: speedMin, speedMax: speedMax, rpmMin: rpmMin, rpmMax: rpmMax
        )
    }

    var body: some View {
        ZStack {
            Map(position: $cameraPosition) {
                TrackMapContent(points: track.points, colorSource: colorSource, range: effectiveRange, lineWidth: 11)
            }
            .mapStyle(styleOption.mapStyle)
            .ignoresSafeArea()
            // ユーザーのピンチズームを記憶し、追従の再センタリングでズームを保持する
            .onMapCameraChange(frequency: .continuous) { context in
                followDistance = context.camera.distance
            }

            controlsOverlay
        }
        .onAppear {
            if isFollowing {
                followLatestPoint(animated: false)
            }
        }
        .onChange(of: track.points.count) { _, _ in
            if isFollowing {
                followLatestPoint(animated: true)
            }
        }
        .onChange(of: headingUp) { _, _ in
            if isFollowing {
                followLatestPoint(animated: true)
            }
        }
        .sheet(isPresented: $showingSettings) {
            TrackMapSettingsView(source: colorSource)
        }
    }

    private var controlsOverlay: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                circleButton("xmark") { dismiss() }

                Spacer()

                circleButton("gearshape") { showingSettings = true }

                // 北向き / 進行方向の即時トグル
                circleButton(headingUp ? "location.north.line.fill" : "safari") {
                    headingUp.toggle()
                }
            }

            HStack(spacing: 10) {
                Picker("色分け", selection: $colorSourceRaw) {
                    ForEach(TrackColorSource.allCases) { source in
                        Text(LocalizedStringKey(source.rawValue)).tag(source.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                Picker("地図", selection: $mapStyleRaw) {
                    ForEach(TrackMapStyleOption.allCases) { option in
                        Text(LocalizedStringKey(option.rawValue)).tag(option.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))

            Spacer()

            TrackLegend(range: effectiveRange, unit: colorSource.unit)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))

            HStack(spacing: 12) {
                Button {
                    isFollowing.toggle()
                    if isFollowing {
                        followLatestPoint(animated: true)
                    }
                } label: {
                    Label(isFollowing ? "追従中" : "追従", systemImage: "location.fill")
                        .font(.body.weight(.semibold))
                        .frame(minHeight: 30)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(
                            isFollowing ? AnyShapeStyle(.blue) : AnyShapeStyle(.regularMaterial),
                            in: Capsule()
                        )
                        .foregroundStyle(isFollowing ? .white : .primary)
                }

                Button {
                    isFollowing = false
                    withAnimation {
                        cameraPosition = .automatic
                    }
                } label: {
                    Label("全体", systemImage: "arrow.down.right.and.arrow.up.left")
                        .font(.body.weight(.semibold))
                        .frame(minHeight: 30)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(.regularMaterial, in: Capsule())
                }

                Spacer()
            }
        }
        .padding()
    }

    private func circleButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.title3)
                .frame(width: 44, height: 44)
                .background(.regularMaterial, in: Circle())
        }
    }

    private func followLatestPoint(animated: Bool) {
        guard let last = track.points.last else { return }
        let heading = headingUp ? (TrackContour.bearingOfTravel(track.points) ?? 0) : 0
        let camera = MapCamera(
            centerCoordinate: last.coordinate,
            distance: followDistance,
            heading: heading,
            pitch: 0
        )
        if animated {
            withAnimation(.easeInOut(duration: 0.5)) {
                cameraPosition = .camera(camera)
            }
        } else {
            cameraPosition = .camera(camera)
        }
    }
}
