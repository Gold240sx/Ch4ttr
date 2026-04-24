import AppKit
import SwiftUI

@MainActor
final class OverlayController {
    private var window: NSWindow?

    func show() {
        if window != nil { return }

        let hosting = NSHostingView(rootView: OverlayView(state: .standby))
        hosting.frame = NSRect(x: 0, y: 0, width: 50, height: 50)

        let panel = NSPanel(
            contentRect: hosting.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = hosting

        positionTopRight(panel)

        panel.orderFrontRegardless()
        window = panel
    }

    func set(state: RecordingState) {
        guard let hosting = window?.contentView as? NSHostingView<OverlayView> else { return }
        hosting.rootView = OverlayView(state: state)
    }

    private func positionTopRight(_ w: NSWindow) {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let x = frame.maxX - 60
        let y = frame.maxY - 60
        w.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

private struct OverlayView: View {
    let state: RecordingState

    var body: some View {
        ZStack {
            Circle()
                .fill(background)
                .overlay(
                    Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 6)
                .overlay(
                    Image(systemName: "mic.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                )
        }
        .frame(width: 40, height: 40)
        .animation(.easeInOut(duration: 0.20), value: state)
        .overlay(pulseOverlay)
    }

    private var background: Color {
        switch state {
        case .standby:
            return Color.black.opacity(0.78)
        case .recording:
            return Color.red.opacity(0.88)
        case .analyzing:
            return Color.orange.opacity(0.88)
        }
    }

    @ViewBuilder
    private var pulseOverlay: some View {
        if state == .recording || state == .analyzing {
            Circle()
                .stroke(Color.white.opacity(0.35), lineWidth: 1)
                .scaleEffect(1.18)
                .opacity(0.0)
                .animation(.easeInOut(duration: state == .recording ? 1.2 : 1.5).repeatForever(autoreverses: true), value: state)
        }
    }
}

