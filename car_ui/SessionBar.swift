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
        // 監査 E-3: 独仏の長い語や大きな文字サイズでは 1 行に収まらないため、
        // 収まるときだけ 1 行、収まらなければ 2 行に折り返す。
        ViewThatFits(in: .horizontal) {
            singleRow
            twoRows
        }
        .font(.caption)
        // 全タブに常設するクロームなので、拡大幅に上限を設ける。
        // 上限なしだと最大文字サイズ(AX5)+ 独語で画面の 4 割を占め、
        // ボタンのラベルが 3 行に折り返して丸く潰れた(2026-08-17 実測)。
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .padding(.horizontal, DS.Space.screenH)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .onReceive(ticker) { now = $0 }
    }

    private var singleRow: some View {
        HStack(spacing: 12) {
            summary
            Spacer(minLength: 4)
            statusChips
            actionButton
        }
    }

    private var twoRows: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                summary
                Spacer(minLength: 4)
                actionButton
            }
            statusChips
        }
    }

    /// 記録中は「記録中・経過・距離」、待機中は「記録していません」
    @ViewBuilder
    private var summary: some View {
        if session.isRecording {
            HStack(spacing: 12) {
                HStack(spacing: 5) {
                    Circle().fill(DS.Role.danger).frame(width: 8, height: 8)
                    Text("記録中").fontWeight(.semibold)
                }
                .foregroundStyle(DS.Role.danger)

                Text(session.elapsedText(now: now))
                    .monospacedDigit()
                Text("\(unitText(session.sessionDistanceKm, kind: .distance, digits: 1)) \(UnitKind.distance.symbol(UnitSettings.shared.system))")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
        } else {
            Text("記録していません")
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        if session.isRecording {
            Button {
                session.stop()
            } label: {
                Text("停止").fontWeight(.semibold).lineLimit(1)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .buttonBorderShape(.capsule)
            .tint(DS.Role.danger)
            .minTapTarget()
        } else {
            Button {
                session.start(distanceKm: location.totalDistanceKm)
            } label: {
                // lineLimit を付けないと大きい文字サイズでラベルが折り返し、
                // ボタンが丸く潰れて何のボタンか読めなくなる
                Text("記録を開始").fontWeight(.semibold).lineLimit(1)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .buttonBorderShape(.capsule)
            .minTapTarget()
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
