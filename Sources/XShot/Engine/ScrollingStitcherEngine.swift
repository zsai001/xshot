import CoreGraphics
import Foundation

public enum ScrollStitchOutcome: Sendable {
    case unchanged
    case stitched(deltaPixels: Int, totalHeight: Int, stickyHeader: Int, stickyFooter: Int)
    case limitReached
}

/// Pure, fast, deterministic Retina vertical long-screenshot stitcher.
/// Automatically detects sticky fixed headers/footers, ignores macOS overlay scrollbars,
/// finds exact pixel vertical scroll deltas via coarse-to-fine strip MAD registration,
/// and supports undo snapshots + manual append fallback.
public final class ScrollingStitcherEngine: @unchecked Sendable {
    public struct Snapshot {
        public let image: CGImage
        public let lastFrame: CGImage
        public let lastTailHeight: Int
    }

    public let maxOutputHeight: Int
    public private(set) var stitchedImage: CGImage
    public private(set) var lastFrame: CGImage
    public private(set) var frameCount: Int = 1
    private var lastTailHeight: Int
    private var undoStack: [Snapshot] = []

    public var canUndo: Bool { !undoStack.isEmpty }

    public init(initialFrame: CGImage, maxOutputHeight: Int = 24_000) {
        self.stitchedImage = initialFrame
        self.lastFrame = initialFrame
        self.lastTailHeight = initialFrame.height
        self.maxOutputHeight = max(initialFrame.height * 2, maxOutputHeight)
    }

    /// Attempts to register `nextFrame` below `lastFrame` and stitch the newly revealed vertical strip.
    @discardableResult
    public func stitchNextFrame(_ nextFrame: CGImage) -> ScrollStitchOutcome {
        guard nextFrame.width == lastFrame.width, nextFrame.height == lastFrame.height else {
            return .unchanged
        }
        guard stitchedImage.height < maxOutputHeight else {
            return .limitReached
        }

        let match = Self.findVerticalScrollDelta(previous: lastFrame, current: nextFrame)
        guard let match else {
            return .unchanged
        }

        // Because `stitchedImage` ends with the bottom `lastTailHeight` rows of `lastFrame`,
        // trimming `trimFooter = min(match.stickyFooter, lastTailHeight)` lands precisely at the
        // bottom of `lastFrame`'s scrollable body, so appending `deltaPixels + match.stickyFooter`
        // yields an exact `stitchedImage.height + deltaPixels` seam with zero duplicated footers!
        let trimFooter = min(match.stickyFooter, lastTailHeight)
        let newHeight = (stitchedImage.height - trimFooter) + match.deltaPixels + match.stickyFooter
        guard newHeight > stitchedImage.height, newHeight <= maxOutputHeight else {
            return newHeight > maxOutputHeight ? .limitReached : .unchanged
        }

        guard let combined = Self.composeStitchedImage(
            existing: stitchedImage,
            existingFooterHeight: trimFooter,
            nextFrame: nextFrame,
            deltaPixels: match.deltaPixels,
            nextFooterHeight: match.stickyFooter
        ) else {
            return .unchanged
        }

        pushUndoSnapshot()
        stitchedImage = combined
        lastFrame = nextFrame
        lastTailHeight = min(nextFrame.height, match.deltaPixels + match.stickyFooter)
        frameCount += 1

        return .stitched(
            deltaPixels: match.deltaPixels,
            totalHeight: combined.height,
            stickyHeader: match.stickyHeader,
            stickyFooter: match.stickyFooter
        )
    }

    /// Manual "Append Screen" action: tries smart overlap stitch first; if the user scrolled more than
    /// a full page in one jump, directly appends `nextFrame` below cleanly.
    @discardableResult
    public func appendManualFrame(_ nextFrame: CGImage) -> ScrollStitchOutcome {
        guard nextFrame.width == lastFrame.width, nextFrame.height == lastFrame.height else {
            return .unchanged
        }
        let smart = stitchNextFrame(nextFrame)
        if case .stitched = smart { return smart }
        if case .limitReached = smart { return .limitReached }

        // Check if visually identical to previous frame so double-clicking doesn't duplicate
        if Self.framesAreNearlyIdentical(lastFrame, nextFrame) {
            return .unchanged
        }

        let newHeight = stitchedImage.height + nextFrame.height
        guard newHeight <= maxOutputHeight else { return .limitReached }

        guard let combined = Self.composeStitchedImage(
            existing: stitchedImage,
            existingFooterHeight: 0,
            nextFrame: nextFrame,
            deltaPixels: nextFrame.height,
            nextFooterHeight: 0
        ) else {
            return .unchanged
        }

        pushUndoSnapshot()
        stitchedImage = combined
        lastFrame = nextFrame
        lastTailHeight = nextFrame.height
        frameCount += 1
        return .stitched(deltaPixels: nextFrame.height, totalHeight: combined.height, stickyHeader: 0, stickyFooter: 0)
    }

    @discardableResult
    public func undoLastStitch() -> Bool {
        guard let prev = undoStack.popLast() else { return false }
        stitchedImage = prev.image
        lastFrame = prev.lastFrame
        lastTailHeight = prev.lastTailHeight
        frameCount = max(1, frameCount - 1)
        return true
    }

    private func pushUndoSnapshot() {
        undoStack.append(Snapshot(image: stitchedImage, lastFrame: lastFrame, lastTailHeight: lastTailHeight))
        if undoStack.count > 12 {
            undoStack.removeFirst()
        }
    }

    // MARK: - Core Registration Math (Pure & Testable)

    public struct ScrollMatchResult: Equatable, Sendable {
        public let deltaPixels: Int
        public let stickyHeader: Int
        public let stickyFooter: Int
        public let mad: Double
    }

    public static func findVerticalScrollDelta(previous: CGImage, current: CGImage) -> ScrollMatchResult? {
        let w = previous.width
        let h = previous.height
        guard w >= 32, h >= 64, current.width == w, current.height == h else { return nil }

        // Crop out left 4% edge & right 10% where macOS overlay scrollbars appear
        let roiX = max(0, Int(Double(w) * 0.04))
        let roiW = max(16, Int(Double(w) * 0.86))
        let sampleW = min(roiW, 256)

        guard let prevLuma = extractLumaGrid(from: previous, roiX: roiX, roiW: roiW, sampleW: sampleW),
              let currLuma = extractLumaGrid(from: current, roiX: roiX, roiW: roiW, sampleW: sampleW) else {
            return nil
        }

        // Compute per-row stationary difference
        var rowDiff = [Double](repeating: 0, count: h)
        for y in 0..<h {
            let offset = y * sampleW
            var sum = 0
            for x in 0..<sampleW {
                sum += abs(Int(prevLuma[offset + x]) - Int(currLuma[offset + x]))
            }
            rowDiff[y] = Double(sum) / Double(sampleW)
        }

        // Reject stationary frame (no real scroll yet)
        let midStart = h / 6
        let midEnd = h - h / 6
        var midSum = 0.0
        for y in midStart..<midEnd { midSum += rowDiff[y] }
        let midMean = midSum / Double(max(1, midEnd - midStart))
        if midMean < 1.6 {
            return nil
        }

        // Auto-detect sticky fixed header and footer bars (static across a real scroll)
        let maxHeader = Int(Double(h) * 0.28)
        var stickyHeader = 0
        while stickyHeader < maxHeader && rowDiff[stickyHeader] < 2.2 {
            stickyHeader += 1
        }
        // Only treat as a real sticky header if it has meaningful thickness (>= 12px)
        if stickyHeader < 12 { stickyHeader = 0 }

        let maxFooter = Int(Double(h) * 0.24)
        var stickyFooter = 0
        while stickyFooter < maxFooter && rowDiff[h - 1 - stickyFooter] < 2.2 {
            stickyFooter += 1
        }
        if stickyFooter < 12 { stickyFooter = 0 }

        let bodyTop = stickyHeader
        let bodyBottom = h - stickyFooter
        let bodyH = bodyBottom - bodyTop
        guard bodyH >= 64 else { return nil }

        let minOverlap = max(36, Int(Double(bodyH) * 0.16))
        let minDelta = max(6, Int(Double(bodyH) * 0.015))
        let maxDelta = bodyH - minOverlap
        guard minDelta <= maxDelta else { return nil }

        // Helper: average MAD between previous[bodyTop + dy ..< bodyBottom] and current[bodyTop ..< bodyBottom - dy]
        func evaluateDelta(_ dy: Int, rowStride: Int) -> Double {
            let overlap = bodyH - dy
            guard overlap >= minOverlap else { return 999.0 }
            var totalDiff = 0
            var rowsChecked = 0
            var r = 0
            while r < overlap {
                let pOff = (bodyTop + dy + r) * sampleW
                let cOff = (bodyTop + r) * sampleW
                var s = 0
                for x in 0..<sampleW {
                    s += abs(Int(prevLuma[pOff + x]) - Int(currLuma[cOff + x]))
                }
                totalDiff += s
                rowsChecked += 1
                r += rowStride
            }
            return Double(totalDiff) / Double(max(1, rowsChecked * sampleW))
        }

        // Stage 1: Coarse scan every 4px (downsampled rows every 3px) -> < 1ms
        var coarseCandidates: [(dy: Int, mad: Double)] = []
        var dy = minDelta
        while dy <= maxDelta {
            let mad = evaluateDelta(dy, rowStride: 3)
            coarseCandidates.append((dy, mad))
            dy += 4
        }

        // Keep top 5 lowest-MAD local troughs for exact 1px refinement
        coarseCandidates.sort { $0.mad < $1.mad }
        let seeds = coarseCandidates.prefix(5)

        var bestDelta = -1
        var bestMAD = Double.greatestFiniteMagnitude
        var tested = Set<Int>()

        for seed in seeds {
            let lo = max(minDelta, seed.dy - 4)
            let hi = min(maxDelta, seed.dy + 4)
            for cand in lo...hi {
                if tested.contains(cand) { continue }
                tested.insert(cand)
                let mad = evaluateDelta(cand, rowStride: 1)
                if mad < bestMAD - 0.15 || (abs(mad - bestMAD) <= 0.15 && (bestDelta < 0 || cand < bestDelta)) {
                    bestMAD = mad
                    bestDelta = cand
                }
            }
        }

        // Validate match confidence:
        // 1) Matched strip error must be very small (< 11.5 / 255)
        // 2) Matched alignment must clearly beat unshifted stationary comparison (prevents false scroll on flicker/video)
        guard bestDelta > 0, bestMAD < 11.5, bestMAD < midMean * 0.62 else {
            return nil
        }

        return ScrollMatchResult(
            deltaPixels: bestDelta,
            stickyHeader: stickyHeader,
            stickyFooter: stickyFooter,
            mad: bestMAD
        )
    }

    private static func framesAreNearlyIdentical(_ a: CGImage, _ b: CGImage) -> Bool {
        let w = a.width
        let h = a.height
        guard w == b.width, h == b.height else { return false }
        let sampleW = min(w, 160)
        guard let la = extractLumaGrid(from: a, roiX: 0, roiW: w, sampleW: sampleW),
              let lb = extractLumaGrid(from: b, roiX: 0, roiW: w, sampleW: sampleW) else {
            return false
        }
        var sum = 0
        var count = 0
        for y in stride(from: 0, to: h, by: 4) {
            let off = y * sampleW
            for x in 0..<sampleW {
                sum += abs(Int(la[off + x]) - Int(lb[off + x]))
                count += 1
            }
        }
        return Double(sum) / Double(max(1, count)) < 1.5
    }

    private static func extractLumaGrid(from image: CGImage, roiX: Int, roiW: Int, sampleW: Int) -> [UInt8]? {
        let h = image.height
        guard sampleW > 0, h > 0 else { return nil }
        guard let cropped = image.cropping(to: CGRect(x: roiX, y: 0, width: roiW, height: h)) else {
            return nil
        }

        var buffer = [UInt8](repeating: 0, count: sampleW * h)
        let cs = CGColorSpaceCreateDeviceGray()
        let ok: Bool = buffer.withUnsafeMutableBytes { rawPtr in
            guard let base = rawPtr.baseAddress,
                  let ctx = CGContext(
                      data: base,
                      width: sampleW,
                      height: h,
                      bitsPerComponent: 8,
                      bytesPerRow: sampleW,
                      space: cs,
                      bitmapInfo: CGImageAlphaInfo.none.rawValue
                  ) else {
                return false
            }
            ctx.interpolationQuality = .low
            ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: sampleW, height: h))
            return true
        }
        return ok ? buffer : nil
    }

    /// Composes `existing[0 ..< existingH - existingFooterHeight]` on top of `nextFrame[nextH - (delta + nextFooter) ..< nextH]`.
    private static func composeStitchedImage(
        existing: CGImage,
        existingFooterHeight: Int,
        nextFrame: CGImage,
        deltaPixels: Int,
        nextFooterHeight: Int
    ) -> CGImage? {
        let w = existing.width
        let keepTopH = max(1, existing.height - max(0, existingFooterHeight))
        let appendH = min(nextFrame.height, max(1, deltaPixels + max(0, nextFooterHeight)))
        let totalH = keepTopH + appendH

        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(
            data: nil,
            width: w,
            height: totalH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.interpolationQuality = .none

        // Top portion (top-left crop from existing[0 ..< keepTopH], drawn at top of bottom-left CG canvas)
        let topCrop = CGRect(x: 0, y: 0, width: w, height: keepTopH)
        if let topSlice = existing.cropping(to: topCrop) {
            ctx.draw(topSlice, in: CGRect(x: 0, y: appendH, width: w, height: keepTopH))
        }

        // Newly revealed bottom strip (top-left crop from nextFrame[nextH - appendH ..< nextH], drawn at y = 0)
        let bottomCrop = CGRect(x: 0, y: nextFrame.height - appendH, width: w, height: appendH)
        if let bottomSlice = nextFrame.cropping(to: bottomCrop) {
            ctx.draw(bottomSlice, in: CGRect(x: 0, y: 0, width: w, height: appendH))
        }

        return ctx.makeImage()
    }
}
