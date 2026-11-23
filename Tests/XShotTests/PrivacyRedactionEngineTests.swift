import AppKit
import CoreGraphics
import XCTest
@testable import XShot

final class PrivacyRedactionEngineTests: XCTestCase {
    func testTextMatchersDetectAllCategoriesWithZeroFalsePositives() {
        let sample = """
        OPENAI_API_KEY=sk-proj-9f8e7d6c5b4a3210abcdef123456
        GITHUB_TOKEN=ghp_1234567890abcdef1234567890abcd
        AWS_KEY=AKIAIOSFODNN7EXAMPLE
        Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U
        db_password = "MySuperSecret99!"
        placeholder_password = changeme
        Contact: alice.founder@xshot.dev
        Phone CN: +86 138 1234 5678
        Phone US: (415) 555-0199
        Date: 2026-11-21
        Server: 192.168.1.42 and local 127.0.0.1
        Card: 4532 0151 1283 0366
        FakeDigits: 1111 2222 3333 4444
        ID: 11010519900307123X
        """

        let matches = PrivacyRedactionEngine.detectMatches(in: sample)
        let texts = Set(matches.map(\.matchedText))
        let categories = Set(matches.map(\.category))

        XCTAssertTrue(categories.contains(.apiKey))
        XCTAssertTrue(categories.contains(.email))
        XCTAssertTrue(categories.contains(.phone))
        XCTAssertTrue(categories.contains(.financialOrID))
        XCTAssertTrue(categories.contains(.ipAddress))

        XCTAssertTrue(texts.contains("sk-proj-9f8e7d6c5b4a3210abcdef123456"))
        XCTAssertTrue(texts.contains("ghp_1234567890abcdef1234567890abcd"))
        XCTAssertTrue(texts.contains("AKIAIOSFODNN7EXAMPLE"))
        XCTAssertTrue(texts.contains("MySuperSecret99!"))
        XCTAssertTrue(texts.contains("alice.founder@xshot.dev"))
        XCTAssertTrue(texts.contains("192.168.1.42"))
        XCTAssertTrue(texts.contains("4532 0151 1283 0366"))
        XCTAssertTrue(texts.contains("11010519900307123X"))

        // Verify false-positive guards!
        XCTAssertFalse(texts.contains("changeme"))
        XCTAssertFalse(texts.contains("127.0.0.1"))
        XCTAssertFalse(texts.contains("2026-11-21"))
        XCTAssertFalse(texts.contains("1111 2222 3333 4444"))
    }

    func testCategoryFilteringRespectsEnabledSet() {
        let line = "email=dev@xshot.app ip=10.0.0.8 key=sk-proj-abcdef1234567890xyz"
        let emailOnly = PrivacyRedactionEngine.detectMatches(in: line, enabledCategories: [.email])
        XCTAssertEqual(emailOnly.count, 1)
        XCTAssertEqual(emailOnly.first?.category, .email)
        XCTAssertEqual(emailOnly.first?.matchedText, "dev@xshot.app")
    }

    func testOnDeviceAppleVisionOCRDetectsAndRedactsSecretsInImage() async throws {
        // Render a crisp synthetic terminal screenshot containing sensitive lines
        let w = 1400
        let h = 620
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            XCTFail("Failed to allocate CGContext")
            return
        }

        ctx.setFillColor(CGColor(srgbRed: 0.08, green: 0.10, blue: 0.14, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))

        let lines = [
            "OPENAI_API_KEY=sk-proj-9f8e7d6c5b4a3210abcdef1234",
            "USER_EMAIL=founder@xshot.dev",
            "MOBILE=13812345678",
            "PROD_HOST=192.168.10.88"
        ]

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 34, weight: .semibold),
            .foregroundColor: NSColor.white
        ]

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        for (i, line) in lines.enumerated() {
            let y = CGFloat(h - 120 - i * 110)
            NSAttributedString(string: line, attributes: attrs).draw(at: CGPoint(x: 70, y: y))
        }
        NSGraphicsContext.restoreGraphicsState()

        let cgImage = try XCTUnwrap(ctx.makeImage())
        let findings = await PrivacyRedactionEngine.detectSensitiveRegions(in: cgImage)

        XCTAssertGreaterThanOrEqual(findings.count, 3, "Vision OCR should detect API key, email, phone, and IP")
        let detectedCats = Set(findings.map(\.category))
        XCTAssertTrue(detectedCats.contains(.apiKey), "Expected API key detection")
        XCTAssertTrue(detectedCats.contains(.email), "Expected email detection")
        XCTAssertTrue(detectedCats.contains(.ipAddress), "Expected IP detection")

        for f in findings {
            XCTAssertGreaterThan(f.pixelRect.width, 20)
            XCTAssertGreaterThan(f.pixelRect.height, 12)
            XCTAssertGreaterThanOrEqual(f.pixelRect.minX, 0)
            XCTAssertLessThanOrEqual(f.pixelRect.maxX, CGFloat(w))
            XCTAssertGreaterThanOrEqual(f.pixelRect.minY, 0)
            XCTAssertLessThanOrEqual(f.pixelRect.maxY, CGFloat(h))
        }

        // Verify mosaic annotations generated from findings render cleanly through ScreenshotRenderer
        let anns = findings.map { $0.makeAnnotation(style: .mosaic) }
        let redacted = ScreenshotRenderer.renderScreenshot(
            rawImage: cgImage,
            annotations: anns,
            style: .defaultScreenshot,
            enableBeautify: true
        )
        XCTAssertNotNil(redacted)
    }
}
