import Foundation
import Testing
@testable import CineLarkPlayback

@Suite("IINA plugin installation")
struct IINAPluginInstallationTests {
    @Test("missing, invalid, outdated, and current plugins are distinguished")
    func installationStatesAreExplicit() throws {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let directory = try makePlugin(version: "0.1.14")
        let malformed = try makePlugin(version: "latest")
        let current = try makePlugin(version: "0.1.15")
        let newer = try makePlugin(version: "0.2.0")
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: malformed)
            try? FileManager.default.removeItem(at: current)
            try? FileManager.default.removeItem(at: newer)
        }

        try FileManager.default.removeItem(
            at: directory.appendingPathComponent("src/main.js", isDirectory: false)
        )

        #expect(IINAPluginInstallation(directoryURL: missing).state(requiring: "0.1.15") == .missing)
        #expect(IINAPluginInstallation(directoryURL: directory).state(requiring: "0.1.15") == .invalid)
        #expect(IINAPluginInstallation(directoryURL: malformed).state(requiring: "0.1.15") == .invalid)
        #expect(IINAPluginInstallation(directoryURL: current).state(requiring: "0.1.15") == .current(version: "0.1.15"))
        #expect(IINAPluginInstallation(directoryURL: newer).state(requiring: "0.1.15") == .current(version: "0.2.0"))
    }

    @Test("an invalid bundled plugin leaves the existing installation intact")
    func invalidBundledPluginDoesNotReplaceExistingInstallation() throws {
        let directory = try makePlugin(version: "0.1.14", marker: "installed")
        let bundled = try makePlugin(version: "latest", marker: "invalid")
        defer { try? FileManager.default.removeItem(at: directory) }
        defer { try? FileManager.default.removeItem(at: bundled) }

        let installation = IINAPluginInstallation(directoryURL: directory)
        #expect(throws: IINAPluginInstallation.InstallationError.invalidBundledPlugin) {
            try installation.replace(with: bundled, requiring: "0.1.17")
        }
        #expect(
            try String(
                contentsOf: directory.appendingPathComponent("src/main.js"),
                encoding: .utf8
            ) == "installed"
        )
    }

    @Test("an existing plugin is replaced from a validated bundled directory")
    func existingPluginIsReplaced() throws {
        let directory = try makePlugin(version: "0.1.14", marker: "installed")
        let bundled = try makePlugin(version: "0.1.17", marker: "bundled")
        defer { try? FileManager.default.removeItem(at: directory) }
        defer { try? FileManager.default.removeItem(at: bundled) }

        let installation = IINAPluginInstallation(directoryURL: directory)
        try installation.replace(with: bundled, requiring: "0.1.17")

        #expect(installation.state(requiring: "0.1.17") == .current(version: "0.1.17"))
        #expect(
            try String(
                contentsOf: directory.appendingPathComponent("src/main.js"),
                encoding: .utf8
            ) == "bundled"
        )
    }

    private func makePlugin(version: String, marker: String = "") throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceDirectory = directory.appendingPathComponent("src", isDirectory: true)
        try FileManager.default.createDirectory(
            at: sourceDirectory,
            withIntermediateDirectories: true
        )
        let manifest = """
        {
          "identifier": "com.samsonlab.cinelark.iina",
          "version": "\(version)"
        }
        """
        try Data(manifest.utf8).write(
            to: directory.appendingPathComponent("Info.json", isDirectory: false)
        )
        try Data(marker.utf8).write(
            to: sourceDirectory.appendingPathComponent("main.js", isDirectory: false)
        )
        try Data().write(to: sourceDirectory.appendingPathComponent("global.js", isDirectory: false))
        return directory
    }
}
