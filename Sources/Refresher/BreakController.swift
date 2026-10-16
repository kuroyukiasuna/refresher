import AppKit
import Combine
import RefresherCore

/// What the menu bar shows.
struct DisplayState: Equatable {
    var phase: Phase = .working
    var timeUntilBreak: TimeInterval = 0
    var isHeadsUp = false
    var pauseReason: PauseReason?
    var nextBreakKind: BreakKind = .short
    /// The meeting currently detected, even one the user chose not to pause for.
    var meeting: MeetingSignal?
    var ignoringMeeting = false
}

/// Connects the scheduler to the real world (a one-second tick, idle time, screen lock, meeting
/// detection) and keeps the heads-up and break screen in step with it.
@MainActor
final class BreakController: ObservableObject {
    @Published private(set) var state = DisplayState()
    let detection = DetectionStatus()

    private let prefs: Preferences
    private var scheduler: BreakScheduler
    private var detector: MeetingDetector
    private var meetings = MeetingDebouncer()
    private var rawMeeting: MeetingSignal?
    private var audio = AudioSnapshot()
    private let audioMonitor = AudioActivityMonitor()
    private let system = SystemStateMonitor()
    private let overlay = BreakOverlay()
    private let headsUp = HeadsUpPanel()
    private var timer: Timer?
    private var noAppNap: NSObjectProtocol?
    private var settingsSubscription: AnyCancellable?

    init(prefs: Preferences) {
        self.prefs = prefs
        scheduler = BreakScheduler(settings: prefs.schedule)
        detector = MeetingDetector(settings: prefs.meetingDetection)
    }

    func start() {
        overlay.onSkip = { [weak self] in self?.skipBreak() }
        overlay.onPostpone = { [weak self] in self?.postpone() }
        headsUp.onStartNow = { [weak self] in self?.takeBreakNow() }
        headsUp.onPostpone = { [weak self] in self?.postpone() }
        headsUp.onSkip = { [weak self] in self?.skipBreak() }
        system.onChange = { [weak self] in self?.tick() }

        audioMonitor.start { [weak self] snapshot in
            guard let self else { return }
            audio = snapshot
            evaluateMeeting()
        }
        // objectWillChange fires before the new value is stored, so act on the next turn.
        settingsSubscription = prefs.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.settingsChanged() }

        // App Nap would throttle the tick, and a long enough gap looks like the Mac slept,
        // which counts as a break. The Mac can still sleep normally.
        noAppNap = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep, reason: "Timing the next break")
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.1
        // .common keeps it ticking while the menu is open.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        tick()
    }

    // MARK: Actions

    func takeBreakNow(_ kind: BreakKind? = nil) {
        play(scheduler.takeBreak(kind))
        render()
    }

    func skipBreak() {
        scheduler.skipBreak()
        render()
    }

    func postpone() {
        scheduler.postpone()
        render()
    }

    func restartTimer() {
        scheduler.restartTimer()
        render()
    }

    /// Pauses for `duration`, or until resumed if nil.
    func pause(for duration: TimeInterval?) {
        scheduler.pause(until: duration.map { Date().addingTimeInterval($0) })
        render()
    }

    func resume() {
        scheduler.resume()
        tick()
    }

    func setIgnoringMeeting(_ ignoring: Bool) {
        if ignoring {
            meetings.ignoreCurrentMeeting()
        } else {
            meetings.stopIgnoring()
        }
        tick()
    }

    // MARK: Updates

    private func tick() {
        let now = Date()
        scheduler.update(settings: prefs.schedule)
        meetings.update(rawMeeting, now: now)
        let conditions = Conditions(
            now: now,
            idleTime: SystemStateMonitor.idleTime(),
            meeting: meetings.activeMeeting?.title,
            screenLocked: system.isAway)
        play(scheduler.tick(conditions))
        render()
    }

    private func evaluateMeeting() {
        detector.settings = prefs.meetingDetection
        rawMeeting = detector.evaluate(audio.clients, cameraInUse: audio.cameraInUse, now: Date())
        detection.update(enabled: prefs.pauseForMeetings, meeting: rawMeeting, audio: audio)
    }

    private func settingsChanged() {
        evaluateMeeting()
        // Turning detection off should take effect now, not after the end-of-meeting grace period.
        if rawMeeting == nil { meetings.reset() }
        tick()
    }

    private func render() {
        switch scheduler.phase {
        case let .onBreak(kind, remaining, total):
            headsUp.hide()
            overlay.show(kind: kind, remaining: remaining, total: total,
                         postponeTitle: "Postpone \(Format.duration(prefs.postponeDuration))")
        case .working:
            overlay.hide()
            if scheduler.isHeadsUp {
                headsUp.show(timeLeft: scheduler.timeUntilBreak, kind: scheduler.nextBreakKind)
            } else {
                headsUp.hide()
            }
        }

        let newState = DisplayState(
            phase: scheduler.phase,
            timeUntilBreak: scheduler.timeUntilBreak,
            isHeadsUp: scheduler.isHeadsUp,
            pauseReason: scheduler.pauseReason,
            nextBreakKind: scheduler.nextBreakKind,
            meeting: meetings.meeting,
            ignoringMeeting: meetings.isIgnored)
        if newState != state { state = newState }
    }

    private func play(_ event: SchedulerEvent?) {
        guard prefs.playSounds, let event else { return }
        switch event {
        case .breakStarted: NSSound(named: "Purr")?.play()
        case .breakCompleted: NSSound(named: "Glass")?.play()
        case .breakInterrupted: break
        }
    }
}

/// Live readout of meeting detection for the settings window.
@MainActor
final class DetectionStatus: ObservableObject {
    @Published private(set) var summary = "Checking…"
    @Published private(set) var detail: String?

    func update(enabled: Bool, meeting: MeetingSignal?, audio: AudioSnapshot) {
        let newSummary: String
        let newDetail: String?
        if !enabled {
            newSummary = "Smart pause is off"
            newDetail = nil
        } else if let meeting {
            newSummary = meeting.title
            newDetail = meeting.evidence
        } else {
            newSummary = "No meeting detected"
            let micApps = Set(audio.clients.filter(\.usesMicrophone).map(\.name)).sorted()
            var activity: [String] = []
            if !micApps.isEmpty { activity.append("Mic in use by \(micApps.joined(separator: ", "))") }
            if audio.cameraInUse { activity.append("Camera is on") }
            newDetail = activity.isEmpty ? nil : activity.joined(separator: " · ")
        }
        if newSummary != summary { summary = newSummary }
        if newDetail != detail { detail = newDetail }
    }
}
