import AppKit
import Combine
import RefresherCore

/// The menu bar icon, its countdown, and its menu.
@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let controller: BreakController
    private let prefs: Preferences
    private let openSettings: () -> Void
    private var headlineItem: NSMenuItem?
    private var subscriptions: Set<AnyCancellable> = []
    private var shownSymbol = ""
    private var shownTitle = ""

    private static let pauseOptions: [(title: String, duration: TimeInterval?)] = [
        ("For 15 Minutes", 15 * 60),
        ("For 30 Minutes", 30 * 60),
        ("For 1 Hour", 60 * 60),
        ("For 2 Hours", 2 * 60 * 60),
        ("Until I Resume", nil),
    ]

    init(controller: BreakController, prefs: Preferences, openSettings: @escaping () -> Void) {
        self.controller = controller
        self.prefs = prefs
        self.openSettings = openSettings
        super.init()

        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        if let button = statusItem.button {
            button.imagePosition = .imageLeading
            button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        }

        // @Published emits before storing, so use the values handed to the sinks.
        controller.$state
            .sink { [weak self] state in
                guard let self else { return }
                render(state, showCountdown: prefs.showCountdownInMenuBar)
            }
            .store(in: &subscriptions)
        prefs.$showCountdownInMenuBar
            .sink { [weak self] showCountdown in
                guard let self else { return }
                render(self.controller.state, showCountdown: showCountdown)
            }
            .store(in: &subscriptions)
    }

    private func render(_ state: DisplayState, showCountdown: Bool) {
        guard let button = statusItem.button else { return }
        let symbol: String
        var title = ""
        switch (state.phase, state.pauseReason) {
        case (.onBreak, _): symbol = "leaf"
        case (_, .meeting?): symbol = "video"
        case (_, .manual?): symbol = "pause.circle"
        case (_, .screenLocked?), (_, .away?): symbol = "moon.zzz"
        case (_, nil):
            symbol = "eye"
            if showCountdown { title = Format.menuBar(state.timeUntilBreak) }
        }
        if symbol != shownSymbol {
            shownSymbol = symbol
            let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Refresher")
            image?.isTemplate = true
            button.image = image
        }
        if title != shownTitle {
            shownTitle = title
            button.title = title
        }
        button.toolTip = state.headline
        // Keeps the top line of an open menu live.
        headlineItem?.attributedTitle = Self.headline(state.headline)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let state = controller.state

        let headline = NSMenuItem(title: state.headline, action: nil, keyEquivalent: "")
        headline.attributedTitle = Self.headline(state.headline)
        headline.isEnabled = false
        menu.addItem(headline)
        headlineItem = headline

        if let meeting = state.meeting {
            let detail = NSMenuItem(
                title: state.ignoringMeeting ? "\(meeting.title): not pausing" : meeting.evidence,
                action: nil, keyEquivalent: "")
            detail.isEnabled = false
            menu.addItem(detail)
        }
        menu.addItem(.separator())

        if case .onBreak = state.phase {
            menu.addItem(ActionMenuItem("End Break") { [weak self] in self?.controller.skipBreak() })
        } else {
            menu.addItem(ActionMenuItem("Take a Break Now") { [weak self] in self?.controller.takeBreakNow() })
            if prefs.longBreaksEnabled {
                menu.addItem(ActionMenuItem("Take a Long Break Now") { [weak self] in self?.controller.takeBreakNow(.long) })
            }
            menu.addItem(ActionMenuItem("Restart Timer") { [weak self] in self?.controller.restartTimer() })
        }
        menu.addItem(.separator())

        if case .manual? = state.pauseReason {
            menu.addItem(ActionMenuItem("Resume") { [weak self] in self?.controller.resume() })
        } else {
            let pauseMenu = NSMenu()
            for option in Self.pauseOptions {
                pauseMenu.addItem(ActionMenuItem(option.title) { [weak self] in self?.controller.pause(for: option.duration) })
            }
            let pause = NSMenuItem(title: "Pause Breaks", action: nil, keyEquivalent: "")
            pause.submenu = pauseMenu
            menu.addItem(pause)
        }
        if state.meeting != nil {
            let ignore = ActionMenuItem("Don't Pause for This Meeting") { [weak self] in
                self?.controller.setIgnoringMeeting(!state.ignoringMeeting)
            }
            ignore.state = state.ignoringMeeting ? .on : .off
            menu.addItem(ignore)
        }
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem("Settings…", key: ",") { [weak self] in self?.openSettings() })
        menu.addItem(ActionMenuItem("Quit Refresher", key: "q") { NSApp.terminate(nil) })
    }

    /// Disabled items draw gray; this keeps the status line readable.
    private static func headline(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: NSColor.labelColor,
        ])
    }
}

extension DisplayState {
    var headline: String {
        if case let .onBreak(_, remaining, _) = phase {
            return "On a break, \(Format.clock(remaining)) left"
        }
        switch pauseReason {
        case let .manual(until)?:
            guard let until else { return "Paused" }
            return "Paused until \(until.formatted(date: .omitted, time: .shortened))"
        case let .meeting(title)?:
            return "Paused — \(title)"
        case .screenLocked?:
            return "Paused while the screen is locked"
        case .away?:
            return "Paused while you're away"
        case nil:
            if isHeadsUp {
                return "\(nextBreakKind == .long ? "Long break" : "Break") in \(Format.clock(timeUntilBreak))"
            }
            return "Next \(nextBreakKind == .long ? "long break" : "break") in \(Format.approximate(timeUntilBreak))"
        }
    }
}
