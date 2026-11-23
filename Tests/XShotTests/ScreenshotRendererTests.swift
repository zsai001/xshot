import AppKit
import CoreGraphics
import Foundation
import XCTest
@testable import XShot

final class ScreenshotRendererTests: XCTestCase {
    private func makeTestImage(width: Int = 800, height: Int = 500) -> CGImage {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(CGColor(srgbRed: 0.12, green: 0.16, blue: 0.24, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setFillColor(CGColor(srgbRed: 0.22, green: 0.74, blue: 0.97, alpha: 1))
        ctx.fill(CGRect(x: 80, y: 80, width: 240, height: 120))
        return ctx.makeImage()!
    }

    func testBeautifiedScreenshotWithAllAnnotationsRendersAndSavesPNG() throws {
        let raw = makeTestImage(width: 960, height: 600)
        let annotations: [AnnotationItem] = [
            AnnotationItem(tool: .arrow, start: CGPoint(x: 100, y: 120), end: CGPoint(x: 340, y: 260)),
            AnnotationItem(tool: .rectangle, start: CGPoint(x: 400, y: 100), end: CGPoint(x: 720, y: 300)),
            AnnotationItem(tool: .ellipse, start: CGPoint(x: 120, y: 320), end: CGPoint(x: 280, y: 460)),
            AnnotationItem(tool: .highlighter, start: CGPoint(x: 400, y: 360), end: CGPoint(x: 740, y: 410)),
            AnnotationItem(tool: .mosaic, start: CGPoint(x: 50, y: 40), end: CGPoint(x: 220, y: 110)),
            AnnotationItem(tool: .blur, start: CGPoint(x: 500, y: 440), end: CGPoint(x: 700, y: 520)),
            AnnotationItem(tool: .step, start: CGPoint(x: 360, y: 270), end: CGPoint(x: 360, y: 270), stepNumber: 1),
            AnnotationItem(tool: .text, start: CGPoint(x: 420, y: 140), end: CGPoint(x: 420, y: 140), text: "XShot Retina!")
        ]

        var style = BeautifyStyle.defaultScreenshot
        style.aspectRatio = .wide16x9
        style.windowChrome = .macOSDark
        style.windowTitle = "XShot Demo"

        let rendered = ScreenshotRenderer.renderScreenshot(
            rawImage: raw,
            annotations: annotations,
            style: style,
            enableBeautify: true
        )
        XCTAssertNotNil(rendered)
        guard let output = rendered else { return }

        XCTAssertGreaterThan(output.width, raw.width)
        XCTAssertGreaterThan(output.height, raw.height)
        XCTAssertEqual(Double(output.width) / Double(output.height), 16.0 / 9.0, accuracy: 0.02)

        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("xshot-test-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: tmpURL) }
        XCTAssertTrue(ExportHelpers.savePNG(output, to: tmpURL))
        let attrs = try FileManager.default.attributesOfItem(atPath: tmpURL.path)
        let size = (attrs[.size] as? Int) ?? 0
        XCTAssertGreaterThan(size, 5_000, "Saved Retina PNG should contain real image data")
    }

    func testClipboardImageReadSupportsRawPNGAndFileURLs() throws {
        let source = makeTestImage(width: 640, height: 420)
        let pb = NSPasteboard.withUniqueName()
        defer { pb.releaseGlobally() }

        // 1. Raw PNG bytes on pasteboard
        let png = try XCTUnwrap(ExportHelpers.pngData(from: source))
        pb.clearContents()
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        pb.writeObjects([item])

        let dims = ExportHelpers.pasteboardImageDimensions(pb)
        XCTAssertEqual(dims?.width, 640)
        XCTAssertEqual(dims?.height, 420)
        let decoded = ExportHelpers.readImageFromPasteboard(pb)
        XCTAssertEqual(decoded?.width, 640)
        XCTAssertEqual(decoded?.height, 420)

        // 2. Copied image file URL on pasteboard (Finder ⌘C)
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("xshot-pb-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: tmpURL) }
        XCTAssertTrue(ExportHelpers.savePNG(source, to: tmpURL))
        pb.clearContents()
        pb.writeObjects([tmpURL as NSURL])

        let fileDecoded = ExportHelpers.readImageFromPasteboard(pb)
        XCTAssertEqual(fileDecoded?.width, 640)
        XCTAssertEqual(fileDecoded?.height, 420)
    }

    func testSystemWallpaperDiscoveryAndImageBackgroundRendering() throws {
        let wallpapers = SystemWallpaperManager.shared.discoverSystemWallpapers(desktopLabel: "Desktop")
        XCTAssertFalse(wallpapers.isEmpty, "macOS should expose system or desktop wallpapers")

        let first = try XCTUnwrap(wallpapers.first)
        XCTAssertEqual(first.kind, .image)
        XCTAssertNotNil(first.imagePath)

        let raw = makeTestImage(width: 720, height: 480)
        var style = BeautifyStyle.defaultScreenshot
        style.background = first
        style.aspectRatio = .wide16x9

        let rendered = ScreenshotRenderer.renderScreenshot(
            rawImage: raw,
            annotations: [],
            style: style,
            enableBeautify: true
        )
        XCTAssertNotNil(rendered)
        XCTAssertGreaterThan(rendered?.width ?? 0, raw.width)
        XCTAssertGreaterThan(rendered?.height ?? 0, raw.height)
    }

    func testFrozenDisplayCropExtractsExactRetinaSubrect() throws {
        // Simulate a 2x Retina 2880x1800 frozen display (1440x900 points)
        let frozen = makeTestImage(width: 2880, height: 1800)
        let localRect = CGRect(x: 100, y: 200, width: 320, height: 240)
        let cropped = try XCTUnwrap(
            ScreenshotEngine.cropFrozenDisplayImage(
                frozen,
                displayLocalRect: localRect,
                displayPointsSize: CGSize(width: 1440, height: 900)
            )
        )
        XCTAssertEqual(cropped.width, 640)
        XCTAssertEqual(cropped.height, 480)
    }

    func testMultiImageLayoutModesAndCollageRendering() throws {
        let img1 = makeTestImage(width: 960, height: 600)
        let img2 = makeTestImage(width: 600, height: 800)
        let img3 = makeTestImage(width: 800, height: 500)
        let img4 = makeTestImage(width: 720, height: 720)
        let images = [img1, img2, img3, img4]

        for mode in MultiImageLayoutMode.allCases {
            for fit in MultiImageFitMode.allCases {
                let plan = MultiImageLayoutEngine.computeLayout(
                    imageSizes: images.map { CGSize(width: $0.width, height: $0.height) },
                    mode: mode,
                    spacing: 24,
                    fitMode: fit
                )
                XCTAssertEqual(plan.slots.count, 4, "All 4 images should get slots in \(mode)")
                XCTAssertGreaterThan(plan.compositeSize.width, 400)
                XCTAssertGreaterThan(plan.compositeSize.height, 400)

                // Ensure slots do not overlap each other and stay inside compositeSize
                for i in 0..<plan.slots.count {
                    let a = plan.slots[i].frame
                    XCTAssertGreaterThanOrEqual(a.minX, 0)
                    XCTAssertGreaterThanOrEqual(a.minY, 0)
                    XCTAssertLessThanOrEqual(a.maxX, plan.compositeSize.width + 1)
                    XCTAssertLessThanOrEqual(a.maxY, plan.compositeSize.height + 1)
                    for j in (i + 1)..<plan.slots.count {
                        let inter = a.intersection(plan.slots[j].frame)
                        XCTAssertTrue(inter.isNull || inter.width <= 1 || inter.height <= 1, "Slots \(i) and \(j) overlapped in \(mode)")
                    }
                }
            }
        }

        // Render full beautified 3-image Bento Hero showcase with cross-card arrow + mosaic
        let crossAnns = [
            AnnotationItem(tool: .arrow, start: CGPoint(x: 200, y: 200), end: CGPoint(x: 1000, y: 300)),
            AnnotationItem(tool: .mosaic, start: CGPoint(x: 80, y: 80), end: CGPoint(x: 240, y: 140))
        ]
        var style = BeautifyStyle.defaultScreenshot
        style.aspectRatio = .wide16x9
        let rendered = ScreenshotRenderer.renderMultiImageScreenshot(
            images: [img1, img2, img3],
            layoutMode: .bentoHero,
            spacing: 24,
            fitMode: .fill,
            annotations: crossAnns,
            style: style,
            enableBeautify: true
        )
        XCTAssertNotNil(rendered)
        XCTAssertGreaterThan(rendered?.width ?? 0, 1200)
    }

    func testMultiImageAutoCollectProgressionBakingAndCap() throws {
        let img1 = makeTestImage(width: 600, height: 400)
        let img2 = makeTestImage(width: 500, height: 500)
        let img3 = makeTestImage(width: 480, height: 720)
        let img4 = makeTestImage(width: 800, height: 450)
        let img5 = makeTestImage(width: 640, height: 480)
        let img6 = makeTestImage(width: 640, height: 480)
        let img7 = makeTestImage(width: 640, height: 480)

        let doc = ScreenshotDocument(
            rawImage: img1,
            annotations: [AnnotationItem(tool: .mosaic, start: CGPoint(x: 40, y: 40), end: CGPoint(x: 180, y: 120))],
            enableBeautify: false
        )
        XCTAssertFalse(doc.isMultiImage)
        XCTAssertEqual(doc.annotations.count, 1)

        // 1 -> 2: bakes existing single-image redactions into tile #1 and switches to horizontal
        XCTAssertTrue(doc.appendCollageImage(img2))
        XCTAssertTrue(doc.isMultiImage)
        XCTAssertEqual(doc.collageImages.count, 2)
        XCTAssertEqual(doc.collageLayout, .horizontal)
        XCTAssertTrue(doc.annotations.isEmpty, "Single-image annotations should be baked onto tile #1")
        XCTAssertTrue(doc.enableBeautify)

        // 2 -> 3: upgrades to bentoHero
        XCTAssertTrue(doc.appendCollageImage(img3))
        XCTAssertEqual(doc.collageImages.count, 3)
        XCTAssertEqual(doc.collageLayout, .bentoHero)

        // 3 -> 4: upgrades to grid2x2
        XCTAssertTrue(doc.appendCollageImage(img4))
        XCTAssertEqual(doc.collageImages.count, 4)
        XCTAssertEqual(doc.collageLayout, .grid2x2)

        // 4 -> 5 -> 6 succeed, 7th hits the 6-image cap
        XCTAssertTrue(doc.appendCollageImage(img5))
        XCTAssertTrue(doc.appendCollageImage(img6))
        XCTAssertFalse(doc.appendCollageImage(img7))
        XCTAssertEqual(doc.collageImages.count, 6)
    }

    func testMultiFilePasteboardDecodeSupportsMultipleCopiedPNGs() throws {
        let a = makeTestImage(width: 320, height: 240)
        let b = makeTestImage(width: 480, height: 360)
        let tmpA = FileManager.default.temporaryDirectory.appendingPathComponent("xshot-multi-a-\(UUID().uuidString).png")
        let tmpB = FileManager.default.temporaryDirectory.appendingPathComponent("xshot-multi-b-\(UUID().uuidString).png")
        defer {
            try? FileManager.default.removeItem(at: tmpA)
            try? FileManager.default.removeItem(at: tmpB)
        }
        XCTAssertTrue(ExportHelpers.savePNG(a, to: tmpA))
        XCTAssertTrue(ExportHelpers.savePNG(b, to: tmpB))

        let pb = NSPasteboard.withUniqueName()
        defer { pb.releaseGlobally() }
        pb.clearContents()
        pb.writeObjects([tmpA as NSURL, tmpB as NSURL])

        let decoded = ExportHelpers.readImagesFromPasteboard(pb, limit: 6)
        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(decoded[0].width, 320)
        XCTAssertEqual(decoded[1].width, 480)
    }
}
