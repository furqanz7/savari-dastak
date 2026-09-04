import Foundation
import Supabase

public struct AdminChangeEvent: Equatable, Sendable {
    public let workspaces: Set<String>

    public init(workspaces: Set<String>) {
        self.workspaces = workspaces
    }
}

public protocol AdminEventClient: Sendable {
    func events() -> AsyncThrowingStream<AdminChangeEvent, any Error>
}

public struct NoopAdminEventClient: AdminEventClient {
    public init() {}

    public func events() -> AsyncThrowingStream<AdminChangeEvent, any Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}

public struct SupabaseAdminEventClient: AdminEventClient {
    private let configuration: BackendConfiguration
    private let accessTokenProvider: @Sendable () async throws -> String?

    public init(
        configuration: BackendConfiguration,
        accessTokenProvider: @escaping @Sendable () async throws -> String?
    ) {
        self.configuration = configuration
        self.accessTokenProvider = accessTokenProvider
    }

    public func events() -> AsyncThrowingStream<AdminChangeEvent, any Error> {
        let configuration = configuration
        let accessTokenProvider = accessTokenProvider

        return AsyncThrowingStream { continuation in
            let task = Task {
                let client = SupabaseClient(
                    supabaseURL: configuration.supabaseURL,
                    supabaseKey: configuration.publishableKey,
                    options: SupabaseClientOptions(
                        auth: .init(
                            emitLocalSessionAsInitialSession: true,
                            accessToken: accessTokenProvider
                        )
                    )
                )
                let channel = client.channel("admin-control") {
                    $0.isPrivate = true
                }
                let broadcasts = channel.broadcastStream(event: "admin_changed")

                do {
                    try await channel.subscribeWithError()
                    for await message in broadcasts {
                        try Task.checkCancellation()
                        guard let event = Self.decode(message) else { continue }
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }

                await client.removeChannel(channel)
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    static func decode(_ message: JSONObject) -> AdminChangeEvent? {
        guard let payload = message["payload"]?.objectValue,
              let values = payload["workspaces"]?.arrayValue else {
            return nil
        }
        let workspaces = Set(values.compactMap(\.stringValue))
        guard !workspaces.isEmpty else { return nil }
        return AdminChangeEvent(workspaces: workspaces)
    }
}
