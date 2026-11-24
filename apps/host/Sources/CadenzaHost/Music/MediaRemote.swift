import Foundation

/// The MediaRemote command IDs that the framework's send function accepts.
enum MediaRemoteCommand: UInt32 {
    case play = 0
    case pause = 1
    case nextTrack = 4
    case previousTrack = 5
}

/// The private MediaRemote framework, loaded at run time. A missing framework or symbol makes a send return false
/// rather than stop the Host from launching. Its behavior has not been checked against Music on the target Mac.
enum MediaRemote {
    private typealias SendCommand = @convention(c) (UInt32, CFDictionary?) -> Bool

    private static let sendCommand: SendCommand? = {
        guard
            let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW),
            let symbol = dlsym(handle, "MRMediaRemoteSendCommand")
        else { return nil }

        return unsafeBitCast(symbol, to: SendCommand.self)
    }()

    static func send(_ command: MediaRemoteCommand) -> Bool {
        sendCommand?(command.rawValue, nil) ?? false
    }
}
