import AppKit

@main
enum RefresherApp {
    @MainActor
    static func main() {
        let arguments = CommandLine.arguments
        if arguments.contains("--detect") {
            DetectCommand.run(once: arguments.contains("--once"))
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // Menu bar only, no Dock icon. Info.plist says so too; this covers `swift run`.
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let prefs = Preferences()
    private lazy var controller = BreakController(prefs: prefs)
    private lazy var settingsWindow = SettingsWindowController(prefs: prefs, detection: controller.detection)
    private var statusBar: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.make { [weak self] in self?.settingsWindow.show() }
        statusBar = StatusBarController(controller: controller, prefs: prefs) { [weak self] in
            self?.settingsWindow.show()
        }
        controller.start()
        if !prefs.hasLaunchedBefore {
            prefs.hasLaunchedBefore = true
            settingsWindow.show()
        }
    }
}
