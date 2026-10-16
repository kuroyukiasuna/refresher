import Foundation

/// Smooths the raw meeting signal. A meeting starts the moment it's detected but only ends after
/// nothing has been detected for `endDelay`, so a mic hiccup or switching calls doesn't bring
/// up a break mid-call.
public struct MeetingDebouncer: Sendable {
    public var endDelay: TimeInterval
    /// The meeting in progress, including one the user chose not to pause for.
    public private(set) var meeting: MeetingSignal?
    public private(set) var isIgnored = false
    private var lastSeen: Date?

    public init(endDelay: TimeInterval = 20) {
        self.endDelay = endDelay
    }

    /// The meeting that should pause breaks right now.
    public var activeMeeting: MeetingSignal? { isIgnored ? nil : meeting }

    public mutating func update(_ raw: MeetingSignal?, now: Date) {
        if let raw {
            meeting = raw
            lastSeen = now
        } else if let lastSeen, now.timeIntervalSince(lastSeen) >= endDelay {
            reset()
        }
    }

    /// Keep breaks going during the current meeting. Lasts until the meeting ends.
    public mutating func ignoreCurrentMeeting() {
        if meeting != nil { isIgnored = true }
    }

    public mutating func stopIgnoring() {
        isIgnored = false
    }

    public mutating func reset() {
        meeting = nil
        lastSeen = nil
        isIgnored = false
    }
}
