//
//  TelemetryRecorder.swift
//  car_ui
//
//  全センサーチャンネル(OBD / GPS / 加速度計)の時系列を常時記録する。
//  値の追加は高頻度でも、SwiftUI への通知は 0.5 秒間隔に間引く。
//

import Combine
import SwiftUI
import UniformTypeIdentifiers

struct TelemetrySample: Identifiable {
    let time: Date
    let value: Double

    var id: Date { time }
}

struct ChannelInfo: Identifiable {
    let id: String
    let name: String
    let unit: String
    let icon: String
    let tint: Color
    let fractionDigits: Int

    static func info(for channelID: String) -> ChannelInfo {
        if let pid = PIDCatalog.definition(forChannel: channelID) {
            return ChannelInfo(
                id: channelID,
                name: pid.name,
                unit: pid.unit,
                icon: pid.icon,
                tint: pid.tint,
                fractionDigits: pid.fractionDigits
            )
        }
        return builtins[channelID] ?? ChannelInfo(
            id: channelID,
            name: channelID,
            unit: "",
            icon: "questionmark.circle",
            tint: .gray,
            fractionDigits: 1
        )
    }

    private static let builtins: [String: ChannelInfo] = [
        "meta.voltage": ChannelInfo(id: "meta.voltage", name: "アダプタ電圧", unit: "V", icon: "bolt.fill", tint: .yellow, fractionDigits: 2),
        "gps.speed": ChannelInfo(id: "gps.speed", name: "車速 (GPS)", unit: "km/h", icon: "location.fill", tint: .blue, fractionDigits: 1),
        "gps.altitude": ChannelInfo(id: "gps.altitude", name: "高度 (GPS)", unit: "m", icon: "mountain.2", tint: .brown, fractionDigits: 1),
        "gps.course": ChannelInfo(id: "gps.course", name: "方位 (GPS)", unit: "°", icon: "safari", tint: .cyan, fractionDigits: 0),
        "gps.distance": ChannelInfo(id: "gps.distance", name: "走行距離 (GPS)", unit: "km", icon: "road.lanes", tint: .green, fractionDigits: 2),
        "motion.gx": ChannelInfo(id: "motion.gx", name: "横 G", unit: "G", icon: "arrow.left.and.right", tint: .pink, fractionDigits: 2),
        "motion.gy": ChannelInfo(id: "motion.gy", name: "前後 G", unit: "G", icon: "arrow.up.and.down", tint: .orange, fractionDigits: 2),
        "motion.gmag": ChannelInfo(id: "motion.gmag", name: "合成 G", unit: "G", icon: "circle.dotted.circle", tint: .purple, fractionDigits: 2),
    ]
}

final class TelemetryRecorder: ObservableObject {
    static let shared = TelemetryRecorder()

    /// 無料版の CSV エクスポート上限(チャンネルごとの直近サンプル数)。Pro は無制限
    /// (実質は maxSamplesPerChannel のリングバッファ全量)。
    static let freeExportRowLimit = 500

    // チャート・スパークラインの再描画トリガ(0.5 秒間隔に間引き)
    @Published private(set) var revision = 0

    private(set) var channelIDs: [String] = []
    private var storage: [String: [TelemetrySample]] = [:]
    private var lastPublish = Date.distantPast

    private let maxSamplesPerChannel = 3600

    var startDate: Date? {
        storage.values.compactMap { $0.first?.time }.min()
    }

    var totalSampleCount: Int {
        storage.values.reduce(0) { $0 + $1.count }
    }

    func record(_ channelID: String, value: Double, at time: Date = Date()) {
        guard value.isFinite else { return }

        if storage[channelID] == nil {
            storage[channelID] = []
            channelIDs.append(channelID)
            channelIDs.sort()
        }

        storage[channelID]?.append(TelemetrySample(time: time, value: value))

        if let count = storage[channelID]?.count, count > maxSamplesPerChannel {
            storage[channelID]?.removeFirst(count - maxSamplesPerChannel)
        }

        let now = Date()
        if now.timeIntervalSince(lastPublish) > 0.5 {
            lastPublish = now
            revision += 1
        }
    }

    func latest(_ channelID: String) -> Double? {
        storage[channelID]?.last?.value
    }

    func samples(_ channelID: String, since: Date? = nil) -> [TelemetrySample] {
        guard let all = storage[channelID] else { return [] }
        guard let since else { return all }
        if let startIndex = all.firstIndex(where: { $0.time >= since }) {
            return Array(all[startIndex...])
        }
        return []
    }

    func clear() {
        storage = [:]
        channelIDs = []
        revision += 1
    }

    // MARK: - CSV エクスポート(long 形式: channel,name,unit,time,value)

    /// `rowLimit` が nil なら全量(Pro)、指定時はチャンネルごとに直近 N 件のみ(無料版)。
    func csvData(for channelIDs: [String], rowLimit: Int? = nil) -> Data {
        var lines = ["channel,name,unit,time,value"]
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        for channelID in channelIDs {
            let info = ChannelInfo.info(for: channelID)
            let allSamples = storage[channelID] ?? []
            let samples = rowLimit.map { Array(allSamples.suffix($0)) } ?? allSamples
            for sample in samples {
                let value = String(format: "%.\(info.fractionDigits)f", sample.value)
                lines.append("\(channelID),\(info.name),\(info.unit),\(formatter.string(from: sample.time)),\(value)")
            }
        }

        return Data(lines.joined(separator: "\n").utf8)
    }
}

struct TelemetryCSV: Transferable {
    let channelIDs: [String]
    /// Pro なら無制限、無料版は `TelemetryRecorder.freeExportRowLimit` 件/ch に切り詰める。
    let isPro: Bool

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { export in
            let limit = export.isPro ? nil : TelemetryRecorder.freeExportRowLimit
            return TelemetryRecorder.shared.csvData(for: export.channelIDs, rowLimit: limit)
        }
        .suggestedFileName("telemetry.csv")
    }
}
