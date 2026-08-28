import Foundation
import CineLarkProfile

struct CloudKitAuditLaunchRequest: Equatable, Sendable {
    static let outputKey = "CINELARK_CLOUDKIT_AUDIT_OUTPUT"
    static let settleSecondsKey = "CINELARK_CLOUDKIT_AUDIT_SETTLE_SECONDS"

    let outputURL: URL
    let settleSeconds: Int

    init?(environment: [String: String]) {
        guard
            let output = environment[Self.outputKey],
            !output.isEmpty,
            NSString(string: output).isAbsolutePath
        else { return nil }
        let settleSeconds: Int
        if let value = environment[Self.settleSecondsKey] {
            guard let parsed = Int(value), (0...300).contains(parsed) else { return nil }
            settleSeconds = parsed
        } else {
            settleSeconds = 30
        }
        self.outputURL = URL(fileURLWithPath: output).standardizedFileURL
        self.settleSeconds = settleSeconds
    }
}

enum CloudKitAuditCapture {
    enum Failure: Error {
        case outputAlreadyExists
    }

    static func run(
        repository: any ProfileRepository,
        request: CloudKitAuditLaunchRequest
    ) async throws {
        let clock = ContinuousClock()
        try await clock.sleep(for: .seconds(request.settleSeconds))

        let snapshot = try await ProfileSyncAuditSnapshot.capture(
            repository: repository,
            capturedAt: Date()
        )
        let outputURL = request.outputURL
        guard !FileManager.default.fileExists(atPath: outputURL.path) else {
            throw Failure.outputAlreadyExists
        }
        let temporaryURL = outputURL.deletingLastPathComponent().appendingPathComponent(
            ".cinelark-audit-\(UUID().uuidString).tmp"
        )
        do {
            try snapshot.encodedData().write(to: temporaryURL, options: .atomic)
            try FileManager.default.moveItem(at: temporaryURL, to: outputURL)
        } catch {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw error
        }
    }
}
