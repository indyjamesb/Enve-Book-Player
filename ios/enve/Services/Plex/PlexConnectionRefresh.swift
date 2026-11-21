import Foundation

/// Which Plex resource a saved connection belongs to.
enum PlexServerMatching {
    static func server(matching machineIdentifier: String?, in servers: [PlexServer]) -> PlexServer? {
        if let machineIdentifier, !machineIdentifier.isEmpty {
            return servers.first { $0.id == machineIdentifier }
        }
        return servers.count == 1 ? servers[0] : nil
    }

    /// Machine id wins. Without one, a unique advertised URL match is used, then a lone server.
    static func server(for connection: ServerConnection, in servers: [PlexServer]) -> PlexServer? {
        if let machineIdentifier = connection.plexMachineIdentifier, !machineIdentifier.isEmpty {
            return servers.first { $0.id == machineIdentifier }
        }
        let needle = normalized(connection.url)
        if !needle.isEmpty {
            let urlMatches = servers.filter { server in
                normalized(server.uri) == needle || server.connections.contains { normalized($0.uri) == needle }
            }
            if urlMatches.count == 1 { return urlMatches[0] }
        }
        return servers.count == 1 ? servers[0] : nil
    }

    private static func normalized(_ url: String) -> String {
        url.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

/// The saved Plex source for a book. Multiple servers are not resolved by array order.
enum PlexPlaybackEndpoint {
    static func connection(backendId: String?, providerId: UUID, connections: [ServerConnection]) -> ServerConnection? {
        let active = connections.filter { $0.type == .plex && !$0.isArchived && $0.isConnected && !$0.url.isEmpty }
        if let backendId = backendId?.lowercased(),
            let match = active.first(where: { $0.id.uuidString.lowercased() == backendId })
        {
            return match
        }
        if let match = active.first(where: { $0.id == providerId }) {
            return match
        }
        return active.count == 1 ? active[0] : nil
    }
}

struct PlexResolvedEndpoint: Equatable, Sendable {
    var url: String
    var machineIdentifier: String
}

/// Network-change snapshot that decides when saved Plex URLs should be probed again.
struct PlexNetworkPathSnapshot: Equatable, Sendable {
    var satisfied: Bool
    var usesWiFi: Bool
    var usesCellular: Bool

    /// The first observation is not a change. Refresh when a path becomes usable, or when Wi-Fi and cellular trade places.
    static func shouldReresolve(from previous: Self?, to current: Self) -> Bool {
        guard let previous, current.satisfied else { return false }
        if !previous.satisfied { return true }
        return previous.usesWiFi != current.usesWiFi || previous.usesCellular != current.usesCellular
    }
}

enum PlexConnectionRefresh {
    /// Nil means keep the saved URL. A failed probe does not clear it. The URL changes only when the winner differs.
    static func resolvedEndpoint(
        for connection: ServerConnection,
        servers: [PlexServer],
        probe: (PlexServer) async -> String?
    ) async -> PlexResolvedEndpoint? {
        guard connection.type == .plex, !connection.isArchived, connection.isConnected else { return nil }
        guard let server = PlexServerMatching.server(for: connection, in: servers) else { return nil }
        guard let winner = await probe(server), !winner.isEmpty else { return nil }
        if winner == connection.url && connection.plexMachineIdentifier == server.id {
            return nil
        }
        return PlexResolvedEndpoint(url: winner, machineIdentifier: server.id)
    }

    static func updated(_ connection: ServerConnection, with endpoint: PlexResolvedEndpoint?) -> ServerConnection {
        guard let endpoint else { return connection }
        var copy = connection
        copy.url = endpoint.url
        copy.plexMachineIdentifier = endpoint.machineIdentifier
        return copy
    }
}
