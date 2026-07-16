//
//  SessionBar.swift
//  car_ui
//
//  主要画面上部の共通ステータスバー(レビュー 1-3・13章)。
//  記録中か・記録時間・距離・GPS品質・OBD接続を一目で示す。
//

import Combine
import SwiftUI

struct SessionBar: View {
    @ObservedObject private var session = DriveSessionManager.shared
    @EnvironmentObject private var obd: ELM327BluetoothModel
    @EnvironmentObject private var location: LocationModel

    /// 1 秒ごとに経過時間表示を更新するためのタイマ
    @State private var now = Date()
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 10) {
            if session.isRecording {
                recordingContent
            } else {
                idleContent
            }
        }
        .font(.caption)
        .padding(.horizontal, DS.Space.screenH)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .onReceive(ticker) { now = $0 }
    }

    private var recordingContent: some View {
        HStack(spacing: 12) {
            HStack(spacing: 5) {
                Circle().fill(DS.Role.danger).frame(width: 8, height: 8)
                Text("記録中").fontWeight(.semibold)
            }
            .foregroundStyle(DS.Role.danger)

            Text(session.elapsedText(now: now))
                .monospacedDigit()
            Text("\(metricText(session.sessionDistanceKm, digits: 1)) km")
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Spacer(minLength: 4)

            statusChips

            Button {
                session.stop()
            } label: {
                Text("停止").fontWeight(.semibold)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(DS.Role.danger)
        }
    }

    private var idleContent: some View {
        HStack(spacing: 12) {
            Text("記録していません")
                .foregroundStyle(.secondary)

            Spacer(minLength: 4)

            statusChips

            Button {
                session.start(distanceKm: location.totalDistanceKm)
            } label: {
                Text("記録を開始").fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }

    /// GPS 品質・OBD 接続の小チップ(色+テキストで状態を明示)
    private var statusChips: some View {
        HStack(spacing: 8) {
            Label {
                Text(location.quality.label)
            } icon: {
                Image(systemName: "location.fill")
            }
            .foregroundStyle(location.quality.color)

            Label {
                Text(obd.phase.isConnected ? "OBD" : "未接続")
            } icon: {
                Image(systemName: obd.phase.isConnected ? "cpu.fill" : "cpu")
            }
            .foregroundStyle(obd.phase.isConnected ? DS.Role.ok : DS.Role.disabled)
        }
        .font(.caption2.weight(.semibold))
        .labelStyle(.titleAndIcon)
    }
}
