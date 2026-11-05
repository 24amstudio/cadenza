import CoreBluetooth
import Foundation

@MainActor
final class BluetoothPeripheral: NSObject, @preconcurrency CBPeripheralManagerDelegate {
    static let serviceUUID = CBUUID(string: "9F4C0001-4B9C-4F2D-9C2A-1C8F8B3D4A10")
    static let writeUUID = CBUUID(string: "9F4C0002-4B9C-4F2D-9C2A-1C8F8B3D4A10")
    static let notifyUUID = CBUUID(string: "9F4C0003-4B9C-4F2D-9C2A-1C8F8B3D4A10")
    // Each Remote has its own window of frames waiting for CoreBluetooth. A slow Remote fills only its own window, so it
    // cannot take the budget from the others. A frame larger than the window is accepted only when that Remote has
    // nothing waiting.
    private static let windowBytes = 8_192

    private struct PendingSend {
        var chunks: [Data]
        var nextChunk: Int
        let completion: (Error?) -> Void
    }

    private var manager: CBPeripheralManager!
    private var notifyCharacteristic: CBMutableCharacteristic?
    private var subscribed: [CBCentral] = []
    private var inbound: [UUID: BluetoothFrameCodec] = [:]
    private var outbound: [UUID: [PendingSend]] = [:]
    private var pendingBytes: [UUID: Int] = [:]
    private var refused: Set<UUID> = []
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
        guard manager.state == .poweredOn else { return }
        publish()
    }

    func stop() {
        started = false
        manager.stopAdvertising()
        manager.removeAllServices()
        notifyCharacteristic = nil
        for sends in outbound.values {
            for send in sends {
                send.completion(CadenzaError.failure("network", "Bluetooth stopped."))
            }
        }
        outbound.removeAll()
        pendingBytes.removeAll()
        refused.removeAll()
        inbound.removeAll()
        subscribed.removeAll()
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
            chunks = try BluetoothFrameCodec.chunks(for: data, maximumChunkBytes: central.maximumUpdateValueLength)
        } catch {
            completion(error)
            return .failed
        }
        // Count what is actually written, including the length header that the codec adds.
        let framedBytes = chunks.reduce(0) { $0 + $1.count }
        let queued = pendingBytes[centralID, default: 0]
        guard queued == 0 || queued + framedBytes <= Self.windowBytes else {
            refused.insert(centralID)
            return .full
        }
        outbound[centralID, default: []].append(PendingSend(chunks: chunks, nextChunk: 0, completion: completion))
        pendingBytes[centralID] = queued + framedBytes
        pump()
        return .accepted
    }

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        onEvent?("bluetooth.state", String(describing: peripheral.state))
        guard started else { return }
        if peripheral.state == .poweredOn { publish() }
        if peripheral.state == .unauthorized { onIssue?("Bluetooth permission is unavailable.") }
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error {
            onIssue?("Cadenza Host could not advertise over Bluetooth: \(error.localizedDescription)")
        } else {
            onEvent?("advertising.started", "Cadenza Host is advertising over Bluetooth.")
        }
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        didAdd service: CBService,
        error: Error?,
    ) {
        if let error {
            onIssue?("Could not publish the Cadenza Bluetooth service: \(error.localizedDescription)")
            return
        }
        peripheral.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [Self.serviceUUID],
            CBAdvertisementDataLocalNameKey: "Cadenza Host",
        ])
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        didReceiveWrite requests: [CBATTRequest],
    ) {
        for request in requests {
            guard request.characteristic.uuid == Self.writeUUID,
                let value = request.value
            else {
                peripheral.respond(to: request, withResult: .requestNotSupported)
                continue
            }
            let centralID = request.central.identifier
            do {
                let codec = inbound[centralID, default: BluetoothFrameCodec()]
                for frame in try codec.append(value) { onReceive?(centralID, frame) }
                inbound[centralID] = codec
                peripheral.respond(to: request, withResult: .success)
            } catch {
                inbound.removeValue(forKey: centralID)
                peripheral.respond(to: request, withResult: .invalidPdu)
                onIssue?("A Remote sent an invalid Bluetooth frame: \(error.localizedDescription)")
            }
        }
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didSubscribeTo characteristic: CBCharacteristic,
    ) {
        guard characteristic.uuid == Self.notifyUUID,
            !subscribed.contains(where: { $0.identifier == central.identifier })
        else { return }
        subscribed.append(central)
        inbound[central.identifier] = BluetoothFrameCodec()
        onEvent?("central.subscribed", "A Remote connected over Bluetooth.")
        onSubscribe?(central.identifier)
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didUnsubscribeFrom characteristic: CBCharacteristic,
    ) {
        guard characteristic.uuid == Self.notifyUUID else { return }
        let centralID = central.identifier
        onEvent?("central.unsubscribed", "A Remote disconnected from Bluetooth.")
        subscribed.removeAll { $0.identifier == centralID }
        inbound.removeValue(forKey: centralID)
        refused.remove(centralID)
        pendingBytes.removeValue(forKey: centralID)
        if let pending = outbound.removeValue(forKey: centralID) {
            for send in pending {
                send.completion(CadenzaError.failure("network", "Bluetooth Remote disconnected."))
            }
        }
        onUnsubscribe?(centralID)
    }

    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        pump()
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
                guard let next = outbound[centralID]?.first else { continue }
                let chunk = next.chunks[next.nextChunk]
                guard manager.updateValue(chunk, for: characteristic, onSubscribedCentrals: [central]) else { return }
                record(centralID, chunkBytes: chunk.count)
                progressed = true
            }
            if progressed { continue }
            // Nothing else can be written now. Refused Remotes whose window has room are told so, and their queues
            // resume from the next pass.
            let ready = refused.filter { pendingBytes[$0, default: 0] < Self.windowBytes }
            if ready.isEmpty { return }
            refused.subtract(ready)
            for centralID in ready { onDrain?(centralID) }
        }
    }

    private func record(_ centralID: UUID, chunkBytes: Int) {
        guard var sends = outbound.removeValue(forKey: centralID) else { return }
        sends[0].nextChunk += 1
        let remaining = (pendingBytes[centralID] ?? 0) - chunkBytes
        if sends[0].nextChunk == sends[0].chunks.count {
            sends.removeFirst().completion(nil)
        }
        if sends.isEmpty {
            pendingBytes.removeValue(forKey: centralID)
        } else {
            pendingBytes[centralID] = remaining
            outbound[centralID] = sends
        }
    }

    private func publish() {
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
