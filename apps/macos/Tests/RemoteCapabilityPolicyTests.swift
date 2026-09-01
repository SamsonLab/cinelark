import Testing
@testable import CineLark

@Suite("Remote capability policy")
struct RemoteCapabilityPolicyTests {
    @Test("Every routed product command uses an advertised capability")
    func routedCapabilitiesAreAdvertised() {
        let messages = [
            "app.activate",
            "navigation.move",
            "navigation.openSection",
            "textInput.update",
            "playback.pause",
            "playback.seekAbsolute",
            "playback.setRate",
            "playback.setFullscreen",
            "playback.selectAudioTrack",
            "playback.closeAndActivateApp",
            "audio.setVolume"
        ]

        for message in messages {
            let required = RemoteCapabilityPolicy.requiredCapability(for: message)
            #expect(required != nil)
            #expect(RemoteCapabilityPolicy.advertised.contains(required!))
        }
    }

    @Test("Snapshot and unsupported commands do not claim product capabilities")
    func unscopedMessagesHaveNoCapability() {
        #expect(RemoteCapabilityPolicy.requiredCapability(for: "app.requestSnapshot") == nil)
        #expect(RemoteCapabilityPolicy.requiredCapability(for: "unknown.command") == nil)
    }
}
