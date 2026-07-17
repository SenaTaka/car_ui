//
//  StatusBanner.swift
//  car_ui
//
//  各種状態(未接続 / Bluetooth無効 / 権限なし / GPS拒否 / 精度低 /
//  データ更新停止 / ストレージ不足 など)を明示するバナー(レビュー 13章)。
//  「正常時しか設計されていない」問題への対応。値が古い・取れない状況を
//  黙って前回値のまま見せない。
//

import SwiftUI

/// 重大度で色を分けるインライン状態バナー
struct StatusBanner: View {
    enum Level {
        case info, warning, error

        var color: Color {
            switch self {
            case .info: return DS.Role.accent
            case .warning: return DS.Role.warn
            case .error: return DS.Role.danger
            }
        }
        var icon: String {
            switch self {
            case .info: return "info.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .error: return "xmark.octagon.fill"
            }
        }
    }

    let level: Level
    let title: LocalizedStringKey
    var message: LocalizedStringKey? = nil
    var actionTitle: LocalizedStringKey? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: level.icon)
                .foregroundStyle(level.color)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                if let message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 4)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(level.color.opacity(0.1), in: RoundedRectangle(cornerRadius: DS.Radius.control))
    }
}
