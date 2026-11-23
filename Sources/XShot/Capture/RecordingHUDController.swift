import AppKit
import SwiftUI

@MainActor
public final class RecordingHUDController {
    private var panel: NSPanel?
    private let state = RecordingHUDState()

    public init() {}

    public func show(
        targetFPS: Int,
        onTogglePause: @escaping () -> Bool,
        onStop: @escaping () -> Void
    ) {
        dismiss()
        state.elapsedSeconds = 0
        state.frameCount = 0
        state.isPaused = false
        state.targetFPS = targetFPS

        let view = RecordingHUDView(
            state: state,
            onTogglePause: { [weak self] in
                let paused = onTogglePause()
                self?.state.isPaused = paused
            },
            onStop: onStop
        )

        let hosting = NSHostingView(rootView: view)
        let size = NSSize(width: 372, height: 46)
        hosting.frame = NSRect(origin: .zero, size: size)

        let screen = NSScreen.main ?? NSScreen.screens.first
        let originX = (screen?.visibleFrame.midX ?? 600) - size.width / 2
        let originY = (screen?.visibleFrame.maxY ?? 800) - size.height - 14

        let p = NSPanel(
            contentRect: NSRect(x: originX, y: originY, width: size.width, height: size.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isReleasedWhenClosed = false
        p.appearance = ThemeLocaleStore.shared.appearanceMode.nsAppearance
        p.level = .floating
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.isMovableByWindowBackground = true
        p.sharingType = .none // Excluded from ScreenCaptureKit!
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = hosting
        p.orderFrontRegardless()
        self.panel = p
    }

    public func update(elapsedSeconds: Double, frameCount: Int) {
        state.elapsedSeconds = elapsedSeconds
        state.frameCount = frameCount
    }

    public func dismiss() {
        guard let p = panel else { return }
        p.orderOut(nil)
        p.contentView = nil
        panel = nil
    }
}

@MainActor
private final class RecordingHUDState: ObservableObject {
    @Published var elapsedSeconds: Double = 0
    @Published var frameCount: Int = 0
    @Published var isPaused: Bool = false
    @Published var targetFPS: Int = 60
}

private struct RecordingHUDView: View {
    @ObservedObject var state: RecordingHUDState
    @ObservedObject private var uiStore = ThemeLocaleStore.shared
    @Environment(\.colorScheme) private var colorScheme
    let onTogglePause: () -> Void
    let onStop: () -> Void
    @State private var pulse = false

    private var resolvedScheme: ColorScheme {
        uiStore.appearanceMode.resolvedColorScheme(environment: colorScheme)
    }

    private var palette: StudioPalette {
        StudioPalette.resolved(mode: uiStore.appearanceMode, environment: colorScheme)
    }

    private var formattedTime: String {
        let total = Int(state.elapsedSeconds)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    var body: some View {
        HStack(spacing: 10) {
            // Drag grip
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(palette.tertiaryText)
                .fixedSize()

            // Pulsing recording dot
            ZStack {
                if !state.isPaused {
                    Circle()
                        .fill(Color.red.opacity(0.35))
                        .frame(width: pulse ? 18 : 10, height: pulse ? 18 : 10)
                        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
                }
                Circle()
                    .fill(state.isPaused ? Color.orange : Color.red)
                    .frame(width: 9, height: 9)
            }
            .frame(width: 18, height: 18)

            // Live clock (strictly single-line, fixed width so pill never jitters)
            Text(formattedTime)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(palette.primaryText)
                .lineLimit(1)
                .fixedSize()

            // FPS pill
            Text("\(state.targetFPS)fps")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(palette.accent)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(palette.accentSoftFill, in: Capsule())

            Spacer(minLength: 6)

            // Pause / Resume
            Button(action: onTogglePause) {
                Image(systemName: state.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(palette.primaryText)
                    .frame(width: 28, height: 28)
                    .background(palette.controlFill, in: Circle())
            }
            .buttonStyle(.plain)
            .help(state.isPaused ? uiStore.t(.hudResumeTooltip) : uiStore.t(.hudPauseTooltip))

            // Stop & Edit CTA — guaranteed single-line layout!
            Button(action: onStop) {
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.white)
                        .frame(width: 8, height: 8)
                    Text(uiStore.t(.hudDone))
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .fixedSize()
                    Text("⌘⇧8")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.78))
                        .lineLimit(1)
                        .fixedSize()
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(
                    LinearGradient(
                        colors: [Color(red: 0.96, green: 0.25, blue: 0.34), Color(red: 0.82, green: 0.14, blue: 0.24)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    in: Capsule()
                )
            }
            .buttonStyle(.plain)
            .fixedSize()
            .help(uiStore.t(.hudStopTooltip))
        }
        .padding(.horizontal, 14)
        .frame(width: 372, height: 46)
        .background(
            Capsule()
                .fill(palette.hudSurface)
                .overlay(Capsule().strokeBorder(palette.hudBorder, lineWidth: 0.9))
        )
        .environment(\.colorScheme, resolvedScheme)
        .preferredColorScheme(uiStore.appearanceMode.swiftUIColorScheme)
        .onAppear { pulse = true }
    }
}
