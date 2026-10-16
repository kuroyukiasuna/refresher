import Foundation
import Testing
@testable import RefresherCore

private let start = Date(timeIntervalSinceReferenceDate: 0)

private func client(
    _ bundleID: String,
    name: String = "App",
    isApp: Bool = true,
    mic: Bool = false,
    audio: Bool = false
) -> AudioClient {
    AudioClient(pid: 1, bundleID: bundleID, name: name, isApp: isApp, usesMicrophone: mic, playsAudio: audio)
}

@Suite struct CallAppTests {
    @Test(arguments: [
        ("us.zoom.xos", CallApp.zoom),
        ("us.zoom.CptHost", .zoom),
        ("com.microsoft.teams2", .teams),
        ("com.microsoft.teams2.helper", .teams),
        ("com.microsoft.teams", .teams),
        ("com.microsoft.vcxpc", .teams),
        ("com.tinyspeck.slackmacgap", .slack),
        ("com.tinyspeck.slackmacgap.helper", .slack),
        ("com.google.Chrome", .browser),
        ("com.google.Chrome.helper", .browser),
        ("com.apple.Safari", .browser),
        ("com.apple.FaceTime", .otherCallApp),
        ("com.apple.avconferenced", .otherCallApp),
    ])
    func recognizesCallApps(bundleID: String, app: CallApp) {
        #expect(CallApp.classify(bundleID) == app)
    }

    @Test func matchesWholeBundleIDComponentsOnly() {
        #expect(CallApp.classify("com.spotify.client") == nil)
        #expect(CallApp.classify("us.zoomer.app") == nil)
        #expect(CallApp.classify("com.google.chromecast") == nil)
        #expect(CallApp.classify("") == nil)
    }

    @Test func installCheckLooksForTheAppItself() {
        for app in CallApp.allCases {
            for bundleID in app.appBundleIDs ?? [] {
                #expect(CallApp.classify(bundleID) == app)
            }
        }
    }
}

@Suite struct MeetingDetectorTests {
    @Test func zoomUsingTheMicIsAMeeting() {
        var detector = MeetingDetector()
        let signal = detector.evaluate([client("us.zoom.xos", name: "zoom.us", mic: true, audio: true)], cameraInUse: false, now: start)
        #expect(signal == MeetingSignal(title: "Zoom meeting", evidence: "Zoom is using the microphone"))
    }

    @Test func slackUsingTheMicIsAHuddle() {
        var detector = MeetingDetector()
        let signal = detector.evaluate([client("com.tinyspeck.slackmacgap", name: "Slack", mic: true)], cameraInUse: false, now: start)
        #expect(signal?.title == "Slack huddle")
    }

    @Test func callAppPlayingSoundIsNotAMeeting() {
        var detector = MeetingDetector()
        #expect(detector.evaluate([client("com.tinyspeck.slackmacgap", audio: true)], cameraInUse: false, now: start) == nil)
    }

    @Test func mutedCallStaysAMeetingWhileCallAudioPlays() {
        var detector = MeetingDetector()
        let slack = "com.tinyspeck.slackmacgap"
        _ = detector.evaluate([client(slack, name: "Slack", mic: true, audio: true)], cameraInUse: false, now: start)
        let muted = detector.evaluate([client(slack, name: "Slack", audio: true)], cameraInUse: false, now: start + 600)
        #expect(muted == MeetingSignal(title: "Slack huddle", evidence: "Slack is playing call audio"))
        #expect(detector.evaluate([], cameraInUse: false, now: start + 601) == nil)
        // Once the call audio stops, audio on its own doesn't count again.
        #expect(detector.evaluate([client(slack, audio: true)], cameraInUse: false, now: start + 602) == nil)
    }

    @Test func callAudioStopsCountingAfterTheLimit() {
        var detector = MeetingDetector()
        _ = detector.evaluate([client("us.zoom.xos", mic: true)], cameraInUse: false, now: start)
        let later = start + MeetingDetector.callAudioLimit + 1
        #expect(detector.evaluate([client("us.zoom.xos", audio: true)], cameraInUse: false, now: later) == nil)
    }

    @Test func browserAudioDoesNotKeepACallGoing() {
        var detector = MeetingDetector()
        let chrome = client("com.google.Chrome", name: "Google Chrome", mic: true, audio: true)
        #expect(detector.evaluate([chrome], cameraInUse: false, now: start)?.title == "Call in Google Chrome")
        #expect(detector.evaluate([client("com.google.Chrome", audio: true)], cameraInUse: false, now: start + 2) == nil)
    }

    @Test func faceTimeCallsGetAFriendlyName() {
        var detector = MeetingDetector()
        let daemon = client("com.apple.avconferenced", name: "avconferenced", isApp: false, mic: true)
        #expect(detector.evaluate([daemon], cameraInUse: false, now: start)?.title == "Call in FaceTime")
    }

    @Test func disabledAppsAreIgnored() {
        var detector = MeetingDetector(settings: MeetingDetectionSettings(slack: false))
        #expect(detector.evaluate([client("com.tinyspeck.slackmacgap", mic: true)], cameraInUse: false, now: start) == nil)
    }

    @Test func anyMicrophoneCountsAppsButNotDaemons() {
        var detector = MeetingDetector(settings: MeetingDetectionSettings(anyMicrophone: true))
        #expect(detector.evaluate([client("com.apple.corespeechd", isApp: false, mic: true)], cameraInUse: false, now: start) == nil)
        let recorder = client("com.example.recorder", name: "Recorder", mic: true)
        #expect(detector.evaluate([recorder], cameraInUse: false, now: start)?.evidence == "Recorder is using the microphone")
    }

    @Test func unknownAppsUsingTheMicDoNotCountByDefault() {
        var detector = MeetingDetector()
        #expect(detector.evaluate([client("com.example.recorder", mic: true)], cameraInUse: false, now: start) == nil)
    }

    @Test func cameraCountsWhenEnabled() {
        var detector = MeetingDetector()
        #expect(detector.evaluate([], cameraInUse: true, now: start)?.title == "Camera in use")
        var withoutCamera = MeetingDetector(settings: MeetingDetectionSettings(camera: false))
        #expect(withoutCamera.evaluate([], cameraInUse: true, now: start) == nil)
    }

    @Test func callAppsOutrankTheCamera() {
        var detector = MeetingDetector()
        let signal = detector.evaluate([client("com.microsoft.teams2", mic: true)], cameraInUse: true, now: start)
        #expect(signal?.title == "Teams meeting")
    }

    @Test func turnedOffMeansNothingIsDetected() {
        var detector = MeetingDetector(settings: MeetingDetectionSettings(enabled: false))
        #expect(detector.evaluate([client("us.zoom.xos", mic: true)], cameraInUse: true, now: start) == nil)
    }
}

@Suite struct MeetingDebouncerTests {
    let zoom = MeetingSignal(title: "Zoom meeting", evidence: "Zoom is using the microphone")

    @Test func startsRightAwayAndEndsAfterTheDelay() {
        var debouncer = MeetingDebouncer(endDelay: 20)
        debouncer.update(zoom, now: start)
        #expect(debouncer.activeMeeting == zoom)
        debouncer.update(nil, now: start + 19)
        #expect(debouncer.activeMeeting == zoom)
        debouncer.update(nil, now: start + 20)
        #expect(debouncer.activeMeeting == nil)
    }

    @Test func ignoringLastsUntilTheMeetingEnds() {
        var debouncer = MeetingDebouncer(endDelay: 20)
        debouncer.update(zoom, now: start)
        debouncer.ignoreCurrentMeeting()
        #expect(debouncer.activeMeeting == nil)
        #expect(debouncer.meeting == zoom)
        debouncer.update(zoom, now: start + 100)
        #expect(debouncer.activeMeeting == nil)
        debouncer.update(nil, now: start + 130)
        debouncer.update(zoom, now: start + 200)
        #expect(debouncer.activeMeeting == zoom)
    }
}
