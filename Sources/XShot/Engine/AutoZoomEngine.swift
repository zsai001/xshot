import CoreGraphics
import Foundation

public struct CameraState: Equatable, Sendable {
    /// Zoom scale >= 1.0
    public var scale: Double
    /// Normalized [0, 1] viewport center X (top-left origin)
    public var centerX: Double
    /// Normalized [0, 1] viewport center Y (top-left origin)
    public var centerY: Double

    public static let identity = CameraState(scale: 1.0, centerX: 0.5, centerY: 0.5)

    /// Returns the source crop rect in **top-left pixel coordinates** of `sourceSize`,
    /// guaranteed to stay within `(0, 0, sourceSize.width, sourceSize.height)`.
    public func sourceCropRect(for sourceSize: CGSize) -> CGRect {
        let clampedScale = max(1.0, scale)
        let cropW = sourceSize.width / clampedScale
        let cropH = sourceSize.height / clampedScale

        let halfW = cropW / 2.0
        let halfH = cropH / 2.0

        let desiredCX = centerX * sourceSize.width
        let desiredCY = centerY * sourceSize.height

        let clampedCX = min(max(desiredCX, halfW), max(halfW, sourceSize.width - halfW))
        let clampedCY = min(max(desiredCY, halfH), max(halfH, sourceSize.height - halfH))

        return CGRect(
            x: clampedCX - halfW,
            y: clampedCY - halfH,
            width: cropW,
            height: cropH
        )
    }
}

public struct RenderedCursorState: Equatable {
    /// Normalized [0, 1] in source frame (top-left origin)
    public var x: Double
    public var y: Double
    public var isVisible: Bool
    public var isPressed: Bool
    /// Active click ripples: (normalizedX, normalizedY, progress 0...1)
    public var activeRipples: [(x: Double, y: Double, progress: Double)]

    public static func == (lhs: RenderedCursorState, rhs: RenderedCursorState) -> Bool {
        lhs.x == rhs.x &&
        lhs.y == rhs.y &&
        lhs.isVisible == rhs.isVisible &&
        lhs.isPressed == rhs.isPressed &&
        lhs.activeRipples.count == rhs.activeRipples.count
    }
}

public struct ActiveKeystrokeVisual: Equatable, Sendable {
    public var event: KeystrokeEvent
    public var opacity: Double
    public var popScale: Double
}

public enum AutoZoomEngine {
    /// Generates smooth, non-overlapping auto-zoom segments from BOTH mouse clicks AND typing input-focus bursts!
    public static func generateAutoZoomSegments(
        clicks: [ClickEvent],
        typingEvents: [TypingFocusEvent] = [],
        includeClicks: Bool = true,
        includeTypingFocus: Bool = true,
        duration: Double,
        defaultScale: Double = 1.75,
        typingScale: Double = 1.9,
        clusterGap: Double = 2.2,
        leadIn: Double = 0.35,
        holdOut: Double = 0.95,
        minSegmentDuration: Double = 1.4
    ) -> [ZoomSegment] {
        guard duration > 0.5 else { return [] }

        var rawSegments: [ZoomSegment] = []

        // 1. Click-triggered zoom clusters
        if includeClicks && !clicks.isEmpty {
            let sorted = clicks.sorted { $0.time < $1.time }
            var clusters: [[ClickEvent]] = []
            var current: [ClickEvent] = [sorted[0]]
            for click in sorted.dropFirst() {
                if let last = current.last, (click.time - last.time) <= clusterGap {
                    current.append(click)
                } else {
                    clusters.append(current)
                    current = [click]
                }
            }
            clusters.append(current)

            for cluster in clusters {
                guard let first = cluster.first, let last = cluster.last else { continue }
                var start = max(0, first.time - leadIn)
                var end = min(duration, last.time + holdOut)
                if (end - start) < minSegmentDuration {
                    end = min(duration, start + minSegmentDuration)
                    if (end - start) < minSegmentDuration {
                        start = max(0, end - minSegmentDuration)
                    }
                }
                let avgX = cluster.map(\.x).reduce(0, +) / Double(cluster.count)
                let avgY = cluster.map(\.y).reduce(0, +) / Double(cluster.count)
                rawSegments.append(ZoomSegment(
                    startTime: start,
                    endTime: end,
                    focusX: min(max(avgX, 0), 1),
                    focusY: min(max(avgY, 0), 1),
                    scale: defaultScale,
                    easeDuration: min(0.42, (end - start) * 0.32),
                    followCursor: true,
                    triggerKind: .click
                ))
            }
        }

        // 2. Typing / Input-Focus zoom clusters (follows text caret where the user is typing!)
        if includeTypingFocus && !typingEvents.isEmpty {
            let sortedT = typingEvents.sorted { $0.time < $1.time }
            var tClusters: [[TypingFocusEvent]] = []
            var current: [TypingFocusEvent] = [sortedT[0]]
            for ev in sortedT.dropFirst() {
                if let last = current.last, (ev.time - last.time) <= 1.8 {
                    current.append(ev)
                } else {
                    tClusters.append(current)
                    current = [ev]
                }
            }
            tClusters.append(current)

            for cluster in tClusters {
                guard let first = cluster.first, let last = cluster.last else { continue }
                var start = max(0, first.time - 0.28)
                var end = min(duration, last.time + 0.90)
                if (end - start) < 1.2 {
                    end = min(duration, start + 1.2)
                    if (end - start) < 1.2 {
                        start = max(0, end - 1.2)
                    }
                }
                let avgX = cluster.map(\.x).reduce(0, +) / Double(cluster.count)
                let avgY = cluster.map(\.y).reduce(0, +) / Double(cluster.count)
                rawSegments.append(ZoomSegment(
                    startTime: start,
                    endTime: end,
                    focusX: min(max(avgX, 0), 1),
                    focusY: min(max(avgY, 0), 1),
                    scale: typingScale,
                    easeDuration: min(0.38, (end - start) * 0.30),
                    followCursor: true,
                    triggerKind: .typing
                ))
            }
        }

        // 3. Sort & cleanly merge overlapping segments (giving `.typing` focus priority when a click starts typing!)
        rawSegments.sort { $0.startTime < $1.startTime }
        var merged: [ZoomSegment] = []
        for seg in rawSegments {
            if var prev = merged.last, seg.startTime <= prev.endTime + 0.18 {
                prev.endTime = max(prev.endTime, seg.endTime)
                if seg.triggerKind == .typing {
                    prev.triggerKind = .typing
                    prev.focusX = seg.focusX
                    prev.focusY = seg.focusY
                    prev.scale = max(prev.scale, seg.scale)
                } else if prev.triggerKind != .typing {
                    prev.focusX = (prev.focusX + seg.focusX) / 2.0
                    prev.focusY = (prev.focusY + seg.focusY) / 2.0
                }
                merged[merged.count - 1] = prev
            } else {
                merged.append(seg)
            }
        }

        return merged
    }

    /// Quintic smoothstep (C2 continuous — ultra-silky velocity & acceleration ease for 60fps video).
    public static func smootherstep(_ t: Double) -> Double {
        let x = min(max(t, 0.0), 1.0)
        return x * x * x * (x * (x * 6.0 - 15.0) + 10.0)
    }

    /// Evaluates the smooth camera zoom and center at a given time `t`.
    /// For `.typing` segments, smoothly pans along recorded caret/input-focus positions!
    public static func evaluateCamera(
        at time: Double,
        segments: [ZoomSegment],
        smoothedCursorPath: [CursorSample],
        typingFocusEvents: [TypingFocusEvent] = [],
        enabled: Bool
    ) -> CameraState {
        guard enabled, !segments.isEmpty else { return .identity }

        for seg in segments {
            guard time >= seg.startTime && time <= seg.endTime else { continue }
            let dur = max(0.001, seg.endTime - seg.startTime)
            let ease = min(max(0.05, seg.easeDuration), dur * 0.45)

            let envelope: Double
            if time < seg.startTime + ease {
                envelope = smootherstep((time - seg.startTime) / ease)
            } else if time > seg.endTime - ease {
                envelope = smootherstep((seg.endTime - time) / ease)
            } else {
                envelope = 1.0
            }

            let targetScale = 1.0 + (max(1.0, seg.scale) - 1.0) * envelope

            var targetX = seg.focusX
            var targetY = seg.focusY
            if seg.followCursor {
                if seg.triggerKind == .typing, let caretPt = sampleTypingFocus(at: time, in: typingFocusEvents) {
                    // Gently track moving text caret while typing across an input box or editor line
                    targetX = seg.focusX * 0.18 + caretPt.x * 0.82
                    targetY = seg.focusY * 0.18 + caretPt.y * 0.82
                } else if let cursor = sampleCursor(at: time, in: smoothedCursorPath), cursor.isInside {
                    targetX = seg.focusX * 0.25 + cursor.x * 0.75
                    targetY = seg.focusY * 0.25 + cursor.y * 0.75
                }
            }

            let cx = 0.5 + (targetX - 0.5) * envelope
            let cy = 0.5 + (targetY - 0.5) * envelope

            return CameraState(scale: targetScale, centerX: cx, centerY: cy)
        }

        return .identity
    }

    /// Smoothly interpolates typing caret focus points at `time`.
    public static func sampleTypingFocus(at time: Double, in events: [TypingFocusEvent]) -> (x: Double, y: Double)? {
        guard !events.isEmpty else { return nil }
        if time <= events[0].time { return (events[0].x, events[0].y) }
        if time >= events[events.count - 1].time {
            let last = events[events.count - 1]
            return (last.x, last.y)
        }
        var lo = 0
        var hi = events.count - 1
        while lo + 1 < hi {
            let mid = (lo + hi) / 2
            if events[mid].time <= time { lo = mid } else { hi = mid }
        }
        let a = events[lo]
        let b = events[hi]
        let span = max(0.0001, b.time - a.time)
        let frac = smootherstep(min(max((time - a.time) / span, 0), 1))
        return (a.x + (b.x - a.x) * frac, a.y + (b.y - a.y) * frac)
    }

    /// Applies critically-damped spring smoothing to raw cursor samples for silky Screen Studio-like pointer motion.
    public static func smoothCursorSamples(
        _ rawSamples: [CursorSample],
        fps: Double = 60.0,
        smoothingHalfLife: Double = 0.045
    ) -> [CursorSample] {
        guard rawSamples.count > 1 else { return rawSamples }

        let sorted = rawSamples.sorted { $0.time < $1.time }
        guard let first = sorted.first, let last = sorted.last else { return sorted }
        let totalDur = max(0.01, last.time - first.time)
        let dt = 1.0 / max(15.0, fps)
        let steps = max(2, Int(ceil(totalDur / dt)) + 1)
        let omega = 4.0 / max(0.012, smoothingHalfLife)

        var posX = first.x
        var posY = first.y
        var velX = 0.0
        var velY = 0.0

        var result: [CursorSample] = []
        result.reserveCapacity(steps)

        var rawIdx = 0
        for step in 0..<steps {
            let t = first.time + Double(step) * dt
            while rawIdx + 1 < sorted.count && sorted[rawIdx + 1].time <= t {
                rawIdx += 1
            }

            let targetSample: CursorSample
            if rawIdx + 1 < sorted.count {
                let a = sorted[rawIdx]
                let b = sorted[rawIdx + 1]
                let span = max(0.0001, b.time - a.time)
                let frac = min(max((t - a.time) / span, 0), 1)
                targetSample = CursorSample(
                    time: t,
                    x: a.x + (b.x - a.x) * frac,
                    y: a.y + (b.y - a.y) * frac,
                    isInside: a.isInside || b.isInside,
                    isPressed: a.isPressed
                )
            } else {
                targetSample = sorted[rawIdx]
            }

            let expTerm = exp(-omega * dt)
            let dx = posX - targetSample.x
            let dy = posY - targetSample.y
            let tempX = (velX + omega * dx) * dt
            let tempY = (velY + omega * dy) * dt

            velX = (velX - omega * tempX) * expTerm
            velY = (velY - omega * tempY) * expTerm
            posX = targetSample.x + (dx + tempX) * expTerm
            posY = targetSample.y + (dy + tempY) * expTerm

            result.append(CursorSample(
                time: t,
                x: posX,
                y: posY,
                isInside: targetSample.isInside,
                isPressed: targetSample.isPressed
            ))
        }

        return result
    }

    public static func sampleCursor(at time: Double, in samples: [CursorSample]) -> CursorSample? {
        guard !samples.isEmpty else { return nil }
        if time <= samples[0].time { return samples[0] }
        if time >= samples[samples.count - 1].time { return samples[samples.count - 1] }

        var lo = 0
        var hi = samples.count - 1
        while lo + 1 < hi {
            let mid = (lo + hi) / 2
            if samples[mid].time <= time { lo = mid } else { hi = mid }
        }

        let a = samples[lo]
        let b = samples[hi]
        let span = max(0.0001, b.time - a.time)
        let frac = min(max((time - a.time) / span, 0), 1)
        return CursorSample(
            time: time,
            x: a.x + (b.x - a.x) * frac,
            y: a.y + (b.y - a.y) * frac,
            isInside: a.isInside || b.isInside,
            isPressed: a.isPressed
        )
    }

    public static func evaluateCursorState(
        at time: Double,
        smoothedSamples: [CursorSample],
        clicks: [ClickEvent],
        rippleDuration: Double = 0.48
    ) -> RenderedCursorState {
        let sample = sampleCursor(at: time, in: smoothedSamples)
        let ripples: [(x: Double, y: Double, progress: Double)] = clicks.compactMap { click in
            let elapsed = time - click.time
            guard elapsed >= 0 && elapsed <= rippleDuration else { return nil }
            return (x: click.x, y: click.y, progress: elapsed / rippleDuration)
        }

        return RenderedCursorState(
            x: sample?.x ?? 0.5,
            y: sample?.y ?? 0.5,
            isVisible: sample?.isInside ?? false,
            isPressed: sample?.isPressed ?? false,
            activeRipples: ripples
        )
    }

    /// Returns the active keystroke HUD visual (physical keycaps or live typing pill) with pop-in & fade envelope.
    public static func activeKeystroke(
        at time: Double,
        keystrokes: [KeystrokeEvent],
        filterMode: KeystrokeFilterMode = .all,
        displayDuration: Double = 1.35
    ) -> ActiveKeystrokeVisual? {
        let latest = keystrokes.last { ev in
            if filterMode == .shortcutsOnly && ev.isTypingText { return false }
            return ev.time <= time && (time - ev.time) <= displayDuration
        }
        guard let latest else { return nil }
        let elapsed = time - latest.time
        let fadeIn = min(1.0, elapsed / 0.10)
        let fadeOut = min(1.0, (displayDuration - elapsed) / 0.28)
        let popIn = latest.isTypingText ? 1.0 : (0.90 + 0.10 * smootherstep(min(1.0, elapsed / 0.14)))
        return ActiveKeystrokeVisual(
            event: latest,
            opacity: max(0, min(fadeIn, fadeOut)),
            popScale: popIn
        )
    }
}
