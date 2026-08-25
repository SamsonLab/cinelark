import Darwin
import Foundation

enum RemoteNetworkAddress {
    struct Candidate: Equatable {
        let interface: String
        let address: String
    }

    enum AddressError: Error {
        case unavailable
    }

    static func preferredIPv4Address() throws -> String {
        guard let address = preferredAddress(from: activeIPv4Addresses()) else {
            throw AddressError.unavailable
        }
        return address
    }

    static func preferredAddress(from candidates: [Candidate]) -> String? {
        candidates
            .filter(isUsable)
            .sorted {
                let left = (priority(of: $0.interface), $0.interface, $0.address)
                let right = (priority(of: $1.interface), $1.interface, $1.address)
                return left < right
            }
            .first?
            .address
    }

    private static func activeIPv4Addresses() -> [Candidate] {
        var firstAddress: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&firstAddress) == 0, let firstAddress else { return [] }
        defer { freeifaddrs(firstAddress) }

        var candidates: [Candidate] = []
        var current: UnsafeMutablePointer<ifaddrs>? = firstAddress
        while let pointer = current {
            let interface = pointer.pointee
            defer { current = interface.ifa_next }
            guard let socketAddress = interface.ifa_addr,
                  socketAddress.pointee.sa_family == UInt8(AF_INET) else {
                continue
            }
            let flags = interface.ifa_flags
            let requiredFlags = UInt32(IFF_UP | IFF_RUNNING)
            guard flags & requiredFlags == requiredFlags,
                  flags & UInt32(IFF_LOOPBACK) == 0 else {
                continue
            }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(
                socketAddress,
                socklen_t(socketAddress.pointee.sa_len),
                &host,
                socklen_t(host.count),
                nil,
                0,
                NI_NUMERICHOST
            ) == 0 else {
                continue
            }
            candidates.append(
                Candidate(
                    interface: String(cString: interface.ifa_name),
                    address: String(
                        decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) },
                        as: UTF8.self
                    )
                )
            )
        }
        return candidates
    }

    private static func isUsable(_ candidate: Candidate) -> Bool {
        let excludedPrefixes = ["lo", "utun", "awdl", "llw", "gif", "stf"]
        guard !excludedPrefixes.contains(where: candidate.interface.hasPrefix) else {
            return false
        }
        var parsed = in_addr()
        guard inet_pton(AF_INET, candidate.address, &parsed) == 1 else { return false }
        return candidate.address != "0.0.0.0" && candidate.address != "255.255.255.255"
    }

    private static func priority(of interface: String) -> Int {
        if interface == "en0" { return 0 }
        if interface.hasPrefix("en") { return 1 }
        if interface.hasPrefix("bridge") { return 3 }
        return 2
    }
}
