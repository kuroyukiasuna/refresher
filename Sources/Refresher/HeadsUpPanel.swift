import AppKit
import RefresherCore
import SwiftUI

/// Small floating notice near the top of the screen just before a break. It never takes
/// focus, so whatever you're typing keeps going to the app you're in.
@MainActor
final class HeadsUpPanel {
    var onStartNow: (() -> Void)?
    var onPostpone: (() -> Void)?
    var onSkip: (() -> Void)?

    private let model = HeadsUpModel()
    private var panel: NSPanel?

    func show(timeLeft: TimeInterval, kind: BreakKind) {
        if model.timeLeft != timeLeft { model.timeLeft = timeLeft }
        if model.kind != kind { model.kind = kind }
        guard panel == nil else { return }

        let panel = makePanel()
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main {
            let visible = screen.visibleFrame
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height - 12))
        }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            panel.animator().alphaValue = 1
        }
        self.panel = panel
    }

    func hide() {
        guard let panel else { return }
        self.panel = nil
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            panel.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated { panel.close() }
        })
    }

    private func makePanel() -> NSPanel {
        let host = FirstMouseHostingView(rootView: HeadsUpView(
            model: model,
            onStartNow: { [weak self] in self?.onStartNow?() },
            onPostpone: { [weak self] in self?.onPostpone?() },
            onSkip: { [weak self] in self?.onSkip?() }))
        let size = host.fittingSize

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true

        let blur = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        blur.material = .popover
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.maskImage = .roundedRectMask(radius: 16)
        host.frame = blur.bounds
        host.autoresizingMask = [.width, .height]
        blur.addSubview(host)
        panel.contentView = blur
        return panel
    }
}

@MainActor
private final class HeadsUpModel: ObservableObject {
    @Published var timeLeft: TimeInterval = 0
    @Published var kind: BreakKind = .short
}

private struct HeadsUpView: View {
    @ObservedObject var model: HeadsUpModel
    let onStartNow: () -> Void
    let onPostpone: () -> Void
    let onSkip: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "eye")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(model.kind == .long ? "Long break" : "Break") in \(Format.clock(model.timeLeft))")
                    .font(.headline)
                    .monospacedDigit()
                Text("Time to rest your eyes soon.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 16)
            Button("Skip", action: onSkip)
                .buttonStyle(PillButtonStyle())
            Button("Postpone", action: onPostpone)
                .buttonStyle(PillButtonStyle())
            Button("Start Now", action: onStartNow)
                .buttonStyle(PillButtonStyle(prominent: true))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .fixedSize()
    }
}

/// Explicit colors, since the panel is never the key window and standard prominent
/// buttons would draw in their inactive gray.
private struct PillButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .background(Capsule().fill(prominent ? Color.accentColor : Color.primary.opacity(0.1)))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule())
    }
}
