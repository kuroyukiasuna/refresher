import AppKit

/// Tracks when the user is verifiably away: screen locked, screensaver on, displays or the
/// whole Mac asleep, or switched to another user account.
@MainActor
final class SystemStateMonitor {
    var onChange: (() -> Void)?
    var isAway: Bool { !awayReasons.isEmpty }

    private var awayReasons: Set<String> = []
    private var observers: [NSObjectProtocol] = []

    init() {
        if Self.isScreenLocked() { awayReasons.insert("locked") }
        let workspace = NSWorkspace.shared.notificationCenter
        track("asleep", in: workspace, starts: NSWorkspace.willSleepNotification, ends: NSWorkspace.didWakeNotification)
        track("displays off", in: workspace, starts: NSWorkspace.screensDidSleepNotification, ends: NSWorkspace.screensDidWakeNotification)
        track("other user", in: workspace, starts: NSWorkspace.sessionDidResignActiveNotification, ends: NSWorkspace.sessionDidBecomeActiveNotification)
        let distributed = DistributedNotificationCenter.default()
        track("locked", in: distributed, starts: .init("com.apple.screenIsLocked"), ends: .init("com.apple.screenIsUnlocked"))
        track("screensaver", in: distributed, starts: .init("com.apple.screensaver.didstart"), ends: .init("com.apple.screensaver.didstop"))
    }

    /// Seconds since the last keyboard, mouse or trackpad input. Needs no permission.
    static func idleTime() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: CGEventType(rawValue: ~0)!)
    }

    private func track(_ reason: String, in center: NotificationCenter, starts: Notification.Name, ends: Notification.Name) {
        for (name, isStart) in [(starts, true), (ends, false)] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if isStart {
                        self.awayReasons.insert(reason)
                    } else {
                        self.awayReasons.remove(reason)
                    }
                    self.onChange?()
                }
            })
        }
    }

    private static func isScreenLocked() -> Bool {
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        return session?["CGSSessionScreenIsLocked"] as? Bool ?? false
    }
}
