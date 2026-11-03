import CryptoKit
import Foundation

// RFC 6455 framing for browser Remotes. Protocol messages travel as unfragmented, masked text frames from the browser.
// Everything else either answers the control protocol or closes the connection with a status code.
enum WebSocketFraming {
    static let handshakeGUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
    static let maximumPayloadBytes = Wire.maximumMessageBytes

    enum Event: Equatable {
        case text([UInt8])
        case ping([UInt8])
        case pong
        case close
    }

    // A protocol violation. The connection answers with a close frame carrying this status and then ends.
    struct ProtocolViolation: Error, Equatable {
        let closeCode: UInt16
    }

    static func acceptValue(forKey key: String) -> String {
        let digest = Insecure.SHA1.hash(data: Data((key + handshakeGUID).utf8))
        return Data(digest).base64EncodedString()
    }

    // A client key is 16 random bytes encoded as base64.
    static func isValidKey(_ key: String) -> Bool {
        guard let bytes = Data(base64Encoded: key) else { return false }
        return bytes.count == 16
    }

    static func handshakeResponse(forKey key: String) -> Data {
        let lines = [
            "HTTP/1.1 101 Switching Protocols",
            "Upgrade: websocket",
            "Connection: Upgrade",
            "Sec-WebSocket-Accept: \(acceptValue(forKey: key))",
            "Cache-Control: no-store",
            "",
            "",
        ]
        return Data(lines.joined(separator: "\r\n").utf8)
    }

    // Removes and returns every complete frame at the start of the buffer. An incomplete frame stays buffered.
    static func parseFrames(_ buffer: inout [UInt8]) throws -> [Event] {
        var events: [Event] = []
        while let event = try parseFrame(&buffer) {
            events.append(event)
        }
        return events
    }

    static func textFrame(_ payload: [UInt8]) -> Data {
        Data(encode(opcode: 0x1, payload: payload))
    }

    static func pongFrame(_ payload: [UInt8]) -> Data {
        Data(encode(opcode: 0xA, payload: payload))
    }

    static func closeFrame(code: UInt16) -> Data {
        Data(encode(opcode: 0x8, payload: [UInt8(code >> 8), UInt8(code & 0xFF)]))
    }

    private static func parseFrame(_ buffer: inout [UInt8]) throws -> Event? {
        guard buffer.count >= 2 else { return nil }
        let first = buffer[0]
        let second = buffer[1]
        // Reserved bits belong to extensions this server does not negotiate.
        guard first & 0x70 == 0 else { throw ProtocolViolation(closeCode: 1002) }
        // Clients must mask every frame; an unmasked frame is a protocol error.
        guard second & 0x80 != 0 else { throw ProtocolViolation(closeCode: 1002) }
        let fin = first & 0x80 != 0
        let opcode = first & 0x0F
        guard let lengths = try payloadLength(buffer, lengthByte: second & 0x7F) else { return nil }
        let (length, headerLength) = lengths
        if opcode >= 0x8 {
            guard fin, length <= 125 else { throw ProtocolViolation(closeCode: 1002) }
        }
        let frameLength = headerLength + 4 + length
        guard buffer.count >= frameLength else { return nil }
        let mask = Array(buffer[headerLength..<(headerLength + 4)])
        let payloadStart = headerLength + 4
        var payload = [UInt8](repeating: 0, count: length)
        for index in 0..<length {
            payload[index] = buffer[payloadStart + index] ^ mask[index % 4]
        }
        buffer.removeFirst(frameLength)
        return try event(opcode: opcode, fin: fin, payload: payload)
    }

    private static func event(opcode: UInt8, fin: Bool, payload: [UInt8]) throws -> Event {
        switch opcode {
        case 0x1:
            // Fragmentation is not negotiated, so every text message must arrive in one frame.
            guard fin else { throw ProtocolViolation(closeCode: 1002) }
            return .text(payload)
        case 0x2:
            // Binary data is not part of the Remote protocol.
            throw ProtocolViolation(closeCode: 1003)
        case 0x8: return .close
        case 0x9: return .ping(payload)
        case 0xA: return .pong
        default: throw ProtocolViolation(closeCode: 1002)
        }
    }

    // Returns the payload length and the number of header bytes before the mask, or nil while the length is incomplete.
    private static func payloadLength(_ buffer: [UInt8], lengthByte: UInt8) throws -> (Int, Int)? {
        switch lengthByte {
        case 126:
            guard buffer.count >= 4 else { return nil }
            let length = Int(buffer[2]) << 8 | Int(buffer[3])
            return (length, 4)
        case 127:
            guard buffer.count >= 10 else { return nil }
            var value: UInt64 = 0
            for index in 2..<10 {
                value = value << 8 | UInt64(buffer[index])
            }
            guard value <= UInt64(maximumPayloadBytes) else { throw ProtocolViolation(closeCode: 1009) }
            return (Int(value), 10)
        default:
            return (Int(lengthByte), 2)
        }
    }

    // Server frames are not masked.
    private static func encode(opcode: UInt8, payload: [UInt8]) -> [UInt8] {
        var frame: [UInt8] = [0x80 | opcode]
        let count = payload.count
        if count < 126 {
            frame.append(UInt8(count))
        } else if count <= 0xFFFF {
            frame.append(126)
            frame.append(UInt8(count >> 8))
            frame.append(UInt8(count & 0xFF))
        } else {
            frame.append(127)
            for shift in stride(from: 56, through: 0, by: -8) {
                frame.append(UInt8((UInt64(count) >> UInt64(shift)) & 0xFF))
            }
        }
        frame.append(contentsOf: payload)
        return frame
    }
}
