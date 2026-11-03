import CryptoKit
import Foundation
import XCTest

@testable import CadenzaHost

final class WebSocketFramingTests: XCTestCase {
    func testAcceptValueMatchesTheRFCExample() {
        XCTAssertEqual(
            WebSocketFraming.acceptValue(forKey: "dGhlIHNhbXBsZSBub25jZQ=="), "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=")
    }

    func testDecodesTheMaskedTextFrameFromTheRFCExample() throws {
        var buffer: [UInt8] = [0x81, 0x85, 0x37, 0xFA, 0x21, 0x3D, 0x7F, 0x9F, 0x4D, 0x51, 0x58]
        XCTAssertEqual(try WebSocketFraming.parseFrames(&buffer), [.text(Array("Hello".utf8))])
        XCTAssertTrue(buffer.isEmpty)
    }

    func testAnIncompleteFrameStaysBufferedUntilItArrives() throws {
        var buffer: [UInt8] = [0x81, 0x85, 0x37, 0xFA]
        XCTAssertEqual(try WebSocketFraming.parseFrames(&buffer), [])
        XCTAssertEqual(buffer.count, 4)
    }

    func testRefusesUnmaskedClientFrames() {
        var buffer: [UInt8] = [0x81, 0x05] + Array("Hello".utf8)
        XCTAssertThrowsError(try WebSocketFraming.parseFrames(&buffer)) { error in
            XCTAssertEqual(
                error as? WebSocketFraming.ProtocolViolation, WebSocketFraming.ProtocolViolation(closeCode: 1002))
        }
    }

    func testRefusesFragmentedAndBinaryMessages() {
        var fragmented: [UInt8] = [0x01, 0x80, 0, 0, 0, 0]
        XCTAssertThrowsError(try WebSocketFraming.parseFrames(&fragmented)) { error in
            XCTAssertEqual(
                error as? WebSocketFraming.ProtocolViolation, WebSocketFraming.ProtocolViolation(closeCode: 1002))
        }
        var binary: [UInt8] = [0x82, 0x80, 0, 0, 0, 0]
        XCTAssertThrowsError(try WebSocketFraming.parseFrames(&binary)) { error in
            XCTAssertEqual(
                error as? WebSocketFraming.ProtocolViolation, WebSocketFraming.ProtocolViolation(closeCode: 1003))
        }
    }

    func testRefusesLengthsAboveTheProtocolLimitBeforeBuffering() {
        var buffer: [UInt8] = [0x81, 0xFF, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x80, 0, 0, 0, 0]
        XCTAssertThrowsError(try WebSocketFraming.parseFrames(&buffer)) { error in
            XCTAssertEqual(
                error as? WebSocketFraming.ProtocolViolation, WebSocketFraming.ProtocolViolation(closeCode: 1009))
        }
    }

    func testAnsweredPingsCarryTheSamePayload() throws {
        var buffer: [UInt8] = [0x89, 0x82, 0, 0, 0, 0, 0x01, 0x02]
        XCTAssertEqual(try WebSocketFraming.parseFrames(&buffer), [.ping([0x01, 0x02])])
        XCTAssertEqual(WebSocketFraming.pongFrame([0x01, 0x02]), Data([0x8A, 0x02, 0x01, 0x02]))
    }

    func testServerFramesUseExtendedLengthsAndAreUnmasked() {
        let frame = WebSocketFraming.textFrame(Array(repeating: 0x61, count: 300))
        XCTAssertEqual(Array(frame.prefix(4)), [0x81, 126, 0x01, 0x2C])
        XCTAssertEqual(frame.count, 4 + 300)
        XCTAssertEqual(WebSocketFraming.closeFrame(code: 1000), Data([0x88, 0x02, 0x03, 0xE8]))
    }

    func testAKeyMustBeSixteenRandomBytes() {
        XCTAssertTrue(WebSocketFraming.isValidKey("dGhlIHNhbXBsZSBub25jZQ=="))
        XCTAssertFalse(WebSocketFraming.isValidKey("c2hvcnQ="))
        XCTAssertFalse(WebSocketFraming.isValidKey("not base64!"))
    }
}

final class WebRemoteRequestTests: XCTestCase {
    private let allowed: Set<String> = ["192.168.1.20:43129", "localhost:43129"]

    private func bytes(_ lines: [String]) -> [UInt8] {
        Array((lines.joined(separator: "\r\n") + "\r\n\r\n").utf8)
    }

    private func socketRequest(
        host: String = "192.168.1.20:43129", origin: String? = "http://192.168.1.20:43129",
        upgrade: String = "websocket", version: String = "13"
    ) -> [UInt8] {
        var lines = [
            "GET /v1/socket HTTP/1.1", "Host: \(host)", "Upgrade: \(upgrade)", "Connection: Upgrade",
            "Sec-WebSocket-Version: \(version)", "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==",
        ]
        if let origin { lines.append("Origin: \(origin)") }
        return bytes(lines)
    }

    func testParsesTheRequestHeadAndReportsItsLength() {
        let request = bytes(["GET / HTTP/1.1", "Host: localhost:43129"])
        guard case .complete(let parsed, let consumed) = WebRemoteRequest.parse(request) else {
            return XCTFail("A complete head should parse.")
        }
        XCTAssertEqual(parsed.method, "GET")
        XCTAssertEqual(parsed.headers["host"], "localhost:43129")
        XCTAssertEqual(consumed, request.count)
    }

    func testWaitsForTheEndOfTheHead() {
        XCTAssertEqual(WebRemoteRequest.parse(Array("GET / HTTP/1.1\r\nHost: x".utf8)), .incomplete)
    }

    func testRefusesOversizedHeadsAndAmbiguousDuplicates() {
        let oversized = Array(repeating: UInt8(0x61), count: WebRemoteRequest.maximumHeadBytes + 1)
        XCTAssertEqual(WebRemoteRequest.parse(oversized), .invalid)
        let duplicated = bytes(["GET / HTTP/1.1", "Host: a", "Host: b"])
        XCTAssertEqual(WebRemoteRequest.parse(duplicated), .invalid)
    }

    func testTheSameOriginSocketRequestIsUpgraded() {
        guard case .complete(let request, _) = WebRemoteRequest.parse(socketRequest()) else {
            return XCTFail("The socket request should parse.")
        }
        XCTAssertEqual(
            WebRemoteRequest.route(request, allowedHosts: allowed),
            .socket(key: "dGhlIHNhbXBsZSBub25jZQ=="))
    }

    func testSocketRequestsFromOtherOriginsAreForbidden() {
        for raw in [
            socketRequest(origin: "http://attacker.example"),
            socketRequest(origin: nil),
            socketRequest(host: "attacker.example:43129", origin: "http://attacker.example:43129"),
        ] {
            guard case .complete(let request, _) = WebRemoteRequest.parse(raw) else {
                return XCTFail("The request should parse before routing.")
            }
            XCTAssertEqual(WebRemoteRequest.route(request, allowedHosts: allowed), .reject(status: 403))
        }
    }

    func testMalformedUpgradesAreBadRequests() {
        guard case .complete(let request, _) = WebRemoteRequest.parse(socketRequest(version: "8")) else {
            return XCTFail("The request should parse before routing.")
        }
        XCTAssertEqual(WebRemoteRequest.route(request, allowedHosts: allowed), .reject(status: 400))
    }

    func testOnlyReadsReachStaticFiles() {
        guard case .complete(let get, _) = WebRemoteRequest.parse(bytes(["GET / HTTP/1.1", "Host: a"])),
            case .complete(let head, _) = WebRemoteRequest.parse(bytes(["HEAD / HTTP/1.1", "Host: a"])),
            case .complete(let post, _) = WebRemoteRequest.parse(bytes(["POST / HTTP/1.1", "Host: a"]))
        else { return XCTFail("The requests should parse.") }
        XCTAssertEqual(WebRemoteRequest.route(get, allowedHosts: allowed), .file(path: "/", headOnly: false))
        XCTAssertEqual(WebRemoteRequest.route(head, allowedHosts: allowed), .file(path: "/", headOnly: true))
        XCTAssertEqual(WebRemoteRequest.route(post, allowedHosts: allowed), .reject(status: 405))
    }
}

final class WebRemoteBundleTests: XCTestCase {
    private func temporaryBundle() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(identifier(), isDirectory: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("_nuxt", isDirectory: true), withIntermediateDirectories: true)
        try Data("<script>window.ready=true</script>".utf8).write(to: root.appendingPathComponent("index.html"))
        try Data("console.log(1)".utf8).write(to: root.appendingPathComponent("_nuxt/app.js"))
        try Data("SECRET=1".utf8).write(to: root.appendingPathComponent(".env"))
        try Data("SECRET=2".utf8).write(to: root.appendingPathComponent("notes.md"))
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("folder", isDirectory: true), withIntermediateDirectories: true)
        return root
    }

    func testRelativePathsStayInsideTheBundle() {
        XCTAssertNil(WebRemoteBundle.relativePath(forRequestPath: "/../secret"))
        XCTAssertNil(WebRemoteBundle.relativePath(forRequestPath: "/%2e%2e/secret"))
        XCTAssertNil(WebRemoteBundle.relativePath(forRequestPath: "/.env"))
        XCTAssertNil(WebRemoteBundle.relativePath(forRequestPath: "/a\\b"))
        XCTAssertNil(WebRemoteBundle.relativePath(forRequestPath: "relative"))
        XCTAssertEqual(WebRemoteBundle.relativePath(forRequestPath: "/"), "index.html")
        XCTAssertEqual(WebRemoteBundle.relativePath(forRequestPath: "/_nuxt/app.js?v=1"), "_nuxt/app.js")
    }

    func testOnlyListedRegularFilesAreServed() throws {
        let bundle = WebRemoteBundle(root: try temporaryBundle())
        XCTAssertEqual(bundle.file(forRequestPath: "/")?.contentType, "text/html; charset=utf-8")
        XCTAssertEqual(bundle.file(forRequestPath: "/_nuxt/app.js")?.isHashedAsset, true)
        XCTAssertNil(bundle.file(forRequestPath: "/.env"))
        XCTAssertNil(bundle.file(forRequestPath: "/notes.md"))
        XCTAssertNil(bundle.file(forRequestPath: "/folder"))
        XCTAssertNil(bundle.file(forRequestPath: "/missing.js"))
    }

    func testInlineScriptsAreAllowedOnlyByTheirHash() throws {
        let bundle = WebRemoteBundle(root: try temporaryBundle())
        let expected = "'sha256-\(Data(SHA256.hash(data: Data("window.ready=true".utf8))).base64EncodedString())'"
        XCTAssertTrue(bundle.contentSecurityPolicy.contains("script-src 'self' \(expected)"))
        XCTAssertFalse(bundle.contentSecurityPolicy.contains("script-src 'self' 'unsafe-inline'"))
    }

    func testExternalScriptsAreNotHashed() {
        let html = "<script>window.x=1</script><script src=\"/a.js\"></script><script type=\"importmap\">{}</script>"
        XCTAssertEqual(WebRemoteBundle.inlineScriptHashes(in: html).count, 2)
    }

    func testAnEmptyInlineScriptHasTheKnownDigest() {
        XCTAssertEqual(
            WebRemoteBundle.inlineScriptHashes(in: "<script></script>"),
            ["'sha256-47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU='"])
    }

    func testThePolicyBlocksFramingAndForeignConnections() {
        let policy = WebRemoteBundle.policy(scriptHashes: [])
        XCTAssertTrue(policy.contains("frame-ancestors 'none'"))
        XCTAssertTrue(policy.contains("default-src 'none'"))
        XCTAssertTrue(policy.contains("connect-src 'self'"))
    }
}
