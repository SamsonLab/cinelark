import XCTest
@testable import CineLark

final class RemoteNetworkAddressTests: XCTestCase {
    func testPrefersPrimaryPhysicalInterfaceOverVPNAndFallbacks() {
        let address = RemoteNetworkAddress.preferredAddress(from: [
            .init(interface: "utun4", address: "198.18.0.1"),
            .init(interface: "en7", address: "10.0.0.12"),
            .init(interface: "bridge100", address: "172.16.0.1"),
            .init(interface: "en0", address: "192.168.20.100")
        ])

        XCTAssertEqual(address, "192.168.20.100")
    }

    func testRejectsLoopbackVPNAndMalformedCandidates() {
        let address = RemoteNetworkAddress.preferredAddress(from: [
            .init(interface: "lo0", address: "127.0.0.1"),
            .init(interface: "utun2", address: "198.18.0.1"),
            .init(interface: "en0", address: "not-an-address")
        ])

        XCTAssertNil(address)
    }
}
