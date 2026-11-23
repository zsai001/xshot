import CoreGraphics
import Foundation

public enum MouseButtonKind: String, Codable, Equatable, Sendable {
    case left
    case right
    case other
}

public struct CursorSample: Codable, Equatable, Sendable {
    /// Seconds from recording start
    public var time: Double
    /// Normalized [0, 1] inside capture rect (0 = left, 1 = right)
    public var x: Double
    /// Normalized [0, 1] inside capture rect (0 = top, 1 = bottom)
    public var y: Double
    public var isInside: Bool
    public var isPressed: Bool

    public init(time: Double, x: Double, y: Double, isInside: Bool = true, isPressed: Bool = false) {
        self.time = time
        self.x = x
        self.y = y
        self.isInside = isInside
        self.isPressed = isPressed
    }
}

public struct ClickEvent: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var time: Double
    public var x: Double
    public var y: Double
    public var button: MouseButtonKind

    public init(id: UUID = UUID(), time: Double, x: Double, y: Double, button: MouseButtonKind = .left) {
        self.id = id
        self.time = time
        self.x = x
        self.y = y
        self.button = button
    }
}

public struct KeystrokeEvent: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var time: Double
    /// Human-readable display string (e.g. "⌘⇧P" or "hello")
    public var text: String
    /// Individual physical keycap tokens for shortcuts/special keys (e.g. ["⌘", "⇧", "P"])
    public var keycaps: [String]
    /// True when this event represents live typed prose/code rather than a shortcut combo
    public var isTypingText: Bool

    public init(
        id: UUID = UUID(),
        time: Double,
        text: String,
        keycaps: [String] = [],
        isTypingText: Bool = false
    ) {
        self.id = id
        self.time = time
        self.text = text
        self.keycaps = keycaps.isEmpty ? [text] : keycaps
        self.isTypingText = isTypingText
    }
}

/// Captured text-input / caret focus position during typing so AutoZoomEngine can smoothly zoom onto where the user is typing!
public struct TypingFocusEvent: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var time: Double
    /// Normalized [0, 1] inside capture rect (top-left origin)
    public var x: Double
    public var y: Double
    /// True when coordinates came from macOS Accessibility exact caret / focused-element bounds
    public var hasExactFocusBounds: Bool

    public init(
        id: UUID = UUID(),
        time: Double,
        x: Double,
        y: Double,
        hasExactFocusBounds: Bool = true
    ) {
        self.id = id
        self.time = time
        self.x = x
        self.y = y
        self.hasExactFocusBounds = hasExactFocusBounds
    }
}

public enum ZoomTriggerKind: String, Codable, Equatable, Sendable {
    case click
    case typing
    case manual
}

public struct ZoomSegment: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var startTime: Double
    public var endTime: Double
    /// Normalized [0, 1] focus point (top-left origin)
    public var focusX: Double
    public var focusY: Double
    /// Zoom factor, e.g. 1.75 means 175%
    public var scale: Double
    /// Ease-in and ease-out duration in seconds
    public var easeDuration: Double
    /// Whether this segment smoothly follows cursor (for clicks) or typing caret (for typing) during its span
    public var followCursor: Bool
    /// Origin of this zoom segment for color-coding on timeline & camera follow behavior
    public var triggerKind: ZoomTriggerKind

    public init(
        id: UUID = UUID(),
        startTime: Double,
        endTime: Double,
        focusX: Double,
        focusY: Double,
        scale: Double = 1.8,
        easeDuration: Double = 0.42,
        followCursor: Bool = true,
        triggerKind: ZoomTriggerKind = .click
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.focusX = focusX
        self.focusY = focusY
        self.scale = scale
        self.easeDuration = easeDuration
        self.followCursor = followCursor
        self.triggerKind = triggerKind
    }

    public var duration: Double {
        max(0, endTime - startTime)
    }
}

public struct RecordingTelemetry: Codable, Equatable, Sendable {
    public var captureQuartzRect: CGRect
    public var cursorSamples: [CursorSample]
    public var clickEvents: [ClickEvent]
    public var keystrokeEvents: [KeystrokeEvent]
    public var typingFocusEvents: [TypingFocusEvent]
    public var duration: Double
    public var hidNativeCursor: Bool

    public init(
        captureQuartzRect: CGRect = .zero,
        cursorSamples: [CursorSample] = [],
        clickEvents: [ClickEvent] = [],
        keystrokeEvents: [KeystrokeEvent] = [],
        typingFocusEvents: [TypingFocusEvent] = [],
        duration: Double = 0,
        hidNativeCursor: Bool = false
    ) {
        self.captureQuartzRect = captureQuartzRect
        self.cursorSamples = cursorSamples
        self.clickEvents = clickEvents
        self.keystrokeEvents = keystrokeEvents
        self.typingFocusEvents = typingFocusEvents
        self.duration = duration
        self.hidNativeCursor = hidNativeCursor
    }
}
