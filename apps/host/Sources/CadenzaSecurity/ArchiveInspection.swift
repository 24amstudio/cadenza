import Foundation

public enum ArchiveInspection {
    public static func validate(_ data: Data) throws {
        guard data.count >= 22, data.count <= 134_217_728 else { throw invalid() }
        let bytes = [UInt8](data)
        let floor = max(0, bytes.count - 65_557)
        guard
            let end = stride(from: bytes.count - 22, through: floor, by: -1).first(where: {
                word(bytes, $0) == 0x0605_4b50 && $0 + 22 + Int(short(bytes, $0 + 20)) == bytes.count
            })
        else { throw invalid() }
        let count = Int(short(bytes, end + 10))
        let start = Int(word(bytes, end + 16))
        let length = Int(word(bytes, end + 12))
        guard short(bytes, end + 4) == 0, short(bytes, end + 6) == 0,
            Int(short(bytes, end + 8)) == count, (1...10_000).contains(count),
            start + length == end
        else { throw invalid() }
        var cursor = start
        var expanded: UInt64 = 0
        var names: Set<String> = []
        var regions: [Range<Int>] = []
        for _ in 0..<count {
            guard cursor >= 0, cursor + 46 <= end, word(bytes, cursor) == 0x0201_4b50 else { throw invalid() }
            let flags = short(bytes, cursor + 8)
            let method = short(bytes, cursor + 10)
            let compressed = Int(word(bytes, cursor + 20))
            let size = word(bytes, cursor + 24)
            let nameSize = Int(short(bytes, cursor + 28))
            let extraSize = Int(short(bytes, cursor + 30))
            let commentSize = Int(short(bytes, cursor + 32))
            let next = cursor + 46 + nameSize + extraSize + commentSize
            guard next <= end, nameSize > 0, nameSize <= 1024,
                flags & 1 == 0, [0, 8].contains(method), short(bytes, cursor + 34) == 0,
                compressed <= 134_217_728, size <= 268_435_456,
                let name = String(bytes: bytes[(cursor + 46)..<(cursor + 46 + nameSize)], encoding: .utf8),
                validPath(name), names.insert(name).inserted
            else { throw invalid() }
            let mode = (word(bytes, cursor + 38) >> 16) & 0xf000
            guard mode == 0 || mode == 0x8000 || (mode == 0x4000 && name.hasSuffix("/")) else { throw invalid() }
            try validateExtras(bytes, start: cursor + 46 + nameSize, end: cursor + 46 + nameSize + extraSize)
            expanded += UInt64(size)
            guard expanded <= 268_435_456 else { throw invalid() }
            let local = Int(word(bytes, cursor + 42))
            guard local >= 0, local + 30 <= start, word(bytes, local) == 0x0403_4b50,
                short(bytes, local + 6) == flags, short(bytes, local + 8) == method
            else { throw invalid() }
            let localNameSize = Int(short(bytes, local + 26))
            let localExtra = Int(short(bytes, local + 28))
            let payload = local + 30 + localNameSize + localExtra
            guard localNameSize == nameSize, payload + compressed <= start,
                bytes[(local + 30)..<(local + 30 + localNameSize)].elementsEqual(
                    bytes[(cursor + 46)..<(cursor + 46 + nameSize)])
            else { throw invalid() }
            try validateExtras(bytes, start: local + 30 + localNameSize, end: payload)
            regions.append(local..<(payload + compressed))
            cursor = next
        }
        guard cursor == end else { throw invalid() }
        let sorted = regions.sorted { $0.lowerBound < $1.lowerBound }
        for index in sorted.indices.dropFirst() where sorted[index - 1].upperBound > sorted[index].lowerBound {
            throw invalid()
        }
    }

    public static func validateExecutable(_ data: Data) throws {
        let bytes = [UInt8](data.prefix(32))
        guard bytes.count == 32, word(bytes, 0) == 0xfeed_facf, word(bytes, 4) == 0x0100_000c else {
            throw ReleaseFailure.invalid("The update must contain the native Apple silicon executable.")
        }
    }

    private static func validPath(_ name: String) -> Bool {
        guard name.hasPrefix("Cadenza Host.app/"), !name.contains("\\"),
            !name.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 })
        else { return false }
        let components = name.split(separator: "/", omittingEmptySubsequences: false)
        return components.dropLast().allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
            && components.last != "." && components.last != ".."
    }

    private static func validateExtras(_ bytes: [UInt8], start: Int, end: Int) throws {
        var cursor = start
        while cursor < end {
            guard cursor + 4 <= end else { throw invalid() }
            let type = short(bytes, cursor)
            let size = Int(short(bytes, cursor + 2))
            guard ![0x0001, 0x000d, 0x7075, 0x756e].contains(type), cursor + 4 + size <= end else { throw invalid() }
            cursor += 4 + size
        }
    }

    private static func short(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
    }

    private static func word(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        UInt32(short(bytes, offset)) | UInt32(short(bytes, offset + 2)) << 16
    }

    private static func invalid() -> ReleaseFailure {
        .invalid("The update archive contains unsupported, unsafe, or oversized entries.")
    }
}
