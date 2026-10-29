import CoreBluetooth
import Foundation

@MainActor
final class BluetoothPeripheral: NSObject, CBPeripheralManagerDelegate {
    static let serviceUUID = CBUUID(string: "9F4C0001-4B9C-4F2D-9C2A-1C8F8B3D4A10")
    static let writeUUID = CBUUID(string: "9F4C0002-4B9C-4F2D-9C2A-1C8F8B3D4A10")
    static let notifyUUID = CBUUID(string: "9F4C0003-4B9C-4F2D-9C2A-1C8F8B3D4A10")
    private static let maximumQueuedBytes = 4_194_304

    private struct PendingSend {
        var chunks: [Data]
        var nextChunk: Int
        let completion: (Error?) -> Void

        var remainingBytes: Int {
            chunks.dropFirst(nextChunk).reduce(0) { $0 + $1.count }
        }
    }

    private var manager: CBPeripheralManager!
    private var notifyCharacteristic: CBMutableCharacteristic?
    private var subscribed: [CBCentral] = []
    private var inbound: [UUID: BluetoothFrameCodec] = [:]
    private var outbound: [UUID: [PendingSend]] = [:]
    private var queuedBytes = 0
    private var started = false
    var onReceive: ((UUID, Data) -> Void)?
    var onSubscribe: ((UUID) -> Void)?
    var onUnsubscribe: ((UUID) -> Void)?
    var onIssue: ((String) -> Void)?

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
        inbound.removeAll()
        queuedBytes = 0
        subscribed.removeAll()
    }

    func send(
        _ data: Data,
        to centralID: UUID,
        completion: @escaping (Error?) -> Void,
    ) -> Bool {
        guard let central = subscribed.first(where: { $0.identifier == centralID }), notifyCharacteristic != nil else {
            return false
        }
        let chunks: [Data]
        do {
            chunks = try BluetoothFrameCodec.chunks(for: data)
        } catch {
            completion(error)
            return false
        }
        guard queuedBytes + data.count <= Self.maximumQueuedBytes else {
            completion(CadenzaError.failure("network", "Bluetooth outbound buffer is full."))
            return false
        }
        outbound[centralID, default: []].append(
            PendingSend(chunks: chunks, nextChunk: 0, completion: completion))
        queuedBytes += data.count
        flush(central: central)
        return true
    }

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        guard started else { return }
        if peripheral.state == .poweredOn { publish() }
        if peripheral.state == .unauthorized { onIssue?("Bluetooth permission is unavailable.") }
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
        onSubscribe?(central.identifier)
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didUnsubscribeFrom characteristic: CBCharacteristic,
    ) {
        guard characteristic.uuid == Self.notifyUUID else { return }
        let centralID = central.identifier
        subscribed.removeAll { $0.identifier == centralID }
        inbound.removeValue(forKey: centralID)
        if let pending = outbound.removeValue(forKey: centralID) {
            for send in pending {
                queuedBytes -= send.remainingBytes
                send.completion(CadenzaError.failure("network", "Bluetooth Remote disconnected."))
            }
        }
        onUnsubscribe?(centralID)
    }

    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        for central in subscribed { flush(central: central) }
    }

    private func flush(central: CBCentral) {
        guard let characteristic = notifyCharacteristic else { return }
        let centralID = central.identifier
        while var pending = outbound[centralID]?.first {
            while pending.nextChunk < pending.chunks.count {
                guard
                    manager.updateValue(
                        pending.chunks[pending.nextChunk],
                        for: characteristic,
                        onSubscribedCentrals: [central]
                    )
                else {
                    outbound[centralID]?[0] = pending
                    return
                }
                queuedBytes -= pending.chunks[pending.nextChunk].count
                pending.nextChunk += 1
            }
            outbound[centralID]?.removeFirst()
            pending.completion(nil)
        }
        if outbound[centralID]?.isEmpty == true { outbound.removeValue(forKey: centralID) }
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
