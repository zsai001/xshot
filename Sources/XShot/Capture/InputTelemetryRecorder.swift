import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Records 60Hz cursor trajectories, mouse clicks, global keystrokes (shortcuts + live typing),
/// and exact macOS Accessibility text-caret / input-focus coordinates for smooth auto-zoom!
public final class InputTelemetryRecorder {
    private let lock = NSLock()
    private var captureQuartzRect: CGRect = .zero
    private var primaryScreenHeight: CGFloat = 1080
    private var startMonotonicTime: TimeInterval = 0
    private var pausedDuration: TimeInterval = 0
    private var pauseStartTime: TimeInterval?
    private var isRecording = false
    private var isMousePressed = false
    private var hidNativeCursor = false

    private var cursorSamples: [CursorSample] = []
    private var clickEvents: [ClickEvent] = []
    private var keystrokeEvents: [KeystrokeEvent] = []
    private var typingFocusEvents: [TypingFocusEvent] = []

    // Typing burst accumulator (guarded by lock)
    private var typingBuffer: String = ""
    private var lastTypingTime: Double = -10
    private var lastClickNormPoint: (x: Double, y: Double)?

    private var timer: DispatchSourceTimer?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?

    public init() {}

    deinit {
        stopMonitors()
    }

    public func start(captureQuartzRect: CGRect, hidNativeCursor: Bool) {
        stopMonitors()

        let primaryH = CoordinateConverter.primaryScreenHeight()
        let now = ProcessInfo.processInfo.systemUptime

        lock.lock()
        self.captureQuartzRect = captureQuartzRect
        self.primaryScreenHeight = primaryH
        self.startMonotonicTime = now
        self.pausedDuration = 0
        self.pauseStartTime = nil
        self.isRecording = true
        self.isMousePressed = false
        self.hidNativeCursor = hidNativeCursor
        self.cursorSamples = []
        self.clickEvents = []
        self.keystrokeEvents = []
        self.typingFocusEvents = []
        self.typingBuffer = ""
        self.lastTypingTime = -10
        self.lastClickNormPoint = nil
        lock.unlock()

        // 60Hz precision cursor position sampler
        let t = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "top.xtags.xshot.telemetry.cursor", qos: .userInteractive))
        t.schedule(deadline: .now(), repeating: .milliseconds(16), leeway: .milliseconds(2))
        t.setEventHandler { [weak self] in
            self?.sampleCurrentCursor()
        }
        t.resume()
        self.timer = t

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp]
            ) { [weak self] event in
                self?.handleMouseEvent(event)
            }

            self.localMouseMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp]
            ) { [weak self] event in
                self?.handleMouseEvent(event)
                return event
            }

            #if !MAC_APP_STORE
            self.globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
                self?.handleKeyEvent(event)
            }

            self.localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
                self?.handleKeyEvent(event)
                return event
            }
            #endif
        }
    }

    public func pause() {
        lock.lock()
        if isRecording && pauseStartTime == nil {
            pauseStartTime = ProcessInfo.processInfo.systemUptime
        }
        lock.unlock()
    }

    public func resume() {
        lock.lock()
        if isRecording, let pStart = pauseStartTime {
            pausedDuration += (ProcessInfo.processInfo.systemUptime - pStart)
            pauseStartTime = nil
        }
        lock.unlock()
    }

    public func stop(finalDuration: Double) -> RecordingTelemetry {
        stopMonitors()

        lock.lock()
        isRecording = false
        let telemetry = RecordingTelemetry(
            captureQuartzRect: captureQuartzRect,
            cursorSamples: cursorSamples,
            clickEvents: clickEvents,
            keystrokeEvents: keystrokeEvents,
            typingFocusEvents: typingFocusEvents,
            duration: max(finalDuration, cursorSamples.last?.time ?? 0),
            hidNativeCursor: hidNativeCursor
        )
        lock.unlock()
        return telemetry
    }

    private func stopMonitors() {
        timer?.cancel()
        timer = nil

        let gm = globalMouseMonitor
        let lm = localMouseMonitor
        let gk = globalKeyMonitor
        let lk = localKeyMonitor
        globalMouseMonitor = nil
        localMouseMonitor = nil
        globalKeyMonitor = nil
        localKeyMonitor = nil

        let cleanup = {
            if let gm { NSEvent.removeMonitor(gm) }
            if let lm { NSEvent.removeMonitor(lm) }
            if let gk { NSEvent.removeMonitor(gk) }
            if let lk { NSEvent.removeMonitor(lk) }
        }
        if Thread.isMainThread {
            cleanup()
        } else {
            DispatchQueue.main.async(execute: cleanup)
        }
    }

    private func elapsedTimeLocked() -> Double? {
        guard isRecording, pauseStartTime == nil else { return nil }
        return max(0, ProcessInfo.processInfo.systemUptime - startMonotonicTime - pausedDuration)
    }

    private func normalizedCursorPoint(from appKitLocation: CGPoint, rect: CGRect, primaryH: CGFloat) -> (x: Double, y: Double, inside: Bool) {
        let qPt = CoordinateConverter.appKitPointToQuartz(appKitLocation, primaryHeight: primaryH)
        return normalizedQuartzPoint(qPt, in: rect)
    }

    private func normalizedQuartzPoint(_ qPt: CGPoint, in rect: CGRect) -> (x: Double, y: Double, inside: Bool) {
        let w = max(1, rect.width)
        let h = max(1, rect.height)
        let nx = Double((qPt.x - rect.origin.x) / w)
        let ny = Double((qPt.y - rect.origin.y) / h)
        let inside = (nx >= -0.04 && nx <= 1.04 && ny >= -0.04 && ny <= 1.04)
        return (min(max(nx, 0), 1), min(max(ny, 0), 1), inside)
    }

    private func sampleCurrentCursor() {
        let loc = NSEvent.mouseLocation
        lock.lock()
        defer { lock.unlock() }
        guard let t = elapsedTimeLocked() else { return }
        let norm = normalizedCursorPoint(from: loc, rect: captureQuartzRect, primaryH: primaryScreenHeight)
        cursorSamples.append(CursorSample(
            time: t,
            x: norm.x,
            y: norm.y,
            isInside: norm.inside,
            isPressed: isMousePressed
        ))
    }

    private func handleMouseEvent(_ event: NSEvent) {
        // Ignore clicks on XShot's own internal capture HUD/overlays (e.g., clicking Pause/Stop during fullscreen capture),
        // while still recording clicks inside XShot's real user-facing windows when recording XShot itself!
        if let win = event.window, win.sharingType == NSWindow.SharingType.none { return }

        let loc = NSEvent.mouseLocation
        lock.lock()
        defer { lock.unlock() }
        guard let t = elapsedTimeLocked() else { return }

        switch event.type {
        case .leftMouseDown, .rightMouseDown:
            isMousePressed = true
            let norm = normalizedCursorPoint(from: loc, rect: captureQuartzRect, primaryH: primaryScreenHeight)
            if norm.inside {
                let btn: MouseButtonKind = (event.type == .leftMouseDown) ? .left : .right
                clickEvents.append(ClickEvent(time: t, x: norm.x, y: norm.y, button: btn))
                lastClickNormPoint = (norm.x, norm.y)
                // Clicking somewhere else resets typing burst buffer
                typingBuffer = ""
            }
        case .leftMouseUp, .rightMouseUp:
            isMousePressed = false
        default:
            break
        }
    }

    // MARK: - Keystrokes & Accessibility Text Caret / Input Focus Tracking

    private struct AXFocusProbe {
        let isSecurePasswordField: Bool
        let quartzPoint: CGPoint?
    }

    private func probeFocusedInputAX() -> AXFocusProbe {
        #if MAC_APP_STORE
        return AXFocusProbe(isSecurePasswordField: false, quartzPoint: nil)
        #else
        guard AXIsProcessTrusted() else {
            return AXFocusProbe(isSecurePasswordField: false, quartzPoint: nil)
        }

        let sysWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(sysWide, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let ref = focusedRef,
              CFGetTypeID(ref) == AXUIElementGetTypeID() else {
            return AXFocusProbe(isSecurePasswordField: false, quartzPoint: nil)
        }
        let element = unsafeBitCast(ref, to: AXUIElement.self)

        // Never leak passwords from secure text fields!
        var subroleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleRef) == .success,
           let subrole = subroleRef as? String,
           subrole == (kAXSecureTextFieldSubrole as String) {
            return AXFocusProbe(isSecurePasswordField: true, quartzPoint: nil)
        }

        // 1. Best accuracy: exact blinking text caret / selected text range bounds!
        var rangeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
           let rangeVal = rangeRef {
            var boundsRef: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(
                element,
                kAXBoundsForRangeParameterizedAttribute as CFString,
                rangeVal,
                &boundsRef
            ) == .success,
               let bRef = boundsRef,
               CFGetTypeID(bRef) == AXValueGetTypeID() {
                var caretRect = CGRect.zero
                if AXValueGetValue(unsafeBitCast(bRef, to: AXValue.self), .cgRect, &caretRect),
                   caretRect.width >= 0, caretRect.height > 0,
                   caretRect.origin.x.isFinite, caretRect.origin.y.isFinite {
                    return AXFocusProbe(
                        isSecurePasswordField: false,
                        quartzPoint: CGPoint(x: caretRect.midX, y: caretRect.midY)
                    )
                }
            }
        }

        // 2. Fallback: focused input element's position + size center
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
           AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
           let pRef = posRef, let sRef = sizeRef,
           CFGetTypeID(pRef) == AXValueGetTypeID(), CFGetTypeID(sRef) == AXValueGetTypeID() {
            var pos = CGPoint.zero
            var size = CGSize.zero
            if AXValueGetValue(unsafeBitCast(pRef, to: AXValue.self), .cgPoint, &pos),
               AXValueGetValue(unsafeBitCast(sRef, to: AXValue.self), .cgSize, &size),
               size.width > 4, size.height > 4 {
                // Anchor slightly toward left-center for wide input boxes so typed text stays framed cleanly
                let anchorX = pos.x + min(size.width * 0.5, 220)
                let anchorY = pos.y + min(size.height * 0.5, 160)
                return AXFocusProbe(
                    isSecurePasswordField: false,
                    quartzPoint: CGPoint(x: anchorX, y: anchorY)
                )
            }
        }

        return AXFocusProbe(isSecurePasswordField: false, quartzPoint: nil)
        #endif
    }

    private func handleKeyEvent(_ event: NSEvent) {
        let axProbe = probeFocusedInputAX()
        if axProbe.isSecurePasswordField {
            return
        }

        let mouseLoc = NSEvent.mouseLocation
        let mods = event.modifierFlags.intersection([.command, .control, .option, .shift])
        let keyCode = event.keyCode
        let rawChars = event.characters ?? ""
        let ignoredModsChars = event.charactersIgnoringModifiers ?? ""

        lock.lock()
        defer { lock.unlock() }
        guard let t = elapsedTimeLocked() else { return }

        // 1. Record Input Focus point for Input-Focus Auto-Zoom!
        let hasShortcutMod = mods.contains(.command) || mods.contains(.control) || mods.contains(.option)
        let isTypingKey = !hasShortcutMod && keyCode != 53 /* Esc */
        if isTypingKey {
            if let qPt = axProbe.quartzPoint {
                let norm = normalizedQuartzPoint(qPt, in: captureQuartzRect)
                if norm.inside {
                    typingFocusEvents.append(TypingFocusEvent(time: t, x: norm.x, y: norm.y, hasExactFocusBounds: true))
                }
            } else if let lastClick = lastClickNormPoint {
                typingFocusEvents.append(TypingFocusEvent(time: t, x: lastClick.x, y: lastClick.y, hasExactFocusBounds: false))
            } else {
                let norm = normalizedCursorPoint(from: mouseLoc, rect: captureQuartzRect, primaryH: primaryScreenHeight)
                if norm.inside {
                    typingFocusEvents.append(TypingFocusEvent(time: t, x: norm.x, y: norm.y, hasExactFocusBounds: false))
                }
            }
        }

        // 2. Format Keystroke Event (Physical Keycaps for shortcuts/special keys, or live typing burst!)
        let specialKeys: [UInt16: String] = [
            36: "↵", 76: "↵", 48: "⇥", 49: "Space", 51: "⌫", 117: "⌦", 53: "Esc",
            123: "←", 124: "→", 125: "↓", 126: "↑"
        ]

        if hasShortcutMod {
            typingBuffer = ""
            var tokens: [String] = []
            if mods.contains(.control) { tokens.append("⌃") }
            if mods.contains(.option) { tokens.append("⌥") }
            if mods.contains(.shift) { tokens.append("⇧") }
            if mods.contains(.command) { tokens.append("⌘") }

            if let special = specialKeys[keyCode] {
                tokens.append(special)
            } else {
                let cleaned = ignoredModsChars.uppercased().trimmingCharacters(in: .controlCharacters)
                if !cleaned.isEmpty {
                    tokens.append(cleaned)
                } else {
                    return
                }
            }
            keystrokeEvents.append(KeystrokeEvent(
                time: t,
                text: tokens.joined(),
                keycaps: tokens,
                isTypingText: false
            ))
            return
        }

        // Backspace during active typing burst edits the live buffer cleanly
        if keyCode == 51 && !typingBuffer.isEmpty && (t - lastTypingTime) <= 1.1 {
            typingBuffer.removeLast()
            lastTypingTime = t
            if !typingBuffer.isEmpty {
                let shown = typingBuffer.count > 24 ? "…" + String(typingBuffer.suffix(23)) : typingBuffer
                keystrokeEvents.append(KeystrokeEvent(time: t, text: shown, keycaps: [shown], isTypingText: true))
            } else {
                keystrokeEvents.append(KeystrokeEvent(time: t, text: "⌫", keycaps: ["⌫"], isTypingText: false))
            }
            return
        }

        // Space during active typing burst appends space into typing text; standalone Space shows keycap
        if keyCode == 49 && !typingBuffer.isEmpty && (t - lastTypingTime) <= 0.95 {
            typingBuffer.append(" ")
            lastTypingTime = t
            let shown = typingBuffer.count > 24 ? "…" + String(typingBuffer.suffix(23)) : typingBuffer
            keystrokeEvents.append(KeystrokeEvent(time: t, text: shown, keycaps: [shown], isTypingText: true))
            return
        }

        if let special = specialKeys[keyCode] {
            typingBuffer = ""
            var tokens: [String] = []
            if mods.contains(.shift) { tokens.append("⇧") }
            tokens.append(special)
            keystrokeEvents.append(KeystrokeEvent(
                time: t,
                text: tokens.joined(),
                keycaps: tokens,
                isTypingText: false
            ))
            return
        }

        // Printable typing character -> accumulate smooth typing burst
        let printable = rawChars.filter { ch in
            guard let scalar = ch.unicodeScalars.first else { return false }
            return !CharacterSet.controlCharacters.contains(scalar)
        }
        guard !printable.isEmpty else { return }

        if (t - lastTypingTime) > 0.95 {
            typingBuffer = ""
        }
        typingBuffer.append(contentsOf: printable)
        if typingBuffer.count > 48 {
            typingBuffer = String(typingBuffer.suffix(48))
        }
        lastTypingTime = t
        let shown = typingBuffer.count > 24 ? "…" + String(typingBuffer.suffix(23)) : typingBuffer
        keystrokeEvents.append(KeystrokeEvent(
            time: t,
            text: shown,
            keycaps: [shown],
            isTypingText: true
        ))
    }
}
