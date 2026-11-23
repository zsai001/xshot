import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Discovers macOS native system wallpapers + the user's live current desktop wallpaper,
/// and provides lightning-fast pre-warmed multi-tier NSCache thumbnail/preview/full-res decoding.
public final class SystemWallpaperManager: @unchecked Sendable {
    public static let shared = SystemWallpaperManager()

    private let lock = NSLock()
    private var cachedStaticWallpapers: [BackgroundPreset]?
    private let thumbCache = NSCache<NSString, CGImage>()
    private let previewCache = NSCache<NSString, CGImage>()
    private let fullCache = NSCache<NSString, CGImage>()

    private init() {
        thumbCache.countLimit = 100
        previewCache.countLimit = 20
        fullCache.countLimit = 6
    }

    /// Pre-warms wallpaper discovery + tiny thumbnails + active desktop preview in the background at launch
    /// so opening the Wallpaper picker displays all system wallpapers instantaneously (0ms).
    public func prewarmAsync(desktopLabel: String = "Desktop") {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let list = self.discoverSystemWallpapers(desktopLabel: desktopLabel)
            // Warm the active desktop wallpaper preview first, then all tiny swatches
            if let firstPath = list.first?.imagePath {
                _ = self.previewImage(forPath: firstPath, maxPixelSize: 1920)
            }
            for preset in list {
                if let path = preset.imagePath {
                    _ = self.thumbnail(forPath: path, maxPixelSize: 180)
                }
            }
        }
    }

    /// Fast synchronous check for already-discovered system wallpapers (nil only before first discovery).
    public func cachedDiscoveredWallpapers(desktopLabel: String = "Desktop") -> [BackgroundPreset]? {
        lock.lock()
        let staticList = cachedStaticWallpapers
        lock.unlock()
        guard let staticList else { return nil }
        return mergeLiveDesktopWallpapers(with: staticList, desktopLabel: desktopLabel)
    }

    /// Returns the user's active desktop wallpaper first, followed by built-in macOS system wallpapers.
    public func discoverSystemWallpapers(desktopLabel: String = "Desktop") -> [BackgroundPreset] {
        let staticList: [BackgroundPreset]
        lock.lock()
        let existing = cachedStaticWallpapers
        lock.unlock()

        if let existing {
            staticList = existing
        } else {
            let scanned = scanBuiltInWallpapers()
            lock.lock()
            cachedStaticWallpapers = scanned
            lock.unlock()
            staticList = scanned
        }

        return mergeLiveDesktopWallpapers(with: staticList, desktopLabel: desktopLabel)
    }

    private func mergeLiveDesktopWallpapers(with staticList: [BackgroundPreset], desktopLabel: String) -> [BackgroundPreset] {
        var results: [BackgroundPreset] = []
        var seenPaths = Set<String>()

        let liveURLs: [URL]
        if Thread.isMainThread {
            liveURLs = NSScreen.screens.compactMap { NSWorkspace.shared.desktopImageURL(for: $0) }
        } else {
            liveURLs = DispatchQueue.main.sync {
                NSScreen.screens.compactMap { NSWorkspace.shared.desktopImageURL(for: $0) }
            }
        }

        for (idx, url) in liveURLs.enumerated() {
            let stdPath = url.standardizedFileURL.path
            guard !seenPaths.contains(stdPath),
                  FileManager.default.isReadableFile(atPath: stdPath),
                  Self.isSupportedImageExtension(url.pathExtension) else { continue }
            seenPaths.insert(stdPath)
            let label = idx == 0 ? desktopLabel : "\(desktopLabel) \(idx + 1)"
            results.append(BackgroundPreset.imagePreset(path: stdPath, name: label, id: "sys-desktop:\(stdPath)"))
        }

        for preset in staticList {
            if let path = preset.imagePath, !seenPaths.contains(path) {
                seenPaths.insert(path)
                results.append(preset)
            }
        }
        return results
    }

    private func scanBuiltInWallpapers() -> [BackgroundPreset] {
        let fm = FileManager.default
        let scanRoots: [(path: String, recursiveDepth: Int)] = [
            ("/System/Library/Desktop Pictures", 1),
            ("/System/Library/Desktop Pictures/.wallpapers", 2),
            ("/Library/Desktop Pictures", 2)
        ]

        var discoveredURLs: [URL] = []
        for root in scanRoots {
            let rootURL = URL(fileURLWithPath: root.path, isDirectory: true)
            guard fm.fileExists(atPath: rootURL.path) else { continue }
            collectImageFiles(in: rootURL, remainingDepth: root.recursiveDepth, into: &discoveredURLs)
        }

        let priorityTokens = ["tahoe", "sequoia", "sonoma", "ventura", "monterey", "radial", "mac ", "imac"]
        discoveredURLs.sort { a, b in
            let na = a.deletingPathExtension().lastPathComponent.lowercased()
            let nb = b.deletingPathExtension().lastPathComponent.lowercased()
            let pa = priorityTokens.firstIndex(where: { na.contains($0) }) ?? 99
            let pb = priorityTokens.firstIndex(where: { nb.contains($0) }) ?? 99
            if pa != pb { return pa < pb }
            return na < nb
        }

        var results: [BackgroundPreset] = []
        var seen = Set<String>()
        for url in discoveredURLs {
            let stdPath = url.standardizedFileURL.path
            let lowerName = url.lastPathComponent.lowercased()
            guard !seen.contains(stdPath),
                  !lowerName.contains("thumbnail"),
                  fm.isReadableFile(atPath: stdPath) else { continue }
            seen.insert(stdPath)
            let name = url.deletingPathExtension().lastPathComponent
            results.append(BackgroundPreset.imagePreset(path: stdPath, name: name))
        }
        return results
    }

    private static func isSupportedImageExtension(_ ext: String) -> Bool {
        ["heic", "jpg", "jpeg", "png", "webp", "tiff", "tif"].contains(ext.lowercased())
    }

    private func collectImageFiles(in directory: URL, remainingDepth: Int, into output: inout [URL]) {
        guard remainingDepth > 0 else { return }
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for item in items {
            let vals = try? item.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
            if vals?.isDirectory == true {
                collectImageFiles(in: item, remainingDepth: remainingDepth - 1, into: &output)
            } else if vals?.isRegularFile == true && Self.isSupportedImageExtension(item.pathExtension) {
                output.append(item)
            }
        }
    }

    /// Zero-latency synchronous RAM cache lookup for thumbnail swatches.
    public func cachedThumbnail(forPath path: String, maxPixelSize: Int = 180) -> CGImage? {
        thumbCache.object(forKey: "\(path)#\(maxPixelSize)" as NSString)
    }

    /// Zero-latency synchronous RAM cache lookup for 120Hz live preview images.
    public func cachedPreviewImage(forPath path: String, maxPixelSize: Int = 1920) -> CGImage? {
        previewCache.object(forKey: "\(path)#\(maxPixelSize)" as NSString)
    }

    /// Ultra-fast thumbnail for inspector swatch grids: prefers Apple's pre-baked `.thumbnails/` file
    /// or embedded HEIC/EXIF thumbnails (< 1ms) before falling back to full downsampling.
    public func thumbnail(forPath path: String, maxPixelSize: Int = 180) -> CGImage? {
        let key = "\(path)#\(maxPixelSize)" as NSString
        if let cached = thumbCache.object(forKey: key) {
            return cached
        }

        // Fast path 1: Apple's pre-baked 354×354 thumbnail in `/System/Library/Desktop Pictures/.thumbnails/`
        if path.hasPrefix("/System/Library/Desktop Pictures/") {
            let filename = URL(fileURLWithPath: path).lastPathComponent
            let appleThumbPath = "/System/Library/Desktop Pictures/.thumbnails/\(filename)"
            if FileManager.default.isReadableFile(atPath: appleThumbPath),
               let img = decodeDownsampled(path: appleThumbPath, maxPixelSize: maxPixelSize, preferEmbeddedThumb: true) {
                thumbCache.setObject(img, forKey: key)
                return img
            }
        }

        // Fast path 2: Embedded thumbnail inside HEIC/JPEG (instant < 1ms!), fallback to downsampled full image
        guard let img = decodeDownsampled(path: path, maxPixelSize: maxPixelSize, preferEmbeddedThumb: true) else {
            return nil
        }
        thumbCache.setObject(img, forKey: key)
        return img
    }

    /// Crisp 1920px preview image cached for locked-120Hz SwiftUI live editing.
    public func previewImage(forPath path: String, maxPixelSize: Int = 1920) -> CGImage? {
        let key = "\(path)#\(maxPixelSize)" as NSString
        if let cached = previewCache.object(forKey: key) {
            return cached
        }
        guard let img = decodeDownsampled(path: path, maxPixelSize: maxPixelSize, preferEmbeddedThumb: false) else {
            return nil
        }
        previewCache.setObject(img, forKey: key)
        return img
    }

    /// High-resolution wallpaper image (up to 4096px) for Retina PNG & 4K MP4 export.
    public func fullResolutionImage(forPath path: String, targetLongEdge: Int = 3840) -> CGImage? {
        let clampedEdge = max(1280, min(4096, targetLongEdge))
        let key = "\(path)#\(clampedEdge)" as NSString
        if let cached = fullCache.object(forKey: key) {
            return cached
        }
        guard let img = decodeDownsampled(path: path, maxPixelSize: clampedEdge, preferEmbeddedThumb: false) else {
            return nil
        }
        fullCache.setObject(img, forKey: key)
        return img
    }

    /// Opens a native macOS file chooser so users can pick any custom local image as wallpaper.
    @MainActor
    public static func pickCustomWallpaperPreset() -> BackgroundPreset? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        if panel.runModal() == .OK, let url = panel.url {
            let name = url.deletingPathExtension().lastPathComponent
            return BackgroundPreset.imagePreset(path: url.standardizedFileURL.path, name: name)
        }
        return nil
    }

    private func decodeDownsampled(path: String, maxPixelSize: Int, preferEmbeddedThumb: Bool) -> CGImage? {
        let url = URL(fileURLWithPath: path)
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        var opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        if preferEmbeddedThumb {
            opts[kCGImageSourceCreateThumbnailFromImageIfAbsent] = true
        } else {
            opts[kCGImageSourceCreateThumbnailFromImageAlways] = true
        }
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
            ?? CGImageSourceCreateImageAtIndex(src, 0, nil)
    }
}
