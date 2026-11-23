import AppKit
import CoreGraphics
import SwiftUI

/// Live click-through border + floating control & preview HUD for Scrolling Long-Screenshot capture.
/// Users can smoothly scroll manually inside ANY app (no extra permissions needed) OR toggle optional
/// gentle auto-scroll (uses CGEvent scroll wheel when Accessibility is authorized).
@MainActor
public final class ScrollingCaptureController {
    private var borderWindow: NSWindow?
    private var hudWindow: NSPanel?
    private var keyMonitor: Any?
    private var pollTimer: Timer?
    private var autoScrollTimer: Timer?

    private var activeTarget: SelectedCaptureTarget?
    private var stitcher: ScrollingStitcherEngine?
    private var isCapturingFrame: Bool = false
    private var hudModel = ScrollingHUDModel()

    private var onComplete: ((CGImage) -> Void)?
    private var onCancel: (() -> Void)?

    public var isActive: Bool { activeTarget != nil }

    public init() {}

    public func begin(
        target: SelectedCaptureTarget,
        initialFrame: CGImage,
        onComplete: @escaping (CGImage) -> Void,
        onCancel: @escaping () -> Void
    ) {
        dismiss()

        self.activeTarget = target
        let engine = ScrollingStitcherEngine(initialFrame: initialFrame)
        self.stitcher = engine
        self.onComplete = onComplete
        self.onCancel = onCancel

        hudModel = ScrollingHUDModel()
        hudModel.update(from: engine)

        showClickThroughBorder(for: target)
        showFloatingHUD(near: target)
        installKeyMonitor()
        startPolling()
    }

    public func finish() {
        guard let finalImage = stitcher?.stitchedImage else {
            cancel()
            return
        }
        let callback = onComplete
        dismiss()
        callback?(finalImage)
    }

    public func cancel() {
        let callback = onCancel
        dismiss()
        callback?()
    }

    public func dismiss() {
        pollTimer?.invalidate()
        pollTimer = nil
        autoScrollTimer?.invalidate()
        autoScrollTimer = nil
        if let km = keyMonitor {
            NSEvent.removeMonitor(km)
            keyMonitor = nil
        }
        borderWindow?.orderOut(nil)
        borderWindow = nil
        hudWindow?.orderOut(nil)
        hudWindow = nil
        activeTarget = nil
        stitcher = nil
        isCapturingFrame = false
        onComplete = nil
        onCancel = nil
    }

    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.20, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.captureAndStitchTick(manual: false)
            }
        }
    }

    private func toggleAutoScroll() {
        hudModel.autoScrolling.toggle()
        if hudModel.autoScrolling {
            startAutoScrollTimer()
        } else {
            autoScrollTimer?.invalidate()
            autoScrollTimer = nil
        }
    }

    private func startAutoScrollTimer() {
        autoScrollTimer?.invalidate()
        guard let target = activeTarget else { return }
        let quartzRect = target.quartzRect
        let scrollCenter = CGPoint(x: quartzRect.midX, y: quartzRect.midY)

        // Move pointer gently into the target region once so scroll events land inside the scrollable pane
        CGWarpMouseCursorPosition(scrollCenter)

        autoScrollTimer = Timer.scheduledTimer(withTimeInterval: 0.11, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.hudModel.autoScrolling, self.isActive else { return }
                if let ev = CGEvent(
                    scrollWheelEvent2Source: nil,
                    units: .pixel,
                    wheelCount: 1,
                    wheel1: -54,
                    wheel2: 0,
                    wheel3: 0
                ) {
                    ev.location = scrollCenter
                    ev.post(tap: .cghidEventTap)
                }
            }
        }
    }

    private func captureAndStitchTick(manual: Bool) async {
        guard !isCapturingFrame, let target = activeTarget, let engine = stitcher else { return }
        isCapturingFrame = true
        defer { isCapturingFrame = false }

        do {
            let frame = try await ScreenshotEngine.capture(target: target)
            guard self.stitcher === engine else { return }
            let outcome: ScrollStitchOutcome = await Task.detached(priority: .userInitiated) {
                manual ? engine.appendManualFrame(frame) : engine.stitchNextFrame(frame)
            }.value

            switch outcome {
            case .stitched:
                hudModel.update(from: engine)
                if manual {
                    NSSound(named: NSSound.Name("Pop"))?.play()
                }
            case .limitReached:
                hudModel.limitReached = true
                hudModel.autoScrolling = false
                autoScrollTimer?.invalidate()
                autoScrollTimer = nil
                NSSound.beep()
            case .unchanged:
                if manual {
                    NSSound.beep()
                }
            }
        } catch {
            // Keep session alive gracefully if a transient frame capture drops
        }
    }

    private func undoLast() {
        guard let engine = stitcher, engine.undoLastStitch() else { return }
        hudModel.limitReached = false
        hudModel.update(from: engine)
        NSSound(named: NSSound.Name("Tink"))?.play()
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Esc
                Task { @MainActor [weak self] in self?.cancel() }
            } else if event.keyCode == 36 { // Return
                Task { @MainActor [weak self] in self?.finish() }
            }
        }
    }

    private func showClickThroughBorder(for target: SelectedCaptureTarget) {
        let appKitRect = CoordinateConverter.quartzToAppKit(target.quartzRect)
        let pad: CGFloat = 4
        let frame = appKitRect.insetBy(dx: -pad, dy: -pad)

        let win = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        win.isReleasedWhenClosed = false
        win.backgroundColor = .clear
        win.isOpaque = false
        win.hasShadow = false
        win.ignoresMouseEvents = true
        win.sharingType = .none
        win.level = .statusBar
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let borderView = NSHostingView(rootView: ScrollingRegionFrameView())
        borderView.frame = NSRect(origin: .zero, size: frame.size)
        win.contentView = borderView
        win.orderFrontRegardless()
        self.borderWindow = win
    }

    private func showFloatingHUD(near target: SelectedCaptureTarget) {
        let appKitRect = CoordinateConverter.quartzToAppKit(target.quartzRect)
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(appKitRect) }) ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let hudW: CGFloat = 248
        let hudH: CGFloat = 336

        // Prefer placing cleanly to the right of the capture region, falling back to left, then bottom-right of screen
        let originX: CGFloat
        if appKitRect.maxX + 16 + hudW <= visible.maxX {
            originX = appKitRect.maxX + 16
        } else if appKitRect.minX - 16 - hudW >= visible.minX {
            originX = appKitRect.minX - 16 - hudW
        } else {
            originX = visible.maxX - hudW - 20
        }
        let originY = min(max(appKitRect.midY - hudH / 2, visible.minY + 20), visible.maxY - hudH - 20)

        let panel = NSPanel(
            contentRect: NSRect(x: originX, y: originY, width: hudW, height: hudH),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.sharingType = .none
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let root = ScrollingCaptureHUDView(
            model: hudModel,
            onToggleAutoScroll: { [weak self] in self?.toggleAutoScroll() },
            onManualAppend: { [weak self] in
                Task { @MainActor [weak self] in
                    await self?.captureAndStitchTick(manual: true)
                }
            },
            onUndo: { [weak self] in self?.undoLast() },
            onCancel: { [weak self] in self?.cancel() },
            onFinish: { [weak self] in self?.finish() }
        )
        panel.contentView = NSHostingView(rootView: root)
        panel.orderFrontRegardless()
        self.hudWindow = panel
    }
}

@MainActor
private final class ScrollingHUDModel: ObservableObject {
    @Published var previewImage: CGImage?
    @Published var pixelWidth: Int = 0
    @Published var pixelHeight: Int = 0
    @Published var frameCount: Int = 1
    @Published var canUndo: Bool = false
    @Published var autoScrolling: Bool = false
    @Published var limitReached: Bool = false

    func update(from engine: ScrollingStitcherEngine) {
        self.previewImage = engine.stitchedImage
        self.pixelWidth = engine.stitchedImage.width
        self.pixelHeight = engine.stitchedImage.height
        self.frameCount = engine.frameCount
        self.canUndo = engine.canUndo
    }
}

private struct ScrollingRegionFrameView: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .strokeBorder(Color(red: 0.06, green: 0.72, blue: 0.98), style: StrokeStyle(lineWidth: 2.5, dash: [8, 5]))
            .padding(1.5)
    }
}

private struct ScrollingCaptureHUDView: View {
    @ObservedObject var model: ScrollingHUDModel
    @ObservedObject private var uiStore = ThemeLocaleStore.shared
    @Environment(\.colorScheme) private var colorScheme

    let onToggleAutoScroll: () -> Void
    let onManualAppend: () -> Void
    let onUndo: () -> Void
    let onCancel: () -> Void
    let onFinish: () -> Void

    private var palette: StudioPalette {
        StudioPalette.resolved(mode: uiStore.appearanceMode, environment: colorScheme)
    }

    var body: some View {
        let cyan = Color(red: 0.06, green: 0.68, blue: 0.94)
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 7) {
                Image(systemName: "arrow.up.and.down.text.horizontal")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(cyan)
                Text(uiStore.t(.scrollHudTitle))
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(palette.primaryText)
                    .lineLimit(1)
                Spacer()
                Text(uiStore.format(.scrollFramesBadgeFormat, model.frameCount))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(cyan)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(cyan.opacity(0.16), in: Capsule())
            }

            Text(model.limitReached ? uiStore.t(.scrollLimitReached) : uiStore.t(.scrollHudHint))
                .font(.system(size: 10))
                .foregroundStyle(model.limitReached ? .orange : palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            // Live Growing Long-Screenshot Strip Preview
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(palette.trackFill)
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.controlBorder, lineWidth: 0.8))

                if let cg = model.previewImage {
                    ScrollViewReader { proxy in
                        ScrollView(.vertical, showsIndicators: true) {
                            Image(decorative: cg, scale: 1.0, orientation: .up)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: .infinity)
                                .id("bottom")
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .padding(3)
                        .onChange(of: model.pixelHeight) { _, _ in
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }

                Text("\(model.pixelWidth) × \(model.pixelHeight)")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(Color.black.opacity(0.76), in: Capsule())
                    .padding(6)
            }
            .frame(height: 150)

            // Secondary Tools: Auto-Scroll Toggle + Manual Append + Undo
            HStack(spacing: 5) {
                Button(action: onToggleAutoScroll) {
                    HStack(spacing: 4) {
                        Image(systemName: model.autoScrolling ? "pause.fill" : "arrow.down.circle.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text(model.autoScrolling ? uiStore.t(.scrollAutoStopBtn) : uiStore.t(.scrollAutoStartBtn))
                            .font(.system(size: 10, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(model.autoScrolling ? .white : cyan)
                    .frame(maxWidth: .infinity)
                    .frame(height: 27)
                }
                .buttonStyle(TactilePillButtonStyle(
                    background: model.autoScrolling ? cyan : cyan.opacity(0.14),
                    hoverBackground: model.autoScrolling ? cyan.opacity(0.86) : cyan.opacity(0.24),
                    borderColor: cyan.opacity(0.55),
                    cornerRadius: 7
                ))

                Button(action: onManualAppend) {
                    Image(systemName: "plus.rectangle.on.rectangle")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.primaryText)
                        .frame(width: 28, height: 27)
                }
                .buttonStyle(TactilePillButtonStyle(
                    background: palette.controlFill,
                    hoverBackground: palette.controlHoverFill,
                    borderColor: palette.controlBorder,
                    cornerRadius: 7
                ))
                .help(uiStore.t(.scrollManualAppendTooltip))

                Button(action: onUndo) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(model.canUndo ? palette.primaryText : palette.tertiaryText)
                        .frame(width: 28, height: 27)
                }
                .buttonStyle(TactilePillButtonStyle(
                    background: palette.controlFill,
                    hoverBackground: model.canUndo ? palette.controlHoverFill : palette.controlFill,
                    borderColor: palette.controlBorder,
                    cornerRadius: 7
                ))
                .disabled(!model.canUndo)
                .help(uiStore.t(.undo))
            }

            // Primary Finish + Cancel Bar
            HStack(spacing: 6) {
                Button(action: onCancel) {
                    Text(uiStore.t(.cancelAction))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.secondaryText)
                        .frame(width: 64, height: 31)
                }
                .buttonStyle(TactilePillButtonStyle(
                    background: palette.controlFill,
                    hoverBackground: palette.controlHoverFill,
                    borderColor: palette.controlBorder,
                    cornerRadius: 8
                ))

                Button(action: onFinish) {
                    Label(uiStore.t(.scrollFinishBtn), systemImage: "checkmark")
                        .font(.system(size: 11.5, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 31)
                }
                .buttonStyle(TactilePrimaryButtonStyle(cornerRadius: 8))
            }
        }
        .padding(12)
        .frame(width: 248)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(palette.hudSurface)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(palette.hudBorder, lineWidth: 1.0))
        )
        .environment(\.colorScheme, uiStore.appearanceMode.resolvedColorScheme(environment: colorScheme))
    }
}
