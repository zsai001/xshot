import CoreGraphics
import Foundation

public struct MultiImageSlot: Equatable, Sendable {
    public let index: Int
    /// Frame in top-left origin composite pixel coordinates.
    public let frame: CGRect
    /// True when the image should aspect-fill (crop cleanly) into `frame`; false when aspect-fit (0 crop).
    public let aspectFill: Bool

    public init(index: Int, frame: CGRect, aspectFill: Bool) {
        self.index = index
        self.frame = frame
        self.aspectFill = aspectFill
    }
}

public struct MultiImageLayoutResult: Equatable, Sendable {
    public let compositeSize: CGSize
    public let slots: [MultiImageSlot]

    public init(compositeSize: CGSize, slots: [MultiImageSlot]) {
        self.compositeSize = compositeSize
        self.slots = slots
    }
}

/// Pure, deterministic layout engine for multi-screenshot compositions (Horizontal, Vertical,
/// Bento Grid, and Hero Showcase). Shared 1:1 between 120Hz live SwiftUI preview & Retina PNG export.
public enum MultiImageLayoutEngine {
    public static func computeLayout(
        imageSizes: [CGSize],
        mode: MultiImageLayoutMode,
        spacing: CGFloat,
        fitMode: MultiImageFitMode
    ) -> MultiImageLayoutResult {
        guard !imageSizes.isEmpty else {
            return MultiImageLayoutResult(compositeSize: CGSize(width: 800, height: 600), slots: [])
        }
        if imageSizes.count == 1 {
            let s = sanitized(imageSizes[0])
            return MultiImageLayoutResult(
                compositeSize: s,
                slots: [MultiImageSlot(index: 0, frame: CGRect(origin: .zero, size: s), aspectFill: false)]
            )
        }

        let sizes = imageSizes.map(sanitized)
        // Scale design-pt spacing proportionally to source image resolution (matches BeautifyStyle padding logic)
        let avgShortEdge = sizes.map { min($0.width, $0.height) }.reduce(0, +) / CGFloat(sizes.count)
        let scaleFactor = max(1.0, avgShortEdge / 720.0)
        let gap = max(0, (spacing * scaleFactor).rounded())

        switch mode {
        case .horizontal:
            return layoutHorizontal(sizes: sizes, gap: gap, fitMode: fitMode)
        case .vertical:
            return layoutVertical(sizes: sizes, gap: gap, fitMode: fitMode)
        case .grid2x2:
            return layoutGrid(sizes: sizes, gap: gap, fitMode: fitMode)
        case .bentoHero:
            return layoutBentoHero(sizes: sizes, gap: gap, fitMode: fitMode)
        }
    }

    /// Returns the exact visual card frame inside `slot`: fills `slot.frame` when `aspectFill == true`,
    /// or hugs the image's natural aspect ratio cleanly centered inside `slot.frame` when `aspectFill == false` (zero pillarbox bars!).
    public static func resolvedCardRect(for imageSize: CGSize, in slot: MultiImageSlot) -> CGRect {
        if slot.aspectFill {
            return slot.frame
        }
        let imgW = max(1, imageSize.width)
        let imgH = max(1, imageSize.height)
        let scale = min(slot.frame.width / imgW, slot.frame.height / imgH)
        let w = (imgW * scale).rounded()
        let h = (imgH * scale).rounded()
        return CGRect(
            x: (slot.frame.midX - w / 2.0).rounded(),
            y: (slot.frame.midY - h / 2.0).rounded(),
            width: max(2, w),
            height: max(2, h)
        )
    }

    private static func sanitized(_ size: CGSize) -> CGSize {
        CGSize(width: max(2, size.width.rounded()), height: max(2, size.height.rounded()))
    }

    // MARK: - 1. Horizontal Row (Side-by-Side Comparison / Mobile Screens)

    private static func layoutHorizontal(sizes: [CGSize], gap: CGFloat, fitMode: MultiImageFitMode) -> MultiImageLayoutResult {
        let baseH = max(360, min(1800, (sizes.map(\.height).reduce(0, +) / CGFloat(sizes.count)).rounded()))
        var slots: [MultiImageSlot] = []
        var cursorX: CGFloat = 0

        if fitMode == .fit {
            for (i, sz) in sizes.enumerated() {
                let w = max(60, (baseH * (sz.width / sz.height)).rounded())
                slots.append(MultiImageSlot(index: i, frame: CGRect(x: cursorX, y: 0, width: w, height: baseH), aspectFill: false))
                cursorX += w + (i < sizes.count - 1 ? gap : 0)
            }
        } else {
            // Equal-width uniform cards using average clamped aspect ratio
            let avgRatio = min(1.85, max(0.55, sizes.map { $0.width / $0.height }.reduce(0, +) / CGFloat(sizes.count)))
            let cellW = max(120, (baseH * avgRatio).rounded())
            for i in sizes.indices {
                slots.append(MultiImageSlot(index: i, frame: CGRect(x: cursorX, y: 0, width: cellW, height: baseH), aspectFill: true))
                cursorX += cellW + (i < sizes.count - 1 ? gap : 0)
            }
        }
        return MultiImageLayoutResult(compositeSize: CGSize(width: max(2, cursorX), height: baseH), slots: slots)
    }

    // MARK: - 2. Vertical Stack (Top-to-Bottom Flow / Code + Output)

    private static func layoutVertical(sizes: [CGSize], gap: CGFloat, fitMode: MultiImageFitMode) -> MultiImageLayoutResult {
        let baseW = max(480, min(2000, (sizes.map(\.width).reduce(0, +) / CGFloat(sizes.count)).rounded()))
        var slots: [MultiImageSlot] = []
        var cursorY: CGFloat = 0

        if fitMode == .fit {
            for (i, sz) in sizes.enumerated() {
                let h = max(60, (baseW * (sz.height / sz.width)).rounded())
                slots.append(MultiImageSlot(index: i, frame: CGRect(x: 0, y: cursorY, width: baseW, height: h), aspectFill: false))
                cursorY += h + (i < sizes.count - 1 ? gap : 0)
            }
        } else {
            let avgRatio = min(2.0, max(0.65, sizes.map { $0.width / $0.height }.reduce(0, +) / CGFloat(sizes.count)))
            let cellH = max(120, (baseW / avgRatio).rounded())
            for i in sizes.indices {
                slots.append(MultiImageSlot(index: i, frame: CGRect(x: 0, y: cursorY, width: baseW, height: cellH), aspectFill: true))
                cursorY += cellH + (i < sizes.count - 1 ? gap : 0)
            }
        }
        return MultiImageLayoutResult(compositeSize: CGSize(width: baseW, height: max(2, cursorY)), slots: slots)
    }

    // MARK: - 3. Balanced Bento Grid (2x1, 2+1 Span, 2x2, 3x2)

    private static func layoutGrid(sizes: [CGSize], gap: CGFloat, fitMode: MultiImageFitMode) -> MultiImageLayoutResult {
        let count = sizes.count
        let cols = (count <= 4) ? 2 : 3
        let rows = Int(ceil(Double(count) / Double(cols)))

        let avgW = sizes.map(\.width).reduce(0, +) / CGFloat(count)
        let avgH = sizes.map(\.height).reduce(0, +) / CGFloat(count)
        let avgRatio = min(1.85, max(0.75, avgW / avgH))

        let cellW = max(360, min(1100, avgW.rounded()))
        let cellH = max(240, (cellW / avgRatio).rounded())

        let totalW = CGFloat(cols) * cellW + CGFloat(cols - 1) * gap
        let totalH = CGFloat(rows) * cellH + CGFloat(rows - 1) * gap

        var slots: [MultiImageSlot] = []
        let useFill = (fitMode == .fill)

        for i in 0..<count {
            let r = i / cols
            let c = i % cols
            let isLastRow = (r == rows - 1)
            let itemsInLastRow = count - r * cols

            let frame: CGRect
            if isLastRow && itemsInLastRow == 1 && cols > 1 {
                // Span full width cleanly for a balanced Bento card (e.g. 3 images -> 2 on top, 1 wide below!)
                frame = CGRect(x: 0, y: CGFloat(r) * (cellH + gap), width: totalW, height: cellH)
            } else if isLastRow && itemsInLastRow < cols {
                // Distribute remaining items evenly across full row width
                let rowCellW = ((totalW - CGFloat(itemsInLastRow - 1) * gap) / CGFloat(itemsInLastRow)).rounded()
                let x = CGFloat(c) * (rowCellW + gap)
                let w = (c == itemsInLastRow - 1) ? (totalW - x) : rowCellW
                frame = CGRect(x: x, y: CGFloat(r) * (cellH + gap), width: w, height: cellH)
            } else {
                frame = CGRect(
                    x: CGFloat(c) * (cellW + gap),
                    y: CGFloat(r) * (cellH + gap),
                    width: cellW,
                    height: cellH
                )
            }
            slots.append(MultiImageSlot(index: i, frame: frame, aspectFill: useFill))
        }

        return MultiImageLayoutResult(compositeSize: CGSize(width: totalW, height: totalH), slots: slots)
    }

    // MARK: - 4. Apple/Linear Bento Hero Showcase (Large Hero Left + Stacked Right Column)

    private static func layoutBentoHero(sizes: [CGSize], gap: CGFloat, fitMode: MultiImageFitMode) -> MultiImageLayoutResult {
        let heroSize = sizes[0]
        let rightCount = sizes.count - 1
        let heroRatio = min(1.85, max(0.75, heroSize.width / heroSize.height))

        let totalH = max(680, min(1600, max(heroSize.height, 920).rounded()))
        let heroW = max(480, (totalH * heroRatio).rounded())
        let rightW = max(320, (heroW * (rightCount == 1 ? 0.72 : 0.62)).rounded())
        let totalW = heroW + gap + rightW

        let useFill = (fitMode == .fill)
        var slots: [MultiImageSlot] = [
            MultiImageSlot(index: 0, frame: CGRect(x: 0, y: 0, width: heroW, height: totalH), aspectFill: useFill)
        ]

        let totalGapY = CGFloat(max(0, rightCount - 1)) * gap
        let eachH = ((totalH - totalGapY) / CGFloat(max(1, rightCount))).rounded()

        for j in 0..<rightCount {
            let y = CGFloat(j) * (eachH + gap)
            let h = (j == rightCount - 1) ? (totalH - y) : eachH
            slots.append(MultiImageSlot(
                index: j + 1,
                frame: CGRect(x: heroW + gap, y: y, width: rightW, height: max(40, h)),
                aspectFill: useFill
            ))
        }

        return MultiImageLayoutResult(compositeSize: CGSize(width: totalW, height: totalH), slots: slots)
    }
}
