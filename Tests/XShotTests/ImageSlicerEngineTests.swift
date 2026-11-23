import CoreGraphics
import Foundation
import XCTest
@testable import XShot

final class ImageSlicerEngineTests: XCTestCase {
    private func makeQuadrantTestImage(width: Int, height: Int) -> CGImage {
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
        // Fill 4 distinct colored quadrants so cropping regions can be verified
        let halfW = CGFloat(width) / 2.0
        let halfH = CGFloat(height) / 2.0
        ctx.setFillColor(CGColor(srgbRed: 0.90, green: 0.20, blue: 0.20, alpha: 1))
        ctx.fill(CGRect(x: 0, y: halfH, width: halfW, height: halfH))
        ctx.setFillColor(CGColor(srgbRed: 0.20, green: 0.75, blue: 0.35, alpha: 1))
        ctx.fill(CGRect(x: halfW, y: halfH, width: halfW, height: halfH))
        ctx.setFillColor(CGColor(srgbRed: 0.20, green: 0.45, blue: 0.95, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: halfW, height: halfH))
        ctx.setFillColor(CGColor(srgbRed: 0.95, green: 0.72, blue: 0.15, alpha: 1))
        ctx.fill(CGRect(x: halfW, y: 0, width: halfW, height: halfH))
        return ctx.makeImage()!
    }

    func testEqualGridPresetsCoverExactPixelsWithZeroGapOrOverlap() {
        // Odd dimensions to verify rounding never leaves a gap or drops a pixel
        let source = makeQuadrantTestImage(width: 1001, height: 703)

        for preset in ImageSlicePreset.allCases {
            let tiles = ImageSlicerEngine.sliceEqualGrid(image: source, rows: preset.rows, cols: preset.cols)
            XCTAssertEqual(tiles.count, preset.rows * preset.cols, "Preset \(preset.gridTag) tile count mismatch")

            // Verify 1-based row-major ordering
            for (offset, tile) in tiles.enumerated() {
                XCTAssertEqual(tile.index, offset + 1)
                XCTAssertEqual(tile.row, offset / preset.cols)
                XCTAssertEqual(tile.col, offset % preset.cols)
                XCTAssertEqual(tile.image.width, Int(tile.pixelRect.width))
                XCTAssertEqual(tile.image.height, Int(tile.pixelRect.height))
            }

            // Sum of tile widths in each row must equal exact source width
            for r in 0..<preset.rows {
                let rowTiles = tiles.filter { $0.row == r }
                let widthSum = rowTiles.reduce(0) { $0 + $1.image.width }
                XCTAssertEqual(widthSum, source.width, "Row \(r) width sum mismatch for \(preset.gridTag)")
                // Contiguous x boundaries
                for c in 0..<(rowTiles.count - 1) {
                    XCTAssertEqual(rowTiles[c].pixelRect.maxX, rowTiles[c + 1].pixelRect.minX)
                }
            }

            // Sum of tile heights in each column must equal exact source height
            for c in 0..<preset.cols {
                let colTiles = tiles.filter { $0.col == c }
                let heightSum = colTiles.reduce(0) { $0 + $1.image.height }
                XCTAssertEqual(heightSum, source.height, "Column \(c) height sum mismatch for \(preset.gridTag)")
                // Contiguous y boundaries
                for r in 0..<(colTiles.count - 1) {
                    XCTAssertEqual(colTiles[r].pixelRect.maxY, colTiles[r + 1].pixelRect.minY)
                }
            }

            // Total pixel area must match exact source area
            let totalArea = tiles.reduce(0) { $0 + ($1.image.width * $1.image.height) }
            XCTAssertEqual(totalArea, source.width * source.height)
        }
    }

    func testCustomNonUniformSplitsProduceExpectedTileDimensions() {
        let source = makeQuadrantTestImage(width: 1000, height: 800)
        let tiles = ImageSlicerEngine.slice(
            image: source,
            rowSplits: [0.25, 0.75], // heights: 200, 400, 200
            colSplits: [0.40]        // widths: 400, 600
        )

        XCTAssertEqual(tiles.count, 6)
        XCTAssertEqual(tiles[0].image.width, 400)
        XCTAssertEqual(tiles[0].image.height, 200)
        XCTAssertEqual(tiles[1].image.width, 600)
        XCTAssertEqual(tiles[1].image.height, 200)
        XCTAssertEqual(tiles[2].image.width, 400)
        XCTAssertEqual(tiles[2].image.height, 400)
        XCTAssertEqual(tiles[3].image.width, 600)
        XCTAssertEqual(tiles[3].image.height, 400)
        XCTAssertEqual(tiles[4].image.width, 400)
        XCTAssertEqual(tiles[4].image.height, 200)
        XCTAssertEqual(tiles[5].image.width, 600)
        XCTAssertEqual(tiles[5].image.height, 200)
    }

    func testExportSlicesWritesNumberedRetinaPNGs() throws {
        let source = makeQuadrantTestImage(width: 800, height: 600)
        let tiles = ImageSlicerEngine.sliceEqualGrid(image: source, rows: 2, cols: 2)

        let tmpParent = FileManager.default.temporaryDirectory
            .appendingPathComponent("xshot-slice-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpParent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpParent) }

        let urls = ImageSlicerEngine.exportSlices(tiles, intoParentDirectory: tmpParent)
        XCTAssertEqual(urls.count, 4)
        XCTAssertEqual(urls.map(\.lastPathComponent), ["01.png", "02.png", "03.png", "04.png"])

        for url in urls {
            let data = try Data(contentsOf: url)
            let decoded = try XCTUnwrap(ExportHelpers.decodeNormalizedCGImage(from: data))
            XCTAssertEqual(decoded.width, 400)
            XCTAssertEqual(decoded.height, 300)
        }
    }
}
