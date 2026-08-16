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
        // 監査 D-5: 以前は各セグメントが独自の NavigationStack を持ち、
        // セグメントがナビゲーションバーの**上**に積まれて階層表現が上下逆だった。
        // 監査 C-1: タブ名「分析」に対しセグメントごとに別のタイトル
        // (センサー / 走行マップ)が出ていたので、セグメント自体を見出しにする。
        NavigationStack {
            Group {
                switch section {
                case 0: SensorsView()
                case 1: ChartsView()
                default: MapAnalysisView()
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("表示", selection: $section) {
                        Text("ライブ").tag(0)
                        Text("チャート").tag(1)
                        Text("マップ").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 320)
                }
            }
        }
    }
}

/// マップ セグメント: 走行軌跡をコンター表示(拡大でフル操作)。
private struct MapAnalysisView: View {
    @EnvironmentObject private var location: LocationModel

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Space.cardGap) {
                TrackMapPanel()
                // レビュー 10-4: 地図⇄チャート連動の再生・スクラブ
                TrackReplayView()
            }
            .padding()
            // タブバー被り回避(レビュー 2-2)
            .padding(.bottom, DS.Space.tabBarClearance)
        }
        .background(Color(.systemGroupedBackground))
        // マップ/リプレイは GPS 軌跡が必要。走行タブを開かなくても
        // 分析マップを見たときに測位を開始する(そうしないと軌跡が溜まらない)
        .onAppear { location.start() }
    }
}
