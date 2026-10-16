import Foundation

public enum Format {
    /// "20 sec", "5 min", "1 min 30 sec", "1 hr 15 min".
    public static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600, minutes = total % 3600 / 60, secs = total % 60
        var parts: [String] = []
        if hours > 0 { parts.append("\(hours) hr") }
        if minutes > 0 { parts.append("\(minutes) min") }
        if secs > 0 || parts.isEmpty { parts.append("\(secs) sec") }
        return parts.joined(separator: " ")
    }

    /// Countdown clock, rounded up so it never shows 0:00 while time remains: "0:20", "4:05", "1:02:03".
    public static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        let hours = total / 3600, minutes = total % 3600 / 60, secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }

    /// Compact menu bar countdown: whole minutes ("18m") until the last minute, then a clock ("0:42").
    public static func menuBar(_ seconds: TimeInterval) -> String {
        seconds > 60 ? "\(Int((seconds / 60).rounded(.up)))m" : clock(seconds)
    }

    /// Time left for use in a sentence: "18 min", "1 hr 30 min", "45 sec".
    public static func approximate(_ seconds: TimeInterval) -> String {
        seconds > 60 ? duration((seconds / 60).rounded(.up) * 60) : duration(seconds.rounded(.up))
    }
}
