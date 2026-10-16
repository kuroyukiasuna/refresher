import Foundation
import RefresherCore

/// `Refresher --detect [--once]` prints what meeting detection sees every two seconds, using
/// the app's saved settings. Run it during a real call to check that the call gets picked up.
enum DetectCommand {
    @MainActor
    static func run(once: Bool) {
        setvbuf(stdout, nil, _IOLBF, 0)
        let monitor = AudioActivityMonitor()
        var detector = MeetingDetector(settings: Preferences().meetingDetection)
        if !once { print("Watching microphone, audio and camera use. Press Ctrl-C to stop.\n") }
        while true {
            let snapshot = monitor.snapshot()
            let meeting = detector.evaluate(snapshot.clients, cameraInUse: snapshot.cameraInUse, now: Date())
            let verdict = meeting.map { "IN A MEETING: \($0.title) (\($0.evidence))" } ?? "No meeting detected"
            print("\(Date().formatted(date: .omitted, time: .standard))  \(verdict)")
            for client in snapshot.clients.sorted(by: { $0.name < $1.name }) {
                let uses = [client.usesMicrophone ? "microphone" : nil, client.playsAudio ? "playing audio" : nil]
                    .compactMap { $0 }
                    .joined(separator: ", ")
                print("    \(client.name) [\(client.bundleID)] pid \(client.pid): \(uses)")
            }
            if snapshot.cameraInUse { print("    A camera is on") }
            if once { return }
            Thread.sleep(forTimeInterval: 2)
        }
    }
}
