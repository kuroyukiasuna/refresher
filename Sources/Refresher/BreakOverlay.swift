import AppKit
import RefresherCore
import SwiftUI

/// The full-screen, blurred break screen: one window per display, above everything,
/// including full-screen apps and the menu bar.
@MainActor
final class BreakOverlay {
    var onSkip: (() -> Void)?
    var onPostpone: (() -> Void)?

    private let model = BreakViewModel()
    private var windows: [OverlayWindow] = []
    private var previousApp: NSRunningApplication?
    private var screenObserver: NSObjectProtocol?

    private var isVisible: Bool { !windows.isEmpty }

    /// Shows the break screen, or keeps its countdown in sync if it's already up.
    func show(kind: BreakKind, remaining: TimeInterval, total: TimeInterval, postponeTitle: String) {
        let endDate = Date().addingTimeInterval(remaining)
        if abs(model.endDate.timeIntervalSince(endDate)) > 0.5 { model.endDate = endDate }
        guard !isVisible else { return }

        model.kind = kind
        model.total = total
        model.tip = BreakTips.random(for: kind)
        model.postponeTitle = postponeTitle
        let frontmost = NSWorkspace.shared.frontmostApplication
        previousApp = frontmost == NSRunningApplication.current ? nil : frontmost
        openWindows()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isVisible else { return }
                self.windows.forEach { $0.close() }
                self.openWindows()
            }
        }
    }

    func hide() {
        guard isVisible else { return }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        let closing = windows
        windows = []
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.4
            closing.forEach { $0.animator().alphaValue = 0 }
        }, completionHandler: {
            MainActor.assumeIsolated { closing.forEach { $0.close() } }
        })
        returnFocus()
    }

    private func openWindows() {
        let content = BreakView(
            model: model,
            onSkip: { [weak self] in self?.onSkip?() },
            onPostpone: { [weak self] in self?.onPostpone?() })
        windows = NSScreen.screens.map { OverlayWindow(screen: $0, content: content) }
        windows.forEach {
            $0.onEscape = { [weak self] in self?.onSkip?() }
            $0.alphaValue = 0
            $0.orderFrontRegardless()
        }
        // Key focus makes Esc work and keeps typing out of the hidden app. A non-activating
        // panel can take it without activating the app. macOS usually refuses activate() from
        // a timer; when a break starts from the menu it goes through, and returnFocus() undoes it.
        NSApp.activate()
        let mouse = NSEvent.mouseLocation
        (windows.first { NSMouseInRect(mouse, $0.frame, false) } ?? windows.first)?.makeKey()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.6
            windows.forEach { $0.animator().alphaValue = 1 }
        }
    }

    private func returnFocus() {
        guard let app = previousApp, !app.isTerminated, NSApp.isActive else { return }
        previousApp = nil
        NSApp.yieldActivation(to: app)
        app.activate(from: .current, options: [])
    }
}

/// Borderless panel covering one display.
private final class OverlayWindow: NSPanel {
    var onEscape: (() -> Void)?

    init(screen: NSScreen, content: some View) {
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false
        animationBehavior = .none

        let blur = NSVisualEffectView()
        blur.material = .fullScreenUI
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.appearance = NSAppearance(named: .darkAqua)
        let host = FirstMouseHostingView(rootView: content)
        host.frame = blur.bounds
        host.autoresizingMask = [.width, .height]
        blur.addSubview(host)
        contentView = blur
    }

    override var canBecomeKey: Bool { true }

    /// Typing that reaches the break screen unhandled would otherwise play the system alert
    /// sound with every key. Esc gets here if the Skip button's shortcut didn't claim it.
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onEscape?() }  // 53 is Esc.
    }

    // ⌘W and ⌘M would beep too, since the window has no close or minimize button.
    override func performClose(_ sender: Any?) {}
    override func performMiniaturize(_ sender: Any?) {}
}

@MainActor
private final class BreakViewModel: ObservableObject {
    @Published var kind: BreakKind = .short
    @Published var endDate = Date()
    @Published var total: TimeInterval = 20
    @Published var tip = ""
    @Published var postponeTitle = ""
}

private struct BreakView: View {
    @ObservedObject var model: BreakViewModel
    let onSkip: () -> Void
    let onPostpone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Image(systemName: model.kind == .long ? "figure.walk" : "eye")
                .font(.system(size: 52, weight: .light))
                .padding(.bottom, 24)
            Text(model.kind == .long ? "Time for a longer break" : "Look away for a moment")
                .font(.system(size: 46, weight: .semibold, design: .rounded))
            Text(model.tip)
                .font(.system(size: 21))
                .foregroundStyle(.white.opacity(0.75))
                .padding(.top, 12)
            CountdownRing(endDate: model.endDate, total: model.total)
                .frame(width: 150, height: 150)
                .padding(.vertical, 44)
            HStack(spacing: 14) {
                Button(model.postponeTitle, action: onPostpone)
                Button("Skip Break", action: onSkip)
                    .keyboardShortcut(.cancelAction)
            }
            .buttonStyle(OverlayButtonStyle())
            Text("Press Esc to skip")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.45))
                .padding(.top, 16)
            Spacer()
        }
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [Color(red: 0.03, green: 0.16, blue: 0.2).opacity(0.55), .black.opacity(0.6)],
                startPoint: .top, endPoint: .bottom))
    }
}

/// Ring that drains smoothly as the break counts down.
private struct CountdownRing: View {
    let endDate: Date
    let total: TimeInterval

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
            let remaining = max(0, endDate.timeIntervalSince(context.date))
            ZStack {
                Circle().stroke(.white.opacity(0.15), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: total > 0 ? remaining / total : 0)
                    .stroke(.white, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(Format.clock(remaining))
                    .font(.system(size: 36, weight: .medium, design: .rounded))
                    .monospacedDigit()
            }
        }
    }
}

private struct OverlayButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .medium))
            .padding(.horizontal, 22)
            .padding(.vertical, 10)
            .background(Capsule().fill(.white.opacity(configuration.isPressed ? 0.3 : 0.15)))
            .overlay(Capsule().strokeBorder(.white.opacity(0.25)))
            .contentShape(Capsule())
    }
}

enum BreakTips {
    static let short = [
        "Look at something at least 20 feet away.",
        "Let your eyes relax, and blink slowly a few times.",
        "Drop your shoulders and unclench your jaw.",
        "Take a slow, deep breath.",
        "Look out of a window if you can.",
        "Roll your neck gently from side to side.",
    ]

    static let long = [
        "Stand up, stretch, and walk around for a few minutes.",
        "Refill your water and get some fresh air.",
        "Step away from the screen. Your eyes will thank you.",
        "Stretch your wrists, neck and back.",
    ]

    static func random(for kind: BreakKind) -> String {
        (kind == .long ? long : short).randomElement() ?? ""
    }
}
