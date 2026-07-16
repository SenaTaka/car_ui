//
//  AnalysisView.swift
//  car_ui
//
//  「分析」タブ(レビュー 1-1・1-2・2-2)。抽象語「データ」を廃し、
//  ライブ(現在値)/ チャート(時系列)/ マップ(走行軌跡)を明示分離する。
//  停車後に見る画面をここへ集約し、運転中に見るメーター/走行と分ける。
//

import SwiftUI

struct AnalysisView: View {
    @AppStorage("analysisSection") private var section = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("表示", selection: $section) {
                Text("ライブ").tag(0)
                Text("チャート").tag(1)
                Text("マップ").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, DS.Space.screenH)
            .padding(.vertical, 6)
            .background(Color(.systemGroupedBackground))

            switch section {
            case 0: SensorsView()
            case 1: ChartsView()
            default: MapAnalysisView()
            }
        }
        .background(Color(.systemGroupedBackground))
    }
}

/// マップ セグメント: 走行軌跡をコンター表示(拡大でフル操作)。
private struct MapAnalysisView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DS.Space.cardGap) {
                    TrackMapPanel()
                }
                .padding()
                // タブバー被り回避(レビュー 2-2)
                .padding(.bottom, 72)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("走行マップ")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
