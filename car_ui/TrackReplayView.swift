//
//  TrackReplayView.swift
//  car_ui
//
//  走行の再生・スクラブ(レビュー 10-4)。タイムラインを動かすと、
//  地図上の位置マーカーとチャートの垂直カーソルが同じ時刻で連動する。
//  「軌跡は見えるが時系列の位置を追えない」問題への対応。
//

import Charts
import Combine
import MapKit
import SwiftUI

struct TrackReplayView: View {
    @ObservedObject private var track = TrackStore.shared

    /// スクラブ位置(points の添字)
    @State private var index: Double = 0
    @State private var isPlaying = false
    @State private var cameraPosition: MapCameraPosition = .automatic
    private let ticker = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()

    private var points: [TrackPoint] { track.points }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("走行リプレイ", systemImage: "play.rectangle")
                .font(.headline)

            if points.count < 2 {
                Text("走行するとここで再生・スクラブできます(GPS 必須)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                replayMap
                replayChart
                transportControls
                currentReadout
            }
        }
        .dataCard()
        .onReceive(ticker) { _ in advanceIfPlaying() }
        .onAppear { index = Double(points.count - 1) }
    }

    private var currentIndex: Int {
        min(max(Int(index.rounded()), 0), points.count - 1)
    }

    private var current: TrackPoint { points[currentIndex] }

    // MARK: - 地図(現在位置マーカー)

    private var replayMap: some View {
        Map(position: $cameraPosition, interactionModes: [.pan, .zoom]) {
            MapPolyline(coordinates: points.map(\.coordinate))
                .stroke(.blue.opacity(0.35), style: StrokeStyle(lineWidth: 6, lineCap: .round))

            Annotation("", coordinate: current.coordinate) {
                ZStack {
                    Circle().fill(.blue).frame(width: 16, height: 16)
                    Circle().stroke(.white, lineWidth: 3).frame(width: 16, height: 16)
                }
            }
        }
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.control))
        .onChange(of: currentIndex) { _, _ in recenter() }
    }

    // MARK: - チャート(速度/回転数 + 垂直カーソル)

    private var replayChart: some View {
        Chart {
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                if let speed = point.speedKPH {
                    LineMark(x: .value("時刻", point.time),
                             y: .value("値", speed),
                             series: .value("系列", "速度"))
                        .foregroundStyle(.blue)
                }
                if let rpm = point.rpm {
                    LineMark(x: .value("時刻", point.time),
                             y: .value("値", rpm / 100),  // rpm は 1/100 スケールで重ねる
                             series: .value("系列", "回転数"))
                        .foregroundStyle(.orange)
                }
            }

            // スクラブ位置の垂直カーソル
            RuleMark(x: .value("現在", current.time))
                .foregroundStyle(.primary.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
        .chartLegend(.hidden)
        .chartYAxis(.hidden)
        .frame(height: 90)
    }

    // MARK: - 再生コントロール + スクラブ

    private var transportControls: some View {
        HStack(spacing: 14) {
            Button {
                isPlaying.toggle()
                if isPlaying, currentIndex >= points.count - 1 { index = 0 }
            } label: {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title)
                    .foregroundStyle(.blue)
            }
            .minTapTarget()

            Slider(value: $index, in: 0...Double(points.count - 1), step: 1)
                .onChange(of: index) { _, _ in isPlaying = false }
                .accessibilityLabel("再生位置")
        }
    }

    private var currentReadout: some View {
        HStack(spacing: 16) {
            Text(current.time, format: .dateTime.hour().minute().second())
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            if let speed = current.speedKPH {
                MetricValue(value: speed, unit: "km/h", digits: 0, valueFont: .subheadline, color: .blue)
            }
            if let rpm = current.rpm {
                MetricValue(value: rpm, unit: "rpm", digits: 0, valueFont: .subheadline, color: .orange)
            }
            Spacer()
        }
    }

    private func advanceIfPlaying() {
        guard isPlaying, points.count >= 2 else { return }
        if currentIndex >= points.count - 1 {
            isPlaying = false
        } else {
            index = min(index + 1, Double(points.count - 1))
        }
    }

    private func recenter() {
        let region = MKCoordinateRegion(center: current.coordinate,
                                        latitudinalMeters: 500, longitudinalMeters: 500)
        withAnimation(.easeInOut(duration: 0.2)) {
            cameraPosition = .region(region)
        }
    }
}
