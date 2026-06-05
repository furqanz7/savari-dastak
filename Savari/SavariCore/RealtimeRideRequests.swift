import Foundation
import Supabase
import PostgREST
import Realtime

extension RealtimeManager {
    func subscribeRideRequests(onUpdate: @escaping ([String: Any]) -> Void) async -> () -> Void {
        let realtimeV2 = await MainActor.run { SupabaseManager.shared.client.realtimeV2 }
        do {
            SavariLog.debug("[RealtimeManager] attempting SDK subscribe to rides")
            let channel = realtimeV2.channel("public:rides")
            let decoder = JSONDecoder()

            let streamTask = Task.detached {
                do {
                    for try await change in channel.postgresChange(AnyAction.self, table: "rides") {
                        switch change {
                        case .insert(let insertion):
                            if let row = try? insertion.decodeRecord(as: RideRow.self, decoder: decoder) {
                                SavariLog.debug("[RealtimeManager][SDK DEBUG] change payload:", insertion.record)
                                let payload = Self.normalizedDictionary(from: row)
                                await MainActor.run { onUpdate(["new": payload]) }
                            } else {
                                do {
                                    let payload = try Self.normalizedRawRidePayload(insertion.record)
                                    await MainActor.run { onUpdate(["new": payload]) }
                                } catch {
                                    SavariLog.debug("[RealtimeManager][SDK] unable to normalize insert payload:", error)
                                }
                            }
                        case .update(let update):
                            let newRow = try update.decodeRecord(as: RideRow.self, decoder: decoder)
                            let oldRow = try? update.decodeOldRecord(as: RideRow.self, decoder: decoder)
                            var payload: [String: Any] = [
                                "new": Self.normalizedDictionary(from: newRow)
                            ]
                            if let oldRow {
                                payload["old"] = Self.normalizedDictionary(from: oldRow)
                            }
                            await MainActor.run { onUpdate(payload) }
                        case .delete(let deletion):
                            let old = try deletion.decodeOldRecord(as: RideRow.self, decoder: decoder)
                            let payload = Self.normalizedDictionary(from: old)
                            SavariLog.debug("[RealtimeManager][SDK] delete:", payload["id"] ?? "(no id)")
                            await MainActor.run { onUpdate(["old": payload]) }
                        }
                    }
                } catch {
                    SavariLog.debug("[RealtimeManager] realtime rides stream ended:", error)
                }
            }

            try await channel.subscribeWithError()
            SavariLog.debug("[RealtimeManager] SDK subscribeWithError succeeded for rides")
            return {
                Task {
                    streamTask.cancel()
                    await channel.unsubscribe()
                }
            }
        } catch {
            SavariLog.debug("[RealtimeManager] subscribeRideRequests via SDK failed:", error)
            SavariLog.debug("[RealtimeManager] falling back to polling for rides")
        }

        var pollingTaskLocal: Task<Void, Never>?
        pollingTaskLocal = Task.detached { [weak self] in
            guard let self else { return }
            var seen = Set<String>()
            while !Task.isCancelled {
                do {
                    SavariLog.debug("[RealtimeManager][polling] querying rides...")
                    let response = try await SupabaseManager.shared.client
                        .from("rides")
                        .select()
                        .execute()
                    if let rows = Self.jsonArray(from: response.data) {
                        SavariLog.debug("[RealtimeManager][polling] found \(rows.count) rows")
                        for row in rows {
                            if let id = row["id"] as? String, !seen.contains(id) {
                                seen.insert(id)
                                SavariLog.debug("[RealtimeManager][polling] new ride id:", id, "status:", row["status"] ?? "nil")
                                await MainActor.run { onUpdate(["new": row]) }
                            }
                        }
                    } else {
                        SavariLog.debug("[RealtimeManager][polling] response.data not [[String:Any]]; raw:", response.data)
                    }
                } catch {
                    SavariLog.debug("[RealtimeManager] ride polling error:", error)
                }
                try? await Task.sleep(nanoseconds: UInt64(self.pollingInterval * 1_000_000_000))
            }
        }

        return {
            pollingTaskLocal?.cancel()
        }
    }

    private static func normalizedDictionary(from row: RideRow) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(row),
              var dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        normalizeRideDestinationFields(&dict)
        return dict
    }

    private static func normalizedRawRidePayload(_ rawPayload: [String: Any]) throws -> [String: Any] {
        let data = try JSONSerialization.data(withJSONObject: rawPayload)
        var dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        normalizeRideDestinationFields(&dict)
        return dict
    }

    private static func normalizeRideDestinationFields(_ dict: inout [String: Any]) {
        if dict["drop_lat"] == nil, let destinationLatitude = dict["dest_lat"] {
            dict["drop_lat"] = destinationLatitude
        }
        if dict["drop_lon"] == nil, let destinationLongitude = dict["dest_lon"] {
            dict["drop_lon"] = destinationLongitude
        }
    }
}
