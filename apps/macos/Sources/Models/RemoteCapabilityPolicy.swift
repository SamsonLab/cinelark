import Foundation

enum RemoteCapabilityPolicy {
    static let advertised = [
        "navigation.basic",
        "navigation.sections",
        "textInput.remote",
        "playback.transport",
        "playback.seek",
        "playback.rate",
        "playback.fullscreen",
        "playback.trackSelection",
        "playback.closeAndActivate",
        "audio.volume"
    ]

    static func requiredCapability(for messageType: String) -> String? {
        switch messageType {
        case "app.requestSnapshot", "playback.requestSnapshot": nil
        case "app.activate", "navigation.move", "navigation.select", "navigation.back":
            "navigation.basic"
        case "navigation.openSection": "navigation.sections"
        case "auth.submitCredentials": nil
        case "textInput.update", "textInput.commit", "textInput.cancel": "textInput.remote"
        case "playback.togglePause", "playback.pause", "playback.resume", "playback.stop":
            "playback.transport"
        case "playback.seekRelative", "playback.seekAbsolute": "playback.seek"
        case "playback.setRate": "playback.rate"
        case "playback.setFullscreen": "playback.fullscreen"
        case "playback.playPrevious", "playback.playNext": nil
        case "playback.selectAudioTrack", "playback.selectSubtitleTrack":
            "playback.trackSelection"
        case "playback.closeAndActivateApp": "playback.closeAndActivate"
        case "audio.setVolume", "audio.adjustVolume", "audio.setMuted": "audio.volume"
        default: nil
        }
    }
}
