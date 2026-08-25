import CryptoKit
import Foundation
import Testing
@testable import CineLarkRemote

@Suite("Remote protocol")
struct RemoteProtocolTests {
    @Test("Swift authentication matches the shared Rust and Dart vector")
    func sharedAuthenticationVector() throws {
        let credential = try #require(
            Data(remoteBase64URLEncoded: "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8")
        )
        let proof = RemoteAuthentication.proof(
            credential: credential,
            serviceID: "ad54e7ba-9409-4f54-8c7c-65e781978cf9",
            connectionID: "8dc63877-bf80-4d63-afc0-bec50d1ecb60",
            nonce: "c3ludGhldGljLW5vbmNl"
        )
        #expect(proof == "mzD1FDUxeqTJFptKfi3MmsuroE65jf6dhK-f3Ar05MU")
    }

    @Test("Gateway configuration uses exact Rust frame names")
    func gatewayConfigurationEncoding() throws {
        let state = RemoteGatewayStoredState(
            serviceID: UUID(uuidString: "ad54e7ba-9409-4f54-8c7c-65e781978cf9")!,
            devices: [
                RemoteDeviceRecord(
                    id: UUID(uuidString: "8dc63877-bf80-4d63-afc0-bec50d1ecb60")!,
                    name: "Synthetic Phone",
                    credential: "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8",
                    capabilities: ["navigation.basic"]
                )
            ]
        )
        #expect(state.devices.first?.id.uuidString.lowercased() == "8dc63877-bf80-4d63-afc0-bec50d1ecb60")
    }

    @Test("TLS identity uses the Rust camel-case PEM field names")
    func tlsIdentityCodingKeys() throws {
        let json = Data(#"{"certificatePem":"certificate","privateKeyPem":"private-key"}"#.utf8)
        let identity = try JSONDecoder().decode(RemoteGatewayIdentity.self, from: json)
        #expect(identity.certificatePEM == "certificate")
        #expect(identity.privateKeyPEM == "private-key")

        let encoded = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(identity))
                as? [String: String]
        )
        #expect(encoded == [
            "certificatePem": "certificate",
            "privateKeyPem": "private-key"
        ])
    }

    @Test("Remote JSON values preserve integer and nullable track IDs")
    func nullableTrackPayload() throws {
        let payload: [String: RemoteJSONValue] = [
            "trackID": .null,
            "revision": .integer(8)
        ]
        let encoded = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode([String: RemoteJSONValue].self, from: encoded)
        #expect(decoded == payload)
    }
}
