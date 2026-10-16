import CoreAudio
import CoreMediaIO
import Darwin
import Foundation
import RefresherCore

/// Who is using the microphone or playing audio right now, and whether a camera is on.
struct AudioSnapshot: Sendable {
    var clients: [AudioClient] = []
    var cameraInUse = false
}

/// Polls Core Audio's per-process state (macOS 14+) and CoreMediaIO. Neither needs any
/// permission: they say which apps have the mic or camera open, never what they hear or see.
final class AudioActivityMonitor: @unchecked Sendable {
    private let queue = DispatchQueue(label: "Refresher.AudioActivityMonitor", qos: .utility)
    private let owners = ProcessOwners()
    private var timer: DispatchSourceTimer?

    /// Delivers a fresh snapshot on the main queue every `interval` seconds.
    func start(every interval: TimeInterval = 2, onUpdate: @escaping @MainActor @Sendable (AudioSnapshot) -> Void) {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(250))
        timer.setEventHandler { [weak self] in
            guard let snapshot = self?.snapshot() else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { onUpdate(snapshot) }
            }
        }
        timer.resume()
        self.timer = timer
    }

    /// Reads the current state. Call it from one thread at a time; `start` uses its own queue.
    func snapshot() -> AudioSnapshot {
        let ownPID = getpid()
        var clients: [AudioClient] = []
        var live = Set<pid_t>()
        for object in CoreAudioProcess.all() {
            guard let pid = CoreAudioProcess.pid(object), pid != ownPID else { continue }
            live.insert(pid)
            let usesMicrophone = CoreAudioProcess.flag(object, kAudioProcessPropertyIsRunningInput)
            let playsAudio = CoreAudioProcess.flag(object, kAudioProcessPropertyIsRunningOutput)
            guard usesMicrophone || playsAudio else { continue }
            let owner = owners.owner(of: pid) { CoreAudioProcess.bundleID(object) }
            clients.append(AudioClient(
                pid: pid, bundleID: owner.bundleID, name: owner.name, isApp: owner.isApp,
                usesMicrophone: usesMicrophone, playsAudio: playsAudio))
        }
        owners.forget(allBut: live)
        return AudioSnapshot(clients: clients, cameraInUse: Camera.isAnyInUse())
    }
}

/// Works out which app a process belongs to, so a call running in a helper process (Slack Helper,
/// Teams' WebKit and XPC services, Chrome's audio service) counts as that app.
private final class ProcessOwners {
    struct Owner {
        var bundleID: String
        var name: String
        var isApp: Bool
    }

    private var cache: [pid_t: Owner] = [:]

    func owner(of pid: pid_t, coreAudioBundleID: () -> String?) -> Owner {
        if let owner = cache[pid] { return owner }
        let owner = resolve(pid, coreAudioBundleID: coreAudioBundleID)
        cache[pid] = owner
        return owner
    }

    func forget(allBut live: Set<pid_t>) {
        cache = cache.filter { live.contains($0.key) }
    }

    private func resolve(_ pid: pid_t, coreAudioBundleID: () -> String?) -> Owner {
        // macOS tracks a "responsible" process for helpers and XPC services: the app that started
        // them, and the one TCC asks about mic access. Try it first, then the process itself.
        var candidates = [pid]
        if let responsible = Self.responsibilityFunction?(pid), responsible > 0, responsible != pid {
            candidates.insert(responsible, at: 0)
        }
        for candidate in candidates {
            guard let path = Self.executablePath(of: candidate),
                  let appPath = AppBundlePath.outermostApp(containing: path),
                  let bundleID = Bundle(path: appPath)?.bundleIdentifier
            else { continue }
            let name = URL(fileURLWithPath: appPath).deletingPathExtension().lastPathComponent
            return Owner(bundleID: bundleID, name: name, isApp: true)
        }
        let name = Self.executablePath(of: pid).map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Process \(pid)"
        return Owner(bundleID: coreAudioBundleID() ?? name, name: name, isApp: false)
    }

    private static func executablePath(of pid: pid_t) -> String? {
        var buffer = [UInt8](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        return length > 0 ? String(decoding: buffer.prefix(Int(length)), as: UTF8.self) : nil
    }

    private typealias ResponsibilityFunction = @convention(c) (pid_t) -> pid_t

    /// Private but long-standing libsystem call; Chromium and Firefox use it for the same job.
    /// Looked up at runtime: if it ever goes away, attribution falls back to executable paths,
    /// which still covers helpers that live inside their app's bundle.
    private static let responsibilityFunction: ResponsibilityFunction? = {
        let defaultHandle = UnsafeMutableRawPointer(bitPattern: -2)  // RTLD_DEFAULT
        guard let symbol = dlsym(defaultHandle, "responsibility_get_pid_responsible_for_pid") else { return nil }
        return unsafeBitCast(symbol, to: ResponsibilityFunction.self)
    }()
}

/// Core Audio keeps one "process object" per process that has talked to it.
private enum CoreAudioProcess {
    static func all() -> [AudioObjectID] {
        var address = Self.address(kAudioHardwarePropertyProcessObjectList)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &objects) == noErr else { return [] }
        return Array(objects.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }

    static func pid(_ object: AudioObjectID) -> pid_t? {
        read(object, kAudioProcessPropertyPID, as: pid_t.self)
    }

    static func flag(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> Bool {
        (read(object, selector, as: UInt32.self) ?? 0) != 0
    }

    static func bundleID(_ object: AudioObjectID) -> String? {
        var address = Self.address(kAudioProcessPropertyBundleID)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr,
              let bundleID = value.map({ $0.takeRetainedValue() as String }), !bundleID.isEmpty
        else { return nil }
        return bundleID
    }

    private static func read<T: FixedWidthInteger>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, as: T.Type) -> T? {
        var address = Self.address(selector)
        var value: T = 0
        var size = UInt32(MemoryLayout<T>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }
}

private enum Camera {
    static func isAnyInUse() -> Bool {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return false }
        var devices = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &address, 0, nil, size, &used, &devices) == noErr else { return false }
        return devices.prefix(Int(used) / MemoryLayout<CMIOObjectID>.size).contains(where: isRunning)
    }

    private static func isRunning(_ device: CMIOObjectID) -> Bool {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard))
        var running: UInt32 = 0
        var used: UInt32 = 0
        let status = CMIOObjectGetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &used, &running)
        return status == noErr && running != 0
    }
}
