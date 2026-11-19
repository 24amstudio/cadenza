import CoreBluetooth
import Foundation

@MainActor
final class BluetoothPeripheral: NSObject, @preconcurrency CBPeripheralManagerDelegate {
    static let serviceUUID = CBUUID(string: "9F4C0001-4B9C-4F2D-9C2A-1C8F8B3D4A10")
    static let writeUUID = CBUUID(string: "9F4C0002-4B9C-4F2D-9C2A-1C8F8B3D4A10")
    static let notifyUUID = CBUUID(string: "9F4C0003-4B9C-4F2D-9C2A-1C8F8B3D4A10")
    // Advertising or service publication can fail while the radio is busy or the system is waking. Each failure waits
    // longer, and the series is bounded so a persistent fault ends in a visible issue instead of a silent loop.
    private static let retryDelays: [Duration] = [.seconds(2), .seconds(5), .seconds(15), .seconds(30)]

    private var manager: CBPeripheralManager!
    private var notifyCharacteristic: CBMutableCharacteristic?
    private var subscribed: [CBCentral] = []
    private var inbound: [UUID: BluetoothFrameCodec] = [:]
    // Each Remote has its own queue, so a slow Remote fills only its own window.
    private var outbound: [UUID: BluetoothSendQueue] = [:]
    private var retry: Task<Void, Never>?
    private var retryFailures = 0
    private var pumping = false
    private var started = false
    var onReceive: ((UUID, Data) -> Void)?
    var onSubscribe: ((UUID) -> Void)?
    var onUnsubscribe: ((UUID) -> Void)?
    // Called once a Remote that was refused a frame can take frames again.
    var onDrain: ((UUID) -> Void)?
    var onIssue: ((String) -> Void)?
    var onEvent: ((String, String) -> Void)?

    override init() {
        super.init()
        manager = CBPeripheralManager(delegate: self, queue: .main)
    }

    func start() {
        started = true
        retryFailures = 0
        guard manager.state == .poweredOn else { return }
        publish()
    }

    func stop() {
        started = false
        retry?.cancel()
        retry = nil
        manager.stopAdvertising()
        manager.removeAllServices()
        notifyCharacteristic = nil
        for centralID in subscribed.map(\.identifier) { release(centralID, reason: "Bluetooth stopped.") }
    }

    func send(
        _ data: Data,
        to centralID: UUID,
        completion: @escaping (Error?) -> Void,
    ) -> TransportSendResult {
        guard let central = subscribed.first(where: { $0.identifier == centralID }), notifyCharacteristic != nil else {
            return .failed
        }
        let chunks: [Data]
        do {
            // The central's negotiated size. Web Bluetooth cannot negotiate an MTU, so a browser central gets 20 bytes.
            let size = max(central.maximumUpdateValueLength, BluetoothFrameCodec.minimumChunkBytes)
            chunks = try BluetoothFrameCodec.chunks(for: data, maximumChunkBytes: size)
        } catch {
            completion(error)
            return .failed
        }
        guard outbound[centralID]?.enqueue(chunks, completion: completion) == true else { return .full }
        pump()
        return .accepted
    }

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        onEvent?("bluetooth.state", String(describing: peripheral.state))
        guard started else { return }
        if peripheral.state == .poweredOn {
            retryFailures = 0
            publish()
            return
        }
        // Centrals are gone with the radio, and CoreBluetooth reports no unsubscribe for them.
        retry?.cancel()
        notifyCharacteristic = nil
        for centralID in subscribed.map(\.identifier) {
            release(centralID, reason: "Bluetooth turned off.")
            onUnsubscribe?(centralID)
        }
        if peripheral.state == .unauthorized { onIssue?("Bluetooth permission is unavailable.") }
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error {
            onEvent?("advertising.failed", error.localizedDescription)
            scheduleRetry(
                "Cadenza Host could not advertise over Bluetooth: \(error.localizedDescription)", republishing: false)
        } else {
            retryFailures = 0
            onEvent?("advertising.started", "Cadenza Host is advertising over Bluetooth.")
        }
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        didAdd service: CBService,
        error: Error?,
    ) {
        if let error {
            scheduleRetry(
                "Could not publish the Cadenza Bluetooth service: \(error.localizedDescription)", republishing: true)
            return
        }
        advertise()
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        didReceiveWrite requests: [CBATTRequest],
    ) {
        // CoreBluetooth wants one response, to the first request, for the whole batch.
        guard let first = requests.first else { return }
        var result = CBATTError.Code.success
        for request in requests {
            let centralID = request.central.identifier
            guard request.characteristic.uuid == Self.writeUUID, let value = request.value else {
                result = .requestNotSupported
                continue
            }
            // A central that was dropped keeps writing until its own link notices. Refusing the write tells it to
            // reconnect, instead of feeding a session that no longer exists.
            guard let codec = inbound[centralID] else {
                result = .writeNotPermitted
                continue
            }
            do {
                for frame in try codec.append(value) { onReceive?(centralID, frame) }
            } catch {
                result = .invalidPdu
                release(centralID, reason: "Invalid Bluetooth frame.")
                onEvent?("central.dropped", "A Remote sent an invalid Bluetooth frame: \(error.localizedDescription)")
                onUnsubscribe?(centralID)
            }
        }
        peripheral.respond(to: first, withResult: result)
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didSubscribeTo characteristic: CBCharacteristic,
    ) {
        guard characteristic.uuid == Self.notifyUUID else { return }
        let centralID = central.identifier
        // A Remote that reconnects can arrive before the old subscription was reported gone. The old session is ended
        // so the new one starts clean, instead of the new subscription being ignored.
        if subscribed.contains(where: { $0.identifier == centralID }) {
            release(centralID, reason: "Bluetooth Remote reconnected.")
            onUnsubscribe?(centralID)
        }
        subscribed.append(central)
        inbound[centralID] = BluetoothFrameCodec()
        outbound[centralID] = BluetoothSendQueue()
        onEvent?(
            "central.subscribed",
            "A Remote connected over Bluetooth (notification size \(central.maximumUpdateValueLength) bytes).")
        onSubscribe?(centralID)
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didUnsubscribeFrom characteristic: CBCharacteristic,
    ) {
        guard characteristic.uuid == Self.notifyUUID else { return }
        let centralID = central.identifier
        guard subscribed.contains(where: { $0.identifier == centralID }) else { return }
        onEvent?("central.unsubscribed", "A Remote disconnected from Bluetooth.")
        release(centralID, reason: "Bluetooth Remote disconnected.")
        onUnsubscribe?(centralID)
        if started, !manager.isAdvertising { advertise() }
    }

    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        pump()
    }

    // Forgets everything held for one Remote and fails what was still waiting for it.
    private func release(_ centralID: UUID, reason: String) {
        subscribed.removeAll { $0.identifier == centralID }
        inbound.removeValue(forKey: centralID)
        guard var queue = outbound.removeValue(forKey: centralID) else { return }
        for completion in queue.removeAll() { completion(CadenzaError.failure("network", reason)) }
    }

    // Hands chunks to CoreBluetooth one Remote at a time, in turn. One large frame therefore cannot hold up the others.
    // When CoreBluetooth's transmit queue is full, everything waits for peripheralManagerIsReady.
    private func pump() {
        guard !pumping, let characteristic = notifyCharacteristic else { return }
        pumping = true
        defer { pumping = false }
        while true {
            var progressed = false
            for central in subscribed {
                let centralID = central.identifier
                guard let chunk = outbound[centralID]?.nextChunk else { continue }
                guard manager.updateValue(chunk, for: characteristic, onSubscribedCentrals: [central]) else { return }
                outbound[centralID]?.didSendChunk()
                progressed = true
            }
            if progressed { continue }
            // Nothing else can be written now. Refused Remotes whose queue has drained are told so, and their frames
            // resume from the next pass.
            let drained = subscribed.map(\.identifier).filter { outbound[$0]?.takeDrainNotice() == true }
            if drained.isEmpty { return }
            for centralID in drained { onDrain?(centralID) }
        }
    }

    // Advertising alone is retried while Remotes are connected, because republishing the service would end their links.
    private func scheduleRetry(_ issue: String, republishing: Bool) {
        guard started, manager.state == .poweredOn else { return }
        guard retryFailures < Self.retryDelays.count else {
            onIssue?(issue)
            return
        }
        let delay = Self.retryDelays[retryFailures]
        retryFailures += 1
        onEvent?("advertising.retry", issue)
        retry?.cancel()
        retry = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, self.started, self.manager.state == .poweredOn else { return }
            if republishing { self.publish() } else { self.advertise() }
        }
    }

    private func advertise() {
        guard started, manager.state == .poweredOn else { return }
        manager.stopAdvertising()
        manager.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [Self.serviceUUID],
            CBAdvertisementDataLocalNameKey: "Cadenza Host",
        ])
    }

    private func publish() {
        retry?.cancel()
        manager.stopAdvertising()
        manager.removeAllServices()
        let write = CBMutableCharacteristic(
            type: Self.writeUUID,
            properties: [.write, .writeWithoutResponse],
            value: nil,
            permissions: [.writeable])
        let notify = CBMutableCharacteristic(
            type: Self.notifyUUID,
            properties: [.notify],
            value: nil,
            permissions: [])
        notifyCharacteristic = notify
        let service = CBMutableService(type: Self.serviceUUID, primary: true)
        service.characteristics = [write, notify]
        manager.add(service)
    }
}
