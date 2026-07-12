import SwiftUI

/// センサーとチャートを 1 タブに統合するラッパー(タブ 5 個維持のため)。
/// SensorsView / ChartsView は各自 NavigationStack を持つので、ここでは持たない。
/// 切替で View は破棄されるが、チャートのデータ源は TelemetryRecorder.shared
/// なので記録は途切れない。
struct DataView: View {
    @AppStorage("dataTabSection") private var section = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("表示", selection: $section) {
                Text("センサー").tag(0)
                Text("チャート").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(Color(.systemGroupedBackground))

            if section == 0 {
                SensorsView()
            } else {
                ChartsView()
            }
        }
        .background(Color(.systemGroupedBackground))
    }
}

#Preview {
    DataView()
        .environmentObject(ELM327BluetoothModel())
        .environmentObject(TelemetryRecorder.shared)
}
