import Foundation
import XCTest

@testable import CadenzaHost

// Runs the real listener and WebSocket upgrade over plain HTTP, the transport the browser Remote uses on the LAN.
@MainActor
final class WebRemoteListenerTests: XCTestCase {
    private var directory: URL?

    override func setUp() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "cadenza-web-listener-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        directory = root
    }

    override func tearDown() async throws {
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    private func makeBundle(in root: URL) throws -> URL {
        let bundle = root.appendingPathComponent("WebRemote", isDirectory: true)
        try FileManager.default.createDirectory(
            at: bundle.appendingPathComponent("_nuxt", isDirectory: true), withIntermediateDirectories: true)
        try Data("<!doctype html><script>window.ready=true</script>".utf8)
            .write(to: bundle.appendingPathComponent("index.html"))
        try Data("console.log('remote')".utf8).write(to: bundle.appendingPathComponent("_nuxt/app.js"))
        return bundle
    }

    func testServesThePageAndUpgradesOnlySameOriginSockets() async throws {
        let root = try XCTUnwrap(directory)
        let port = UInt16.random(in: 49_152...60_000)
        let bundle = try makeBundle(in: root)
        let listener = WebRemoteListener()
        listener.onSocket = { socket in
            socket.onText = { bytes in _ = socket.send(Data(bytes)) }
        }
        try await listener.start(
            port: port, bundle: WebRemoteBundle(root: bundle), allowedHosts: { ["127.0.0.1:\(port)"] })
        defer { listener.stop() }

        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }

        let page = try await session.data(from: URL(string: "http://127.0.0.1:\(port)/")!)
        let pageResponse = try XCTUnwrap(page.1 as? HTTPURLResponse)
        XCTAssertEqual(pageResponse.statusCode, 200)
        XCTAssertTrue(String(decoding: page.0, as: UTF8.self).contains("window.ready=true"))
        XCTAssertTrue(
            (pageResponse.value(forHTTPHeaderField: "Content-Security-Policy") ?? "").contains(
                "script-src 'self' 'sha256-"))
        XCTAssertEqual(pageResponse.value(forHTTPHeaderField: "X-Content-Type-Options"), "nosniff")

        let script = try await session.data(from: URL(string: "http://127.0.0.1:\(port)/_nuxt/app.js")!)
        XCTAssertEqual((script.1 as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(String(decoding: script.0, as: UTF8.self), "console.log('remote')")

        var sameOrigin = URLRequest(url: URL(string: "ws://127.0.0.1:\(port)/v1/socket")!)
        sameOrigin.setValue("http://127.0.0.1:\(port)", forHTTPHeaderField: "Origin")
        let socket = session.webSocketTask(with: sameOrigin)
        socket.resume()
        try await socket.send(.string("{\"type\":\"ping\"}"))
        guard case .string(let echoed) = try await socket.receive() else {
            return XCTFail("The Remote socket should answer with a text message.")
        }
        XCTAssertEqual(echoed, "{\"type\":\"ping\"}")
        socket.cancel(with: .normalClosure, reason: nil)

        var foreign = URLRequest(url: URL(string: "ws://127.0.0.1:\(port)/v1/socket")!)
        foreign.setValue("http://attacker.example", forHTTPHeaderField: "Origin")
        let refused = session.webSocketTask(with: foreign)
        refused.resume()
        do {
            _ = try await refused.receive()
            XCTFail("A socket from another origin must not be upgraded.")
        } catch {
            // The upgrade is refused before any message can be exchanged.
        }
    }
}
