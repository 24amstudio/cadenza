import Foundation

/// How an operation reaches Music, from the least to the most intrusive. Only `.system` needs Music in front.
enum InputRoute: CaseIterable {
    /// Accessibility actions and attribute writes on Music's elements; they work on a background application.
    case accessibility
    /// Mouse and key events delivered to Music's process with `CGEvent.postToPid`, which does not activate it.
    case process
    /// Events posted to the HID tap, which go to the frontmost application, so Music must be activated first.
    case system

    var name: String {
        switch self {
        case .accessibility: "accessibility"
        case .process: "process events"
        case .system: "system events with Music in front"
        }
    }

    var sendsInput: Bool { self != .accessibility }
}

extension MusicAccessibility {
    /// Runs `operation` once per route until one succeeds. Music is activated, and focus handed back afterwards, only
    /// when every earlier route failed.
    func escalating<Value>(
        deadline: Int64, routes: [InputRoute] = InputRoute.allCases,
        operation: @escaping (InputRoute, Int64) async throws -> Value
    ) async throws -> Value {
        try await activation.run(
            deadline: deadline,
            steps: routes.map { route in
                ActivationFallback.Step(name: route.name, tier: route == .system ? .activating : .quiet) {
                    try await operation(route, $0)
                }
            })
    }

    func requireInput(_ route: InputRoute) throws {
        guard route.sendsInput else {
            throw CadenzaError.failure(
                "native_queue_unavailable", "Accessibility alone could not do this; it needs mouse or key input.")
        }
    }
}
