import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

private final class InternalPasteboardTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var changeCount: Int = -1

    func record(_ count: Int) {
        lock.lock()
        changeCount = count
        lock.unlock()
    }

    func latest() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return changeCount
    }
}

public enum ExportHelpers {
    private static let pasteboardTracker = InternalPasteboardTracker()

    /// Tracks the `NSPasteboard.general.changeCount` written by XShot itself so auto-collect clipboard
    /// monitoring never loops on XShot's own auto-copied outputs.
    public static var lastInternalPasteboardChangeCount: Int {
        pasteboardTracker.latest()
    }

    public static var screenshotsDirectory: URL {
        let base = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures")
        let dir = base.appendingPathComponent("XShot", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public static var recordingsDirectory: URL {
        let base = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Movies")
        let dir = base.appendingPathComponent("XShot", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public static var temporaryRecordingsDirectory: URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("XShot-Raw", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public static func timestampedFilename(prefix: String, ext: String) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd-HHmmss"
        return "\(prefix)-\(fmt.string(from: Date())).\(ext)"
    }

    @discardableResult
    public static func savePNG(_ cgImage: CGImage, to url: URL) -> Bool {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            return false
        }
        // Tag crisp 144 DPI (2x Retina) metadata so web & macOS preview render crisp
        let props: [CFString: Any] = [
            kCGImagePropertyDPIWidth: 144,
            kCGImagePropertyDPIHeight: 144
        ]
        CGImageDestinationAddImage(dest, cgImage, props as CFDictionary)
        return CGImageDestinationFinalize(dest)
    }

    public static func pngData(from cgImage: CGImage) -> Data? {
        let mutableData = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(mutableData, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        let props: [CFString: Any] = [
            kCGImagePropertyDPIWidth: 144,
            kCGImagePropertyDPIHeight: 144
        ]
        CGImageDestinationAddImage(dest, cgImage, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return mutableData as Data
    }

    public static func copyImageToPasteboard(_ cgImage: CGImage) {
        let pb = NSPasteboard.general
        pb.clearContents()
        let item = NSPasteboardItem()
        if let png = pngData(from: cgImage) {
            item.setData(png, forType: .png)
        }
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width / 2, height: cgImage.height / 2))
        if let tiff = nsImage.tiffRepresentation {
            item.setData(tiff, forType: .tiff)
        }
        pb.writeObjects([item])
        pasteboardTracker.record(pb.changeCount)
    }

    public static func copyFileURLToPasteboard(_ url: URL) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([url as NSURL])
        pasteboardTracker.record(pb.changeCount)
    }

    public static func copyFileURLsToPasteboard(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(urls.map { $0 as NSURL })
        pasteboardTracker.record(pb.changeCount)
    }

    public static func copyTextToPasteboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        pasteboardTracker.record(pb.changeCount)
    }

    public static func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    public static func revealFilesInFinder(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    public static func saveScreenshotQuickly(_ cgImage: CGImage) -> URL? {
        let url = screenshotsDirectory.appendingPathComponent(timestampedFilename(prefix: "XShot", ext: "png"))
        return savePNG(cgImage, to: url) ? url : nil
    }

    // MARK: - Lossless Clipboard Image Decoding (Raw PNG/HEIC/WebP/JPEG/TIFF + Finder Copied Image Files)

    private static let clipboardImageTypes: [NSPasteboard.PasteboardType] = [
        .png,
        NSPasteboard.PasteboardType(UTType.heic.identifier),
        NSPasteboard.PasteboardType(UTType.webP.identifier),
        NSPasteboard.PasteboardType(UTType.jpeg.identifier),
        .tiff,
        NSPasteboard.PasteboardType(UTType.gif.identifier)
    ]

    /// Reads up to `limit` images from the pasteboard (supports multi-file ⌘C in Finder as well as single copied images).
    public static func readImagesFromPasteboard(_ pasteboard: NSPasteboard = .general, limit: Int = 6) -> [CGImage] {
        let capped = max(1, limit)
        // Prefer multiple copied image file URLs if more than one image file is on the pasteboard
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] {
            let imageURLs = urls.filter { isImageFileURL($0) }
            if imageURLs.count > 1 {
                let decoded = imageURLs.prefix(capped).compactMap { decodeNormalizedCGImage(from: $0) }
                if !decoded.isEmpty { return decoded }
            }
        }
        if let single = readImageFromPasteboard(pasteboard) {
            return [single]
        }
        return []
    }

    /// Reads an image from the pasteboard at full lossless pixel resolution (supports screenshots,
    /// browser "Copy Image", Figma/Sketch PNGs, and image files copied via ⌘C in Finder).
    public static func readImageFromPasteboard(_ pasteboard: NSPasteboard = .general) -> CGImage? {
        // 1. Direct encoded image bytes (preserves full 2x Retina pixel dimensions!)
        for type in clipboardImageTypes {
            if let data = pasteboard.data(forType: type),
               let cg = decodeNormalizedCGImage(from: data) {
                return cg
            }
        }

        // 2. Copied file URLs (e.g., ⌘C on a .png/.jpg/.heic/.webp file in Finder)
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] {
            for url in urls where isImageFileURL(url) {
                if let cg = decodeNormalizedCGImage(from: url) {
                    return cg
                }
            }
        }

        // 3. Fallback via NSImage (e.g. PDF / PICT / custom app pasteboard representations)
        if let nsImage = NSImage(pasteboard: pasteboard) {
            if let bestRep = nsImage.representations
                .compactMap({ $0 as? NSBitmapImageRep })
                .max(by: { ($0.pixelsWide * $0.pixelsHigh) < ($1.pixelsWide * $1.pixelsHigh) }),
               let cg = bestRep.cgImage {
                return cg
            }
            var rect = CGRect(origin: .zero, size: nsImage.size)
            if let cg = nsImage.cgImage(forProposedRect: &rect, context: nil, hints: nil) {
                return cg
            }
        }

        return nil
    }

    /// Lightweight metadata probe returning pixel dimensions if the pasteboard currently contains an image.
    public static func pasteboardImageDimensions(_ pasteboard: NSPasteboard = .general) -> CGSize? {
        for type in clipboardImageTypes {
            if let data = pasteboard.data(forType: type),
               let src = CGImageSourceCreateWithData(data as CFData, nil),
               let sz = imagePixelDimensions(from: src) {
                return sz
            }
        }
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] {
            for url in urls where isImageFileURL(url) {
                if let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                   let sz = imagePixelDimensions(from: src) {
                    return sz
                }
            }
        }
        return nil
    }

    public static func isImageFileURL(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        if let vals = try? url.resourceValues(forKeys: [.contentTypeKey]),
           let ut = vals.contentType {
            return ut.conforms(to: .image)
        }
        if let ut = UTType(filenameExtension: url.pathExtension) {
            return ut.conforms(to: .image)
        }
        return false
    }

    public static func decodeNormalizedCGImage(from data: Data) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return decodeOrientedCGImage(from: src)
    }

    public static func decodeNormalizedCGImage(from url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return decodeOrientedCGImage(from: src)
    }

    private static func imagePixelDimensions(from source: CGImageSource) -> CGSize? {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? CGFloat,
              let h = props[kCGImagePropertyPixelHeight] as? CGFloat,
              w > 0, h > 0 else {
            return nil
        }
        let orientation = (props[kCGImagePropertyOrientation] as? UInt32) ?? 1
        if orientation >= 5 && orientation <= 8 {
            return CGSize(width: h, height: w)
        }
        return CGSize(width: w, height: h)
    }

    private static func decodeOrientedCGImage(from source: CGImageSource) -> CGImage? {
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let orientation = (props?[kCGImagePropertyOrientation] as? UInt32) ?? 1
        if orientation == 1 {
            return CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
        let maxEdge = Int(max(
            (props?[kCGImagePropertyPixelWidth] as? CGFloat) ?? 4096,
            (props?[kCGImagePropertyPixelHeight] as? CGFloat) ?? 4096
        ))
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(64, maxEdge)
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, opts as CFDictionary)
            ?? CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
