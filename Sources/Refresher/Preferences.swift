import Foundation
import RefresherCore

/// User settings, saved to UserDefaults as they change. Durations are in seconds, so short
/// values for testing work too: `defaults write dev.refresher.Refresher workInterval -float 30`.
@MainActor
final class Preferences: ObservableObject {
    @Published var workInterval: TimeInterval { didSet { save(workInterval, .workInterval) } }
    @Published var shortBreakDuration: TimeInterval { didSet { save(shortBreakDuration, .shortBreakDuration) } }
    @Published var longBreaksEnabled: Bool { didSet { save(longBreaksEnabled, .longBreaksEnabled) } }
    @Published var longBreakEvery: Int { didSet { save(longBreakEvery, .longBreakEvery) } }
    @Published var longBreakDuration: TimeInterval { didSet { save(longBreakDuration, .longBreakDuration) } }
    @Published var headsUpEnabled: Bool { didSet { save(headsUpEnabled, .headsUpEnabled) } }
    @Published var headsUpLead: TimeInterval { didSet { save(headsUpLead, .headsUpLead) } }
    @Published var postponeDuration: TimeInterval { didSet { save(postponeDuration, .postponeDuration) } }
    @Published var playSounds: Bool { didSet { save(playSounds, .playSounds) } }
    @Published var awayResetEnabled: Bool { didSet { save(awayResetEnabled, .awayResetEnabled) } }
    @Published var awayThreshold: TimeInterval { didSet { save(awayThreshold, .awayThreshold) } }
    @Published var showCountdownInMenuBar: Bool { didSet { save(showCountdownInMenuBar, .showCountdownInMenuBar) } }

    @Published var pauseForMeetings: Bool { didSet { save(pauseForMeetings, .pauseForMeetings) } }
    @Published var detectZoom: Bool { didSet { save(detectZoom, .detectZoom) } }
    @Published var detectTeams: Bool { didSet { save(detectTeams, .detectTeams) } }
    @Published var detectSlack: Bool { didSet { save(detectSlack, .detectSlack) } }
    @Published var detectBrowsers: Bool { didSet { save(detectBrowsers, .detectBrowsers) } }
    @Published var detectOtherCallApps: Bool { didSet { save(detectOtherCallApps, .detectOtherCallApps) } }
    @Published var detectCamera: Bool { didSet { save(detectCamera, .detectCamera) } }
    @Published var detectAnyMicrophone: Bool { didSet { save(detectAnyMicrophone, .detectAnyMicrophone) } }

    var hasLaunchedBefore: Bool {
        get { defaults.bool(forKey: Key.hasLaunchedBefore.rawValue) }
        set { defaults.set(newValue, forKey: Key.hasLaunchedBefore.rawValue) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        func load<T>(_ key: Key, _ fallback: T) -> T {
            defaults.object(forKey: key.rawValue) as? T ?? fallback
        }
        workInterval = load(.workInterval, 20 * 60)
        shortBreakDuration = load(.shortBreakDuration, 20)
        longBreaksEnabled = load(.longBreaksEnabled, false)
        longBreakEvery = load(.longBreakEvery, 3)
        longBreakDuration = load(.longBreakDuration, 5 * 60)
        headsUpEnabled = load(.headsUpEnabled, true)
        headsUpLead = load(.headsUpLead, 30)
        postponeDuration = load(.postponeDuration, 5 * 60)
        playSounds = load(.playSounds, true)
        awayResetEnabled = load(.awayResetEnabled, true)
        awayThreshold = load(.awayThreshold, 5 * 60)
        showCountdownInMenuBar = load(.showCountdownInMenuBar, true)
        pauseForMeetings = load(.pauseForMeetings, true)
        detectZoom = load(.detectZoom, true)
        detectTeams = load(.detectTeams, true)
        detectSlack = load(.detectSlack, true)
        detectBrowsers = load(.detectBrowsers, true)
        detectOtherCallApps = load(.detectOtherCallApps, true)
        detectCamera = load(.detectCamera, true)
        detectAnyMicrophone = load(.detectAnyMicrophone, false)
    }

    var schedule: ScheduleSettings {
        ScheduleSettings(
            workInterval: max(workInterval, 5),
            shortBreakDuration: max(shortBreakDuration, 1),
            longBreaksEnabled: longBreaksEnabled,
            longBreakEvery: max(longBreakEvery, 2),
            longBreakDuration: max(longBreakDuration, 1),
            headsUpLead: headsUpEnabled ? headsUpLead : 0,
            postponeDuration: postponeDuration,
            awayThreshold: awayResetEnabled ? awayThreshold : nil)
    }

    var meetingDetection: MeetingDetectionSettings {
        MeetingDetectionSettings(
            enabled: pauseForMeetings,
            zoom: detectZoom,
            teams: detectTeams,
            slack: detectSlack,
            browsers: detectBrowsers,
            otherCallApps: detectOtherCallApps,
            camera: detectCamera,
            anyMicrophone: detectAnyMicrophone)
    }

    private func save(_ value: Any, _ key: Key) {
        defaults.set(value, forKey: key.rawValue)
    }

    private enum Key: String {
        case workInterval, shortBreakDuration, longBreaksEnabled, longBreakEvery, longBreakDuration
        case headsUpEnabled, headsUpLead, postponeDuration, playSounds
        case awayResetEnabled, awayThreshold, showCountdownInMenuBar
        case pauseForMeetings, detectZoom, detectTeams, detectSlack, detectBrowsers
        case detectOtherCallApps, detectCamera, detectAnyMicrophone
        case hasLaunchedBefore
    }
}
