//
//  HUDView.swift
//  car_ui
//
//  ヘッドアップディスプレイ: フロントガラスに映すための大型速度表示。
//  ミラー反転トグル付き。夜間の反射視認性のため緑基調・黒背景。
//

import SwiftUI

struct HUDView: View {
    @EnvironmentObject private var obd: ELM327BluetoothModel
    @EnvironmentObject private var location: LocationModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("hud.mirrored") private var mirrored = false
    @State private var showsControls = true

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
    }

    private var hudContent: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 4) {
                Text(metricText(currentSpeed, digits: 0))
                    .font(.system(size: 170, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .foregroundStyle(hudColor)

                Text("km/h")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(hudColor.opacity(0.7))
            }

            if let rpm = obd.liveValues[0x0C] {
                VStack(spacing: 6) {
                    Gauge(value: min(max(rpm, 0), 8000), in: 0...8000) {
                        EmptyView()
                    }
                    .gaugeStyle(.linearCapacity)
                    .tint(rpm > 6000 ? .red : hudColor)

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
