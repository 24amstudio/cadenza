extension HostModel {
    /// The connected Remotes that can take a Wi-Fi subwoofer split. A Remote needs a connected LAN path, because a
    /// Bluetooth-only Remote cannot stream.
    var wifiSplitRemotes: [PairedRemote] {
        connectedRemotes.filter { remote in
            remote.status?.paths.contains { $0.transport == "lan" && $0.state == "connected" } == true
        }
    }
}
