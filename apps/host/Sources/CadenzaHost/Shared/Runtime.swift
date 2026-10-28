import Foundation

func identifier() -> String { UUID().uuidString.lowercased() }

func monotonicMs() -> Int64 {
    Int64(ProcessInfo.processInfo.systemUptime * 1_000)
}

func wallMs() -> Int64 { Int64(Date().timeIntervalSince1970 * 1_000) }
