import AppKit

@MainActor
final class CineLarkAppDelegate: NSObject, NSApplicationDelegate {
    var prepareForTermination: (() async -> Void)?
    private var isPreparingForTermination = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let prepareForTermination else {
            return .terminateNow
        }
        guard !isPreparingForTermination else {
            return .terminateLater
        }

        isPreparingForTermination = true
        Task { @MainActor in
            await prepareForTermination()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
