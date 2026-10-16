import Foundation

public enum AppBundlePath {
    /// The top-level .app containing an executable, so a helper resolves to the app it ships in:
    /// ".../Slack.app/Contents/Frameworks/Slack Helper.app/Contents/MacOS/Slack Helper" → ".../Slack.app".
    public static func outermostApp(containing executablePath: String) -> String? {
        let components = executablePath.split(separator: "/")
        guard let index = components.firstIndex(where: { $0.hasSuffix(".app") }) else { return nil }
        return "/" + components[...index].joined(separator: "/")
    }
}
