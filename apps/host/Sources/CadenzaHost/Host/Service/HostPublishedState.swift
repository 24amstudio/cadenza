import Foundation

/// What the Host adds to each state snapshot beyond the queue. Cast discovery starts with the first snapshot and runs
/// for the life of the Host, so the device list is current when a Remote asks for it.
@MainActor
final class HostPublishedState {
    var hostBudget: HostOperatingBudget = .unrestricted
    let castDiscovery = CastDiscovery()

    func apply(to snapshot: inout HostSnapshot) {
        snapshot.hostBudget = hostBudget.rawValue
        castDiscovery.start()
        let stored = UserDefaults.standard.string(forKey: "castPresentationMode")
        let presentation = stored.flatMap(CastPresentationMode.init(rawValue:)) ?? .auto
        snapshot.cast = CastSnapshot.make(devices: castDiscovery.devices, presentation: presentation)
    }
}
