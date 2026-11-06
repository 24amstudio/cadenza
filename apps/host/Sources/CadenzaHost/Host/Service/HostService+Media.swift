import CryptoKit
import Foundation
import OSLog

// Artwork and motion for a Remote. Full images and motion travel as bounded chunks, paced by the network queue.
extension HostService {
    // Sends the preview first when asked, then the song's motion video when Apple has one, otherwise the full image.
    func loadArtwork(
        peer: NetworkService.Peer, requestId: String?, url: String?, progressive: Bool, previewOnly: Bool,
        motionOccurrenceId: String?
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
        let motionDeadline = monotonicMs() + Self.motionDeadlineMs
        network.send(Frame(type: "operation.started", requestId: requestId), to: peer)
        jobs[key] = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.jobs.removeValue(forKey: key) }
            do {
                guard let data = try await self.artwork.data(for: url) else {
                    throw CadenzaError.failure("artwork_unavailable", "Artwork is unavailable.")
                }
                guard !Task.isCancelled else { return }
                let full = try ArtworkProvider.fullSize(of: data)
                if progressive || previewOnly {
                    // The preview goes first, so a Remote on a slow link can show the cover while the rest follows.
                    var preview = Frame(type: "artwork", requestId: requestId)
                    preview.artworkUrl = url
                    preview.variant = "preview"
                    preview.artworkDataBase64 = try ArtworkProvider.preview(of: data).base64EncodedString()
                    self.network.send(preview, to: peer)
                }
                if previewOnly { return }
                // Motion replaces the full image on the wire. The Remote keeps showing the preview until it verifies.
                var motionVideo: Data?
                if let occurrenceId = motionOccurrenceId {
                    motionVideo = await self.currentMotion(occurrenceId: occurrenceId)
                }
                // A cancelled request sends nothing more, including when its song changed during the lookup.
                guard !Task.isCancelled else { return }
                if let video = motionVideo, let occurrenceId = motionOccurrenceId {
                    await self.sendMotion(
                        video, requestId: requestId, occurrenceId: occurrenceId, deadline: motionDeadline, to: peer)
                } else if progressive {
                    await self.sendArtworkChunks(full, requestId: requestId, url: url, to: peer)
                } else {
                    var frame = Frame(type: "artwork", requestId: requestId)
                    frame.artworkUrl = url
                    frame.artworkDataBase64 = full.base64EncodedString()
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

    // The Remote no longer needs this image or its motion, such as after its song changed. The transfer stops, and the
    // frames it has not started sending are dropped, so the next song's transfer does not wait behind them.
    func cancelArtwork(requestId: String?, peer: NetworkService.Peer) {
        guard let requestId else { return }
        jobs[peer.id + requestId]?.cancel()
        network.cancelBulk(transfer: requestId, to: peer)
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

    // The song's motion video. Nil when Apple has none, the lookup fails, or the song has changed, and each of those sends
    // the full image instead.
    private func currentMotion(occurrenceId: String) async -> Data? {
        guard let current = try? queue.snapshot().current, current.occurrenceId == occurrenceId else { return nil }
        guard let video = try? await motion.video(album: current.song.album, artist: current.song.artist) else {
            return nil
        }
        guard (try? queue.snapshot().current?.occurrenceId) == occurrenceId else { return nil }
        return video
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
        let deadline = monotonicMs() + Self.motionDeadlineMs
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
                await self.sendMotion(
                    video, requestId: requestId, occurrenceId: occurrenceId, deadline: deadline, to: peer)
            } catch {
                if !Task.isCancelled {
                    unavailable.message = error.localizedDescription
                    self.network.send(unavailable, to: peer)
                }
            }
        }
    }

    private static let motionChunkBytes = 480 * 1_024
    // A motion video must reach the Remote within this long after its request, so a slow link cannot hold the next song.
    static let motionDeadlineMs: Int64 = 30_000
    // A Bluetooth frame holds the link until its notifications are sent, so over Bluetooth the video moves in frames the
    // size of artwork chunks and control frames interleave. At this size the largest permitted video needs 512 chunks.
    static let bluetoothMotionChunkBytes = 2 * 1_024
    private static let artworkChunkBytes = 1_024

    private func sendMotion(
        _ video: Data, requestId: String, occurrenceId: String, deadline: Int64, to peer: NetworkService.Peer
    ) async {
        let started = monotonicMs()
        let chunkBytes = peer.transport == "ble" ? Self.bluetoothMotionChunkBytes : Self.motionChunkBytes
        let count = (video.count + chunkBytes - 1) / chunkBytes
        let digest = SHA256.hash(data: video).map { String(format: "%02x", $0) }.joined()
        var sent = 0
        await network.sendBulk(
            count: count,
            makeFrame: { index in
                // The transfer ends at its deadline or when its song has changed, so the link is free for the next song.
                guard monotonicMs() < deadline else { return nil }
                guard (try? self.queue.snapshot().current?.occurrenceId) == occurrenceId else { return nil }
                let start = index * chunkBytes
                var frame = Frame(type: "motion.chunk", requestId: requestId)
                frame.occurrenceId = occurrenceId
                frame.chunkIndex = index
                frame.chunkCount = count
                frame.totalBytes = video.count
                frame.sha256 = digest
                frame.dataBase64 = video[start..<min(start + chunkBytes, video.count)].base64EncodedString()
                sent += 1
                return frame
            }, to: peer)
        let elapsed = monotonicMs() - started
        let metadata = ["occurrence_id": occurrenceId, "bytes": String(video.count), "elapsed_ms": String(elapsed)]
        if sent == count {
            logger.log(
                .info, category: "motion", action: "motion.sent", "Motion artwork sent in \(sent) chunks",
                metadata: metadata)
        } else {
            logger.log(
                .warning, category: "motion", action: "motion.stopped",
                "Motion artwork stopped after \(sent) of \(count) chunks", metadata: metadata)
        }
    }
}
