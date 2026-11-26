import Darwin
import Foundation

/// Records what Host was doing when a fatal signal ended it, so the next launch can report it. The handler writes
/// with write(2), time(2), and backtrace_symbols_fd into buffers allocated at install time, and it re-raises the signal
/// so the watchdog still sees an unclean exit. Symbol names are best effort. The signal, the time, and the active track
/// are always written.
enum CrashCapture {
    private static let recordName = "crash-pending.txt"
    private static let fatalSignals: [Int32] = [SIGABRT, SIGBUS, SIGFPE, SIGILL, SIGSEGV, SIGTRAP]
    private static let trackCapacity = 512
    private static let frameCapacity: Int32 = 64

    // Written once in install(directory:). The handler reads them without a lock, which is acceptable for a record
    // taken while the process is already dying.
    nonisolated(unsafe) private static var descriptor: Int32 = -1
    nonisolated(unsafe) private static var recordPath: String?
    nonisolated(unsafe) private static var activeTrack: UnsafeMutablePointer<CChar>?
    nonisolated(unsafe) private static var frames: UnsafeMutablePointer<UnsafeMutableRawPointer?>?
    nonisolated(unsafe) private static var previousRecord: String?

    private static let handler: @convention(c) (Int32) -> Void = { number in
        CrashCapture.writeFatalRecord(number)
        _ = Darwin.signal(number, SIG_DFL)
        _ = Darwin.raise(number)
    }

    /// Reads the previous session's record, starts this session's record, and installs the fatal-signal handlers.
    static func install(directory: URL) {
        let logs = directory.appendingPathComponent("logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let path = logs.appendingPathComponent(recordName).path
        previousRecord = (try? String(contentsOfFile: path, encoding: .utf8)).flatMap { $0.isEmpty ? nil : $0 }
        recordPath = path
        descriptor = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0o600)

        let track = UnsafeMutablePointer<CChar>.allocate(capacity: trackCapacity)
        track.initialize(repeating: 0, count: trackCapacity)
        activeTrack = track

        let buffer = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: Int(frameCapacity))
        buffer.initialize(repeating: nil, count: Int(frameCapacity))
        frames = buffer
        // The first backtrace loads the unwinder, which may allocate. Calling it here keeps that out of the handler.
        _ = backtrace(buffer, 1)

        for number in fatalSignals {
            _ = Darwin.signal(number, handler)
        }
    }

    /// Keeps the song a fatal record should name. Call it when the song changes, not on each progress sample.
    static func setActiveTrack(_ text: String) {
        guard let activeTrack else { return }
        let bytes = Array(text.utf8.prefix(trackCapacity - 1))
        for (index, byte) in bytes.enumerated() {
            activeTrack[index] = CChar(bitPattern: byte)
        }
        activeTrack[bytes.count] = 0
    }

    /// The record a fatal signal left in the previous session. It is returned once, so the caller logs it once.
    static func takePreviousRecord() -> String? {
        defer { previousRecord = nil }
        return previousRecord
    }

    /// A clean exit removes the record, so the next launch does not report a crash that did not happen.
    static func finishSession() {
        guard descriptor >= 0 else { return }
        _ = close(descriptor)
        descriptor = -1
        if let recordPath { _ = unlink(recordPath) }
    }

    private static func writeFatalRecord(_ number: Int32) {
        guard descriptor >= 0 else { return }
        emit("Cadenza Host ended from ")
        emitSignalName(number)
        emit(" at unix time ")
        emitNumber(Int(time(nil)))
        emit("\nactive track: ")
        if let activeTrack {
            _ = write(descriptor, activeTrack, strnlen(activeTrack, trackCapacity))
        }
        emit("\nstack:\n")
        if let frames {
            let count = backtrace(frames, frameCapacity)
            backtrace_symbols_fd(frames, count, descriptor)
        }
    }

    private static func emit(_ text: StaticString) {
        _ = write(descriptor, text.utf8Start, text.utf8CodeUnitCount)
    }

    private static func emitSignalName(_ number: Int32) {
        switch number {
        case SIGABRT: emit("SIGABRT")
        case SIGBUS: emit("SIGBUS")
        case SIGFPE: emit("SIGFPE")
        case SIGILL: emit("SIGILL")
        case SIGSEGV: emit("SIGSEGV")
        case SIGTRAP: emit("SIGTRAP")
        default: emit("an unrecognized signal")
        }
    }

    private static func emitNumber(_ value: Int) {
        withUnsafeTemporaryAllocation(of: UInt8.self, capacity: 20) { buffer in
            var remaining = max(0, value)
            var index = buffer.count
            repeat {
                index -= 1
                buffer[index] = UInt8(48 + remaining % 10)
                remaining /= 10
            } while remaining > 0 && index > 0
            _ = write(descriptor, buffer.baseAddress! + index, buffer.count - index)
        }
    }
}
