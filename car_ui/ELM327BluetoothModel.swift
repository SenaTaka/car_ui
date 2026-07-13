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
    @Published private(set) var liveValues: [UInt8: Double] = [:]
    @Published private(set) var adapterVoltage: Double?
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var isDemo = false
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
    private var demoTask: Task<Void, Never>?
    private var didStartInitialization = false
    private var pollCycle = 0
    private var slowPIDRotationIndex = 0
    private var supportedMode01PIDs: Set<UInt8> = []

    // 背面での駐車検知オートオフ(12V バッテリー保護)
    private var isBackgrounded = false
    private var engineOffSince: Date?
    private var lastRpmUpdate: Date?
    /// この電圧を下回ると「オルタネータ非発電」の候補とみなす
    private static let engineOffVoltage = 13.0
    /// この RPM 以上の新鮮な値があればエンジン稼働中と判断(誤オートオフを防ぐ)
    private static let engineRunningRpm: Double = 300
    /// RPM をこの秒数以内に取得できていなければ「稼働の確証なし」とする
    private static let rpmFreshWindow: TimeInterval = 5
    /// 停止検知がこの秒数続いたら背面接続を自動切断
    private static let parkedGracePeriod: TimeInterval = 120

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
        if isDemo {
            resetConnectionState(keepLog: true)
            phase = .idle
            appendLog("デモモード終了")
            return
        }

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
        guard phase.isConnected, !isDemo, pollingTask == nil else { return }

        isPolling = true
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollLiveData()
                self?.evaluateParkedAutoDisconnect()
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
    }

    /// アプリの前面/背面状態を通知する(背面時のみ駐車オートオフを働かせる)。
    func setBackgrounded(_ backgrounded: Bool) {
        isBackgrounded = backgrounded
        if !backgrounded { engineOffSince = nil }
    }

    /// 背面でエンジン停止が一定時間続いたら、12V バッテリー保護のため自動切断する。
    /// 停止判定は「電圧低下」かつ「RPM 非稼働」の両方(条件B)。
    /// 新鮮な RPM がアイドル相当以上なら走行中とみなし発動しない
    /// ため、スマート充電で走行中に電圧が 13V を割る車でも誤切断しない。
    /// 前面では判定しない(ユーザーが見ている)。
    private func evaluateParkedAutoDisconnect() {
        guard isBackgrounded, phase.isConnected, !isDemo else {
            engineOffSince = nil
            return
        }
        // 電圧が取れないアダプタでは誤切断を避けるため判定を見送る
        guard let voltage = adapterVoltage else { return }

        let now = Date()
        // 直近に取得した RPM がアイドル相当以上なら「稼働の確証あり」。
        // 停止後は 01 0C が NO DATA になり値が更新されないため、鮮度でも判断する。
        let hasFreshRpm = lastRpmUpdate.map { now.timeIntervalSince($0) < Self.rpmFreshWindow } ?? false
        let engineRunning = hasFreshRpm && (liveValues[0x0C] ?? 0) >= Self.engineRunningRpm
        let engineOff = voltage < Self.engineOffVoltage && !engineRunning

        if engineOff {
            if let since = engineOffSince {
                if now.timeIntervalSince(since) >= Self.parkedGracePeriod {
                    appendLog("エンジン停止を検知(背面)。バッテリー保護のため自動切断します")
                    disconnect()
                }
            } else {
                engineOffSince = now
            }
        } else {
            engineOffSince = nil
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        isPolling = false
    }

    // MARK: - デモモード(アダプタなしで全機能を試せる擬似データ)

    func startDemoMode() {
        disconnectHardwareIfNeeded()
        resetConnectionState(keepLog: true)

        isDemo = true
        phase = .connected("デモモード")
        adapterInfo = "DEMO"
        protocolDescription = "シミュレーション"
        let demoPIDs: Set<UInt8> = [
            0x04, 0x05, 0x06, 0x07, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10,
            0x11, 0x1F, 0x2F, 0x33, 0x42, 0x46, 0x5C, 0x5E, 0x62
        ]
        supportedMode01PIDs = demoPIDs
        supportedMode01PIDCount = demoPIDs.count
        isPolling = true
        appendLog("デモモード開始(擬似データを生成)")

        demoTask = Task { [weak self] in
            var t = 0.0
            while !Task.isCancelled {
                self?.generateDemoData(t)
                t += 0.25
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
    }

    private func generateDemoData(_ t: Double) {
        guard isDemo else { return }

        let throttle = max(0, min(100, 25 + 35 * sin(t / 5) + 10 * sin(t / 1.3)))
        let rpm = 900 + throttle * 52 + 180 * sin(t / 2)
        let speed = max(0, 55 + 50 * sin(t / 9))

        applyDemoValue(0x0C, rpm)
        applyDemoValue(0x0D, speed)
        applyDemoValue(0x11, throttle)
        applyDemoValue(0x04, max(5, min(95, throttle * 0.9 + 8 * sin(t / 4))))
        applyDemoValue(0x05, min(96, 62 + t * 0.4))
        applyDemoValue(0x06, 3.5 * sin(t / 6))
        applyDemoValue(0x07, 1.8 + 0.7 * sin(t / 30))
        applyDemoValue(0x0B, 28 + throttle * 0.7)
        applyDemoValue(0x0E, 12 + 8 * sin(t / 7))
        applyDemoValue(0x0F, 28 + 4 * sin(t / 40))
        applyDemoValue(0x10, 2 + throttle * 0.5)
        applyDemoValue(0x1F, t)
        applyDemoValue(0x2F, max(3, 68 - t * 0.01))
        applyDemoValue(0x33, 101)
        applyDemoValue(0x42, 13.8 + 0.3 * sin(t / 3))
        applyDemoValue(0x46, 31)
        applyDemoValue(0x5C, min(104, 55 + t * 0.35))
        applyDemoValue(0x5E, 0.7 + throttle * 0.11)
        applyDemoValue(0x62, max(0, min(100, throttle * 0.92)))

        adapterVoltage = 13.8 + 0.3 * sin(t / 3)
        lastUpdated = Date()
    }

    private func applyDemoValue(_ pid: UInt8, _ value: Double) {
        liveValues[pid] = value
        if let definition = PIDCatalog.byPID[pid] {
            TelemetryRecorder.shared.record(definition.channelID, value: value)
        }
    }

    private func disconnectHardwareIfNeeded() {
        if let connectedPeripheral {
            centralManager.cancelPeripheralConnection(connectedPeripheral)
        }
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

    /// Mode 04: DTC 消去。Pro 限定機能で、呼び出し可否の判定は UI 側(ToolsView)で行う。
    func clearDiagnosticTroubleCodes() {
        guard phase.isConnected else { return }

        isReadingDiagnostics = true
        diagnosticStatus = "消去中"

        Task { [weak self] in
            guard let self else { return }
            _ = await self.request("04", timeout: 5)
            self.diagnosticCodes = []
            self.diagnosticStatus = "消去完了"
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
            adapterVoltage = parseVoltage(voltageResponse)
        }

        phase = .connected(displayName(for: connectedPeripheral))
        appendLog("ELM327 初期化完了")
        startPolling()
    }

    private func pollLiveData() async {
        guard phase.isConnected else { return }

        // 高速系 PID は毎サイクル、それ以外の対応 PID はラウンドロビンで巡回
        for pid in PIDCatalog.fastPIDs {
            await pollMode01(pid)
        }

        let slowPIDs = slowPollTargets()
        if !slowPIDs.isEmpty {
            for _ in 0..<min(3, slowPIDs.count) {
                let pid = slowPIDs[slowPIDRotationIndex % slowPIDs.count]
                slowPIDRotationIndex += 1
                await pollMode01(pid)
            }
        }

        pollCycle += 1
        if pollCycle.isMultiple(of: 8), let voltageResponse = await request("ATRV", timeout: 2) {
            if let voltage = parseVoltage(voltageResponse) {
                adapterVoltage = voltage
                lastUpdated = Date()
                TelemetryRecorder.shared.record("meta.voltage", value: voltage)
            }
        }
    }

    private func slowPollTargets() -> [UInt8] {
        let fastSet = Set(PIDCatalog.fastPIDs)
        let base: Set<UInt8> = supportedMode01PIDs.isEmpty
            ? [0x05, 0x06, 0x07, 0x0B, 0x0E, 0x0F, 0x10, 0x2F, 0x33, 0x42, 0x46, 0x5C]
            : supportedMode01PIDs
        return base
            .filter { PIDCatalog.byPID[$0] != nil && !fastSet.contains($0) }
            .sorted()
    }

    private func pollMode01(_ pid: UInt8) async {
        guard let definition = PIDCatalog.byPID[pid] else { return }
        guard isMode01PIDSupported(pid) else { return }
        guard let response = await request(definition.command, timeout: 2) else { return }
        guard let bytes = mode01Payload(from: response, pid: pid), !bytes.isEmpty,
              let value = definition.decode(bytes) else {
            return
        }

        liveValues[pid] = value
        lastUpdated = Date()
        if pid == 0x0C { lastRpmUpdate = Date() }
        TelemetryRecorder.shared.record(definition.channelID, value: value)
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
        demoTask?.cancel()
        demoTask = nil
        isDemo = false
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
        liveValues = [:]
        adapterVoltage = nil
        lastUpdated = nil
        lastRpmUpdate = nil
        engineOffSince = nil
        diagnosticCodes = []
        diagnosticStatus = "未読取"
        pollCycle = 0
        slowPIDRotationIndex = 0
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
        // デモモード中は実機 BLE 状態変化(シミュレータの .unsupported 等)で
        // phase を上書きしない(遅延コールバックがデモ表示を消してしまうため)。
        guard !isDemo else { return }
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

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
