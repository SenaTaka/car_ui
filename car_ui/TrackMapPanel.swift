//
//  TrackMapPanel.swift
//  car_ui
//
//  GPS 走行軌跡を地図に描画し、速度または回転数で色分け(コンター)する。
//  DriveView のパネル表示と、拡大(フルスクリーン・追従固定)表示の両方を提供。
//

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
    /// コンターの色分け段数
    static let bucketCount = 10
    /// 点間がこの秒数を超えたら別の走行として線を切る(トンネル・駐車)
    static let segmentGapSeconds: TimeInterval = 60

    struct ColoredSegment: Identifiable {
        let id: Int
        let coordinates: [CLLocationCoordinate2D]
        let color: Color
    }

    static func valueRange(_ points: [TrackPoint], source: TrackColorSource) -> ClosedRange<Double>? {
        let values = points.compactMap { source.value(of: $0) }
        guard let minValue = values.min(), let maxValue = values.max() else { return nil }
        return minValue...max(maxValue, minValue + 0.001)
    }

    /// 連続する点を色バケット単位でまとめ、Polyline の本数を抑える。
    static func segments(_ points: [TrackPoint], source: TrackColorSource) -> [ColoredSegment] {
        guard points.count >= 2 else { return [] }
        let range = valueRange(points, source: source)

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
        let t = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        return min(bucketCount - 1, max(0, Int(t * Double(bucketCount))))
    }

    /// 0(遅い/低回転)= 青 → 1(速い/高回転)= 赤 のヒートマップ配色
    static func color(forNormalized t: Double) -> Color {
        Color(hue: 0.66 * (1 - min(max(t, 0), 1)), saturation: 0.9, brightness: 0.9)
    }
}

// MARK: - 共用の地図コンテンツ + 凡例

private struct TrackMapContent: MapContent {
    let points: [TrackPoint]
    let colorSource: TrackColorSource

    var body: some MapContent {
        ForEach(TrackContour.segments(points, source: colorSource)) { segment in
            MapPolyline(coordinates: segment.coordinates)
                .stroke(segment.color, lineWidth: 4)
        }

        if let last = points.last {
            Annotation("現在", coordinate: last.coordinate) {
                Circle()
                    .fill(.blue)
                    .stroke(.white, lineWidth: 2)
                    .frame(width: 12, height: 12)
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
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)

            LinearGradient(
                colors: (0..<TrackContour.bucketCount).map {
                    TrackContour.color(forNormalized: Double($0) / Double(TrackContour.bucketCount - 1))
                },
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 8)
            .clipShape(Capsule())

            Text(metricText(range?.upperBound, digits: 0))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)

            Text(unit)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - DriveView 内のパネル

struct TrackMapPanel: View {
    @ObservedObject private var track = TrackStore.shared
    @AppStorage("trackMap.colorSource") private var colorSourceRaw = TrackColorSource.speed.rawValue
    @AppStorage("trackMap.style") private var mapStyleRaw = TrackMapStyleOption.standard.rawValue
    @State private var showingExpanded = false
    @State private var showingClearConfirmation = false

    private var colorSource: TrackColorSource {
        TrackColorSource(rawValue: colorSourceRaw) ?? .speed
    }

    private var styleOption: TrackMapStyleOption {
        TrackMapStyleOption(rawValue: mapStyleRaw) ?? .standard
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
                            Text(option.rawValue).tag(option.rawValue)
                        }
                    }
                } label: {
                    Label(styleOption.rawValue, systemImage: "globe.asia.australia")
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
                    Text(source.rawValue).tag(source.rawValue)
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
                    TrackMapContent(points: track.points, colorSource: colorSource)
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

                TrackLegend(
                    range: TrackContour.valueRange(track.points, source: colorSource),
                    unit: colorSource.unit
                )
            }
        }
        .panelStyle()
        .fullScreenCover(isPresented: $showingExpanded) {
            TrackMapExpandedView()
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
    @State private var cameraPosition: MapCameraPosition = .automatic

    private var colorSource: TrackColorSource {
        TrackColorSource(rawValue: colorSourceRaw) ?? .speed
    }

    private var styleOption: TrackMapStyleOption {
        TrackMapStyleOption(rawValue: mapStyleRaw) ?? .standard
    }

    var body: some View {
        ZStack {
            Map(position: $cameraPosition) {
                TrackMapContent(points: track.points, colorSource: colorSource)
            }
            .mapStyle(styleOption.mapStyle)
            .ignoresSafeArea()

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
    }

    private var controlsOverlay: some View {
        VStack(spacing: 10) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .padding(12)
                        .background(.regularMaterial, in: Circle())
                }

                Spacer()

                Picker("色分け", selection: $colorSourceRaw) {
                    ForEach(TrackColorSource.allCases) { source in
                        Text(source.rawValue).tag(source.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)
                .padding(6)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            }

            HStack {
                Spacer()

                Picker("地図", selection: $mapStyleRaw) {
                    ForEach(TrackMapStyleOption.allCases) { option in
                        Text(option.rawValue).tag(option.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)
                .padding(6)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            }

            Spacer()

            HStack(spacing: 10) {
                Button {
                    isFollowing.toggle()
                    if isFollowing {
                        followLatestPoint(animated: true)
                    }
                } label: {
                    Label(isFollowing ? "追従中" : "追従", systemImage: "location.fill")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
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
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule())
                }

                Spacer()

                TrackLegend(
                    range: TrackContour.valueRange(track.points, source: colorSource),
                    unit: colorSource.unit
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
                .frame(maxWidth: 240)
            }
        }
        .padding()
    }

    private func followLatestPoint(animated: Bool) {
        guard let last = track.points.last else { return }
        let region = MKCoordinateRegion(
            center: last.coordinate,
            latitudinalMeters: 800,
            longitudinalMeters: 800
        )
        if animated {
            withAnimation(.easeInOut(duration: 0.5)) {
                cameraPosition = .region(region)
            }
        } else {
            cameraPosition = .region(region)
        }
    }
}
