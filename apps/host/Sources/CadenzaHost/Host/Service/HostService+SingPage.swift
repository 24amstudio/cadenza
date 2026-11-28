import Foundation

extension HostService {
    func configureSingPage() {
        publishedState.singPageURL = { [weak self] in self?.singPageURL() }
        webRemote.singPageToken = { [weak self] in self?.publishedState.singPage.accessToken }
        webRemote.onSingSocket = { [weak self] socket in self?.openSingSocket(socket) }
    }

    func singPageURL() -> URL? {
        guard configuration.webEnabled, webRemote.ready else { return nil }
        let token = publishedState.singPage.accessToken
        return URL(string: "http://127.0.0.1:\(configuration.webPort)/sing?token=\(token)")
    }

    func openSingSocket(_ socket: WebRemoteSession) {
        let id = publishedState.singFeed.attach { [weak socket] data in socket?.send(data) ?? false }
        socket.onSocketClosed = { [weak self] in self?.publishedState.singFeed.detach(id) }
    }
}
