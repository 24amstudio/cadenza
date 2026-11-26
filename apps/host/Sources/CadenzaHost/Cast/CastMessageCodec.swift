import Foundation

/// One CASTV2 message. Cast devices exchange these over TLS on port 8009, each one prefixed with its length.
struct CastMessage: Equatable, Sendable {
    var sourceId: String
    var destinationId: String
    var namespace: String
    var payload: String
}

/// Protocol buffer framing for CASTV2 messages. Cadenza writes and reads only the string fields it uses.
enum CastMessageCodec {
    private static let sourceField = 2
    private static let destinationField = 3
    private static let namespaceField = 4
    private static let payloadTypeField = 5
    private static let payloadField = 6
    private static let stringPayload: UInt64 = 0
    private static let lengthDelimited: UInt64 = 2
    private static let varintWire: UInt64 = 0
    private static let fixed64Wire: UInt64 = 1
    private static let fixed32Wire: UInt64 = 5

    static func encode(_ message: CastMessage) -> [UInt8] {
        var bytes: [UInt8] = []
        appendString(&bytes, field: sourceField, message.sourceId)
        appendString(&bytes, field: destinationField, message.destinationId)
        appendString(&bytes, field: namespaceField, message.namespace)
        appendVarintField(&bytes, field: payloadTypeField, value: stringPayload)
        appendString(&bytes, field: payloadField, message.payload)
        return bytes
    }

    /// The message with its four-byte big-endian length in front, as a Cast device expects it on the wire.
    static func frame(_ message: CastMessage) -> [UInt8] {
        let body = encode(message)
        let length = UInt32(body.count)
        return [
            UInt8(length >> 24), UInt8((length >> 16) & 0xFF), UInt8((length >> 8) & 0xFF), UInt8(length & 0xFF),
        ] + body
    }

    /// The body length that a four-byte prefix announces, or nil until all four bytes have arrived.
    static func bodyLength(prefix: [UInt8]) -> Int? {
        guard prefix.count >= 4 else { return nil }

        return prefix.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
    }

    static func decode(_ bytes: [UInt8]) -> CastMessage? {
        var index = 0
        var strings: [Int: String] = [:]
        while index < bytes.count {
            guard let key = readVarint(bytes, &index) else { return nil }
            let field = Int(key >> 3)
            switch key & 0x7 {
            case varintWire:
                guard readVarint(bytes, &index) != nil else { return nil }
            case lengthDelimited:
                guard let length = readVarint(bytes, &index), length <= UInt64(bytes.count - index) else { return nil }
                let end = index + Int(length)
                strings[field] = String(decoding: bytes[index..<end], as: UTF8.self)
                index = end
            case fixed64Wire:
                index += 8
            case fixed32Wire:
                index += 4
            default:
                return nil
            }
            guard index <= bytes.count else { return nil }
        }
        guard let source = strings[sourceField],
            let destination = strings[destinationField],
            let namespace = strings[namespaceField]
        else { return nil }

        return CastMessage(
            sourceId: source, destinationId: destination, namespace: namespace,
            payload: strings[payloadField] ?? "")
    }

    private static func readVarint(_ bytes: [UInt8], _ index: inout Int) -> UInt64? {
        var value: UInt64 = 0
        var shift: UInt64 = 0
        while index < bytes.count, shift < 64 {
            let byte = bytes[index]
            index += 1
            value |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return value }
            shift += 7
        }
        return nil
    }

    private static func appendVarint(_ bytes: inout [UInt8], _ value: UInt64) {
        var remaining = value
        repeat {
            var byte = UInt8(remaining & 0x7F)
            remaining >>= 7
            if remaining != 0 { byte |= 0x80 }
            bytes.append(byte)
        } while remaining != 0
    }

    private static func appendVarintField(_ bytes: inout [UInt8], field: Int, value: UInt64) {
        appendVarint(&bytes, UInt64(field << 3) | varintWire)
        appendVarint(&bytes, value)
    }

    private static func appendString(_ bytes: inout [UInt8], field: Int, _ value: String) {
        appendVarint(&bytes, UInt64(field << 3) | lengthDelimited)
        let utf8 = Array(value.utf8)
        appendVarint(&bytes, UInt64(utf8.count))
        bytes.append(contentsOf: utf8)
    }
}
