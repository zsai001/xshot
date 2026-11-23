import AppKit
import CoreGraphics
import XCTest
@testable import XShot

final class TextExtractionEngineTests: XCTestCase {
    func testOrganizeLinesEmptyReturnsEmpty() {
        let result = TextExtractionEngine.organizeLines([])
        XCTAssertTrue(result.isEmpty)
        XCTAssertEqual(result.lineCount, 0)
        XCTAssertEqual(result.characterCount, 0)
        XCTAssertEqual(result.fullText, "")
        XCTAssertEqual(result.joinedParagraphText, "")
    }

    func testOrganizeLinesReadingOrderAndCJKParagraphJoining() {
        // Out-of-order boxes covering:
        // Row 1 (two horizontal columns on the same visual baseline)
        // Row 2 (tightly wrapped CJK line directly beneath Row 1)
        // Row 3 (blank paragraph gap below Row 2, English start)
        // Row 4 (tightly wrapped English line beneath Row 3, hyphenated continuation)
        // Row 5 (hyphen continuation target)
        let raw: [RecognizedTextLine] = [
            RecognizedTextLine(text: "文字提取", pixelRect: CGRect(x: 40, y: 80, width: 140, height: 28)),
            RecognizedTextLine(text: "截屏", pixelRect: CGRect(x: 130, y: 42, width: 70, height: 28)),
            RecognizedTextLine(text: "中文", pixelRect: CGRect(x: 40, y: 40, width: 70, height: 28)),
            RecognizedTextLine(text: "fast OCR", pixelRect: CGRect(x: 40, y: 248, width: 160, height: 26)),
            RecognizedTextLine(text: "XShot runs super-", pixelRect: CGRect(x: 40, y: 212, width: 220, height: 26))
        ]

        let result = TextExtractionEngine.organizeLines(raw)
        XCTAssertEqual(result.lineCount, 5)
        XCTAssertEqual(
            result.fullText,
            """
            中文 截屏
            文字提取
            XShot runs super-
            fast OCR
            """
        )
        XCTAssertEqual(
            result.joinedParagraphText,
            "中文 截屏文字提取\n\nXShot runs superfast OCR"
        )
        XCTAssertGreaterThan(result.characterCount, 20)
    }

    func testVisionExtractsEnglishAndChineseFromRenderedRetinaImage() async throws {
        let image = try makeSyntheticTextImage(
            size: CGSize(width: 1200, height: 480),
            lines: [
                ("XShot Retina Screenshot Studio", CGPoint(x: 70, y: 310), 46),
                ("本地文字识别测试 2026", CGPoint(x: 70, y: 150), 46)
            ]
        )

        let result = await TextExtractionEngine.extractText(from: image)
        XCTAssertFalse(result.isEmpty, "Vision OCR should extract text from crisp Retina render")
        XCTAssertGreaterThanOrEqual(result.lineCount, 2)
        XCTAssertTrue(result.fullText.contains("XShot"), "Expected 'XShot' in: \(result.fullText)")
        XCTAssertTrue(result.fullText.contains("Screenshot"), "Expected 'Screenshot' in: \(result.fullText)")
        XCTAssertTrue(
            result.fullText.contains("文字识别") || result.fullText.contains("本地"),
            "Expected Chinese text in: \(result.fullText)"
        )
        XCTAssertFalse(result.joinedParagraphText.isEmpty)

        let bounds = CGRect(x: 0, y: 0, width: 1200, height: 480)
        for line in result.lines {
            XCTAssertGreaterThan(line.pixelRect.width, 0)
            XCTAssertGreaterThan(line.pixelRect.height, 0)
            XCTAssertTrue(bounds.contains(CGPoint(x: line.pixelRect.midX, y: line.pixelRect.midY)))
        }
    }

    private func makeSyntheticTextImage(
        size: CGSize,
        lines: [(text: String, origin: CGPoint, fontSize: CGFloat)]
    ) throws -> CGImage {
        let width = Int(size.width)
        let height = Int(size.height)
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw XCTSkip("Unable to create CGContext for OCR test fixture")
        }

        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(origin: .zero, size: size))

        let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsCtx
        for item in lines {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: item.fontSize, weight: .semibold),
                .foregroundColor: NSColor.black
            ]
            NSAttributedString(string: item.text, attributes: attrs).draw(at: item.origin)
        }
        NSGraphicsContext.restoreGraphicsState()

        guard let cg = ctx.makeImage() else {
            throw XCTSkip("Unable to materialize CGImage for OCR test fixture")
        }
        return cg
    }
}
