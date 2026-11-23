import AppKit
import CoreGraphics
import Foundation

public enum ImageSlicePreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case twoHorizontal // 1x2
    case twoVertical   // 2x1
    case threeVertical // 3x1
    case grid2x2       // 2x2
    case grid3x3       // 3x3

    public var id: String { rawValue }

    public var rows: Int {
        switch self {
        case .twoHorizontal: return 1
        case .twoVertical: return 2
        case .threeVertical: return 3
        case .grid2x2: return 2
        case .grid3x3: return 3
        }
    }

    public var cols: Int {
        switch self {
        case .twoHorizontal: return 2
        case .twoVertical: return 1
        case .threeVertical: return 1
        case .grid2x2: return 2
        case .grid3x3: return 3
        }
    }

    public var displayName: String {
        switch self {
        case .twoHorizontal: return L10n.t(.slicePreset1x2)
        case .twoVertical: return L10n.t(.slicePreset2x1)
        case .threeVertical: return L10n.t(.slicePreset3x1)
        case .grid2x2: return L10n.t(.slicePreset2x2)
        case .grid3x3: return L10n.t(.slicePreset3x3)
        }
    }

    public var gridTag: String {
        "\(rows)×\(cols)"
    }
}

public struct ImageSliceTile: Identifiable {
    public let id: Int
    public let index: Int // 1-based tile order (row-major)
    public let row: Int
    public let col: Int
    public let pixelRect: CGRect
    public let image: CGImage

    public init(index: Int, row: Int, col: Int, pixelRect: CGRect, image: CGImage) {
        self.id = index
        self.index = index
        self.row = row
        self.col = col
        self.pixelRect = pixelRect
        self.image = image
    }
}

/// Lossless single-image grid & custom-line slicer for X 2x2/3x3 grids and long-screenshot threads.
public enum ImageSlicerEngine {
    /// Generates evenly-spaced interior split fractions in (0, 1) for `count` segments.
    public static func equalSplits(segments count: Int) -> [CGFloat] {
        let clamped = max(1, min(6, count))
        guard clamped > 1 else { return [] }
        return (1..<clamped).map { CGFloat($0) / CGFloat(clamped) }
    }

    /// Computes exact integer pixel boundary coordinates `[0, ..., totalPixels]` from normalized interior splits.
    public static func pixelBoundaries(totalPixels: Int, splits: [CGFloat]) -> [Int] {
        guard totalPixels >= 2 else { return [0, max(1, totalPixels)] }
        let sorted = splits
            .map { min(max($0, 0.02), 0.98) }
            .sorted()

        var bounds: [Int] = [0]
        for frac in sorted {
            let px = Int((CGFloat(totalPixels) * frac).rounded())
            let minNext = (bounds.last ?? 0) + 1
            let maxNext = totalPixels - 1
            if minNext <= maxNext {
                bounds.append(min(max(px, minNext), maxNext))
            }
        }
        bounds.append(totalPixels)
        return bounds
    }

    /// Slices `image` losslessly along exact pixel boundaries with zero gaps and zero overlapping pixels.
    public static func slice(
        image: CGImage,
        rowSplits: [CGFloat],
        colSplits: [CGFloat]
    ) -> [ImageSliceTile] {
        let imgW = image.width
        let imgH = image.height
        guard imgW >= 2, imgH >= 2 else { return [] }

        let xBounds = pixelBoundaries(totalPixels: imgW, splits: colSplits)
        let yBounds = pixelBoundaries(totalPixels: imgH, splits: rowSplits)

        var tiles: [ImageSliceTile] = []
        var counter = 1
        for r in 0..<(yBounds.count - 1) {
            let y0 = yBounds[r]
            let y1 = yBounds[r + 1]
            let h = y1 - y0
            guard h >= 1 else { continue }

            for c in 0..<(xBounds.count - 1) {
                let x0 = xBounds[c]
                let x1 = xBounds[c + 1]
                let w = x1 - x0
                guard w >= 1 else { continue }

                let rect = CGRect(x: x0, y: y0, width: w, height: h)
                if let cropped = image.cropping(to: rect) {
                    tiles.append(ImageSliceTile(
                        index: counter,
                        row: r,
                        col: c,
                        pixelRect: rect,
                        image: cropped
                    ))
                    counter += 1
                }
            }
        }
        return tiles
    }

    /// Convenience helper for equal `rows × cols` slicing.
    public static func sliceEqualGrid(image: CGImage, rows: Int, cols: Int) -> [ImageSliceTile] {
        slice(
            image: image,
            rowSplits: equalSplits(segments: rows),
            colSplits: equalSplits(segments: cols)
        )
    }

    /// Exports all sliced tiles as numbered Retina 144-DPI PNGs (`01.png`, `02.png`, ...) inside a dedicated subfolder.
    public static func exportSlices(
        _ tiles: [ImageSliceTile],
        intoParentDirectory parentDir: URL = ExportHelpers.screenshotsDirectory
    ) -> [URL] {
        guard !tiles.isEmpty else { return [] }
        let folderName = ExportHelpers.timestampedFilename(prefix: "XShot-Slice", ext: "").trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let targetDir = parentDir.appendingPathComponent(folderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)

        var urls: [URL] = []
        for tile in tiles {
            let name = String(format: "%02d.png", tile.index)
            let url = targetDir.appendingPathComponent(name)
            if ExportHelpers.savePNG(tile.image, to: url) {
                urls.append(url)
            }
        }
        return urls
    }
}
