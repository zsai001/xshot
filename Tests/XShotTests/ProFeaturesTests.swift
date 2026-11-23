import AppKit
import Carbon
import CoreGraphics
import XCTest
@testable import XShot

final class ProFeaturesTests: XCTestCase {
    // MARK: - 1. Customizable Global Hotkeys

    func testHotKeyManagerPersistenceConflictDetectionAndReset() {
        let suiteName = "top.xtags.xshot.tests.hotkeys.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let manager = HotKeyManager(userDefaults: defaults, storageKey: "test.hotkeys", registerWithSystem: false)
        XCTAssertFalse(manager.hasAnyCustomization)
        XCTAssertEqual(manager.label(for: .captureArea), "⇧⌘2")
        XCTAssertEqual(manager.label(for: .captureScroll), "⇧⌘5")

        // Bare letter without primary modifier is rejected; Function keys and Cmd/Opt/Ctrl combos are accepted
        XCTAssertNil(HotKeyBinding.from(keyCode: UInt16(kVK_ANSI_A), modifierFlags: []))
        XCTAssertNil(HotKeyBinding.from(keyCode: UInt16(kVK_ANSI_A), modifierFlags: [.shift]))
        XCTAssertNotNil(HotKeyBinding.from(keyCode: UInt16(kVK_F8), modifierFlags: []))

        let customBinding = HotKeyBinding(
            keyCode: UInt32(kVK_ANSI_K),
            carbonModifiers: UInt32(controlKey | optionKey)
        )
        XCTAssertEqual(customBinding.displayLabel, "⌃⌥K")

        let updateRes = manager.updateBinding(customBinding, for: .captureScroll)
        XCTAssertEqual(updateRes, .updated(customBinding))
        XCTAssertTrue(manager.isCustomized(.captureScroll))
        XCTAssertTrue(manager.hasAnyCustomization)
        XCTAssertEqual(manager.label(for: .captureScroll), "⌃⌥K")

        // Conflict detection prevents binding the exact same chord to another action
        let conflictRes = manager.updateBinding(customBinding, for: .extractTextArea)
        XCTAssertEqual(conflictRes, .conflict(.captureScroll))

        // Reloading from UserDefaults preserves custom shortcut
        let reloaded = HotKeyManager(userDefaults: defaults, storageKey: "test.hotkeys", registerWithSystem: false)
        XCTAssertEqual(reloaded.binding(for: .captureScroll), customBinding)
        XCTAssertEqual(reloaded.label(for: .captureScroll), "⌃⌥K")

        // Reset restores defaults cleanly
        reloaded.resetAllToDefaults()
        XCTAssertFalse(reloaded.hasAnyCustomization)
        XCTAssertEqual(reloaded.label(for: .captureScroll), "⇧⌘5")
    }

    // MARK: - 2. Custom Watermark Signature Rendering

    func testWatermarkRendersOnRawBeautifiedAndTiledScreenshots() throws {
        let base = try makeSolidImage(width: 960, height: 600, r: 0.08, g: 0.10, b: 0.14)

        var style = BeautifyStyle.defaultScreenshot
        style.watermark = WatermarkConfig(
            enabled: true,
            text: "@XShotStudio",
            position: .bottomRight,
            visualStyle: .badgeAccent,
            opacity: 0.95,
            scale: 1.2,
            showBrandGlyph: true
        )

        // Works even when Beautify shell is disabled
        let rawWithWatermark = ScreenshotRenderer.renderScreenshot(
            rawImage: base,
            annotations: [],
            style: style,
            enableBeautify: false
        )
        XCTAssertNotNil(rawWithWatermark)
        if let rawWM = rawWithWatermark {
            XCTAssertEqual(rawWM.width, 960)
            XCTAssertEqual(rawWM.height, 600)
            let brEnergy = try meanPixelDelta(from: base, to: rawWM, regionTopLeft: CGRect(x: 680, y: 500, width: 270, height: 95))
            let tlEnergy = try meanPixelDelta(from: base, to: rawWM, regionTopLeft: CGRect(x: 10, y: 10, width: 200, height: 90))
            XCTAssertGreaterThan(brEnergy, 3.0, "Bottom-right badge watermark should visibly draw in bottom-right region")
            XCTAssertLessThan(tlEnergy, 0.5, "Top-left corner should remain untouched for bottom-right watermark")
        }

        // Works with diagonal tiled anti-theft pattern
        style.watermark.position = .tiled
        let tiled = ScreenshotRenderer.renderScreenshot(
            rawImage: base,
            annotations: [],
            style: style,
            enableBeautify: false
        )
        XCTAssertNotNil(tiled)
        if let tiled {
            let centerEnergy = try meanPixelDelta(from: base, to: tiled, regionTopLeft: CGRect(x: 200, y: 150, width: 560, height: 300))
            XCTAssertGreaterThan(centerEnergy, 0.5, "Tiled watermark should visibly cover canvas center")
        }

        // Works with Beautify shell enabled
        style.watermark.position = .bottomLeft
        let beautified = ScreenshotRenderer.renderScreenshot(
            rawImage: base,
            annotations: [],
            style: style,
            enableBeautify: true
        )
        XCTAssertNotNil(beautified)
        XCTAssertGreaterThan(beautified?.width ?? 0, 960)
    }

    // MARK: - 3. Scrolling Long-Screenshot Stitcher

    func testScrollingStitcherExactPixelAlignmentStickyHeaderAndUndo() throws {
        // Build a richly textured 420x1100 document with varied bands and distinct horizontal text rows
        let masterDoc = try makeScrollableDocumentImage(width: 420, height: 1100)
        let viewportH = 420
        let stickyHeaderH = 44
        let stickyFooterH = 36

        let frame0 = try makeViewportFrame(from: masterDoc, scrollOffset: 0, viewportHeight: viewportH, stickyHeader: stickyHeaderH, stickyFooter: stickyFooterH)
        let frame1 = try makeViewportFrame(from: masterDoc, scrollOffset: 140, viewportHeight: viewportH, stickyHeader: stickyHeaderH, stickyFooter: stickyFooterH)
        let frame2 = try makeViewportFrame(from: masterDoc, scrollOffset: 300, viewportHeight: viewportH, stickyHeader: stickyHeaderH, stickyFooter: stickyFooterH)

        let engine = ScrollingStitcherEngine(initialFrame: frame0)
        XCTAssertEqual(engine.stitchedImage.height, viewportH)
        XCTAssertEqual(engine.frameCount, 1)
        XCTAssertFalse(engine.canUndo)

        // Identical frame should be ignored cleanly
        let sameOutcome = engine.stitchNextFrame(frame0)
        if case .unchanged = sameOutcome {
            // expected
        } else {
            XCTFail("Expected stationary frame to return .unchanged, got \(sameOutcome)")
        }

        // Scroll +140px
        let out1 = engine.stitchNextFrame(frame1)
        switch out1 {
        case .stitched(let delta, let totalH, let header, let footer):
            XCTAssertLessThanOrEqual(abs(delta - 140), 2, "Expected scroll delta ~140px, got \(delta)")
            XCTAssertGreaterThanOrEqual(header, 36, "Expected sticky header detection")
            XCTAssertGreaterThanOrEqual(footer, 28, "Expected sticky footer detection")
            XCTAssertLessThanOrEqual(abs(totalH - (viewportH + 140)), 4, "Total height should be ~560 without duplicating sticky bars")
        default:
            XCTFail("Expected .stitched for +140px scroll, got \(out1)")
        }
        XCTAssertEqual(engine.frameCount, 2)
        XCTAssertTrue(engine.canUndo)
        let heightAfterFrame1 = engine.stitchedImage.height

        // Scroll another +160px (total offset 300px)
        let out2 = engine.stitchNextFrame(frame2)
        switch out2 {
        case .stitched(let delta, let totalH, _, _):
            XCTAssertLessThanOrEqual(abs(delta - 160), 2, "Expected scroll delta ~160px, got \(delta)")
            XCTAssertLessThanOrEqual(abs(totalH - (viewportH + 300)), 6, "Total height should be ~720")
        default:
            XCTFail("Expected .stitched for +160px scroll, got \(out2)")
        }
        XCTAssertEqual(engine.frameCount, 3)

        // Undo restores exact prior stitched frame
        XCTAssertTrue(engine.undoLastStitch())
        XCTAssertEqual(engine.frameCount, 2)
        XCTAssertEqual(engine.stitchedImage.height, heightAfterFrame1)
    }

    // MARK: - 4. Webcam Picture-in-Picture Geometry & Metal GPU Compositing

    func testWebcamPiPGeometryAndMetalCompositeWithWatermark() throws {
        let canvas = CGSize(width: 1280, height: 720)
        let bounds = CGRect(origin: .zero, size: canvas)

        for shape in WebcamPiPShape.allCases {
            for corner in WebcamPiPCorner.allCases {
                let cfg = WebcamPiPConfig(enabled: true, shape: shape, corner: corner, sizeFraction: 0.24, mirrored: true, showBorder: true)
                let rect = cfg.frameRectCI(in: canvas)
                XCTAssertTrue(bounds.contains(rect), "PiP rect \(rect) must fit inside canvas \(bounds)")
                XCTAssertGreaterThan(rect.width, 60)
                XCTAssertGreaterThan(rect.height, 60)
            }
        }

        // Verify live GPU preview compositor blends webcam bubble + watermark visibly onto the canvas!
        let screenFrame = try makeSolidImage(width: 960, height: 540, r: 0.08, g: 0.12, b: 0.20)
        let camFrame = try makeSolidImage(width: 640, height: 360, r: 0.96, g: 0.20, b: 0.62)

        var style = BeautifyStyle.defaultVideo
        style.watermark = WatermarkConfig(enabled: true, text: "@XShotCam", position: .bottomRight, visualStyle: .glassPill)

        var optsNoCam = VideoCompositeOptions(style: style, trimStart: 0, trimEnd: 1.0)
        optsNoCam.webcamPiP = WebcamPiPConfig(enabled: false)

        var optsWithCam = VideoCompositeOptions(style: style, trimStart: 0, trimEnd: 1.0)
        optsWithCam.webcamPiP = WebcamPiPConfig(enabled: true, shape: .circle, corner: .bottomLeft, sizeFraction: 0.24, mirrored: true, showBorder: true)

        let exporter = VideoCompositorExporter()
        guard let withoutCam = exporter.renderPreviewFrame(
            sourceCGImage: screenFrame,
            time: 0.2,
            options: optsNoCam,
            smoothedCursorPath: [],
            maxPreviewEdge: 960,
            webcamCGImage: nil
        ), let withCam = exporter.renderPreviewFrame(
            sourceCGImage: screenFrame,
            time: 0.2,
            options: optsWithCam,
            smoothedCursorPath: [],
            maxPreviewEdge: 960,
            webcamCGImage: camFrame
        ) else {
            XCTFail("Preview frame rendering failed")
            return
        }

        XCTAssertEqual(withoutCam.width, withCam.width)
        XCTAssertEqual(withoutCam.height, withCam.height)

        // Bottom-left region (top-left Y near canvas height) must show strong magenta webcam delta
        let pipRectCI = optsWithCam.webcamPiP.frameRectCI(in: CGSize(width: withCam.width, height: withCam.height))
        let pipRectTopLeft = CGRect(
            x: pipRectCI.minX,
            y: CGFloat(withCam.height) - pipRectCI.maxY,
            width: pipRectCI.width,
            height: pipRectCI.height
        )
        let blDelta = try meanPixelDelta(from: withoutCam, to: withCam, regionTopLeft: pipRectTopLeft)
        let trDelta = try meanPixelDelta(from: withoutCam, to: withCam, regionTopLeft: CGRect(x: CGFloat(withCam.width) - 120, y: 10, width: 100, height: 100))

        XCTAssertGreaterThan(blDelta, 35.0, "Webcam PiP bubble should composite brightly into bottom-left corner")
        XCTAssertLessThan(trDelta, 1.0, "Opposite top-right corner should remain unaffected by bottom-left PiP")
    }

    // MARK: - 5. Multi-Mode Editor Canvas Viewport (Long Screenshot Readability)

    func testCanvasViewportModesForNormalAndLongScreenshots() {
        let viewport = CGSize(width: 840, height: 660)
        let normalCanvas = CGSize(width: 1600, height: 1000)
        let longCanvas = CGSize(width: 1400, height: 6400)

        XCTAssertEqual(CanvasViewportCalculator.recommendedInitialMode(for: normalCanvas), .fitScreen)
        XCTAssertEqual(CanvasViewportCalculator.recommendedInitialMode(for: longCanvas), .fitWidth)

        let longFit = CanvasViewportCalculator.computeLayout(
            canvasPixelSize: longCanvas,
            viewportSize: viewport,
            mode: .fitScreen,
            customZoom: 1.0,
            screenBackingScale: 2.0
        )
        let longFitWidth = CanvasViewportCalculator.computeLayout(
            canvasPixelSize: longCanvas,
            viewportSize: viewport,
            mode: .fitWidth,
            customZoom: 1.0,
            screenBackingScale: 2.0
        )
        let longActual = CanvasViewportCalculator.computeLayout(
            canvasPixelSize: longCanvas,
            viewportSize: viewport,
            mode: .actualSize,
            customZoom: 1.0,
            screenBackingScale: 2.0
        )
        let longZoomed200 = CanvasViewportCalculator.computeLayout(
            canvasPixelSize: longCanvas,
            viewportSize: viewport,
            mode: .custom,
            customZoom: 2.0,
            screenBackingScale: 2.0
        )

        // Fit Screen shrinks the 6400px tall screenshot down to fit inside 660pt height (no scroll)
        XCTAssertFalse(longFit.needsScroll)
        XCTAssertLessThan(longFit.canvasRect.width, 160)

        // Fit Width makes the same long screenshot span the full comfortable width (~784pt) and scroll smoothly!
        XCTAssertTrue(longFitWidth.needsScroll)
        XCTAssertGreaterThan(longFitWidth.canvasRect.width, 750)
        XCTAssertGreaterThan(longFitWidth.documentSize.height, 3000)
        XCTAssertGreaterThan(longFitWidth.displayScale, longFit.displayScale * 4.0)

        // 1:1 Retina Actual Size renders at exact 100% (1400px / 2x = 700pt)
        XCTAssertEqual(longActual.zoomPercentage, 100)
        XCTAssertEqual(longActual.canvasRect.width, 700, accuracy: 1.0)
        XCTAssertEqual(longActual.canvasRect.height, 3200, accuracy: 1.0)
        XCTAssertTrue(longActual.needsScroll)

        // Custom 200% zoom doubles 1:1 scale & requires both H/V scrolling
        XCTAssertEqual(longZoomed200.zoomPercentage, 200)
        XCTAssertEqual(longZoomed200.canvasRect.width, 1400, accuracy: 1.0)
        XCTAssertTrue(longZoomed200.needsScroll)

        // Stepped zoom progression
        XCTAssertEqual(CanvasViewportCalculator.steppedZoom(from: 1.0, zoomIn: true), 1.25)
        XCTAssertEqual(CanvasViewportCalculator.steppedZoom(from: 1.0, zoomIn: false), 0.75)
    }

    // MARK: - Helpers

    private func makeSolidImage(width: Int, height: Int, r: CGFloat, g: CGFloat, b: CGFloat) throws -> CGImage {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw XCTSkip("CGContext failed") }
        ctx.setFillColor(CGColor(srgbRed: r, green: g, blue: b, alpha: 1.0))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let cg = ctx.makeImage() else { throw XCTSkip("makeImage failed") }
        return cg
    }

    private func makeScrollableDocumentImage(width: Int, height: Int) throws -> CGImage {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw XCTSkip("CGContext failed") }
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // Draw unique non-repeating cards & labels every 48px down the tall canvas (top-left flipped)
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)

        for idx in 0..<(height / 48) {
            let y = CGFloat(idx * 48)
            let hue = CGFloat((idx * 37) % 360) / 360.0
            let barW = CGFloat(120 + ((idx * 53) % 240))
            ctx.setFillColor(NSColor(calibratedHue: hue, saturation: 0.65, brightness: 0.85, alpha: 1.0).cgColor)
            ctx.fill(CGRect(x: 24 + CGFloat((idx * 19) % 40), y: y + 8, width: barW, height: 22))

            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .bold),
                .foregroundColor: NSColor.black
            ]
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
            NSAttributedString(string: "Row #\(idx) — XShot Scroll Item \(idx * 17)", attributes: attrs)
                .draw(at: CGPoint(x: 30, y: y + 10))
            NSGraphicsContext.restoreGraphicsState()
        }

        guard let cg = ctx.makeImage() else { throw XCTSkip("makeImage failed") }
        return cg
    }

    private func makeViewportFrame(
        from master: CGImage,
        scrollOffset: Int,
        viewportHeight: Int,
        stickyHeader: Int,
        stickyFooter: Int
    ) throws -> CGImage {
        let w = master.width
        let bodyH = viewportHeight - stickyHeader - stickyFooter
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(
            data: nil, width: w, height: viewportHeight, bitsPerComponent: 8, bytesPerRow: 0,
            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw XCTSkip("CGContext failed") }

        // Body slice from master[scrollOffset ..< scrollOffset + bodyH]
        let cropRect = CGRect(x: 0, y: scrollOffset, width: w, height: bodyH)
        if let bodySlice = master.cropping(to: cropRect) {
            ctx.draw(bodySlice, in: CGRect(x: 0, y: stickyFooter, width: w, height: bodyH))
        }

        // Fixed sticky header at top (bottom-left CG y = viewportHeight - stickyHeader)
        ctx.setFillColor(CGColor(srgbRed: 0.12, green: 0.15, blue: 0.22, alpha: 1.0))
        ctx.fill(CGRect(x: 0, y: viewportHeight - stickyHeader, width: w, height: stickyHeader))

        // Fixed sticky footer at bottom (bottom-left CG y = 0)
        ctx.setFillColor(CGColor(srgbRed: 0.16, green: 0.18, blue: 0.25, alpha: 1.0))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: stickyFooter))

        guard let cg = ctx.makeImage() else { throw XCTSkip("makeImage failed") }
        return cg
    }

    private func meanPixelDelta(from a: CGImage, to b: CGImage, regionTopLeft: CGRect) throws -> Double {
        let clamped = regionTopLeft.integral.intersection(CGRect(x: 0, y: 0, width: min(a.width, b.width), height: min(a.height, b.height)))
        guard !clamped.isEmpty,
              let ca = a.cropping(to: clamped),
              let cb = b.cropping(to: clamped) else {
            throw XCTSkip("Invalid comparison crop")
        }
        let w = ca.width
        let h = ca.height
        let bytesA = try rgbaBytes(of: ca)
        let bytesB = try rgbaBytes(of: cb)
        var sum = 0
        for i in 0..<(w * h * 4) where i % 4 != 3 {
            sum += abs(Int(bytesA[i]) - Int(bytesB[i]))
        }
        return Double(sum) / Double(max(1, w * h * 3))
    }

    private func rgbaBytes(of image: CGImage) throws -> [UInt8] {
        let w = image.width
        let h = image.height
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ok = buf.withUnsafeMutableBytes { ptr -> Bool in
            guard let base = ptr.baseAddress,
                  let ctx = CGContext(
                      data: base, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                      space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { throw XCTSkip("Failed reading RGBA bytes") }
        return buf
    }
}
