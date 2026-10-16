import Foundation

/// A process using Core Audio, attributed to the app that owns it.
public struct AudioClient: Equatable, Sendable {
    public var pid: Int32
    /// Bundle ID of the owning app (Slack Helper counts as Slack), or the process's own ID
    /// if it isn't part of an app.
    public var bundleID: String
    public var name: String
    /// False for daemons and command-line tools.
    public var isApp: Bool
    public var usesMicrophone: Bool
    public var playsAudio: Bool

    public init(pid: Int32, bundleID: String, name: String, isApp: Bool, usesMicrophone: Bool, playsAudio: Bool) {
        self.pid = pid
        self.bundleID = bundleID
        self.name = name
        self.isApp = isApp
        self.usesMicrophone = usesMicrophone
        self.playsAudio = playsAudio
    }
}

public struct MeetingSignal: Equatable, Sendable {
    /// Short label such as "Zoom meeting" or "Slack huddle".
    public var title: String
    /// What gave it away, such as "Zoom is using the microphone".
    public var evidence: String

    public init(title: String, evidence: String) {
        self.title = title
        self.evidence = evidence
    }
}

/// Apps that Refresher recognizes as calls when they use the microphone.
public enum CallApp: CaseIterable, Sendable {
    case zoom
    case teams
    case slack
    case otherCallApp
    case browser

    /// Matches a bundle ID exactly or anything nested under it, so "com.google.chrome"
    /// covers "com.google.Chrome.helper" but not "com.google.chromecast".
    public static func classify(_ bundleID: String) -> CallApp? {
        let id = bundleID.lowercased()
        return allCases.first { app in
            app.bundleIDs.contains { id == $0 || id.hasPrefix($0 + ".") }
        }
    }

    var bundleIDs: [String] {
        switch self {
        case .zoom: ["us.zoom"]
        case .teams: ["com.microsoft.teams", "com.microsoft.teams2", "com.microsoft.vcxpc"]
        case .slack: ["com.tinyspeck.slackmacgap"]
        case .otherCallApp: [
            "com.apple.facetime", "com.apple.avconferenced",
            "com.cisco.webexmeetingsapp", "com.webex.meetingmanager", "cisco-systems.spark",
            "com.hnc.discord", "com.skype.skype", "com.logmein.gotomeeting", "com.logmein.goto",
            "com.amazon.amazon-chime", "com.ringcentral.glip", "co.teamport.around", "app.tuple.app",
            "net.whatsapp.whatsapp", "org.whispersystems.signal-desktop", "com.loom.desktop",
        ]
        case .browser: [
            "com.google.chrome", "com.apple.safari", "com.apple.safaritechnologypreview",
            "com.microsoft.edgemac", "company.thebrowser.browser", "company.thebrowser.dia",
            "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition", "org.mozilla.nightly",
            "com.brave.browser", "com.operasoftware.opera", "com.vivaldi.vivaldi",
            "app.zen-browser.zen", "org.chromium.chromium", "com.kagi.kagimacos",
        ]
        }
    }

    /// The app's own bundle IDs, for checking whether it's installed. Nil for the groups of
    /// apps, which are always offered.
    public var appBundleIDs: [String]? {
        switch self {
        case .zoom: ["us.zoom.xos"]
        case .teams: ["com.microsoft.teams2", "com.microsoft.teams"]
        case .slack: ["com.tinyspeck.slackmacgap"]
        case .otherCallApp, .browser: nil
        }
    }

    func displayName(bundleID: String, fallback: String) -> String {
        switch self {
        case .zoom: "Zoom"
        case .teams: "Microsoft Teams"
        case .slack: "Slack"
        // FaceTime calls run in a system daemon.
        case .otherCallApp where bundleID.lowercased() == "com.apple.avconferenced": "FaceTime"
        case .otherCallApp, .browser: fallback
        }
    }

    func meetingTitle(appName: String) -> String {
        switch self {
        case .zoom: "Zoom meeting"
        case .teams: "Teams meeting"
        case .slack: "Slack huddle"
        case .otherCallApp, .browser: "Call in \(appName)"
        }
    }

    /// Dedicated call apps only play continuous audio during a call, so once one has used the mic,
    /// its call audio alone keeps the meeting going (some let go of the mic while you're muted).
    /// Browsers don't get this, since they also play videos.
    var callAudioKeepsMeetingGoing: Bool { self != .browser }

    /// Lower wins when several things are detected at once.
    var rank: Int {
        switch self {
        case .zoom, .teams, .slack: 0
        case .otherCallApp: 1
        case .browser: 2
        }
    }
}

public struct MeetingDetectionSettings: Equatable, Sendable {
    public var enabled: Bool
    public var zoom: Bool
    public var teams: Bool
    public var slack: Bool
    public var browsers: Bool
    public var otherCallApps: Bool
    public var camera: Bool
    public var anyMicrophone: Bool

    public init(
        enabled: Bool = true,
        zoom: Bool = true,
        teams: Bool = true,
        slack: Bool = true,
        browsers: Bool = true,
        otherCallApps: Bool = true,
        camera: Bool = true,
        anyMicrophone: Bool = false
    ) {
        self.enabled = enabled
        self.zoom = zoom
        self.teams = teams
        self.slack = slack
        self.browsers = browsers
        self.otherCallApps = otherCallApps
        self.camera = camera
        self.anyMicrophone = anyMicrophone
    }

    func includes(_ app: CallApp) -> Bool {
        switch app {
        case .zoom: zoom
        case .teams: teams
        case .slack: slack
        case .otherCallApp: otherCallApps
        case .browser: browsers
        }
    }
}

/// Turns a snapshot of who's using the microphone, speakers and camera into "is there a meeting?".
public struct MeetingDetector: Sendable {
    /// How long a call app's audio can keep a meeting going after the app last used the mic.
    public static let callAudioLimit: TimeInterval = 2 * 60 * 60

    public var settings: MeetingDetectionSettings
    /// Call apps seen using the mic, keyed by bundle ID, with when they last used it.
    private var micLastUsed: [String: Date] = [:]

    public init(settings: MeetingDetectionSettings = MeetingDetectionSettings()) {
        self.settings = settings
    }

    public mutating func evaluate(_ clients: [AudioClient], cameraInUse: Bool, now: Date) -> MeetingSignal? {
        guard settings.enabled else {
            micLastUsed = [:]
            return nil
        }

        var found: [(rank: Int, signal: MeetingSignal)] = []
        var inCall: [String: Date] = [:]

        for (bundleID, processes) in Dictionary(grouping: clients, by: \.bundleID) {
            let usesMicrophone = processes.contains { $0.usesMicrophone }
            let playsAudio = processes.contains { $0.playsAudio }
            let name = processes[0].name

            if let app = CallApp.classify(bundleID), settings.includes(app) {
                let appName = app.displayName(bundleID: bundleID, fallback: name)
                let title = app.meetingTitle(appName: appName)
                if usesMicrophone {
                    inCall[bundleID] = now
                    found.append((app.rank, MeetingSignal(title: title, evidence: "\(appName) is using the microphone")))
                } else if playsAudio, app.callAudioKeepsMeetingGoing,
                          let lastUsed = micLastUsed[bundleID], now.timeIntervalSince(lastUsed) < Self.callAudioLimit {
                    inCall[bundleID] = lastUsed
                    found.append((app.rank, MeetingSignal(title: title, evidence: "\(appName) is playing call audio")))
                }
            } else if settings.anyMicrophone, usesMicrophone, processes.contains(where: { $0.isApp }) {
                found.append((4, MeetingSignal(title: "Microphone in use", evidence: "\(name) is using the microphone")))
            }
        }
        micLastUsed = inCall

        if settings.camera, cameraInUse {
            found.append((3, MeetingSignal(title: "Camera in use", evidence: "An app is using the camera")))
        }
        return found.min { ($0.rank, $0.signal.title) < ($1.rank, $1.signal.title) }?.signal
    }
}
