import Foundation

public enum BreakKind: Equatable, Sendable {
    case short
    case long
}

public struct ScheduleSettings: Equatable, Sendable {
    public var workInterval: TimeInterval
    public var shortBreakDuration: TimeInterval
    public var longBreaksEnabled: Bool
    /// Every Nth break is a long one.
    public var longBreakEvery: Int
    public var longBreakDuration: TimeInterval
    /// How long before a break the heads-up appears. Zero turns it off.
    public var headsUpLead: TimeInterval
    public var postponeDuration: TimeInterval
    /// No keyboard or mouse input for this long counts as a break. Nil turns idle detection off.
    public var awayThreshold: TimeInterval?

    public init(
        workInterval: TimeInterval = 20 * 60,
        shortBreakDuration: TimeInterval = 20,
        longBreaksEnabled: Bool = false,
        longBreakEvery: Int = 3,
        longBreakDuration: TimeInterval = 5 * 60,
        headsUpLead: TimeInterval = 30,
        postponeDuration: TimeInterval = 5 * 60,
        awayThreshold: TimeInterval? = 5 * 60
    ) {
        self.workInterval = workInterval
        self.shortBreakDuration = shortBreakDuration
        self.longBreaksEnabled = longBreaksEnabled
        self.longBreakEvery = longBreakEvery
        self.longBreakDuration = longBreakDuration
        self.headsUpLead = headsUpLead
        self.postponeDuration = postponeDuration
        self.awayThreshold = awayThreshold
    }
}

public enum PauseReason: Equatable, Sendable {
    /// Paused from the menu. `until` is nil when paused until resumed.
    case manual(until: Date?)
    /// Screen locked, screensaver running, displays asleep.
    case screenLocked
    /// A meeting or call is in progress; the value describes it ("Zoom meeting").
    case meeting(String)
    /// No keyboard or mouse input for longer than the away threshold.
    case away
}

public enum Phase: Equatable, Sendable {
    case working
    case onBreak(BreakKind, remaining: TimeInterval, total: TimeInterval)
}

public enum SchedulerEvent: Equatable, Sendable {
    case breakStarted(BreakKind)
    case breakCompleted
    /// A meeting started during a break, so the break was put off until after it.
    case breakInterrupted
}

/// The outside world at one moment, as the scheduler needs to see it.
public struct Conditions: Sendable {
    public var now: Date
    /// Seconds since the last keyboard or mouse input.
    public var idleTime: TimeInterval
    /// The meeting in progress, if any.
    public var meeting: String?
    public var screenLocked: Bool

    public init(now: Date, idleTime: TimeInterval = 0, meeting: String? = nil, screenLocked: Bool = false) {
        self.now = now
        self.idleTime = idleTime
        self.meeting = meeting
        self.screenLocked = screenLocked
    }
}

/// Decides when breaks happen. The app feeds it `Conditions` about once a second and shows
/// whatever phase it ends up in; it has no timers of its own, so it's easy to test.
public struct BreakScheduler: Sendable {
    /// A break cut short by a meeting comes back this long after the meeting ends.
    public static let missedBreakDelay: TimeInterval = 2 * 60
    /// Ticks normally arrive every second; a longer gap means the Mac was asleep.
    static let sleepGap: TimeInterval = 15

    public private(set) var settings: ScheduleSettings
    public private(set) var phase: Phase = .working
    /// Time worked since the last break, not counting pauses.
    public private(set) var workElapsed: TimeInterval = 0
    public private(set) var breaksSinceLongBreak = 0
    public private(set) var pauseReason: PauseReason?

    private var manualPause: ManualPause?
    private var lastTick: Date?
    private var lockedSince: Date?
    private var inMeeting = false
    private var event: SchedulerEvent?

    private struct ManualPause: Sendable {
        var until: Date?
    }

    public init(settings: ScheduleSettings = ScheduleSettings()) {
        self.settings = settings
    }

    public var timeUntilBreak: TimeInterval { max(0, settings.workInterval - workElapsed) }

    public var nextBreakKind: BreakKind {
        settings.longBreaksEnabled && breaksSinceLongBreak + 1 >= settings.longBreakEvery ? .long : .short
    }

    public var isOnBreak: Bool {
        if case .onBreak = phase { return true }
        return false
    }

    public var isManuallyPaused: Bool { manualPause != nil }

    /// Whether the heads-up for the upcoming break should be showing.
    public var isHeadsUp: Bool {
        guard phase == .working, pauseReason == nil, settings.headsUpLead > 0 else { return false }
        return timeUntilBreak <= min(settings.headsUpLead, settings.workInterval / 2)
    }

    public mutating func update(settings newSettings: ScheduleSettings) {
        // Restart the countdown when the interval changes, rather than firing a break mid-edit.
        if newSettings.workInterval != settings.workInterval, !isOnBreak {
            workElapsed = 0
        }
        settings = newSettings
    }

    /// Moves time forward to `conditions.now` and reports what happened, if anything.
    @discardableResult
    public mutating func tick(_ conditions: Conditions) -> SchedulerEvent? {
        event = nil
        let now = conditions.now
        var elapsed = lastTick.map { max(0, now.timeIntervalSince($0)) } ?? 0
        lastTick = now
        let slept = elapsed > Self.sleepGap
        if slept, !isOnBreak {
            // Time asleep is time away from the screen, not work.
            rest(for: elapsed)
            elapsed = 0
        }

        if let until = manualPause?.until, now >= until {
            manualPause = nil
        }

        if conditions.screenLocked {
            if lockedSince == nil { lockedSince = now }
        } else if let since = lockedSince {
            lockedSince = nil
            // During a break the countdown already ran while locked.
            if !isOnBreak { rest(for: now.timeIntervalSince(since)) }
        }

        let meetingStarted = conditions.meeting != nil && !inMeeting
        inMeeting = conditions.meeting != nil
        pauseReason = reason(for: conditions)

        switch phase {
        case let .onBreak(kind, remaining, total):
            // Only a meeting that starts mid-break interrupts it. A break the user starts
            // during a meeting is one they asked for.
            if meetingStarted {
                phase = .working
                workElapsed = max(0, settings.workInterval - Self.missedBreakDelay)
                event = .breakInterrupted
            } else if remaining - elapsed <= 0 {
                // No chime when the break ran out while the Mac was asleep.
                finishBreak(kind, completed: !slept)
            } else {
                phase = .onBreak(kind, remaining: remaining - elapsed, total: total)
            }
        case .working:
            switch pauseReason {
            case nil:
                workElapsed += elapsed
                if workElapsed >= settings.workInterval {
                    startBreak(nextBreakKind)
                }
            case .away?:
                rest(for: conditions.idleTime)
            default:
                break
            }
        }
        return event
    }

    /// Starts a break right away. Pass nil for whichever kind is due next.
    @discardableResult
    public mutating func takeBreak(_ kind: BreakKind? = nil) -> SchedulerEvent? {
        event = nil
        startBreak(kind ?? nextBreakKind)
        return event
    }

    /// Ends the current break early, or skips the upcoming one. Either way the cycle moves on.
    public mutating func skipBreak() {
        if case let .onBreak(kind, _, _) = phase {
            finishBreak(kind, completed: false)
        } else {
            finishBreak(nextBreakKind, completed: false)
        }
    }

    /// Pushes the current or upcoming break back by the postpone duration.
    public mutating func postpone() {
        phase = .working
        workElapsed = max(0, settings.workInterval - settings.postponeDuration)
    }

    /// Starts the work countdown over without counting a break.
    public mutating func restartTimer() {
        phase = .working
        workElapsed = 0
    }

    /// Pauses breaks until `date`, or until `resume()` if `date` is nil. Ends a break in progress.
    public mutating func pause(until date: Date?) {
        if case let .onBreak(kind, _, _) = phase {
            finishBreak(kind, completed: false)
        }
        manualPause = ManualPause(until: date)
        pauseReason = .manual(until: date)
    }

    public mutating func resume() {
        manualPause = nil
        if case .manual? = pauseReason { pauseReason = nil }
    }

    private func reason(for conditions: Conditions) -> PauseReason? {
        if let manualPause { return .manual(until: manualPause.until) }
        if conditions.screenLocked { return .screenLocked }
        if let meeting = conditions.meeting { return .meeting(meeting) }
        if let threshold = settings.awayThreshold, conditions.idleTime >= threshold { return .away }
        return nil
    }

    /// Time verifiably away from the screen counts as a break.
    private mutating func rest(for duration: TimeInterval) {
        if duration >= settings.shortBreakDuration { workElapsed = 0 }
        if duration >= settings.longBreakDuration { breaksSinceLongBreak = 0 }
    }

    private mutating func startBreak(_ kind: BreakKind) {
        let length = kind == .long ? settings.longBreakDuration : settings.shortBreakDuration
        phase = .onBreak(kind, remaining: length, total: length)
        event = .breakStarted(kind)
    }

    private mutating func finishBreak(_ kind: BreakKind, completed: Bool) {
        phase = .working
        workElapsed = 0
        breaksSinceLongBreak = kind == .long ? 0 : breaksSinceLongBreak + 1
        if completed { event = .breakCompleted }
    }
}
