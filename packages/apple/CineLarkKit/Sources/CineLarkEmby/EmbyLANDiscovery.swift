@preconcurrency import Network
import Foundation
import CineLarkPluginAPI

public struct EmbyDiscoveryClient: Sendable {
    public var discover: @Sendable (Duration) async throws -> [DiscoveredSource]

    public init(
        discover: @escaping @Sendable (Duration) async throws -> [DiscoveredSource]
    ) {
        self.discover = discover
    }

    public static let live = Self { timeout in
        try await EmbyUDPDiscovery.discover(timeout: timeout)
    }
}

enum EmbyDiscoveryParser {
    private struct Response: Decodable {
        let address: String?
        let endpointAddress: String?
        let id: String?
        let name: String?

        enum CodingKeys: String, CodingKey {
            case address = "Address"
            case endpointAddress = "EndpointAddress"
            case id = "Id"
            case name = "Name"
        }
    }

    static func parse(_ data: Data) -> DiscoveredSource? {
        guard
            let response = try? JSONDecoder().decode(Response.self, from: data),
            let rawAddress = response.address ?? response.endpointAddress,
            let address = normalizedURL(rawAddress)
        else { return nil }
        return DiscoveredSource(
            name: response.name ?? address.host ?? "Emby",
            address: address,
            serverID: response.id
        )
    }

    private static func normalizedURL(_ value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), url.scheme != nil { return url }
        return URL(string: "http://\(trimmed)")
    }
}

private enum EmbyUDPDiscovery {
    static func discover(timeout: Duration) async throws -> [DiscoveredSource] {
        let accumulator = DiscoveryAccumulator()
        let parameters = NWParameters.udp
        parameters.allowLocalEndpointReuse = true
        let connection = NWConnection(
            host: "255.255.255.255",
            port: 7359,
            using: parameters
        )
        connection.stateUpdateHandler = { state in
            guard case .ready = state else { return }
            connection.send(
                content: Data("who is EmbyServer?".utf8),
                completion: .contentProcessed { _ in }
            )
        }
        receiveNext(connection, accumulator: accumulator)
        connection.start(queue: .global(qos: .userInitiated))

        do {
            try await Task.sleep(for: timeout)
        } catch {
            connection.cancel()
            throw error
        }
        connection.cancel()
        return await accumulator.values()
    }

    private static func receiveNext(
        _ connection: NWConnection,
        accumulator: DiscoveryAccumulator
    ) {
        connection.receiveMessage { data, _, _, error in
            if let data, let source = EmbyDiscoveryParser.parse(data) {
                Task { await accumulator.insert(source) }
            }
            guard error == nil else { return }
            receiveNext(connection, accumulator: accumulator)
        }
    }
}

private actor DiscoveryAccumulator {
    private var sources: [String: DiscoveredSource] = [:]

    func insert(_ source: DiscoveredSource) {
        let key = source.serverID ?? source.address.absoluteString
        sources[key] = source
    }

    func values() -> [DiscoveredSource] {
        sources.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
