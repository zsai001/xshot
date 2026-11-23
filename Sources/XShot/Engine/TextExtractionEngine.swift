import CoreGraphics
import Foundation
import Vision

public struct RecognizedTextLine: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let text: String
    public let confidence: Float
    /// Bounding box in top-left image pixel space (`0...imageWidth`, `0...imageHeight`).
    public let pixelRect: CGRect

    public init(
        id: UUID = UUID(),
        text: String,
        confidence: Float = 1.0,
        pixelRect: CGRect
    ) {
        self.id = id
        self.text = text
        self.confidence = confidence
        self.pixelRect = pixelRect
    }
}

public struct TextExtractionResult: Equatable, Sendable {
    public let lines: [RecognizedTextLine]
    public let fullText: String
    public let joinedParagraphText: String

    public init(lines: [RecognizedTextLine], fullText: String, joinedParagraphText: String) {
        self.lines = lines
        self.fullText = fullText
        self.joinedParagraphText = joinedParagraphText
    }

    public static let empty = TextExtractionResult(lines: [], fullText: "", joinedParagraphText: "")

    public var isEmpty: Bool { lines.isEmpty || fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    public var lineCount: Int { lines.count }
    public var characterCount: Int { fullText.filter { !$0.isWhitespace && !$0.isNewline }.count }
}

/// 100% on-device Apple Vision OCR engine supporting Chinese, English, Japanese, Korean, and European scripts.
/// Preserves natural visual lines and builds clean joined paragraphs with CJK-aware spacing.
public enum TextExtractionEngine {
    public static func extractText(from cgImage: CGImage) async -> TextExtractionResult {
        await Task.detached(priority: .userInitiated) {
            extractTextSync(from: cgImage)
        }.value
    }

    public static func extractTextSync(from cgImage: CGImage) -> TextExtractionResult {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        request.recognitionLanguages = [
            "zh-Hans", "zh-Hant", "en-US", "ja-JP", "ko-KR",
            "es-ES", "fr-FR", "de-DE", "pt-BR", "ru-RU"
        ]
        request.minimumTextHeight = 0.008

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return .empty
        }

        guard let observations = request.results, !observations.isEmpty else {
            return .empty
        }

        let imgW = CGFloat(cgImage.width)
        let imgH = CGFloat(cgImage.height)
        let bounds = CGRect(x: 0, y: 0, width: imgW, height: imgH)

        var rawLines: [RecognizedTextLine] = []
        rawLines.reserveCapacity(observations.count)

        for obs in observations {
            guard let candidate = obs.topCandidates(1).first else { continue }
            let trimmed = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let box = obs.boundingBox
            let pxRect = CGRect(
                x: box.minX * imgW,
                y: (1.0 - box.maxY) * imgH,
                width: box.width * imgW,
                height: box.height * imgH
            ).intersection(bounds)

            guard !pxRect.isNull, pxRect.width >= 2, pxRect.height >= 2 else { continue }
            rawLines.append(RecognizedTextLine(
                text: trimmed,
                confidence: candidate.confidence,
                pixelRect: pxRect
            ))
        }

        return organizeLines(rawLines)
    }

    /// Pure reading-order sorter & paragraph builder (groups horizontal columns on the same visual row,
    /// orders rows top-to-bottom, and joins wrapped paragraphs with CJK-aware spacing).
    public static func organizeLines(_ rawLines: [RecognizedTextLine]) -> TextExtractionResult {
        guard !rawLines.isEmpty else { return .empty }

        // Sort top-to-bottom first
        let byTop = rawLines.sorted { a, b in
            if abs(a.pixelRect.midY - b.pixelRect.midY) > min(a.pixelRect.height, b.pixelRect.height) * 0.50 {
                return a.pixelRect.midY < b.pixelRect.midY
            }
            return a.pixelRect.minX < b.pixelRect.minX
        }

        // Cluster into visual rows sharing baseline overlap
        var rows: [[RecognizedTextLine]] = []
        for item in byTop {
            if let lastRow = rows.last, let anchor = lastRow.first {
                let tol = max(6.0, min(anchor.pixelRect.height, item.pixelRect.height) * 0.55)
                if abs(item.pixelRect.midY - anchor.pixelRect.midY) <= tol {
                    rows[rows.count - 1].append(item)
                    continue
                }
            }
            rows.append([item])
        }

        var orderedLines: [RecognizedTextLine] = []
        var rowTexts: [(text: String, rect: CGRect)] = []

        for var row in rows {
            row.sort { $0.pixelRect.minX < $1.pixelRect.minX }
            orderedLines.append(contentsOf: row)

            let combinedRowText = row.map(\.text).joined(separator: " ")
            let unionRect = row.reduce(row[0].pixelRect) { $0.union($1.pixelRect) }
            rowTexts.append((combinedRowText, unionRect))
        }

        let fullText = rowTexts.map(\.text).joined(separator: "\n")
        let joinedParagraph = buildJoinedParagraphs(from: rowTexts)

        return TextExtractionResult(
            lines: orderedLines,
            fullText: fullText,
            joinedParagraphText: joinedParagraph
        )
    }

    private static func buildJoinedParagraphs(from rows: [(text: String, rect: CGRect)]) -> String {
        guard let first = rows.first else { return "" }
        var output = first.text
        var prev = first

        for current in rows.dropFirst() {
            let verticalGap = current.rect.minY - prev.rect.maxY
            let avgH = max(8.0, (prev.rect.height + current.rect.height) / 2.0)

            if verticalGap > avgH * 1.15 {
                output += "\n\n" + current.text
            } else {
                let prevEndsCJK = prev.text.last.map(isCJKCharacter) ?? false
                let currStartsCJK = current.text.first.map(isCJKCharacter) ?? false
                if prevEndsCJK && currStartsCJK {
                    output += current.text
                } else if prev.text.hasSuffix("-") && !prev.text.hasSuffix(" -") {
                    output.removeLast()
                    output += current.text
                } else {
                    output += " " + current.text
                }
            }
            prev = current
        }
        return output
    }

    private static func isCJKCharacter(_ ch: Character) -> Bool {
        for scalar in ch.unicodeScalars {
            switch scalar.value {
            case 0x4E00...0x9FFF,   // CJK Unified Ideographs
                 0x3400...0x4DBF,   // CJK Extension A
                 0x3000...0x303F,   // CJK Punctuation
                 0x3040...0x30FF,   // Hiragana & Katakana
                 0xFF00...0xFFEF:   // Fullwidth Forms
                return true
            default:
                continue
            }
        }
        return false
    }
}
