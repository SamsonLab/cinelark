import Foundation
import Testing
@testable import CineLarkPlayback

@Suite("IINA plugin installation")
struct IINAPluginInstallationTests {
    @Test("outdated plugins require an update")
    func outdatedPluginRequiresUpdate() throws {
        let directory = try makePlugin(version: "0.1.5")
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(IINAPluginInstallation(directoryURL: directory).requiresVersion("0.1.6"))
    }

    @Test("current and newer plugins remain installed")
    func currentAndNewerPluginsRemainInstalled() throws {
        let current = try makePlugin(version: "0.1.6")
        let newer = try makePlugin(version: "0.2.0")
        defer {
            try? FileManager.default.removeItem(at: current)
            try? FileManager.default.removeItem(at: newer)
        }

        #expect(!IINAPluginInstallation(directoryURL: current).requiresVersion("0.1.6"))
        #expect(!IINAPluginInstallation(directoryURL: newer).requiresVersion("0.1.6"))
    }

    @Test("missing player entries require reinstallation")
    func missingEntriesRequireReinstallation() throws {
        let directory = try makePlugin(version: "0.1.6")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.removeItem(
            at: directory.appendingPathComponent("src/main.js", isDirectory: false)
        )

        #expect(IINAPluginInstallation(directoryURL: directory).requiresVersion("0.1.6"))
    }

    private func makePlugin(version: String) throws -> URL {
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
        try Data().write(to: sourceDirectory.appendingPathComponent("main.js", isDirectory: false))
        try Data().write(to: sourceDirectory.appendingPathComponent("global.js", isDirectory: false))
        return directory
    }
}
