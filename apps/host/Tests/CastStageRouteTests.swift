import Foundation
import Testing

@testable import CadenzaHost

struct CastStageRouteTests {
    private let host = "192.168.1.10:8765"

    private func upgrade(_ path: String, origin: String? = nil) -> WebRemoteRequest {
        WebRemoteRequest(
            method: "GET", path: path,
            headers: [
                "host": host, "origin": origin ?? "http://\(host)", "upgrade": "websocket",
                "connection": "Upgrade", "sec-websocket-version": "13",
                "sec-websocket-key": "dGhlIHNhbXBsZSBub25jZQ==",
            ])
    }

    @Test func aStageReceiverUsesItsRoleOnTheStageChannel() {
        #expect(
            WebRemoteRequest.route(upgrade("/cast/live?role=tv_stage"), allowedHosts: [host])
                == .stageSocket(key: "dGhlIHNhbXBsZSBub25jZQ==", role: "tv_stage"))
        #expect(
            WebRemoteRequest.route(upgrade("/cast/live?role=android_tv_receiver"), allowedHosts: [host])
                == .stageSocket(key: "dGhlIHNhbXBsZSBub25jZQ==", role: "android_tv_receiver"))
    }

    @Test func aStageSocketWithoutAKnownRoleOrFromAnotherOriginIsRefused() {
        #expect(WebRemoteRequest.route(upgrade("/cast/live"), allowedHosts: [host]) == .reject(status: 400))
        #expect(WebRemoteRequest.route(upgrade("/cast/live?role=remote"), allowedHosts: [host]) == .reject(status: 400))
        #expect(
            WebRemoteRequest.route(
                upgrade("/cast/live?role=tv_stage", origin: "http://evil.example"), allowedHosts: [host])
                == .reject(status: 403))
    }

    @Test func aStageMediaPathIsServedReadOnlyAndOnlyToGet() {
        let media = WebRemoteRequest(method: "GET", path: "/api/v1/cast/motion/abc.mp4", headers: [:])
        #expect(WebRemoteRequest.route(media, allowedHosts: [host]) == .stageMedia)
        let post = WebRemoteRequest(method: "POST", path: "/api/v1/cast/motion/abc.mp4", headers: [:])
        #expect(WebRemoteRequest.route(post, allowedHosts: [host]) == .reject(status: 405))
    }

    @Test func theRemoteSocketIsUnchanged() {
        #expect(
            WebRemoteRequest.route(upgrade("/v1/socket"), allowedHosts: [host])
                == .socket(key: "dGhlIHNhbXBsZSBub25jZQ=="))
    }

    @Test func tvAndSingAreServedFromTheSameAppShell() {
        #expect(WebRemoteBundle.pageRoute("/tv") == "/")
        #expect(WebRemoteBundle.pageRoute("/tv/?x=1") == "/")
        #expect(WebRemoteBundle.pageRoute("/sing?token=abc") == "/")
        #expect(WebRemoteBundle.pageRoute("/app.js") == "/app.js")
    }

    @Test func theSingSocketOpensOnlyWithTheWindowsAccessToken() {
        let key = "dGhlIHNhbXBsZSBub25jZQ=="
        #expect(
            WebRemoteRequest.route(
                upgrade("/sing/live?token=secret"), allowedHosts: [host], singPageToken: "secret")
                == .singSocket(key: key))
        #expect(
            WebRemoteRequest.route(
                upgrade("/sing/live?token=guess"), allowedHosts: [host], singPageToken: "secret")
                == .reject(status: 403))
        #expect(
            WebRemoteRequest.route(upgrade("/sing/live"), allowedHosts: [host], singPageToken: "secret")
                == .reject(status: 403))
        #expect(
            WebRemoteRequest.route(
                upgrade("/sing/live?token=secret"), allowedHosts: [host], singPageToken: nil)
                == .reject(status: 403))
    }

    @Test func theSingSocketIsRefusedFromAnotherOrigin() {
        #expect(
            WebRemoteRequest.route(
                upgrade("/sing/live?token=secret", origin: "http://evil.example"), allowedHosts: [host],
                singPageToken: "secret") == .reject(status: 403))
    }
}
