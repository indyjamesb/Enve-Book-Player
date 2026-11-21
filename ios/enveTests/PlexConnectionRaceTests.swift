import Foundation
import Testing
import os

@testable import enve

nonisolated private final class PlexProbeProtocol: URLProtocol, @unchecked Sendable {
    struct Behavior: Sendable {
        var status: Int
        var hang: Bool
    }

    private static let behaviors = OSAllocatedUnfairLock(initialState: [String: Behavior]())
    private static let requestedHosts = OSAllocatedUnfairLock(initialState: [String]())

    static func reset(behaviors: [String: Behavior]) {
        self.behaviors.withLock { $0 = behaviors }
        requestedHosts.withLock { $0 = [] }
    }

    static func requestedHost(_ host: String) -> Bool {
        requestedHosts.withLock { $0.contains(host) }
    }

    static func recordProbe(_ identifier: String, into lock: OSAllocatedUnfairLock<String>) {
        lock.withLock { $0 = identifier }
    }

    static func probedIdentifier(_ lock: OSAllocatedUnfairLock<String>) -> String {
        lock.withLock { $0 }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    private let finished = OSAllocatedUnfairLock(initialState: false)

    override func startLoading() {
        guard let url = request.url, let host = url.host else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        Self.requestedHosts.withLock { $0.append(host) }
        guard url.path == "/identity" else {
            finish(URLError(.unsupportedURL))
            return
        }
        let behavior = Self.behaviors.withLock { $0[host] }
        guard let behavior else {
            finish(URLError(.cannotConnectToHost))
            return
        }
        if behavior.hang { return }
        let response = HTTPURLResponse(url: url, statusCode: behavior.status, httpVersion: "HTTP/1.1", headerFields: nil)!
        let alreadyFinished = finished.withLock { state -> Bool in
            if state { return true }
            state = true
            return false
        }
        guard !alreadyFinished else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if behavior.status == 200 {
            client?.urlProtocol(self, didLoad: Data("<MediaContainer/>".utf8))
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {
        finish(URLError(.cancelled))
    }

    private func finish(_ error: URLError) {
        let alreadyFinished = finished.withLock { state -> Bool in
            if state { return true }
            state = true
            return false
        }
        guard !alreadyFinished else { return }
        client?.urlProtocol(self, didFailWithError: error)
    }
}

@Suite(.serialized)
@MainActor
struct PlexConnectionRaceTests {
    @Test func localWinsWhenPublicHangs() async {
        let local = "https://10-0-0-8.abcdef.plex.direct:32400"
        let remote = "https://203.0.113.10:32400"
        PlexProbeProtocol.reset(behaviors: [
            "10-0-0-8.abcdef.plex.direct": .init(status: 200, hang: false),
            "203.0.113.10": .init(status: 200, hang: true),
        ])
        let (service, session) = makeService()
        defer { session.invalidateAndCancel() }

        let start = Date()
        let winner = await service.findBestConnection(server: server(id: "machine", connections: [
            endpoint(local, local: true),
            endpoint(remote, local: false),
        ]), recordGlobally: false)
        let elapsed = Date().timeIntervalSince(start)

        #expect(winner == local)
        #expect(elapsed < 1)
        #expect(!PlexProbeProtocol.requestedHost("203.0.113.10"))
    }

    @Test func publicWinsWhenLocalFails() async {
        let local = "http://10.0.0.8:32400"
        let remote = "https://203.0.113.10:32400"
        let relay = "https://relay.plex.test:32400"
        PlexProbeProtocol.reset(behaviors: [
            "10.0.0.8": .init(status: 500, hang: false),
            "203.0.113.10": .init(status: 200, hang: false),
            "relay.plex.test": .init(status: 200, hang: false),
        ])
        let (service, session) = makeService()
        defer { session.invalidateAndCancel() }

        let winner = await service.findBestConnection(server: server(id: "machine", connections: [
            endpoint(local, local: true),
            endpoint(remote, local: false),
            endpoint(relay, local: false, relay: true),
        ]), recordGlobally: false)

        #expect(winner == remote)
        #expect(!PlexProbeProtocol.requestedHost("relay.plex.test"))
    }

    @Test func relayIsLast() async {
        let local = "http://10.0.0.8:32400"
        let remote = "https://203.0.113.10:32400"
        let relay = "https://relay.plex.test:32400"
        PlexProbeProtocol.reset(behaviors: [
            "10.0.0.8": .init(status: 500, hang: false),
            "203.0.113.10": .init(status: 500, hang: false),
            "relay.plex.test": .init(status: 200, hang: false),
        ])
        let (service, session) = makeService()
        defer { session.invalidateAndCancel() }

        let winner = await service.findBestConnection(server: server(id: "machine", connections: [
            endpoint(relay, local: false, relay: true),
            endpoint(remote, local: false),
            endpoint(local, local: true),
        ]), recordGlobally: false)

        #expect(winner == relay)
    }

    @Test func localPlexDirectIsPreferredWhenBothWork() async {
        let raw = "http://10.0.0.8:32400"
        let direct = "https://10-0-0-8.abcdef.plex.direct:32400"
        let remote = "https://203.0.113.10:32400"
        PlexProbeProtocol.reset(behaviors: [
            "10.0.0.8": .init(status: 200, hang: true),
            "10-0-0-8.abcdef.plex.direct": .init(status: 200, hang: false),
            "203.0.113.10": .init(status: 200, hang: false),
        ])
        let (service, session) = makeService()
        defer { session.invalidateAndCancel() }

        let start = Date()
        let winner = await service.findBestConnection(server: server(id: "machine", connections: [
            endpoint(raw, local: true),
            endpoint(remote, local: false),
            endpoint(direct, local: true),
        ]), recordGlobally: false)

        #expect(winner == direct)
        #expect(Date().timeIntervalSince(start) < 1)
        #expect(!PlexProbeProtocol.requestedHost("203.0.113.10"))
    }

    @Test func machineIdentifierSelectsTheMatchingServerRatherThanTheFirst() {
        let servers = [
            server(id: "machine-a", connections: [endpoint("https://a.example:32400", local: false)]),
            server(id: "machine-b", connections: [endpoint("https://b.example:32400", local: false)]),
        ]
        #expect(PlexServerMatching.server(matching: "machine-b", in: servers)?.id == "machine-b")
        #expect(PlexServerMatching.server(matching: nil, in: servers) == nil)

        let first = ServerConnection(
            name: "A", url: "https://a.example:32400", type: .plex, isConnected: true, plexMachineIdentifier: "machine-a")
        var second = ServerConnection(
            name: "B", url: "https://b.example:32400", type: .plex, isConnected: true, plexMachineIdentifier: "machine-b")
        second.id = UUID()
        let picked = PlexPlaybackEndpoint.connection(
            backendId: second.id.uuidString,
            providerId: UUID(),
            connections: [first, second]
        )
        #expect(picked?.id == second.id)
        #expect(picked?.url == "https://b.example:32400")
    }

    @Test func pathChangeReresolvesAndKeepsTheLastURLOnFailure() async {
        let wifi = PlexNetworkPathSnapshot(satisfied: true, usesWiFi: true, usesCellular: false)
        let cellular = PlexNetworkPathSnapshot(satisfied: true, usesWiFi: false, usesCellular: true)
        let offline = PlexNetworkPathSnapshot(satisfied: false, usesWiFi: false, usesCellular: false)
        #expect(PlexNetworkPathSnapshot.shouldReresolve(from: wifi, to: cellular))
        #expect(PlexNetworkPathSnapshot.shouldReresolve(from: cellular, to: wifi))
        #expect(PlexNetworkPathSnapshot.shouldReresolve(from: offline, to: wifi))
        #expect(!PlexNetworkPathSnapshot.shouldReresolve(from: nil, to: wifi))
        #expect(!PlexNetworkPathSnapshot.shouldReresolve(from: wifi, to: wifi))
        #expect(!PlexNetworkPathSnapshot.shouldReresolve(from: wifi, to: offline))

        var saved = ServerConnection(
            name: "Home",
            url: "http://10.0.0.8:32400",
            type: .plex,
            isConnected: true,
            plexMachineIdentifier: "machine-b"
        )
        let servers = [
            server(id: "machine-a", connections: [endpoint("https://a.example:32400", local: false)]),
            server(id: "machine-b", connections: [endpoint("https://10-0-0-8.abcdef.plex.direct:32400", local: true)]),
        ]
        let probed = OSAllocatedUnfairLock(initialState: "")
        let replaced = await PlexConnectionRefresh.resolvedEndpoint(for: saved, servers: servers) { candidate in
            PlexProbeProtocol.recordProbe(candidate.id, into: probed)
            return "https://10-0-0-8.abcdef.plex.direct:32400"
        }
        let updated = PlexConnectionRefresh.updated(saved, with: replaced)
        #expect(PlexProbeProtocol.probedIdentifier(probed) == "machine-b")
        #expect(updated.url == "https://10-0-0-8.abcdef.plex.direct:32400")
        #expect(updated.plexMachineIdentifier == "machine-b")

        saved.url = updated.url
        let unchanged = await PlexConnectionRefresh.resolvedEndpoint(for: saved, servers: servers) { _ in saved.url }
        #expect(unchanged == nil)
        #expect(PlexConnectionRefresh.updated(saved, with: unchanged).url == saved.url)

        let failed = await PlexConnectionRefresh.resolvedEndpoint(for: saved, servers: servers) { _ in nil }
        #expect(failed == nil)
        #expect(PlexConnectionRefresh.updated(saved, with: failed).url == saved.url)
    }

    @Test func machineIdentifierIsOptionalForOlderSavedConnections() throws {
        let id = UUID()
        let json = """
        {"id":"\(id.uuidString)","name":"Old","url":"https://plex.example","type":"plex"}
        """
        let decoded = try JSONDecoder().decode(ServerConnection.self, from: Data(json.utf8))
        #expect(decoded.plexMachineIdentifier == nil)
        #expect(decoded.name == "Old")

        let encoded = ServerConnection(
            id: id, name: "Old", url: "https://plex.example", type: .plex, plexMachineIdentifier: "machine-b")
        let roundTrip = try JSONDecoder().decode(ServerConnection.self, from: JSONEncoder().encode(encoded))
        #expect(roundTrip.plexMachineIdentifier == "machine-b")
    }

    private func makeService() -> (PlexService, URLSession) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PlexProbeProtocol.self]
        configuration.timeoutIntervalForRequest = 2
        configuration.timeoutIntervalForResource = 2
        configuration.waitsForConnectivity = false
        let session = URLSession(configuration: configuration)
        return (PlexService(session: session), session)
    }

    private func server(id: String, connections: [PlexConnection]) -> PlexServer {
        PlexServer(
            id: id,
            name: id,
            uri: connections.first?.uri ?? "",
            local: connections.contains(where: \.local),
            httpsRequired: connections.contains(where: \.isSecure),
            owned: id == "machine-b",
            synced: false,
            accessToken: "fixture-token",
            connections: connections
        )
    }

    private func endpoint(_ uri: String, local: Bool, relay: Bool = false) -> PlexConnection {
        PlexConnection(
            uri: uri,
            local: local,
            protocol: uri.hasPrefix("https") ? "https" : "http",
            address: nil,
            port: 32400,
            relay: relay
        )
    }
}
