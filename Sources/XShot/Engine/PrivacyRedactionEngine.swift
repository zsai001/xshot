import CoreGraphics
import Foundation
import Vision

public enum PrivacyCategory: String, CaseIterable, Identifiable, Codable, Sendable, Hashable {
    case apiKey
    case email
    case phone
    case financialOrID
    case ipAddress

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .apiKey: return L10n.t(.privacyCatApiKey)
        case .email: return L10n.t(.privacyCatEmail)
        case .phone: return L10n.t(.privacyCatPhone)
        case .financialOrID: return L10n.t(.privacyCatFinancialID)
        case .ipAddress: return L10n.t(.privacyCatIP)
        }
    }

    public var systemImage: String {
        switch self {
        case .apiKey: return "key.fill"
        case .email: return "envelope.fill"
        case .phone: return "phone.fill"
        case .financialOrID: return "creditcard.fill"
        case .ipAddress: return "network"
        }
    }
}

public enum PrivacyRedactionStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case mosaic
    case blur

    public var id: String { rawValue }

    public var annotationTool: AnnotationTool {
        switch self {
        case .mosaic: return .mosaic
        case .blur: return .blur
        }
    }

    public var displayName: String {
        switch self {
        case .mosaic: return L10n.t(.toolMosaic)
        case .blur: return L10n.t(.toolBlur)
        }
    }
}

public struct PrivacyTextMatch: Equatable, Sendable {
    public let category: PrivacyCategory
    public let matchedText: String
    public let range: Range<String.Index>
    public let maskedPreview: String

    public init(category: PrivacyCategory, matchedText: String, range: Range<String.Index>, maskedPreview: String) {
        self.category = category
        self.matchedText = matchedText
        self.range = range
        self.maskedPreview = maskedPreview
    }
}

public struct PrivacyFinding: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var annotationID: UUID
    public let category: PrivacyCategory
    public let maskedPreview: String
    /// Exact region in top-left image pixel space.
    public let pixelRect: CGRect

    public init(
        id: UUID = UUID(),
        annotationID: UUID = UUID(),
        category: PrivacyCategory,
        maskedPreview: String,
        pixelRect: CGRect
    ) {
        self.id = id
        self.annotationID = annotationID
        self.category = category
        self.maskedPreview = maskedPreview
        self.pixelRect = pixelRect
    }

    public func makeAnnotation(style: PrivacyRedactionStyle) -> AnnotationItem {
        AnnotationItem(
            id: annotationID,
            tool: style.annotationTool,
            start: CGPoint(x: pixelRect.minX, y: pixelRect.minY),
            end: CGPoint(x: pixelRect.maxX, y: pixelRect.maxY)
        )
    }
}

/// 100% on-device Apple Vision OCR + high-precision sensitive text detector for instant auto-redaction.
/// Never sends any screenshot pixels or text off-device.
public enum PrivacyRedactionEngine {
    private struct PatternRule {
        let category: PrivacyCategory
        let regex: NSRegularExpression
        let captureGroup: Int
        let validator: ((String) -> Bool)?
    }

    private static let rules: [PatternRule] = {
        func compile(_ pattern: String, options: NSRegularExpression.Options = []) -> NSRegularExpression {
            try! NSRegularExpression(pattern: pattern, options: options)
        }

        return [
            // 1. API Keys, Secrets, JWTs, Cloud & SaaS Tokens
            PatternRule(
                category: .apiKey,
                regex: compile(#"(?<![A-Za-z0-9_\-])(?:sk-(?:proj-|ant-|live-|test-)?[A-Za-z0-9_\-]{14,}|(?:sk|pk|rk)_(?:live|test)_[A-Za-z0-9]{12,}|(?:ghp|gho|ghu|ghs|ghr|github_pat)_[A-Za-z0-9_]{16,}|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_\-]{24,}|xox[baprs]-[0-9A-Za-z\-]{10,}|hf_[A-Za-z0-9]{18,}|gsk_[A-Za-z0-9]{18,}|npm_[A-Za-z0-9]{20,}|eyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}(?:\.[A-Za-z0-9_\-]+)?)"#),
                captureGroup: 0,
                validator: nil
            ),
            // Bearer tokens (redact token value only, keeping "Bearer " clear!)
            PatternRule(
                category: .apiKey,
                regex: compile(#"\bBearer\s+([A-Za-z0-9._\-]{14,})"#, options: [.caseInsensitive]),
                captureGroup: 1,
                validator: nil
            ),
            // .env / JSON / YAML / CLI key-value secrets (redact ONLY the secret value after = or :)
            PatternRule(
                category: .apiKey,
                regex: compile(#"(?:api[_\-]?key|api[_\-]?secret|access[_\-]?token|refresh[_\-]?token|auth[_\-]?token|client[_\-]?secret|private[_\-]?key|secret[_\-]?key|password|passwd|pwd|db[_\-]?pass|signing[_\-]?secret)\s*["']?\s*[:=]\s*["']?([^\s"',;}{`]{6,})["']?"#, options: [.caseInsensitive]),
                captureGroup: 1,
                validator: { val in
                    let lower = val.lowercased()
                    // Ignore obvious placeholder values in docs/examples
                    let placeholders = ["true", "false", "null", "none", "undefined", "your_api_key", "changeme", "example", "placeholder"]
                    return !placeholders.contains(lower) && !val.hasPrefix("$") && !val.hasPrefix("<")
                }
            ),

            // 2. Email Addresses
            PatternRule(
                category: .email,
                regex: compile(#"(?<![A-Za-z0-9._%+\-])[A-Za-z0-9._%+\-]{1,64}@[A-Za-z0-9.\-]+\.[A-Za-z]{2,12}\b"#),
                captureGroup: 0,
                validator: nil
            ),

            // 3. Phone Numbers (China, US/CA, Japan, Korea, International)
            PatternRule(
                category: .phone,
                regex: compile(#"(?<!\d)(?:\+?86[\s\-]?)?1[3-9]\d[\s\-]?\d{4}[\s\-]?\d{4}(?!\d)"#),
                captureGroup: 0,
                validator: nil
            ),
            PatternRule(
                category: .phone,
                regex: compile(#"(?<!\d)(?:\+\d{1,3}[\s\-]?)?(?:\(\d{3}\)[\s\-]?|\d{3}[\s\-])\d{3}[\s\-]\d{4}(?!\d)"#),
                captureGroup: 0,
                validator: { str in
                    // Avoid matching ISO dates like 2026-11-21
                    let digits = str.filter(\.isNumber)
                    return digits.count >= 10 && digits.count <= 13
                }
            ),
            PatternRule(
                category: .phone,
                regex: compile(#"(?<!\d)(?:0[789]0|010)[\s\-]\d{4}[\s\-]\d{4}(?!\d)"#),
                captureGroup: 0,
                validator: nil
            ),

            // 4. Credit/Debit Cards (Luhn validated!) & National IDs / SSN
            PatternRule(
                category: .financialOrID,
                regex: compile(#"(?<!\d)(?:\d{4}[\s\-]?){3}\d{3,4}(?!\d)"#),
                captureGroup: 0,
                validator: { str in
                    let digits = str.filter(\.isNumber)
                    guard digits.count >= 13 && digits.count <= 19 else { return false }
                    // Require real payment network IIN prefix (Amex 3, Visa 4, Mastercard 5, UnionPay/Discover 6)
                    guard let first = digits.first, ["3", "4", "5", "6"].contains(first) else { return false }
                    if Set(digits).count <= 1 { return false }
                    return passesLuhnCheck(digits)
                }
            ),
            // China 18-digit Resident ID
            PatternRule(
                category: .financialOrID,
                regex: compile(#"(?<!\d)[1-9]\d{5}(?:19|20)\d{2}(?:0[1-9]|1[0-2])(?:0[1-9]|[12]\d|3[01])\d{3}[\dXx](?!\d)"#),
                captureGroup: 0,
                validator: nil
            ),
            // US SSN
            PatternRule(
                category: .financialOrID,
                regex: compile(#"(?<!\d)(?!000|666|9\d\d)\d{3}-(?!00)\d{2}-(?!0000)\d{4}(?!\d)"#),
                captureGroup: 0,
                validator: nil
            ),

            // 5. IPv4 Addresses (skip harmless localhost 127.0.0.1 and 0.0.0.0)
            PatternRule(
                category: .ipAddress,
                regex: compile(#"(?<!\d)(?:(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)\.){3}(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(?!\d)"#),
                captureGroup: 0,
                validator: { ip in
                    ip != "127.0.0.1" && ip != "0.0.0.0" && ip != "255.255.255.255"
                }
            )
        ]
    }()

    /// Pure text matcher (also directly unit-testable without OCR).
    public static func detectMatches(
        in text: String,
        enabledCategories: Set<PrivacyCategory> = Set(PrivacyCategory.allCases)
    ) -> [PrivacyTextMatch] {
        guard !text.isEmpty, !enabledCategories.isEmpty else { return [] }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        var rawMatches: [PrivacyTextMatch] = []

        for rule in rules where enabledCategories.contains(rule.category) {
            let hits = rule.regex.matches(in: text, options: [], range: nsRange)
            for hit in hits {
                guard rule.captureGroup < hit.numberOfRanges else { continue }
                let groupRange = hit.range(at: rule.captureGroup)
                guard groupRange.location != NSNotFound,
                      let swiftRange = Range(groupRange, in: text) else { continue }
                let matched = String(text[swiftRange])
                if let validator = rule.validator, !validator(matched) {
                    continue
                }
                rawMatches.append(PrivacyTextMatch(
                    category: rule.category,
                    matchedText: matched,
                    range: swiftRange,
                    maskedPreview: maskPreview(matched, category: rule.category)
                ))
            }
        }

        // Deduplicate overlapping spans (prefer earlier category priority & longer match)
        var deduped: [PrivacyTextMatch] = []
        for candidate in rawMatches {
            let overlaps = deduped.contains { existing in
                existing.range.overlaps(candidate.range)
            }
            if !overlaps {
                deduped.append(candidate)
            }
        }
        return deduped
    }

    /// Runs on-device Apple Vision OCR on `cgImage` and returns exact pixel bounding boxes for sensitive substrings.
    public static func detectSensitiveRegions(
        in cgImage: CGImage,
        enabledCategories: Set<PrivacyCategory> = Set(PrivacyCategory.allCases)
    ) async -> [PrivacyFinding] {
        guard !enabledCategories.isEmpty else { return [] }
        return await Task.detached(priority: .userInitiated) {
            detectSensitiveRegionsSync(in: cgImage, enabledCategories: enabledCategories)
        }.value
    }

    /// Synchronous worker executed on a background queue.
    public static func detectSensitiveRegionsSync(
        in cgImage: CGImage,
        enabledCategories: Set<PrivacyCategory> = Set(PrivacyCategory.allCases)
    ) -> [PrivacyFinding] {
        guard !enabledCategories.isEmpty else { return [] }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false // Crucial for exact API keys, emails, tokens & IPs!
        request.automaticallyDetectsLanguage = true
        request.recognitionLanguages = ["en-US", "zh-Hans", "zh-Hant", "ja-JP", "ko-KR"]
        request.minimumTextHeight = 0.008

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }

        guard let observations = request.results, !observations.isEmpty else {
            return []
        }

        let imgW = CGFloat(cgImage.width)
        let imgH = CGFloat(cgImage.height)
        let imageBounds = CGRect(x: 0, y: 0, width: imgW, height: imgH)
        var findings: [PrivacyFinding] = []

        for obs in observations {
            guard let candidate = obs.topCandidates(1).first else { continue }
            let lineText = candidate.string
            let matches = detectMatches(in: lineText, enabledCategories: enabledCategories)
            guard !matches.isEmpty else { continue }

            for match in matches {
                let normBox: CGRect
                if let exactBox = try? candidate.boundingBox(for: match.range)?.boundingBox {
                    normBox = exactBox
                } else {
                    normBox = obs.boundingBox
                }

                // Convert Vision bottom-left normalized rect -> XShot top-left pixel space
                let rawRect = CGRect(
                    x: normBox.minX * imgW,
                    y: (1.0 - normBox.maxY) * imgH,
                    width: normBox.width * imgW,
                    height: normBox.height * imgH
                )
                guard rawRect.width >= 6, rawRect.height >= 4 else { continue }

                // Generous safety margin so zero edge pixels of secrets bleed out
                let padX = max(5.0, rawRect.height * 0.24)
                let padY = max(4.0, rawRect.height * 0.18)
                let padded = rawRect.insetBy(dx: -padX, dy: -padY).intersection(imageBounds)
                guard !padded.isNull, padded.width >= 8, padded.height >= 6 else { continue }

                // Skip near-duplicate overlapping boxes
                let isDuplicate = findings.contains { existing in
                    let inter = existing.pixelRect.intersection(padded)
                    guard !inter.isNull, !inter.isEmpty else { return false }
                    let interArea = inter.width * inter.height
                    let minArea = min(existing.pixelRect.width * existing.pixelRect.height, padded.width * padded.height)
                    return minArea > 0 && (interArea / minArea) > 0.65
                }
                if !isDuplicate {
                    findings.append(PrivacyFinding(
                        category: match.category,
                        maskedPreview: match.maskedPreview,
                        pixelRect: padded
                    ))
                }
            }
        }

        // Order top-to-bottom, left-to-right for clean inspector listing
        findings.sort { a, b in
            if abs(a.pixelRect.minY - b.pixelRect.minY) > 14 {
                return a.pixelRect.minY < b.pixelRect.minY
            }
            return a.pixelRect.minX < b.pixelRect.minX
        }
        return findings
    }

    public static func maskPreview(_ value: String, category: PrivacyCategory) -> String {
        switch category {
        case .email:
            let parts = value.split(separator: "@", maxSplits: 1)
            if parts.count == 2 {
                let user = String(parts[0])
                let dom = String(parts[1])
                let prefix = String(user.prefix(2))
                return "\(prefix)•••@\(dom)"
            }
        case .ipAddress:
            let parts = value.split(separator: ".")
            if parts.count == 4 {
                return "\(parts[0]).•••.•••.\(parts[3])"
            }
        case .phone, .financialOrID, .apiKey:
            break
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 6 {
            return String(trimmed.prefix(1)) + "••••"
        }
        return "\(trimmed.prefix(3))••••\(trimmed.suffix(3))"
    }

    private static func passesLuhnCheck(_ digits: String) -> Bool {
        var sum = 0
        var shouldDouble = false
        for ch in digits.reversed() {
            guard let d = ch.wholeNumberValue else { return false }
            if shouldDouble {
                let doubled = d * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            } else {
                sum += d
            }
            shouldDouble.toggle()
        }
        return sum % 10 == 0
    }
}
