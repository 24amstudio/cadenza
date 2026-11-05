import CryptoKit
import Foundation
import OSLog

// Artwork and motion for a Remote. Full images and motion travel as bounded chunks, paced by the network queue.
extension HostService {
    func loadArtwork(
        peer: NetworkService.Peer, requestId: String?, url: String?, progressive: Bool
    ) {
        guard let requestId, let url else {
            fail(
                CadenzaError.failure("artwork_unavailable", "Artwork request is invalid."),
                request: Frame(type: "artwork.get", requestId: requestId), peer: peer)
            return
        }
        // A refusal is answered with artwork.unavailable, which releases the Remote's pending request. An error
        // frame would leave that request pending, so the artwork would never be asked for again.
        guard ArtworkProvider.isServableURL(url), jobs.count < 16 else {
            var refusal = Frame(type: "artwork.unavailable", requestId: requestId)
            refusal.artworkUrl = url
            refusal.message = "Artwork is not available from Cadenza Host right now."
            network.send(refusal, to: peer)
            return
        }
        let key = peer.id + requestId
        jobs[key]?.cancel()
        network.send(Frame(type: "operation.started", requestId: requestId), to: peer)
        jobs[key] = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.jobs.removeValue(forKey: key) }
            do {
                guard let data = try await self.artwork.data(for: url) else {
                    throw CadenzaError.failure("artwork_unavailable", "Artwork is unavailable.")
                }
                if progressive {
                    // The preview goes first, so a Remote on a slow link can show the cover while the full image follows.
                    var preview = Frame(type: "artwork", requestId: requestId)
                    preview.artworkUrl = url
                    preview.variant = "preview"
                    preview.artworkDataBase64 = try ArtworkProvider.preview(of: data).base64EncodedString()
                    self.network.send(preview, to: peer)
                    await self.sendArtworkChunks(data, requestId: requestId, url: url, to: peer)
                } else {
                    var frame = Frame(type: "artwork", requestId: requestId)
                    frame.artworkUrl = url
                    frame.artworkDataBase64 = data.base64EncodedString()
                    self.network.send(frame, to: peer)
                }
            } catch {
                if !Task.isCancelled {
                    var frame = Frame(type: "artwork.unavailable", requestId: requestId)
                    frame.artworkUrl = url
                    frame.message = error.localizedDescription
                    self.network.send(frame, to: peer)
                }
            }
        }
    }

    // The full image travels as bounded chunks. Each chunk carries the digest of the whole file for the Remote to check.
    private func sendArtworkChunks(_ data: Data, requestId: String, url: String, to peer: NetworkService.Peer) async {
        let count = (data.count + Self.artworkChunkBytes - 1) / Self.artworkChunkBytes
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        await network.sendBulk(
            count: count,
            makeFrame: { index in
                let start = index * Self.artworkChunkBytes
                var frame = Frame(type: "artwork.chunk", requestId: requestId)
                frame.artworkUrl = url
                frame.chunkIndex = index
                frame.chunkCount = count
                frame.totalBytes = data.count
                frame.sha256 = digest
                frame.dataBase64 = data[start..<min(start + Self.artworkChunkBytes, data.count)].base64EncodedString()
                return frame
            }, to: peer)
    }

    func loadMotion(peer: NetworkService.Peer, requestId: String?, occurrenceId: String?) {
        guard let requestId, let occurrenceId else {
            fail(
                CadenzaError.failure("motion_unavailable", "Motion request is invalid."),
                request: Frame(type: "motion.get", requestId: requestId), peer: peer)
            return
        }
        let key = peer.id + requestId
        jobs[key]?.cancel()
        jobs[key] = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.jobs.removeValue(forKey: key) }
            var unavailable = Frame(type: "motion.unavailable", requestId: requestId)
            unavailable.occurrenceId = occurrenceId
            do {
                guard let current = try self.queue.snapshot().current, current.occurrenceId == occurrenceId,
                    let video = try await self.motion.video(album: current.song.album, artist: current.song.artist)
                else {
                    self.network.send(unavailable, to: peer)
                    return
                }
                // The song may change during the download. The newer occurrence has its own request.
                guard try self.queue.snapshot().current?.occurrenceId == occurrenceId else { return }
                await self.sendMotion(video, requestId: requestId, occurrenceId: occurrenceId, to: peer)
            } catch {
                if !Task.isCancelled {
                    unavailable.message = error.localizedDescription
                    self.network.send(unavailable, to: peer)
                }
            }
        }
    }

    private static let motionChunkBytes = 480 * 1_024
    private static let artworkChunkBytes = 1_024

    private func sendMotion(_ video: Data, requestId: String, occurrenceId: String, to peer: NetworkService.Peer) async
    {
        let count = (video.count + Self.motionChunkBytes - 1) / Self.motionChunkBytes
        let digest = SHA256.hash(data: video).map { String(format: "%02x", $0) }.joined()
        await network.sendBulk(
            count: count,
            makeFrame: { index in
                let start = index * Self.motionChunkBytes
                var frame = Frame(type: "motion.chunk", requestId: requestId)
                frame.occurrenceId = occurrenceId
                frame.chunkIndex = index
                frame.chunkCount = count
                frame.totalBytes = video.count
                frame.sha256 = digest
                frame.dataBase64 = video[start..<min(start + Self.motionChunkBytes, video.count)].base64EncodedString()
                return frame
            }, to: peer)
        logger.log(
            .info, category: "motion", action: "motion.sent", "Motion artwork sent in \(count) chunks",
            metadata: ["occurrence_id": occurrenceId, "bytes": String(video.count)])
    }
}
