import AppKit
import CoreGraphics
import SwiftUI

public struct OnScreenWindowCandidate: Sendable {
    public let windowID: CGWindowID
    public let title: String
    public let appName: String
    public let layer: Int
    public let quartzFrame: CGRect
    public let appKitFrame: CGRect
}

/// Multi-display non-activating crosshair, frozen-screen popup capture, resizable recording box,
/// & window-picker overlay. Never steals active-app focus so transient popups/menus stay visible!
@MainActor
public final class SelectionOverlayController {
    private var windows: [OverlayPanel] = []
    private var overlayViews: [SelectionOverlayView] = []
    private var localKeyMonitor: Any?
    private var globalKeyMonitor: Any?
    private var onComplete: ((SelectedCaptureTarget) -> Void)?
    private var onCancel: (() -> Void)?
    private var mode: CaptureMode = .area
    private var intent: CaptureIntent = .screenshot
    private var candidates: [OnScreenWindowCandidate] = []

    public init() {}

    public func beginSelection(
        mode: CaptureMode,
        intent: CaptureIntent,
        frozenDisplays: [CGDirectDisplayID: CGImage] = [:],
        preEnumeratedWindows: [OnScreenWindowCandidate]? = nil,
        onComplete: @escaping (SelectedCaptureTarget) -> Void,
        onCancel: @escaping () -> Void
    ) {
        dismiss()

        self.mode = mode
        self.intent = intent
        self.onComplete = onComplete
        self.onCancel = onCancel
        if mode == .window {
            self.candidates = preEnumeratedWindows ?? Self.enumerateVisibleWindows()
        } else {
            self.candidates = []
        }

        // Do NOT call NSApp.activate(ignoringOtherApps: true) — calling it raises XShot's other windows
        // and swaps the macOS Menu Bar, causing a visible jump/flash! Because OverlayPanel has
        // `.nonactivatingPanel` + `canBecomeKey = true`, `makeKeyAndOrderFront(nil)` gives full native
        // mouseMoved / cursor / Esc handling while keeping other apps and XShot windows completely still!
        for screen in NSScreen.screens {
            let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? CGMainDisplayID()
            let frozenCG = frozenDisplays[displayID]

            let panel = OverlayPanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isReleasedWhenClosed = false
            panel.level = .screenSaver
            panel.animationBehavior = .none // CRITICAL: prevents macOS panel zoom/bounce ("动一下")!
            panel.backgroundColor = .clear
            panel.isOpaque = (frozenCG != nil)
            panel.hasShadow = false
            panel.ignoresMouseEvents = false
            panel.acceptsMouseMovedEvents = true
            panel.sharingType = .none
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

            let container = NSView(frame: CGRect(origin: .zero, size: screen.frame.size))
            container.wantsLayer = true
            container.layer?.backgroundColor = NSColor.clear.cgColor

            // Static GPU-backed frozen screen layer (uploaded ONCE -> 0ms redraw, 0px drift, 120Hz smooth!)
            if let frozenCG {
                let backdrop = NSView(frame: container.bounds)
                backdrop.wantsLayer = true
                backdrop.autoresizingMask = [.width, .height]
                if let bLayer = backdrop.layer {
                    CATransaction.begin()
                    CATransaction.setDisableActions(true)
                    bLayer.contents = frozenCG
                    bLayer.contentsScale = screen.backingScaleFactor
                    bLayer.contentsGravity = .resize
                    bLayer.masksToBounds = true
                    CATransaction.commit()
                }
                container.addSubview(backdrop)
            }

            let overlayView = SelectionOverlayView(
                screen: screen,
                mode: mode,
                intent: intent,
                hasFrozenBackdrop: (frozenCG != nil),
                candidates: candidates,
                onSelectTarget: { [weak self] target in
                    guard let self else { return }
                    let completion = self.onComplete
                    self.dismiss()
                    let delay: TimeInterval = frozenCG != nil ? 0.01 : 0.06
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        completion?(target)
                    }
                },
                onCancel: { [weak self] in
                    guard let self else { return }
                    let cancel = self.onCancel
                    self.dismiss()
                    cancel?()
                }
            )
            overlayView.autoresizingMask = [.width, .height]
            container.addSubview(overlayView)

            panel.contentView = container
            panel.setFrame(screen.frame, display: true)
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(overlayView)
            windows.append(panel)
            overlayViews.append(overlayView)
        }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if self?.handleKeyEvent(event) == true {
                return nil
            }
            return event
        }
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            Task { @MainActor [weak self] in
                _ = self?.handleKeyEvent(event)
            }
        }
    }

    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        if event.keyCode == 53 { // Escape
            let cancel = self.onCancel
            self.dismiss()
            cancel?()
            return true
        }
        if event.keyCode == 36 && intent == .recording { // Enter confirms active recording selection
            for view in overlayViews {
                if view.confirmRecordingSelectionIfReady() {
                    return true
                }
            }
        }
        return false
    }

    public func dismiss() {
        if let lm = localKeyMonitor {
            NSEvent.removeMonitor(lm)
            localKeyMonitor = nil
        }
        if let gm = globalKeyMonitor {
            NSEvent.removeMonitor(gm)
            globalKeyMonitor = nil
        }
        let closing = windows
        windows.removeAll()
        overlayViews.removeAll()
        for w in closing {
            w.orderOut(nil)
        }
        // Defer view teardown to next runloop turn so in-flight mouseDown/keyDown unwinds cleanly
        if !closing.isEmpty {
            DispatchQueue.main.async {
                for w in closing {
                    w.contentView = nil
                }
            }
        }
        NSCursor.arrow.set()
    }

    public static func enumerateVisibleWindows() -> [OnScreenWindowCandidate] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let excludedInternalIDs = CaptureWindowFilter.internalOverlayWindowIDs()
        var statusBarWindowIDs = Set<CGWindowID>()
        var ownWindowTitles: [CGWindowID: String] = [:]
        for win in NSApp?.windows ?? [] {
            guard let wid = CGWindowID(exactly: win.windowNumber), wid > 0 else { continue }
            if String(describing: type(of: win)).contains("StatusBar") {
                statusBarWindowIDs.insert(wid)
            }
            ownWindowTitles[wid] = win.title
        }
        let primaryH = CoordinateConverter.primaryScreenHeight()
        let screenSizes = NSScreen.screens.map(\.frame.size)
        let excludedBundleIDs: Set<String> = [
            "com.apple.dock",
            "com.apple.WindowManager",
            "com.apple.systemuiserver",
            "com.apple.wallpaper.agent",
            "com.apple.loginwindow",
            "com.apple.notificationcenterui"
        ]
        var bundleIDCache: [pid_t: String] = [:]
        var results: [OnScreenWindowCandidate] = []

        for info in list {
            guard let layer = info[kCGWindowLayer as String] as? Int,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let wid = info[kCGWindowNumber as String] as? CGWindowID,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let qRect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  qRect.width >= 50, qRect.height >= 36 else {
                continue
            }

            if let alpha = info[kCGWindowAlpha as String] as? Double, alpha <= 0.01 {
                continue
            }

            let appName = (info[kCGWindowOwnerName as String] as? String) ?? "App"
            let rawTitle = (info[kCGWindowName as String] as? String) ?? ""
            if appName == "Window Server" || rawTitle == "Dock" || rawTitle == "Menubar" {
                continue
            }

            let bundleID: String
            if let cached = bundleIDCache[pid] {
                bundleID = cached
            } else {
                let resolved = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? ""
                bundleIDCache[pid] = resolved
                bundleID = resolved
            }
            if excludedBundleIDs.contains(bundleID) {
                continue
            }

            if pid == ownPID {
                // Allow XShot's real windows (Editor, Studio, Settings, Quick Preview, Popover, Pinned Images),
                // excluding internal capture overlays (`sharingType == .none`) and menu bar status icon.
                if excludedInternalIDs.contains(wid) || statusBarWindowIDs.contains(wid) {
                    continue
                }
                // Standard windows (0), floating panels like Quick Preview / Pinned (3), or Menu Popover (101)
                if layer != 0 && layer != 3 && layer != 101 {
                    continue
                }
            } else {
                // Standard app windows (layer 0), floating panels (layer 3), or popovers/context menus (layer 101).
                // Strictly skips Dock (layer 20), Menubar (24), Status items (25), and invisible fullscreen system layers!
                if layer != 0 && layer != 3 && layer != 101 {
                    continue
                }
                // Never let a fullscreen transparent overlay at layer > 0 block real windows underneath!
                if layer > 0 {
                    let coversWholeScreen = screenSizes.contains { sz in
                        qRect.width >= sz.width * 0.95 && qRect.height >= sz.height * 0.95
                    }
                    if coversWholeScreen { continue }
                }
            }

            let title = rawTitle.isEmpty && pid == ownPID ? (ownWindowTitles[wid] ?? "") : rawTitle
            let appKitRect = CoordinateConverter.quartzToAppKit(qRect, primaryHeight: primaryH)
            results.append(OnScreenWindowCandidate(
                windowID: wid,
                title: title,
                appName: appName,
                layer: layer,
                quartzFrame: qRect,
                appKitFrame: appKitRect
            ))
        }
        return results
    }
}

private final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

private enum DragInteraction {
    case drawing(start: CGPoint)
    case moving(startMouse: CGPoint, initialRect: CGRect)
    case resizing(corner: Int, initialRect: CGRect) // 0:BL, 1:BR, 2:TL, 3:TR
}

private final class SelectionOverlayView: NSView {
    private let screen: NSScreen
    private let mode: CaptureMode
    private let intent: CaptureIntent
    private let hasFrozenBackdrop: Bool
    private let candidates: [OnScreenWindowCandidate]
    private let onSelectTarget: (SelectedCaptureTarget) -> Void
    private let onCancel: () -> Void

    private var interaction: DragInteraction?
    private var currentMouse: CGPoint = .zero
    private var selectedLocalRect: CGRect?
    private var hoveredWindow: OnScreenWindowCandidate?
    private var trackingArea: NSTrackingArea?

    private var confirmButtonRect: CGRect = .zero
    private var snap16x9ButtonRect: CGRect = .zero
    private var snap1x1ButtonRect: CGRect = .zero
    private var cancelButtonRect: CGRect = .zero

    init(
        screen: NSScreen,
        mode: CaptureMode,
        intent: CaptureIntent,
        hasFrozenBackdrop: Bool,
        candidates: [OnScreenWindowCandidate],
        onSelectTarget: @escaping (SelectedCaptureTarget) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.screen = screen
        self.mode = mode
        self.intent = intent
        self.hasFrozenBackdrop = hasFrozenBackdrop
        self.candidates = candidates
        self.onSelectTarget = onSelectTarget
        self.onCancel = onCancel
        super.init(frame: CGRect(origin: .zero, size: screen.frame.size))
        self.wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func confirmRecordingSelectionIfReady() -> Bool {
        guard intent == .recording, let rect = selectedLocalRect, rect.width >= 20, rect.height >= 20 else {
            return false
        }
        emitAreaTarget(localRect: rect)
        return true
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: mode == .window ? .pointingHand : .crosshair)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        let ta = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .cursorUpdate, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(ta)
        trackingArea = ta
    }

    override func cursorUpdate(with event: NSEvent) {
        if mode == .window {
            NSCursor.pointingHand.set()
        } else {
            NSCursor.crosshair.set()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if mode == .window {
            NSCursor.pointingHand.set()
        } else {
            NSCursor.crosshair.set()
        }
        // Seed initial mouse position so crosshair / hovered window highlights immediately on open!
        let globalMouse = NSEvent.mouseLocation
        let localPt = CGPoint(x: globalMouse.x - screen.frame.origin.x, y: globalMouse.y - screen.frame.origin.y)
        if bounds.contains(localPt) {
            currentMouse = localPt
            if mode == .window {
                hoveredWindow = candidates.first(where: { $0.appKitFrame.contains(globalMouse) })
            }
            needsDisplay = true
        }
    }

    private func cornerPoints(for rect: CGRect) -> [CGPoint] {
        [
            CGPoint(x: rect.minX, y: rect.minY), // 0 BL
            CGPoint(x: rect.maxX, y: rect.minY), // 1 BR
            CGPoint(x: rect.minX, y: rect.maxY), // 2 TL
            CGPoint(x: rect.maxX, y: rect.maxY)  // 3 TR
        ]
    }

    private func hitCorner(at pt: CGPoint, in rect: CGRect) -> Int? {
        for (i, c) in cornerPoints(for: rect).enumerated() {
            if hypot(pt.x - c.x, pt.y - c.y) <= 13 { return i }
        }
        return nil
    }

    override func mouseMoved(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        currentMouse = pt

        if mode == .window {
            let globalAppKit = CGPoint(x: screen.frame.origin.x + pt.x, y: screen.frame.origin.y + pt.y)
            hoveredWindow = candidates.first(where: { $0.appKitFrame.contains(globalAppKit) })
            NSCursor.pointingHand.set()
        } else if intent == .recording, let rect = selectedLocalRect, interaction == nil {
            if confirmButtonRect.contains(pt) || snap16x9ButtonRect.contains(pt) || snap1x1ButtonRect.contains(pt) || cancelButtonRect.contains(pt) {
                NSCursor.pointingHand.set()
            } else if hitCorner(at: pt, in: rect) != nil {
                NSCursor.crosshair.set()
            } else if rect.contains(pt) {
                NSCursor.openHand.set()
            } else {
                NSCursor.crosshair.set()
            }
        } else {
            NSCursor.crosshair.set()
        }
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        currentMouse = pt

        if mode == .window {
            let globalAppKit = CGPoint(x: screen.frame.origin.x + pt.x, y: screen.frame.origin.y + pt.y)
            let targetWin = hoveredWindow ?? candidates.first(where: { $0.appKitFrame.contains(globalAppKit) })
            if let win = targetWin {
                onSelectTarget(.window(
                    windowID: win.windowID,
                    title: win.title,
                    appName: win.appName,
                    quartzFrame: win.quartzFrame,
                    scaleFactor: screen.backingScaleFactor
                ))
            }
            return
        }

        if intent == .recording, let rect = selectedLocalRect {
            if confirmButtonRect.contains(pt) {
                emitAreaTarget(localRect: rect)
                return
            }
            if snap16x9ButtonRect.contains(pt) {
                snapSelection(toRatio: 16.0 / 9.0)
                return
            }
            if snap1x1ButtonRect.contains(pt) {
                snapSelection(toRatio: 1.0)
                return
            }
            if cancelButtonRect.contains(pt) {
                onCancel()
                return
            }
            if let corner = hitCorner(at: pt, in: rect) {
                interaction = .resizing(corner: corner, initialRect: rect)
                return
            }
            if rect.contains(pt) {
                NSCursor.closedHand.set()
                interaction = .moving(startMouse: pt, initialRect: rect)
                return
            }
        }

        interaction = .drawing(start: pt)
        selectedLocalRect = CGRect(origin: pt, size: .zero)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard mode == .area, let action = interaction else { return }
        let pt = convert(event.locationInWindow, from: nil)
        currentMouse = pt

        switch action {
        case .drawing(let start):
            selectedLocalRect = CGRect(
                x: min(start.x, pt.x),
                y: min(start.y, pt.y),
                width: abs(pt.x - start.x),
                height: abs(pt.y - start.y)
            ).intersection(bounds)

        case .moving(let startMouse, let initial):
            let dx = pt.x - startMouse.x
            let dy = pt.y - startMouse.y
            let nx = min(max(0, initial.origin.x + dx), bounds.width - initial.width)
            let ny = min(max(0, initial.origin.y + dy), bounds.height - initial.height)
            selectedLocalRect = CGRect(x: nx, y: ny, width: initial.width, height: initial.height)

        case .resizing(let corner, let initial):
            var minX = initial.minX
            var maxX = initial.maxX
            var minY = initial.minY
            var maxY = initial.maxY
            if corner == 0 || corner == 2 { minX = min(pt.x, maxX - 40) }
            if corner == 1 || corner == 3 { maxX = max(pt.x, minX + 40) }
            if corner == 0 || corner == 1 { minY = min(pt.y, maxY - 40) }
            if corner == 2 || corner == 3 { maxY = max(pt.y, minY + 40) }
            selectedLocalRect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).intersection(bounds)
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard mode == .area, let action = interaction else { return }
        interaction = nil
        NSCursor.crosshair.set()

        guard let rect = selectedLocalRect, rect.width >= 20, rect.height >= 20 else {
            selectedLocalRect = nil
            needsDisplay = true
            return
        }

        if intent == .screenshot {
            if case .drawing = action {
                emitAreaTarget(localRect: rect)
            }
        } else {
            needsDisplay = true
        }
    }

    private func snapSelection(toRatio ratio: CGFloat) {
        guard let rect = selectedLocalRect else { return }
        let cx = rect.midX
        let cy = rect.midY
        var w = rect.width
        var h = w / ratio
        if h > bounds.height - 80 {
            h = bounds.height - 80
            w = h * ratio
        }
        if w > bounds.width - 40 {
            w = bounds.width - 40
            h = w / ratio
        }
        let x = min(max(12, cx - w / 2), bounds.width - w - 12)
        let y = min(max(12, cy - h / 2), bounds.height - h - 12)
        selectedLocalRect = CGRect(x: x.rounded(), y: y.rounded(), width: w.rounded(), height: h.rounded())
        needsDisplay = true
    }

    private func emitAreaTarget(localRect: CGRect) {
        let appKitRect = CGRect(
            x: screen.frame.origin.x + localRect.origin.x,
            y: screen.frame.origin.y + localRect.origin.y,
            width: localRect.width,
            height: localRect.height
        )
        let primaryH = CoordinateConverter.primaryScreenHeight()
        let quartzRect = CoordinateConverter.appKitToQuartz(appKitRect, primaryHeight: primaryH)
        let displayQuartz = CoordinateConverter.appKitToQuartz(screen.frame, primaryHeight: primaryH)
        let displayLocal = CoordinateConverter.quartzToDisplayLocal(quartzRect, displayQuartzBounds: displayQuartz)
        let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? CGMainDisplayID()

        onSelectTarget(.area(
            displayID: displayID,
            appKitRect: appKitRect,
            quartzRect: quartzRect,
            displayLocalRect: displayLocal,
            scaleFactor: screen.backingScaleFactor
        ))
    }

    private func drawScrim(in ctx: CGContext, cutoutRect: CGRect?) {
        // Frozen backdrop sits on the dedicated GPU subview right underneath this view,
        // so we only draw a lightweight even-odd scrim here at locked 120Hz (0 CPU image blits!).
        ctx.saveGState()
        ctx.setFillColor(NSColor.black.withAlphaComponent(hasFrozenBackdrop ? 0.35 : 0.34).cgColor)
        if let cut = cutoutRect, cut.width > 2, cut.height > 2 {
            let path = CGMutablePath()
            path.addRect(bounds)
            path.addRect(cut)
            ctx.addPath(path)
            ctx.fillPath(using: .evenOdd)
        } else {
            ctx.fill(bounds)
        }
        ctx.restoreGState()
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        if mode == .window {
            drawWindowMode(in: ctx)
            return
        }

        drawScrim(in: ctx, cutoutRect: selectedLocalRect)

        if selectedLocalRect == nil || interaction != nil {
            ctx.saveGState()
            ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.36).cgColor)
            ctx.setLineWidth(1)
            ctx.setLineDash(phase: 0, lengths: [4, 4])
            ctx.move(to: CGPoint(x: currentMouse.x, y: 0))
            ctx.addLine(to: CGPoint(x: currentMouse.x, y: bounds.height))
            ctx.move(to: CGPoint(x: 0, y: currentMouse.y))
            ctx.addLine(to: CGPoint(x: bounds.width, y: currentMouse.y))
            ctx.strokePath()
            ctx.restoreGState()
        }

        if let rect = selectedLocalRect, rect.width > 2, rect.height > 2 {
            let accent = (intent == .recording)
                ? NSColor(srgbRed: 0.96, green: 0.25, blue: 0.37, alpha: 1.0)
                : NSColor(srgbRed: 0.14, green: 0.78, blue: 0.98, alpha: 1.0)

            ctx.saveGState()
            ctx.setStrokeColor(accent.cgColor)
            ctx.setLineWidth(2.0)
            ctx.stroke(rect)
            ctx.restoreGState()

            let pxW = Int((rect.width * screen.backingScaleFactor).rounded())
            let pxH = Int((rect.height * screen.backingScaleFactor).rounded())
            drawPillBadge(
                text: "\(pxW) × \(pxH) px",
                at: CGPoint(x: rect.minX, y: min(bounds.height - 34, rect.maxY + 8)),
                background: NSColor(red: 0.07, green: 0.08, blue: 0.11, alpha: 0.92)
            )

            if intent == .recording && interaction == nil {
                for c in cornerPoints(for: rect) {
                    let hRect = CGRect(x: c.x - 5.5, y: c.y - 5.5, width: 11, height: 11)
                    ctx.setFillColor(NSColor.white.cgColor)
                    ctx.fillEllipse(in: hRect)
                    ctx.setStrokeColor(accent.cgColor)
                    ctx.setLineWidth(2.0)
                    ctx.strokeEllipse(in: hRect)
                }
                drawRecordingActionBar(below: rect)
            }
        } else {
            let hint = (intent == .recording)
                ? L10n.t(.overlayHintRecording)
                : L10n.t(.overlayHintScreenshot)
            drawPillBadge(
                text: hint,
                at: CGPoint(x: bounds.midX - 205, y: bounds.height - 86),
                background: NSColor(red: 0.07, green: 0.08, blue: 0.11, alpha: 0.92)
            )
        }
    }

    private func drawWindowMode(in ctx: CGContext) {
        if let win = hoveredWindow {
            let localRect = CGRect(
                x: win.appKitFrame.origin.x - screen.frame.origin.x,
                y: win.appKitFrame.origin.y - screen.frame.origin.y,
                width: win.appKitFrame.width,
                height: win.appKitFrame.height
            ).intersection(bounds)

            if !localRect.isNull && !localRect.isEmpty {
                drawScrim(in: ctx, cutoutRect: localRect)

                let accent = (intent == .recording)
                    ? NSColor(srgbRed: 0.96, green: 0.25, blue: 0.37, alpha: 1.0)
                    : NSColor(srgbRed: 0.14, green: 0.78, blue: 0.98, alpha: 1.0)

                ctx.saveGState()
                ctx.setFillColor(accent.withAlphaComponent(0.10).cgColor)
                ctx.fill(localRect)
                ctx.setStrokeColor(accent.cgColor)
                ctx.setLineWidth(3.0)
                let path = CGPath(roundedRect: localRect, cornerWidth: 10, cornerHeight: 10, transform: nil)
                ctx.addPath(path)
                ctx.strokePath()
                ctx.restoreGState()

                let label = win.title.isEmpty ? win.appName : "\(win.appName) — \(win.title.prefix(34))"
                let prefix = (intent == .recording) ? L10n.t(.overlayWindowRecordPrefix) : L10n.t(.overlayWindowShotPrefix)
                let actionLabel = prefix + label
                drawPillBadge(
                    text: actionLabel,
                    at: CGPoint(x: max(16, localRect.midX - 140), y: max(20, min(bounds.height - 44, localRect.midY))),
                    background: NSColor(red: 0.07, green: 0.08, blue: 0.11, alpha: 0.92)
                )
                return
            }
        }

        drawScrim(in: ctx, cutoutRect: nil)
        drawPillBadge(
            text: L10n.t(.overlayHintWindow),
            at: CGPoint(x: bounds.midX - 155, y: bounds.height - 86),
            background: NSColor(red: 0.07, green: 0.08, blue: 0.11, alpha: 0.92)
        )
    }

    private func drawRecordingActionBar(below rect: CGRect) {
        let barW: CGFloat = 352
        let barH: CGFloat = 42
        let barX = max(16, min(bounds.width - barW - 16, rect.midX - barW / 2))
        let barY = (rect.minY > barH + 18) ? (rect.minY - barH - 12) : (rect.minY + 14)

        let barRect = CGRect(x: barX, y: barY, width: barW, height: barH)
        let bgPath = NSBezierPath(roundedRect: barRect, xRadius: 12, yRadius: 12)
        NSColor(red: 0.07, green: 0.08, blue: 0.11, alpha: 0.94).setFill()
        bgPath.fill()
        NSColor.white.withAlphaComponent(0.16).setStroke()
        bgPath.lineWidth = 1
        bgPath.stroke()

        confirmButtonRect = CGRect(x: barX + 6, y: barY + 6, width: 158, height: 30)
        drawBarButton(confirmButtonRect, title: L10n.t(.overlayStartRecording), fill: NSColor(srgbRed: 0.92, green: 0.22, blue: 0.32, alpha: 1.0), textColor: .white)

        snap16x9ButtonRect = CGRect(x: barX + 170, y: barY + 6, width: 52, height: 30)
        drawBarButton(snap16x9ButtonRect, title: "16:9", fill: NSColor.white.withAlphaComponent(0.11), textColor: .white.withAlphaComponent(0.92))

        snap1x1ButtonRect = CGRect(x: barX + 228, y: barY + 6, width: 46, height: 30)
        drawBarButton(snap1x1ButtonRect, title: "1:1", fill: NSColor.white.withAlphaComponent(0.11), textColor: .white.withAlphaComponent(0.92))

        cancelButtonRect = CGRect(x: barX + 280, y: barY + 6, width: 66, height: 30)
        drawBarButton(cancelButtonRect, title: L10n.t(.overlayCancel), fill: NSColor.white.withAlphaComponent(0.08), textColor: .white.withAlphaComponent(0.75))
    }

    private func drawBarButton(_ rect: CGRect, title: String, fill: NSColor, textColor: NSColor) {
        let p = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        fill.setFill()
        p.fill()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: textColor
        ]
        let s = NSAttributedString(string: title, attributes: attrs)
        let sz = s.size()
        s.draw(at: CGPoint(x: rect.midX - sz.width / 2, y: rect.midY - sz.height / 2))
    }

    private func drawPillBadge(text: String, at origin: CGPoint, background: NSColor) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let size = str.size()
        let rect = CGRect(
            x: max(12, min(bounds.width - size.width - 28, origin.x)),
            y: max(12, min(bounds.height - size.height - 20, origin.y)),
            width: size.width + 20,
            height: size.height + 10
        )
        let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        background.setFill()
        path.fill()
        NSColor.white.withAlphaComponent(0.14).setStroke()
        path.lineWidth = 1
        path.stroke()

        str.draw(at: CGPoint(x: rect.minX + 10, y: rect.minY + 5))
    }
}
