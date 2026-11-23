import CoreGraphics
import XCTest
@testable import XShot

final class AutoZoomEngineTests: XCTestCase {
    func testCoordinateConversionsRoundTrip() {
        let primaryH: CGFloat = 1080
        let appKitRect = CGRect(x: 100, y: 200, width: 400, height: 300)
        let quartzRect = CoordinateConverter.appKitToQuartz(appKitRect, primaryHeight: primaryH)
        XCTAssertEqual(quartzRect, CGRect(x: 100, y: 580, width: 400, height: 300))

        let roundTripped = CoordinateConverter.quartzToAppKit(quartzRect, primaryHeight: primaryH)
        XCTAssertEqual(roundTripped, appKitRect)

        // Even pixel dimension rounding for H.264/HEVC encoders
        XCTAssertEqual(CoordinateConverter.evenPixelDimension(1919.2), 1920)
        XCTAssertEqual(CoordinateConverter.evenPixelDimension(1080.0), 1080)
        XCTAssertEqual(CoordinateConverter.evenPixelDimension(1.0), 2)
    }

    func testCanvasLayout16x9ProducesEvenDimensions() {
        let style = BeautifyStyle(
            background: .defaultVideo,
            padding: 60,
            cornerRadius: 20,
            shadowRadius: 36,
            shadowOpacity: 0.5,
            aspectRatio: .wide16x9,
            windowChrome: .macOSDark
        )
        let layout = CoordinateConverter.computeCanvasLayout(
            sourceSize: CGSize(width: 1441, height: 901),
            style: style,
            maxLongEdge: 1920,
            evenDimensions: true
        )
        XCTAssertEqual(Int(layout.canvasSize.width) % 2, 0)
        XCTAssertEqual(Int(layout.canvasSize.height) % 2, 0)
        XCTAssertLessThanOrEqual(Int(max(layout.canvasSize.width, layout.canvasSize.height)), 1920)
        XCTAssertGreaterThan(layout.chromeHeight, 0)
        XCTAssertTrue(layout.contentRect.minX >= 0 && layout.contentRect.minY >= 0)
    }

    func testAutoZoomClustersClicksCleanly() {
        let clicks = [
            ClickEvent(time: 1.0, x: 0.25, y: 0.30),
            ClickEvent(time: 1.8, x: 0.35, y: 0.32),
            ClickEvent(time: 6.5, x: 0.80, y: 0.75)
        ]
        let segments = AutoZoomEngine.generateAutoZoomSegments(clicks: clicks, duration: 10.0, defaultScale: 1.8)
        XCTAssertEqual(segments.count, 2)
        XCTAssertLessThan(segments[0].startTime, 1.0)
        XCTAssertGreaterThan(segments[0].endTime, 1.8)
        XCTAssertEqual(segments[0].focusX, 0.30, accuracy: 0.01)
        XCTAssertGreaterThan(segments[1].startTime, segments[0].endTime)
    }

    func testCameraCropAlwaysStaysWithinSourceBounds() {
        let camera = CameraState(scale: 2.2, centerX: 0.02, centerY: 0.98)
        let source = CGSize(width: 1920, height: 1080)
        let crop = camera.sourceCropRect(for: source)
        XCTAssertGreaterThanOrEqual(crop.minX, 0)
        XCTAssertGreaterThanOrEqual(crop.minY, 0)
        XCTAssertLessThanOrEqual(crop.maxX, source.width + 0.01)
        XCTAssertLessThanOrEqual(crop.maxY, source.height + 0.01)
        XCTAssertEqual(crop.width, source.width / 2.2, accuracy: 0.5)
    }

    func testSmoothCursorReducesJitter() {
        var raw: [CursorSample] = []
        for i in 0...60 {
            let t = Double(i) / 60.0
            let jitter = (i % 2 == 0) ? 0.015 : -0.015
            raw.append(CursorSample(time: t, x: 0.5 + jitter, y: 0.5))
        }
        let smoothed = AutoZoomEngine.smoothCursorSamples(raw, fps: 60.0)
        XCTAssertGreaterThan(smoothed.count, 50)
        let midDeviations = smoothed.dropFirst(15).map { abs($0.x - 0.5) }
        let maxDev = midDeviations.max() ?? 1.0
        XCTAssertLessThan(maxDev, 0.012, "Spring smoothing should dampen high-frequency cursor jitter")
    }

    func testTypingInputFocusGeneratesZoomAndFollowsMovingCaret() {
        let typingEvents = [
            TypingFocusEvent(time: 2.0, x: 0.25, y: 0.40, hasExactFocusBounds: true),
            TypingFocusEvent(time: 2.6, x: 0.40, y: 0.40, hasExactFocusBounds: true),
            TypingFocusEvent(time: 3.2, x: 0.58, y: 0.40, hasExactFocusBounds: true)
        ]

        let segments = AutoZoomEngine.generateAutoZoomSegments(
            clicks: [],
            typingEvents: typingEvents,
            includeClicks: true,
            includeTypingFocus: true,
            duration: 8.0
        )

        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].triggerKind, .typing)
        XCTAssertGreaterThan(segments[0].scale, 1.5)

        let earlyCam = AutoZoomEngine.evaluateCamera(
            at: 2.1,
            segments: segments,
            smoothedCursorPath: [],
            typingFocusEvents: typingEvents,
            enabled: true
        )
        let lateCam = AutoZoomEngine.evaluateCamera(
            at: 3.1,
            segments: segments,
            smoothedCursorPath: [],
            typingFocusEvents: typingEvents,
            enabled: true
        )
        XCTAssertGreaterThan(earlyCam.scale, 1.4)
        XCTAssertGreaterThan(lateCam.centerX, earlyCam.centerX + 0.1, "Camera should smoothly pan right as typing caret advances")
    }

    func testActiveKeystrokeReturnsPhysicalKeycapsAndPopEnvelope() {
        let events = [
            KeystrokeEvent(time: 1.0, text: "⌘⇧P", keycaps: ["⌘", "⇧", "P"], isTypingText: false),
            KeystrokeEvent(time: 3.0, text: "hello xshot", keycaps: ["hello xshot"], isTypingText: true)
        ]
        let shortcut = AutoZoomEngine.activeKeystroke(at: 1.15, keystrokes: events)
        XCTAssertNotNil(shortcut)
        XCTAssertEqual(shortcut?.event.keycaps, ["⌘", "⇧", "P"])
        XCTAssertFalse(shortcut?.event.isTypingText ?? true)
        XCTAssertGreaterThan(shortcut?.opacity ?? 0, 0.9)

        let typing = AutoZoomEngine.activeKeystroke(at: 3.2, keystrokes: events)
        XCTAssertNotNil(typing)
        XCTAssertEqual(typing?.event.text, "hello xshot")
        XCTAssertTrue(typing?.event.isTypingText ?? false)
    }
}
