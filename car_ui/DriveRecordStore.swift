//
//  DriveRecordStore.swift
//  car_ui
//
//  0-100 km/h 加速計測 + G フォースピークの保存記録(Pro 限定)。
//  UserDefaults に JSON で永続化する軽量ストア。
//

import Foundation
import Observation

struct DriveRecord: Identifiable, Codable {
    struct Split: Codable {
        let targetKPH: Int
        let seconds: Double
    }

    let id: UUID
    let date: Date
    let splits: [Split]
    let peakG: Double
}

@MainActor
@Observable
final class DriveRecordStore {
    private static let storageKey = "driveRecords.v1"
    private static let maxRecords = 100

    private(set) var records: [DriveRecord] = []

    init() {
        load()
    }

    @discardableResult
    func save(splits: [AccelTestModel.Split], peakG: Double) -> DriveRecord {
        let record = DriveRecord(
            id: UUID(),
            date: Date(),
            splits: splits.map { DriveRecord.Split(targetKPH: $0.targetKPH, seconds: $0.seconds) },
            peakG: peakG
        )
        records.insert(record, at: 0)
        if records.count > Self.maxRecords {
            records.removeLast(records.count - Self.maxRecords)
        }
        persist()
        return record
    }

    func delete(atOffsets offsets: IndexSet) {
        for index in offsets.sorted(by: >) where records.indices.contains(index) {
            records.remove(at: index)
        }
        persist()
    }

    func delete(_ record: DriveRecord) {
        records.removeAll { $0.id == record.id }
        persist()
    }

    /// 0-100 km/h のベストタイム(秒)。該当スプリットがない記録は対象外。
    var bestZeroToHundred: Double? {
        records.compactMap { record in
            record.splits.first { $0.targetKPH == 100 }?.seconds
        }.min()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey) else { return }
        records = (try? JSONDecoder().decode([DriveRecord].self, from: data)) ?? []
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}
