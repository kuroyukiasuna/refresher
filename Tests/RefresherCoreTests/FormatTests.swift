import Testing
@testable import RefresherCore

@Suite struct FormatTests {
    @Test func durations() {
        #expect(Format.duration(20) == "20 sec")
        #expect(Format.duration(300) == "5 min")
        #expect(Format.duration(90) == "1 min 30 sec")
        #expect(Format.duration(4500) == "1 hr 15 min")
        #expect(Format.duration(0) == "0 sec")
    }

    @Test func clocks() {
        #expect(Format.clock(20) == "0:20")
        #expect(Format.clock(19.2) == "0:20")
        #expect(Format.clock(245) == "4:05")
        #expect(Format.clock(3723) == "1:02:03")
        #expect(Format.clock(-3) == "0:00")
    }

    @Test func menuBarCountdown() {
        #expect(Format.menuBar(20 * 60) == "20m")
        #expect(Format.menuBar(61) == "2m")
        #expect(Format.menuBar(60) == "1:00")
        #expect(Format.menuBar(42) == "0:42")
    }

    @Test func approximateTimeLeft() {
        #expect(Format.approximate(17 * 60 + 5) == "18 min")
        #expect(Format.approximate(89 * 60 + 30) == "1 hr 30 min")
        #expect(Format.approximate(44.5) == "45 sec")
    }
}

@Suite struct AppBundlePathTests {
    @Test func helpersResolveToTheirApp() {
        #expect(AppBundlePath.outermostApp(containing: "/Applications/Slack.app/Contents/Frameworks/Slack Helper.app/Contents/MacOS/Slack Helper") == "/Applications/Slack.app")
        #expect(AppBundlePath.outermostApp(containing: "/Applications/Microsoft Teams.app/Contents/XPCServices/vcxpc.xpc/Contents/MacOS/vcxpc") == "/Applications/Microsoft Teams.app")
        #expect(AppBundlePath.outermostApp(containing: "/Applications/zoom.us.app/Contents/MacOS/zoom.us") == "/Applications/zoom.us.app")
    }

    @Test func nonAppExecutablesHaveNoApp() {
        #expect(AppBundlePath.outermostApp(containing: "/usr/libexec/avconferenced") == nil)
        #expect(AppBundlePath.outermostApp(containing: "/usr/bin/afplay") == nil)
    }
}
