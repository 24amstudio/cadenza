import Foundation

enum HostResources {
    static var bundle: Bundle {
        if let root = Bundle.main.resourceURL,
           let bundle = Bundle(url: root.appendingPathComponent("CadenzaHost_CadenzaHost.bundle")) {
            return bundle
        }
        return Bundle.module
    }
}
