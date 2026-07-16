//
//  DriveRecordsView.swift
//  car_ui
//
//  保存済みドライブ記録(0-100 加速スプリット + G ピーク)の一覧・詳細・
//  削除・共有(監査 REL-005 対応: Pro 特典「記録の保存」の閲覧画面)。
//

import SwiftUI

struct DriveRecordsView: View {
    let store: DriveRecordStore

    var body: some View {
        Group {
            if store.records.isEmpty {
                ContentUnavailableView(
                    "保存済み記録はありません",
                    systemImage: "flag.checkered",
                    description: Text("0-100 km/h 計測の完了後に「記録を保存」(Pro)で追加されます。")
                )
            } else {
                List {
                    ForEach(store.records) { record in
                        NavigationLink {
                            DriveRecordDetailView(record: record, isBest: isBest(record))
                        } label: {
                            recordRow(record)
                        }
                    }
                    .onDelete { offsets in
                        store.delete(atOffsets: offsets)
                    }
                }
            }
        }
        .navigationTitle("保存済み記録")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !store.records.isEmpty {
                EditButton()
            }
        }
    }

    private func isBest(_ record: DriveRecord) -> Bool {
        guard let best = store.bestZeroToHundred,
              let time = record.splits.first(where: { $0.targetKPH == 100 })?.seconds else {
            return false
        }
        return time == best
    }

    private func recordRow(_ record: DriveRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(record.date, format: .dateTime.year().month().day().hour().minute())
                    .font(.subheadline.weight(.semibold))

                if isBest(record) {
                    Text("ベスト")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.green.opacity(0.15), in: Capsule())
                        .foregroundStyle(.green)
                }
            }

            HStack(spacing: 12) {
                if let time = record.splits.first(where: { $0.targetKPH == 100 })?.seconds {
                    Label("0-100: \(metricText(time, digits: 2)) 秒", systemImage: "flag.checkered")
                } else if let last = record.splits.last {
                    Label("0-\(last.targetKPH): \(metricText(last.seconds, digits: 2)) 秒", systemImage: "flag")
                }
                Label("\(metricText(record.peakG, digits: 2)) G", systemImage: "circle.dotted.circle")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

struct DriveRecordDetailView: View {
    let record: DriveRecord
    let isBest: Bool

    var body: some View {
        List {
            Section("スプリット") {
                ForEach(record.splits, id: \.targetKPH) { split in
                    HStack {
                        Text("0-\(split.targetKPH) km/h")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(metricText(split.seconds, digits: 2)) 秒")
                            .font(.subheadline.weight(.bold).monospacedDigit())
                    }
                }
            }

            Section("G フォース") {
                HStack {
                    Text("ピーク")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(metricText(record.peakG, digits: 2)) G")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                }
            }

            if isBest {
                Section {
                    Label("この記録が 0-100 km/h のベストタイムです", systemImage: "trophy")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                }
            }
        }
        .navigationTitle(record.date.formatted(.dateTime.month().day().hour().minute()))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ShareLink(item: shareText) {
                Label("共有", systemImage: "square.and.arrow.up")
            }
        }
    }

    private var shareText: String {
        var lines = ["car_ui 加速計測 \(record.date.formatted(.dateTime.year().month().day().hour().minute()))"]
        lines += record.splits.map { "0-\($0.targetKPH) km/h: \(metricText($0.seconds, digits: 2)) 秒" }
        lines.append("ピーク G: \(metricText(record.peakG, digits: 2)) G")
        return lines.joined(separator: "\n")
    }
}
