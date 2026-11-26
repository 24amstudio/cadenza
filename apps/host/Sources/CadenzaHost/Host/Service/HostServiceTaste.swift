import Foundation

extension HostService {
    /// Keeps the digest a Remote sent at hello. A hello without one means the Remote has opted out, so its digest is removed.
    func receiveTasteDigest(_ auth: DeviceAuth) throws {
        let digests = TasteDigestStore(database: store.database)
        if let digest = auth.tasteDigest {
            try digests.save(try digest.validated(), remoteId: auth.remoteId, at: Date())
        } else {
            try digests.remove(remoteId: auth.remoteId)
        }
    }
}
