//
//  HUDView.swift
//  car_ui
//
//  ヘッドアップディスプレイ: フロントガラスに映すための大型速度表示。
//  ミラー反転トグル付き。夜間の反射視認性のため緑基調・黒背景。
//

import SwiftUI
import UIKit

/// 画面スリープ防止の調停役(監査 B-4)。
///
/// ContentView は「前面 + OBD 接続中 + 設定オン」でしかスリープを止めない。
/// ところが HUD は GPS 速度だけでも動くので、アダプタ無しで HUD を使うと
/// 走行中に画面が消えていた。HUD 表示中はこのフラグで無条件に点灯を維持する。
@Observable
final class ScreenWakeCoordinator {
    static let shared = ScreenWakeCoordinator()
    private init() {}

    /// HUD 表示中か。ContentView の updateScreenWake がこれを見る。
    var hudIsPresented = false
}

struct HUDView: View {
    @EnvironmentObject private var obd: ELM327BluetoothModel
    @EnvironmentObject private var location: LocationModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("hud.mirrored") private var mirrored = false
    @State private var showsControls = true
    /// HUD を出る時に戻すための元の画面輝度
    @State private var previousBrightness: CGFloat?

    private let hudColor = Color(red: 0.35, green: 1.0, blue: 0.45)

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            // 表示コンテンツのみ反転(操作ボタンは反転させない)
            hudContent
                .scaleEffect(x: mirrored ? -1 : 1, y: 1)

            if showsControls {
                controls
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                showsControls.toggle()
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        // 監査 B-4: HUD は GPS 速度だけでも動くので、OBD 接続の有無に関係なく点灯を維持する
        .onAppear {
            ScreenWakeCoordinator.shared.hudIsPresented = true
            UIApplication.shared.isIdleTimerDisabled = true
            // フロントガラスへの反射で読むため、表示中だけ輝度を上げて離脱時に戻す
            if let screen = activeScreen {
                previousBrightness = screen.brightness
                screen.brightness = 1.0
            }
        }
        .onDisappear {
            ScreenWakeCoordinator.shared.hudIsPresented = false
            if let previousBrightness, let screen = activeScreen {
                screen.brightness = previousBrightness
            }
        }
    }

    /// `UIScreen.main` は iOS 26 で非推奨。表示中のシーンから画面を取る。
    private var activeScreen: UIScreen? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .screen
    }

    private var hudContent: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 4) {
                Text(unitText(currentSpeed, kind: .speed, digits: 0))
                    .font(.system(size: 170, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .foregroundStyle(hudColor)

                Text(UnitKind.speed.symbol(UnitSettings.shared.system))
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(hudColor.opacity(0.7))
            }

            if let rpm = obd.liveValues[0x0C] {
                // 監査 B-5: 上限・レッドラインは車両プロファイル由来(旧: 8000/6000 固定)
                let vehicle = VehicleProfile.shared
                VStack(spacing: 6) {
                    Gauge(value: min(max(rpm, 0), vehicle.maxRpm), in: 0...vehicle.maxRpm) {
                        EmptyView()
                    }
                    .gaugeStyle(.linearCapacity)
                    .tint(vehicle.isOverRedline(rpm) ? .red : hudColor)

                    Text("\(metricText(rpm, digits: 0)) rpm")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(hudColor.opacity(0.7))
                }
                .padding(.horizontal, 40)
            }

            Spacer()
        }
        .padding()
    }

    private var controls: some View {
        VStack {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(12)
                        .background(.white.opacity(0.12), in: Circle())
                }
                .accessibilityLabel("閉じる")

                Spacer()

                Button {
                    mirrored.toggle()
                } label: {
                    Label("ミラー反転", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(mirrored ? .black : .white.opacity(0.8))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            mirrored ? AnyShapeStyle(hudColor) : AnyShapeStyle(.white.opacity(0.12)),
                            in: Capsule()
                        )
                }
            }

            Spacer()

            Text("フロントガラスの下に置いて反射で読み取ります。タップで操作ボタンを隠せます。")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.45))
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private var currentSpeed: Double? {
        obd.liveValues[0x0D] ?? location.speedKPH
    }
}
