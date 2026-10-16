import AppKit
import RefresherCore
import SwiftUI

@MainActor
final class SettingsWindowController {
    private let prefs: Preferences
    private let detection: DetectionStatus
    private let loginItem = LoginItem()
    private let callApps = InstalledCallApps()
    private var window: NSWindow?

    init(prefs: Preferences, detection: DetectionStatus) {
        self.prefs = prefs
        self.detection = detection
    }

    func show() {
        loginItem.refresh()
        callApps.refresh()
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(
            rootView: SettingsView(prefs: prefs, detection: detection, loginItem: loginItem, callApps: callApps)))
        window.title = "Refresher Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}

private struct SettingsView: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var detection: DetectionStatus
    @ObservedObject var loginItem: LoginItem
    @ObservedObject var callApps: InstalledCallApps

    var body: some View {
        Form {
            breaks
            smartPause
            reminders
            away
            general
        }
        .formStyle(.grouped)
        .frame(width: 500)
        .frame(minHeight: 400, idealHeight: 780)
    }

    private var breaks: some View {
        Section("Breaks") {
            MinutesField(title: "Remind me every", seconds: $prefs.workInterval, range: 1...240)
            Picker("Break length", selection: $prefs.shortBreakDuration) {
                durationOptions([10, 15, 20, 30, 45, 60, 90, 120, 180, 300], including: prefs.shortBreakDuration)
            }
            Toggle(isOn: $prefs.longBreaksEnabled) {
                Text("Long breaks")
                Text("Every few breaks, step away for longer.")
            }
            if prefs.longBreaksEnabled {
                Picker("Make long", selection: $prefs.longBreakEvery) {
                    ForEach(2...8, id: \.self) { Text("Every \(Self.ordinal($0)) break").tag($0) }
                }
                MinutesField(title: "Long break length", seconds: $prefs.longBreakDuration, range: 1...60)
            }
        }
    }

    private var reminders: some View {
        Section("Reminders") {
            Toggle("Heads-up before each break", isOn: $prefs.headsUpEnabled)
            if prefs.headsUpEnabled {
                Picker("Show it", selection: $prefs.headsUpLead) {
                    durationOptions([10, 30, 60], including: prefs.headsUpLead, suffix: " before")
                }
            }
            Picker("Postpone by", selection: $prefs.postponeDuration) {
                durationOptions([60, 120, 300, 600, 900], including: prefs.postponeDuration)
            }
            Toggle(isOn: $prefs.playSounds) {
                Text("Play sounds")
                Text("A soft chime when a break starts and ends.")
            }
        }
    }

    private var smartPause: some View {
        Section {
            Toggle("Pause during meetings and calls", isOn: $prefs.pauseForMeetings)
            Group {
                if callApps.contains(.zoom) { Toggle("Zoom", isOn: $prefs.detectZoom) }
                if callApps.contains(.teams) { Toggle("Microsoft Teams", isOn: $prefs.detectTeams) }
                if callApps.contains(.slack) { Toggle("Slack huddles", isOn: $prefs.detectSlack) }
                Toggle(isOn: $prefs.detectBrowsers) {
                    Text("Calls in a web browser")
                    Text("Google Meet, or Teams and Zoom on the web")
                }
                Toggle(isOn: $prefs.detectOtherCallApps) {
                    Text("Other call apps")
                    Text("FaceTime, Webex, Discord, Skype and more")
                }
                Toggle("Any app using the camera", isOn: $prefs.detectCamera)
                Toggle(isOn: $prefs.detectAnyMicrophone) {
                    Text("Any app using the microphone")
                    Text("Also pauses for dictation, voice memos and the like")
                }
            }
            .disabled(!prefs.pauseForMeetings)
            LabeledContent("Right now") {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(detection.summary)
                    if let detail = detection.detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Smart pause")
        } footer: {
            Text("Refresher only checks which apps have the microphone or camera open. It never records or listens to anything.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var away: some View {
        Section("Stepping away") {
            Toggle(isOn: $prefs.awayResetEnabled) {
                Text("Count time away as a break")
                Text("Locking the screen or sleeping the Mac always counts.")
            }
            if prefs.awayResetEnabled {
                Picker("Away after no activity for", selection: $prefs.awayThreshold) {
                    durationOptions([120, 180, 300, 600, 900], including: prefs.awayThreshold)
                }
            }
        }
    }

    private var general: some View {
        Section("General") {
            Toggle("Show countdown in the menu bar", isOn: $prefs.showCountdownInMenuBar)
            Toggle("Launch at login", isOn: Binding(get: { loginItem.isEnabled }, set: loginItem.setEnabled))
            if let message = loginItem.message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Picker rows for preset durations, plus the current value if it was set to something
    /// else (with `defaults write`, say), so the picker never shows up blank.
    private func durationOptions(_ presets: [TimeInterval], including current: TimeInterval, suffix: String = "") -> some View {
        let values = presets.contains(current) ? presets : (presets + [current]).sorted()
        return ForEach(values, id: \.self) { Text(Format.duration($0) + suffix).tag($0) }
    }

    private static func ordinal(_ n: Int) -> String {
        switch n {
        case 2: "2nd"
        case 3: "3rd"
        default: "\(n)th"
        }
    }
}

/// Whole minutes, typed or stepped, stored as seconds.
private struct MinutesField: View {
    let title: String
    @Binding var seconds: TimeInterval
    let range: ClosedRange<Int>

    var body: some View {
        let minutes = Binding<Int>(
            get: { Int((seconds / 60).rounded()) },
            set: { seconds = TimeInterval(min(max($0, range.lowerBound), range.upperBound)) * 60 })
        LabeledContent(title) {
            HStack(spacing: 6) {
                TextField(title, value: minutes, format: .number)
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 52)
                Text("min")
                    .foregroundStyle(.secondary)
                Stepper(title, value: minutes, in: range)
                    .labelsHidden()
            }
        }
    }
}
