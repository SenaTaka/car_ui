//
//  ELM327BluetoothModel.swift
//  car_ui
//
//  Created by Codex on 2026/07/09.
//

@preconcurrency import CoreBluetooth
import Combine
import Foundation

struct OBDPeripheral: Identifiable, Equatable {
    let id: UUID
    let name: String
    let rssi: Int
    let isLikelyAdapter: Bool
    let serviceUUIDs: [String]

    fileprivate let peripheral: CBPeripheral

    static func == (lhs: OBDPeripheral, rhs: OBDPeripheral) -> Bool {
        lhs.id == rhs.id
    }
}

struct VehicleTelemetry: Equatable {
    var rpm: Int?
    var speedKPH: Int?
    var coolantTempC: Int?
    var intakeTempC: Int?
    var throttlePercent: Double?
    var engineLoadPercent: Double?
    var moduleVoltage: Double?
    var mafGramsPerSecond: Double?
    var lastUpdated: Date?

    static let empty = VehicleTelemetry()
}

enum OBDConnectionPhase: Equatable {
    case waitingForBluetooth
    case idle
    case scanning
    case connecting(String)
    case discovering(String)
    case initializing(String)
    case connected(String)
    case disconnected(String)
    case unavailable(String)
    case failed(String)

    var title: String {
        switch self {
        case .waitingForBluetooth:
            return "Bluetooth 確認中"
        case .idle:
            return "未接続"
        case .scanning:
            return "スキャン中"
        case .connecting(let name):
            return "\(name) に接続中"
        case .discovering(let name):
            return "\(name) を確認中"
        case .initializing(let name):
            return "\(name) を初期化中"
        case .connected(let name):
            return "\(name) に接続済み"
        case .disconnected(let message):
            return message
        case .unavailable(let message):
            return message
        case .failed(let message):
            return message
        }
    }

    var isConnected: Bool {
        if case .connected = self {
            return true
        }
        return false
    }
}

@MainActor
final class ELM327BluetoothModel: NSObject, ObservableObject {
    @Published private(set) var phase: OBDConnectionPhase = .waitingForBluetooth
    @Published private(set) var discoveredPeripherals: [OBDPeripheral] = []
    @Published private(set) var telemetry: VehicleTelemetry = .empty
    @Published private(set) var adapterInfo = "未取得"
    @Published private(set) var protocolDescription = "未取得"
    @Published private(set) var supportedMode01PIDCount = 0
    @Published private(set) var diagnosticCodes: [String] = []
    @Published private(set) var diagnosticStatus = "未読取"
    @Published private(set) var isPolling = false
    @Published private(set) var isReadingDiagnostics = false
    @Published private(set) var manualCommandResponse = "未送信"
    @Published private(set) var isSendingManualCommand = false
    @Published private(set) var logLines: [String] = []

    private var centralManager: CBCentralManager!
    private var peripheralsByID: [UUID: CBPeripheral] = [:]
    private var connectedPeripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?

    private var receiveBuffer = ""
    private var commandQueue: [PendingCommand] = []
    private var currentCommand: PendingCommand?
    private var nextCommandID = 0

    private var commandTimeoutTask: Task<Void, Never>?
    private var transportDiscoveryTask: Task<Void, Never>?
    private var startupTask: Task<Void, Never>?
    private var pollingTask: Task<Void, Never>?
    private var didStartInitialization = false
    private var pollCycle = 0
    private var supportedMode01PIDs: Set<UInt8> = []

    private let likelyNameMarkers = [
        "OBD", "ELM", "V-LINK", "VLINK", "LELINK", "VEEPEAK", "VIECAR",
        "CARISTA", "KONNWEI", "KONNWEY", "VGATE", "IOS-VLINK", "OBDII", "OBD-II"
    ]

    private let likelyServiceUUIDs: Set<String> = [
        "FFE0",
        "FFF0",
        "18F0",
        "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
    ]

    private let preferredWriteUUIDs: Set<String> = [
        "FFE1",
        "FFF1",
        "FFF2",
        "2AF1",
        "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
    ]

    private let preferredNotifyUUIDs: Set<String> = [
        "FFE1",
        "FFF1",
        "FFF2",
        "2AF0",
        "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"
    ]

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }

    var canScan: Bool {
        centralManager?.state == .poweredOn
    }

    var canConnect: Bool {
        switch phase {
        case .idle, .scanning, .disconnected, .failed:
            return canScan
        default:
            return false
        }
    }

    func startScan() {
        guard canScan else {
            appendLog("Bluetooth が利用可能になるまで待機しています")
            return
        }

        stopPolling()
        discoveredPeripherals.removeAll()
        peripheralsByID.removeAll()
        phase = .scanning
        appendLog("BLE スキャン開始")
        centralManager.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    func stopScan() {
        centralManager.stopScan()
        if case .scanning = phase {
            phase = .idle
        }
        appendLog("BLE スキャン停止")
    }

    func connect(to device: OBDPeripheral) {
        guard canScan else {
            phase = .unavailable("Bluetooth が利用できません")
            return
        }

        centralManager.stopScan()
        resetConnectionState(keepLog: true)
        peripheralsByID[device.id] = device.peripheral
        connectedPeripheral = device.peripheral
        phase = .connecting(device.name)
        appendLog("\(device.name) に接続開始")
        centralManager.connect(device.peripheral, options: nil)
    }

    func disconnect() {
        stopPolling()
        startupTask?.cancel()
        startupTask = nil
        cancelPendingCommands()

        if let connectedPeripheral {
            centralManager.cancelPeripheralConnection(connectedPeripheral)
        } else {
            resetConnectionState(keepLog: true)
            phase = .idle
        }
    }

    func startPolling() {
        guard phase.isConnected, pollingTask == nil else { return }

        isPolling = true
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollLiveData()
                try? await Task.sleep(nanoseconds: 800_000_000)
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        isPolling = false
    }

    func readDiagnosticTroubleCodes() {
        guard phase.isConnected else { return }

        isReadingDiagnostics = true
        diagnosticStatus = "読取中"

        Task { [weak self] in
            guard let self else { return }
            let response = await self.request("03", timeout: 5)
            let codes = self.parseDiagnosticTroubleCodes(response)
            self.diagnosticCodes = codes
            self.diagnosticStatus = codes.isEmpty ? "故障コードなし" : "\(codes.count) 件"
            self.isReadingDiagnostics = false
        }
    }

    func sendManualCommand(_ rawCommand: String) {
        let command = sanitizedCommand(rawCommand)
        guard !command.isEmpty else {
            manualCommandResponse = "コマンドが空です"
            return
        }
        guard phase.isConnected else {
            manualCommandResponse = "未接続です"
            return
        }

        isSendingManualCommand = true
        manualCommandResponse = "送信中: \(command)"

        Task { [weak self] in
            guard let self else { return }
            let response = await self.request(command, timeout: 5)
            self.manualCommandResponse = response.map(self.displayResponse)?.nonEmpty ?? "応答なし"
            self.isSendingManualCommand = false
        }
    }

    private func initializeELM() async {
        guard let connectedPeripheral else { return }

        phase = .initializing(displayName(for: connectedPeripheral))
        adapterInfo = "初期化中"
        protocolDescription = "自動判定中"
        diagnosticCodes = []
        diagnosticStatus = "未読取"
        appendLog("ELM327 初期化開始")

        guard let resetResponse = await request("ATZ", timeout: 5) else {
            phase = .failed("ELM327 から応答がありません")
            appendLog("ATZ がタイムアウトしました")
            return
        }

        let resetInfo = displayResponse(resetResponse)
        if !resetInfo.isEmpty {
            adapterInfo = resetInfo
        }

        _ = await request("ATE0")
        _ = await request("ATL0")
        _ = await request("ATS0")
        _ = await request("ATH0")
        _ = await request("ATAT1")
        _ = await request("ATSP0", timeout: 4)

        if let protocolResponse = await request("ATDP", timeout: 3) {
            let protocolText = displayResponse(protocolResponse)
            if !protocolText.isEmpty {
                protocolDescription = protocolText
            }
        }

        await refreshSupportedMode01PIDs()

        if let voltageResponse = await request("ATRV", timeout: 3) {
            telemetry.moduleVoltage = parseVoltage(voltageResponse)
        }

        phase = .connected(displayName(for: connectedPeripheral))
        appendLog("ELM327 初期化完了")
        startPolling()
    }

    private func pollLiveData() async {
        guard phase.isConnected else { return }

        await pollMode01("010C", pid: 0x0C)
        await pollMode01("010D", pid: 0x0D)
        await pollMode01("0105", pid: 0x05)
        await pollMode01("0111", pid: 0x11)
        await pollMode01("0104", pid: 0x04)
        await pollMode01("010F", pid: 0x0F)
        await pollMode01("0110", pid: 0x10)

        pollCycle += 1
        if pollCycle.isMultiple(of: 4), let voltageResponse = await request("ATRV", timeout: 2) {
            telemetry.moduleVoltage = parseVoltage(voltageResponse)
            telemetry.lastUpdated = Date()
        }
    }

    private func pollMode01(_ command: String, pid: UInt8) async {
        guard isMode01PIDSupported(pid) else { return }
        guard let response = await request(command, timeout: 2) else { return }
        applyMode01(response: response, pid: pid)
    }

    private func applyMode01(response: String, pid: UInt8) {
        guard let bytes = mode01Payload(from: response, pid: pid), !bytes.isEmpty else {
            return
        }

        switch pid {
        case 0x04:
            telemetry.engineLoadPercent = percent(from: bytes[0])
        case 0x05:
            telemetry.coolantTempC = Int(bytes[0]) - 40
        case 0x0C where bytes.count >= 2:
            telemetry.rpm = Int((UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 4)
        case 0x0D:
            telemetry.speedKPH = Int(bytes[0])
        case 0x0F:
            telemetry.intakeTempC = Int(bytes[0]) - 40
        case 0x10 where bytes.count >= 2:
            let rawValue = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
            telemetry.mafGramsPerSecond = Double(rawValue) / 100
        case 0x11:
            telemetry.throttlePercent = percent(from: bytes[0])
        default:
            break
        }

        telemetry.lastUpdated = Date()
    }

    private func percent(from byte: UInt8) -> Double {
        (Double(byte) * 100 / 255).rounded(toPlaces: 1)
    }

    private func request(_ command: String, timeout: TimeInterval = 2) async -> String? {
        guard connectedPeripheral != nil, writeCharacteristic != nil else { return nil }

        return await withCheckedContinuation { continuation in
            enqueue(command, timeout: timeout) { response in
                continuation.resume(returning: response)
            }
        }
    }

    private func enqueue(
        _ command: String,
        timeout: TimeInterval,
        completion: @escaping (String?) -> Void
    ) {
        nextCommandID += 1
        commandQueue.append(
            PendingCommand(
                id: nextCommandID,
                command: command,
                timeout: timeout,
                completion: completion
            )
        )
        sendNextCommandIfPossible()
    }

    private func sendNextCommandIfPossible() {
        guard currentCommand == nil else { return }
        guard let connectedPeripheral, let writeCharacteristic else { return }
        guard !commandQueue.isEmpty else { return }

        let command = commandQueue.removeFirst()
        currentCommand = command
        receiveBuffer = ""

        guard let data = "\(command.command)\r".data(using: .ascii) else {
            finishCurrentCommand(response: nil)
            return
        }

        let writeType: CBCharacteristicWriteType = writeCharacteristic.properties.contains(.write)
            ? .withResponse
            : .withoutResponse

        appendLog("→ \(command.command)")
        connectedPeripheral.writeValue(data, for: writeCharacteristic, type: writeType)
        scheduleTimeout(for: command)
    }

    private func scheduleTimeout(for command: PendingCommand) {
        commandTimeoutTask?.cancel()
        commandTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(command.timeout * 1_000_000_000))
            self?.finishTimedOutCommand(command.id)
        }
    }

    private func finishTimedOutCommand(_ commandID: Int) {
        guard currentCommand?.id == commandID else { return }
        appendLog("× \(currentCommand?.command ?? "") タイムアウト")
        finishCurrentCommand(response: nil)
    }

    private func finishCurrentCommand(response: String?) {
        commandTimeoutTask?.cancel()
        commandTimeoutTask = nil

        let command = currentCommand
        currentCommand = nil

        if let response {
            appendLog("← \(displayResponse(response))")
        }

        command?.completion(response)
        sendNextCommandIfPossible()
    }

    private func cancelPendingCommands() {
        commandTimeoutTask?.cancel()
        commandTimeoutTask = nil

        if let currentCommand {
            currentCommand.completion(nil)
        }

        commandQueue.forEach { $0.completion(nil) }
        commandQueue.removeAll()
        currentCommand = nil
        receiveBuffer = ""
    }

    private func handleIncomingData(_ data: Data) {
        guard let chunk = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
            return
        }

        receiveBuffer += chunk
        if receiveBuffer.contains(">") {
            let response = receiveBuffer
            receiveBuffer = ""
            finishCurrentCommand(response: response)
        }
    }

    private func resetConnectionState(keepLog: Bool = false) {
        stopPolling()
        transportDiscoveryTask?.cancel()
        transportDiscoveryTask = nil
        startupTask?.cancel()
        startupTask = nil
        commandTimeoutTask?.cancel()
        commandTimeoutTask = nil
        cancelPendingCommands()

        connectedPeripheral?.delegate = nil
        connectedPeripheral = nil
        writeCharacteristic = nil
        notifyCharacteristic = nil
        receiveBuffer = ""
        didStartInitialization = false
        adapterInfo = "未取得"
        protocolDescription = "未取得"
        telemetry = .empty
        diagnosticCodes = []
        diagnosticStatus = "未読取"
        pollCycle = 0
        supportedMode01PIDs = []
        supportedMode01PIDCount = 0
        manualCommandResponse = "未送信"
        isSendingManualCommand = false

        if !keepLog {
            logLines = []
        }
    }

    private func displayName(for peripheral: CBPeripheral) -> String {
        peripheral.name?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "ELM327"
    }

    private func updateDiscoveredPeripheral(
        peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi: NSNumber
    ) {
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = advertisedName?.nonEmpty ?? peripheral.name?.nonEmpty ?? "名称未取得"
        let advertisedServices = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        let serviceUUIDs = advertisedServices.map(normalizedUUID)
        let isLikelyAdapter = looksLikeOBDAdapter(name: name, serviceUUIDs: serviceUUIDs)

        guard isLikelyAdapter || name != "名称未取得" else { return }

        peripheralsByID[peripheral.identifier] = peripheral
        let candidate = OBDPeripheral(
            id: peripheral.identifier,
            name: name,
            rssi: rssi.intValue,
            isLikelyAdapter: isLikelyAdapter,
            serviceUUIDs: serviceUUIDs,
            peripheral: peripheral
        )

        if let existingIndex = discoveredPeripherals.firstIndex(where: { $0.id == candidate.id }) {
            discoveredPeripherals[existingIndex] = candidate
        } else {
            discoveredPeripherals.append(candidate)
        }

        discoveredPeripherals.sort {
            if $0.isLikelyAdapter != $1.isLikelyAdapter {
                return $0.isLikelyAdapter && !$1.isLikelyAdapter
            }
            return $0.rssi > $1.rssi
        }
    }

    private func looksLikeOBDAdapter(name: String, serviceUUIDs: [String]) -> Bool {
        let uppercasedName = name.uppercased()
        let hasKnownName = likelyNameMarkers.contains { uppercasedName.contains($0) }
        let hasKnownService = serviceUUIDs.contains { likelyServiceUUIDs.contains($0) }
        return hasKnownName || hasKnownService
    }

    private func discoverTransport(on peripheral: CBPeripheral) {
        peripheral.delegate = self
        phase = .discovering(displayName(for: peripheral))
        peripheral.discoverServices(nil)

        transportDiscoveryTask?.cancel()
        transportDiscoveryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            self?.failIfTransportWasNotFound()
        }
    }

    private func failIfTransportWasNotFound() {
        guard !didStartInitialization else { return }

        phase = .failed("ELM327 の BLE 通信特性が見つかりません")
        appendLog("UART 互換の BLE characteristic が見つかりません")
    }

    private func inspect(characteristic: CBCharacteristic, on peripheral: CBPeripheral) {
        let uuid = normalizedUUID(characteristic.uuid)
        let properties = characteristic.properties
        let canNotify = properties.contains(.notify) || properties.contains(.indicate)
        let canWrite = properties.contains(.write) || properties.contains(.writeWithoutResponse)

        if canNotify {
            if notifyCharacteristic == nil || preferredNotifyUUIDs.contains(uuid) {
                notifyCharacteristic = characteristic
            }
        }

        if canWrite {
            if writeCharacteristic == nil || preferredWriteUUIDs.contains(uuid) {
                writeCharacteristic = characteristic
            }
        }

        if let notifyCharacteristic {
            peripheral.setNotifyValue(true, for: notifyCharacteristic)
        }

        startInitializationIfReady()
    }

    private func startInitializationIfReady() {
        guard !didStartInitialization else { return }
        guard writeCharacteristic != nil, notifyCharacteristic != nil else { return }

        didStartInitialization = true
        transportDiscoveryTask?.cancel()
        transportDiscoveryTask = nil

        startupTask = Task { [weak self] in
            await self?.initializeELM()
        }
    }

    private func refreshSupportedMode01PIDs() async {
        var detectedPIDs: Set<UInt8> = []
        var basePID: UInt8 = 0x00

        while true {
            let command = String(format: "01%02X", basePID)
            guard let response = await request(command, timeout: 3),
                  let payload = mode01Payload(from: response, pid: basePID),
                  payload.count >= 4 else {
                break
            }

            let pids = supportedPIDs(from: Array(payload.prefix(4)), basePID: basePID)
            detectedPIDs.formUnion(pids)

            let nextGroupPID = basePID &+ 0x20
            guard pids.contains(nextGroupPID), basePID < 0xE0 else {
                break
            }

            basePID = nextGroupPID
        }

        supportedMode01PIDs = detectedPIDs
        supportedMode01PIDCount = detectedPIDs.count

        if detectedPIDs.isEmpty {
            appendLog("対応 Mode 01 PID を取得できませんでした")
        } else {
            appendLog("対応 Mode 01 PID: \(detectedPIDs.count) 件")
        }
    }

    private func supportedPIDs(from bytes: [UInt8], basePID: UInt8) -> Set<UInt8> {
        let bitMask = bytes.prefix(4).reduce(UInt32(0)) { partialResult, byte in
            (partialResult << 8) | UInt32(byte)
        }

        var pids: Set<UInt8> = []
        for bitIndex in 0..<32 {
            let bit = UInt32(1) << UInt32(31 - bitIndex)
            if bitMask & bit != 0 {
                pids.insert(basePID &+ UInt8(bitIndex + 1))
            }
        }
        return pids
    }

    private func isMode01PIDSupported(_ pid: UInt8) -> Bool {
        supportedMode01PIDs.isEmpty || supportedMode01PIDs.contains(pid)
    }

    private func mode01Payload(from response: String, pid: UInt8) -> [UInt8]? {
        guard let bytes = responseBytes(from: response, responseMode: 0x41, pid: pid) else {
            return nil
        }
        return bytes
    }

    private func parseDiagnosticTroubleCodes(_ response: String?) -> [String] {
        guard let response,
              let bytes = responseBytes(from: response, responseMode: 0x43, pid: nil) else {
            return []
        }

        var codes: [String] = []
        var index = 0

        while index + 1 < bytes.count {
            let high = bytes[index]
            let low = bytes[index + 1]
            index += 2

            guard high != 0 || low != 0 else { continue }

            let family = ["P", "C", "B", "U"][Int((high & 0xC0) >> 6)]
            let firstDigit = String((high & 0x30) >> 4, radix: 16).uppercased()
            let secondDigit = String(high & 0x0F, radix: 16).uppercased()
            let thirdDigit = String((low & 0xF0) >> 4, radix: 16).uppercased()
            let fourthDigit = String(low & 0x0F, radix: 16).uppercased()
            codes.append("\(family)\(firstDigit)\(secondDigit)\(thirdDigit)\(fourthDigit)")
        }

        return codes
    }

    private func responseBytes(from response: String, responseMode: UInt8, pid: UInt8?) -> [UInt8]? {
        let uppercased = response.uppercased()
        let negativeMarkers = [
            "NO DATA", "UNABLE TO CONNECT", "CAN ERROR", "BUS ERROR",
            "STOPPED", "ERROR", "?", "DATA ERROR"
        ]

        guard !negativeMarkers.contains(where: { uppercased.contains($0) }) else {
            return nil
        }

        var cleaned = uppercased
        [
            "SEARCHING...",
            "SEARCHING",
            "BUS INIT: OK",
            "BUSINIT:OK",
            "OK",
            ">"
        ].forEach {
            cleaned = cleaned.replacingOccurrences(of: $0, with: " ")
        }

        for bytes in responseByteCandidates(from: cleaned) {
            if let payload = responsePayload(from: bytes, responseMode: responseMode, pid: pid) {
                return payload
            }
        }

        return nil
    }

    private func responsePayload(from bytes: [UInt8], responseMode: UInt8, pid: UInt8?) -> [UInt8]? {
        var index = 0
        while index < bytes.count {
            if bytes[index] == responseMode {
                if let pid {
                    if index + 1 < bytes.count, bytes[index + 1] == pid {
                        return Array(bytes.dropFirst(index + 2))
                    }
                } else {
                    return Array(bytes.dropFirst(index + 1))
                }
            }
            index += 1
        }

        return nil
    }

    private func responseByteCandidates(from cleanedResponse: String) -> [[UInt8]] {
        let hexCharacters = Set("0123456789ABCDEF")
        let tokenizedBytes = cleanedResponse
            .split { !hexCharacters.contains($0) }
            .flatMap { token -> [UInt8] in
                let hex = String(token)

                if hex.count == 3 || hex.count == 7 || hex.count == 8 {
                    return []
                }

                if hex.count == 1 {
                    return []
                }

                if hex.count.isMultiple(of: 2) {
                    return hexBytes(from: hex)
                }

                return hexBytes(from: String(hex.dropFirst()))
            }

        let compactHex = String(cleanedResponse.filter { hexCharacters.contains($0) })
        var candidates = [tokenizedBytes]

        for offset in 0...1 where compactHex.count > offset {
            let startIndex = compactHex.index(compactHex.startIndex, offsetBy: offset)
            candidates.append(hexBytes(from: String(compactHex[startIndex...])))
        }

        return candidates.filter { !$0.isEmpty }
    }

    private func hexBytes(from compactHex: String) -> [UInt8] {
        var bytes: [UInt8] = []
        var index = compactHex.startIndex

        while let nextIndex = compactHex.index(index, offsetBy: 2, limitedBy: compactHex.endIndex),
              nextIndex <= compactHex.endIndex {
            let byteString = String(compactHex[index..<nextIndex])
            if let value = UInt8(byteString, radix: 16) {
                bytes.append(value)
            }
            index = nextIndex

            if index == compactHex.endIndex {
                break
            }
        }

        return bytes
    }

    private func parseVoltage(_ response: String) -> Double? {
        let allowedCharacters = Set("0123456789.")
        var current = ""
        var candidates: [String] = []

        for character in response {
            if allowedCharacters.contains(character) {
                current.append(character)
            } else if !current.isEmpty {
                candidates.append(current)
                current = ""
            }
        }

        if !current.isEmpty {
            candidates.append(current)
        }

        return candidates.compactMap(Double.init).first
    }

    private func displayResponse(_ response: String) -> String {
        response
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: ">", with: "")
            .split(separator: " ")
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sanitizedCommand(_ rawCommand: String) -> String {
        let allowedCharacters = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        return String(rawCommand.uppercased().filter { allowedCharacters.contains($0) })
    }

    private func appendLog(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        logLines.append("\(formatter.string(from: Date()))  \(message)")

        if logLines.count > 80 {
            logLines.removeFirst(logLines.count - 80)
        }
    }

    private func normalizedUUID(_ uuid: CBUUID) -> String {
        uuid.uuidString.uppercased()
    }
}

extension ELM327BluetoothModel: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .unknown, .resetting:
            phase = .waitingForBluetooth
        case .unsupported:
            phase = .unavailable("この端末は Bluetooth LE に対応していません")
        case .unauthorized:
            phase = .unavailable("Bluetooth 権限がありません")
        case .poweredOff:
            phase = .unavailable("Bluetooth がオフです")
            resetConnectionState(keepLog: true)
        case .poweredOn:
            if case .waitingForBluetooth = phase {
                phase = .idle
            }
            appendLog("Bluetooth 使用可能")
        @unknown default:
            phase = .unavailable("Bluetooth の状態を確認できません")
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        updateDiscoveredPeripheral(
            peripheral: peripheral,
            advertisementData: advertisementData,
            rssi: RSSI
        )
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectedPeripheral = peripheral
        appendLog("\(displayName(for: peripheral)) に接続しました")
        discoverTransport(on: peripheral)
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        let message = error?.localizedDescription ?? "接続に失敗しました"
        resetConnectionState(keepLog: true)
        phase = .failed(message)
        appendLog(message)
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        let message = error?.localizedDescription ?? "\(displayName(for: peripheral)) との接続を解除しました"
        resetConnectionState(keepLog: true)
        phase = .disconnected(message)
        appendLog(message)
    }
}

extension ELM327BluetoothModel: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            phase = .failed(error.localizedDescription)
            appendLog(error.localizedDescription)
            return
        }

        peripheral.services?.forEach { service in
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        if let error {
            appendLog(error.localizedDescription)
            return
        }

        service.characteristics?.forEach { characteristic in
            inspect(characteristic: characteristic, on: peripheral)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error {
            appendLog(error.localizedDescription)
            return
        }

        guard let data = characteristic.value else { return }
        handleIncomingData(data)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error {
            appendLog(error.localizedDescription)
        }
    }
}

private struct PendingCommand {
    let id: Int
    let command: String
    let timeout: TimeInterval
    let completion: (String?) -> Void
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10, Double(places))
        return (self * divisor).rounded() / divisor
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
