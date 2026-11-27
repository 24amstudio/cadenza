import SystemConfiguration

/// This Mac's Bonjour name, such as `my-mac.local`. A browser resolves it through mDNS, so it keeps reaching the Host
/// after the Mac's LAN address changes. Nil when the Mac has no local host name.
enum BonjourName {
    static func current() -> String? {
        guard let localName = SCDynamicStoreCopyLocalHostName(nil) as String?, !localName.isEmpty else { return nil }

        return localName.lowercased() + ".local"
    }
}
