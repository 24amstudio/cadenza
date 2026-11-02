import Foundation

/// Moves separator work away from the Core Audio callback and bounds queued
/// audio so a slow model cannot grow memory without limit.
final class SingAudioPipeline: @unchecked Sendable {
    private let separator: SingSeparator
    private let output: SingOutputSink
    private let mixState: SingMixState
    private let worker = DispatchQueue(label: "app.cadence.host.sing.dsp", qos: .userInitiated)
    private let lock = NSLock()
    private let maximumPending = 3
    private var accepting = false
    private var pending = 0
    // Bumped by flush(). Output from an older generation is dropped under `lock`, so
    // no stale audio can reach the output after flush() returns.
    private var generation = 0
    private var failureReported = false
    private let onFailure: @Sendable (String) -> Void

    init(
        separator: SingSeparator,
        output: SingOutputSink,
        mixState: SingMixState,
        onFailure: @escaping @Sendable (String) -> Void
    ) {
        self.separator = separator
        self.output = output
        self.mixState = mixState
        self.onFailure = onFailure
    }

    func start() {
        lock.lock()
        accepting = true
        pending = 0
        failureReported = false
        lock.unlock()
    }

    func submit(_ buffer: SingAudioBuffer) {
        lock.lock()
        guard accepting, pending < maximumPending else {
            lock.unlock()
            buffer.release()
            return
        }
        pending += 1
        let submittedGeneration = generation
        lock.unlock()
        worker.async { [weak self] in
            defer { buffer.release() }
            guard let self else { return }
            defer { self.finished() }
            do {
                if let streaming = self.separator as? SingStreamingSeparator {
                    for processed in try streaming.processStreaming(buffer, vocalPercent: self.mixState.get()) {
                        self.enqueue(processed, submittedGeneration: submittedGeneration)
                    }
                } else {
                    let processed = try self.separator.process(buffer, vocalPercent: self.mixState.get())
                    self.enqueue(processed, submittedGeneration: submittedGeneration)
                }
            } catch {
                self.fail(error.localizedDescription)
            }
        }
    }

    /// Discards queued output and buffered input. The separator is reset on the DSP queue after
    /// work already submitted, so no earlier block can refill it after the reset.
    func flush() {
        lock.lock()
        generation += 1
        output.flush()
        lock.unlock()
        worker.async { [weak self] in
            guard let self, let streaming = self.separator as? SingStreamingSeparator else { return }
            streaming.discardStreamingState()
        }
    }

    private func enqueue(_ buffer: SingAudioBuffer, submittedGeneration: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard submittedGeneration == generation else { return }
        output.enqueue(buffer)
    }

    func stop() {
        lock.lock()
        accepting = false
        lock.unlock()
        worker.sync {
            do {
                if let streaming = separator as? SingStreamingSeparator {
                    for buffer in try streaming.finishStreaming() {
                        output.enqueue(buffer)
                    }
                }
            } catch {
                fail(error.localizedDescription)
            }
        }
    }

    private func fail(_ message: String) {
        lock.lock()
        accepting = false
        let shouldReport = !failureReported
        failureReported = true
        lock.unlock()
        // Audio engine teardown belongs to SingCoordinator's MainActor. Calling
        // AVAudioEngine.stop from this DSP queue races route changes and can take
        // down the Host while the user is starting Sing.
        if shouldReport { onFailure(message) }
    }

    private func finished() {
        lock.lock()
        pending = max(0, pending - 1)
        lock.unlock()
    }
}
