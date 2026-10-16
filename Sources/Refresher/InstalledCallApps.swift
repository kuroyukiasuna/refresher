import AppKit
import RefresherCore

/// Which call apps are on this Mac, so Settings only offers switches for those. None of them
/// is required: detection never sees an app that isn't installed, so there's nothing to turn off.
@MainActor
final class InstalledCallApps: ObservableObject {
    @Published private(set) var apps: Set<CallApp> = []

    init() {
        refresh()
    }

    func contains(_ app: CallApp) -> Bool { apps.contains(app) }

    /// Picks up apps installed or removed since the last check.
    func refresh() {
        let installed = Set(CallApp.allCases.filter { app in
            guard let bundleIDs = app.appBundleIDs else { return true }
            return bundleIDs.contains { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }
        })
        if installed != apps { apps = installed }
    }
}
