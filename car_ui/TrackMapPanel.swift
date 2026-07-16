//
//  TrackMapPanel.swift
//  car_ui
//
//  GPS 走行軌跡を地図に描画し、速度または回転数で色分け(コンター)する。
//  DriveView に配置。
//

import MapKit
import SwiftUI

struct TrackMapPanel: View {
    enum ColorSource: String, CaseIterable, Identifiable {
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

    @ObservedObject private var track = TrackStore.shared
    @State private var colorSource: ColorSource = .speed
    @State private var showingClearConfirmation = false

    /// 点間がこの秒数を超えたら別の走行として線を切る(トンネル・駐車)
    private static let segmentGapSeconds: TimeInterval = 60
    /// コンターの色分け段数
    private static let bucketCount = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("走行マップ", systemImage: "map")
                    .font(.headline)

                Spacer()

                Button("消去") {
                    showingClearConfirmation = true
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(track.points.isEmpty)
            }

            Picker("色分け", selection: $colorSource) {
                ForEach(ColorSource.allCases) { source in
                    Text(source.rawValue).tag(source)
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
                Map(initialPosition: .automatic) {
                    ForEach(coloredSegments) { segment in
                        MapPolyline(coordinates: segment.coordinates)
                            .stroke(segment.color, lineWidth: 4)
                    }

                    if let last = track.points.last {
                        Annotation("現在", coordinate: last.coordinate) {
                            Circle()
                                .fill(.blue)
                                .stroke(.white, lineWidth: 2)
                                .frame(width: 12, height: 12)
                        }
                    }
                }
                .frame(height: 280)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .id(mapRefreshKey)

                legend
            }
        }
        .panelStyle()
        .alert("軌跡を消去しますか?", isPresented: $showingClearConfirmation) {
            Button("消去", role: .destructive) {
                track.clear()
            }
            Button("キャンセル", role: .cancel) {}
        }
    }

    // 地図の再構築は点数の増分で間引く(毎点更新の負荷とカメラ暴れを防ぐ)
    private var mapRefreshKey: Int {
        track.points.count / 10
    }

    private var legend: some View {
        HStack(spacing: 8) {
            Text(metricText(valueRange?.lowerBound, digits: 0))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)

            LinearGradient(
                colors: (0..<Self.bucketCount).map { color(forNormalized: Double($0) / Double(Self.bucketCount - 1)) },
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 8)
            .clipShape(Capsule())

            Text(metricText(valueRange?.upperBound, digits: 0))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)

            Text(colorSource.unit)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 色分けセグメント生成

    private struct ColoredSegment: Identifiable {
        let id: Int
        let coordinates: [CLLocationCoordinate2D]
        let color: Color
    }

    private var valueRange: ClosedRange<Double>? {
        let values = track.points.compactMap { colorSource.value(of: $0) }
        guard let minValue = values.min(), let maxValue = values.max() else { return nil }
        return minValue...max(maxValue, minValue + 0.001)
    }

    /// 連続する点を色バケット単位でまとめ、Polyline の本数を抑える。
    private var coloredSegments: [ColoredSegment] {
        let points = track.points
        guard points.count >= 2 else { return [] }
        let range = valueRange

        var segments: [ColoredSegment] = []
        var currentCoords: [CLLocationCoordinate2D] = [points[0].coordinate]
        var currentBucket = bucket(for: points[0], range: range)
        var segmentID = 0

        for index in 1..<points.count {
            let point = points[index]
            let gap = point.time.timeIntervalSince(points[index - 1].time)

            if gap > Self.segmentGapSeconds {
                appendSegment(&segments, coords: currentCoords, bucket: currentBucket, id: &segmentID)
                currentCoords = [point.coordinate]
                currentBucket = bucket(for: point, range: range)
                continue
            }

            let newBucket = bucket(for: point, range: range)
            if newBucket != currentBucket {
                currentCoords.append(point.coordinate)
                appendSegment(&segments, coords: currentCoords, bucket: currentBucket, id: &segmentID)
                currentCoords = [point.coordinate]
                currentBucket = newBucket
            } else {
                currentCoords.append(point.coordinate)
            }
        }

        appendSegment(&segments, coords: currentCoords, bucket: currentBucket, id: &segmentID)
        return segments
    }

    private func appendSegment(
        _ segments: inout [ColoredSegment],
        coords: [CLLocationCoordinate2D],
        bucket: Int?,
        id: inout Int
    ) {
        guard coords.count >= 2 else { return }
        id += 1
        let segmentColor: Color = bucket.map { self.color(forNormalized: Double($0) / Double(Self.bucketCount - 1)) } ?? .gray
        segments.append(ColoredSegment(id: id, coordinates: coords, color: segmentColor))
    }

    private func bucket(for point: TrackPoint, range: ClosedRange<Double>?) -> Int? {
        guard let range, let value = colorSource.value(of: point) else { return nil }
        let t = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        return min(Self.bucketCount - 1, max(0, Int(t * Double(Self.bucketCount))))
    }

    /// 0(遅い/低回転)= 青 → 1(速い/高回転)= 赤 のヒートマップ配色
    private func color(forNormalized t: Double) -> Color {
        Color(hue: 0.66 * (1 - min(max(t, 0), 1)), saturation: 0.9, brightness: 0.9)
    }
}
