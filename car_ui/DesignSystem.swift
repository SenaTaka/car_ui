//
//  DesignSystem.swift
//  car_ui
//
//  アプリ全体のデザイントークン(色の役割・角丸・余白・タイポ・状態色)。
//  UIレビュー(3章・15章)の「画面ごとに独立設計で不統一」への対応。
//  画面はここを参照し、独自のグレーや角丸・余白を散在させない。
//

import SwiftUI
import UIKit

enum DS {
    // MARK: - 色の役割(意味を固定する)

    enum Role {
        /// 選択状態・GPS・主要アクション
        static let accent = Color.blue
        /// RPM・エンジン系
        static let engine = Color.orange
        /// 正常・接続済み
        static let ok = Color.green
        /// 注意
        static let warn = Color.yellow
        /// 警告・停止・異常
        static let danger = Color.red
        /// 加速度・G
        static let motion = Color.purple
        /// 無効・未取得
        static let disabled = Color.secondary
    }

    // MARK: - 角丸(大/小/カプセルは Capsule() を直接使う)

    enum Radius {
        static let card: CGFloat = 16
        static let control: CGFloat = 12
        static let small: CGFloat = 10
    }

    // MARK: - 余白(8pt グリッド)

    enum Space {
        static let screenH: CGFloat = 16
        static let cardGap: CGFloat = 14
        static let cardPadding: CGFloat = 16
        static let section: CGFloat = 24
        static let tight: CGFloat = 8
    }

    // MARK: - 最小タップ領域(HIG 44pt)

    static let minTapTarget: CGFloat = 44

    // MARK: - データ鮮度(古い値のグレー化しきい値)

    /// この秒数を超えて更新されない値は「古い」とみなす
    static let staleThreshold: TimeInterval = 5
}

// MARK: - カードスタイル(Primary / Data / Control の 3 種)

extension View {
    /// データ表示カード(標準)。既存 panelStyle と同義でトークン参照に統一。
    func dataCard() -> some View {
        self
            .padding(DS.Space.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: DS.Radius.card))
    }

    /// 最小タップ領域を保証する(小さいアイコンボタン等に付与)
    func minTapTarget() -> some View {
        self.frame(minWidth: DS.minTapTarget, minHeight: DS.minTapTarget)
    }
}
