import Foundation
import Supabase

public struct OrderChangeEvent: Equatable, Sendable {
    public enum EntityKind: String, Equatable, Sendable {
        case merchantOrder = "merchant_order"
        case parcel
    }

    public let entityKind: EntityKind
    public let entityID: UUID
    public let stateVersion: Int

    public init(entityKind: EntityKind, entityID: UUID, stateVersion: Int) {
        self.entityKind = entityKind
        self.entityID = entityID
        self.stateVersion = stateVersion
    }
}

public protocol OrderEventClient: Sendable {
    func events(accountID: UUID) -> AsyncThrowingStream<OrderChangeEvent, any Error>
}

public struct NoopOrderEventClient: OrderEventClient {
    public init() {}

    public func events(
        accountID _: UUID
    ) -> AsyncThrowingStream<OrderChangeEvent, any Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}

public struct SupabaseOrderEventClient: OrderEventClient {
    private let configuration: BackendConfiguration
    private let accessTokenProvider: @Sendable () async throws -> String?

    public init(
        configuration: BackendConfiguration,
        accessTokenProvider: @escaping @Sendable () async throws -> String?
    ) {
        self.configuration = configuration
        self.accessTokenProvider = accessTokenProvider
    }

    public func events(
        accountID: UUID
    ) -> AsyncThrowingStream<OrderChangeEvent, any Error> {
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
                let channel = client.channel("order-account:\(accountID.uuidString.lowercased())") {
                    $0.isPrivate = true
                }
                let broadcasts = channel.broadcastStream(event: "order_changed")

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

    static func decode(_ message: JSONObject) -> OrderChangeEvent? {
        guard let payload = message["payload"]?.objectValue,
              let kindValue = payload["entityKind"]?.stringValue,
              let kind = OrderChangeEvent.EntityKind(rawValue: kindValue),
              let entityIDValue = payload["entityId"]?.stringValue,
              let entityID = UUID(uuidString: entityIDValue),
              let stateVersion = payload["stateVersion"]?.intValue,
              stateVersion >= 0 else {
            return nil
        }
        return OrderChangeEvent(
            entityKind: kind,
            entityID: entityID,
            stateVersion: stateVersion
        )
    }
}
