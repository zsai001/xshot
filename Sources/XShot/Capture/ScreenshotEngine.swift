import AppKit
import CoreGraphics
import Foundation
@preconcurrency import ScreenCaptureKit

public enum ScreenshotCaptureError: LocalizedError {
    case displayNotFound
    case windowNotFound
    case captureFailed(String)

    public var errorDescription: String? {
        switch self {
        case .displayNotFound: return L10n.t(.errDisplayNotFound)
        case .windowNotFound: return L10n.t(.errWindowNotFoundClosed)
        case .captureFailed(let msg): return L10n.format(.errCaptureFailedFormat, msg)
        }
    }
}

public enum CaptureWindowFilter {
    /// Returns CGWindowIDs of XShot's internal capture-only overlays (crosshair selector,
    /// red recording border, floating REC HUD, quick-preview toast) marked with `sharingType == .none`.
    /// XShot's own user-facing windows (Screenshot Editor, Video Studio, Settings, Pinned Images,
    /// Menu Bar Popover) keep default `.readOnly` sharing so users can screenshot & record XShot itself.
    @MainActor
    public static func internalOverlayWindowIDs() -> Set<CGWindowID> {
        var ids = Set<CGWindowID>()
        for win in NSApp?.windows ?? [] {
            if win.sharingType == .none, let wid = CGWindowID(exactly: win.windowNumber), wid > 0 {
                ids.insert(wid)
            }
        }
        return ids
    }
}

public enum ScreenshotEngine {
    /// Captures a crisp Retina sRGB CGImage via macOS native ScreenCaptureKit (`SCScreenshotManager`).
    public static func capture(target: SelectedCaptureTarget) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let excludedIDs = await CaptureWindowFilter.internalOverlayWindowIDs()
        let excludedWindows = content.windows.filter { excludedIDs.contains($0.windowID) }

        let filter: SCContentFilter
        let config = SCStreamConfiguration()
        config.showsCursor = false
        config.scalesToFit = true
        config.colorSpaceName = CGColorSpace.sRGB
        config.pixelFormat = kCVPixelFormatType_32BGRA

        switch target {
        case .area(let displayID, _, _, let displayLocalRect, let scaleFactor):
            guard let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first else {
                throw ScreenshotCaptureError.displayNotFound
            }
            filter = SCContentFilter(display: display, excludingWindows: excludedWindows)
            let effectiveScale = max(scaleFactor, CGFloat(filter.pointPixelScale))
            config.sourceRect = displayLocalRect
            config.width = max(2, Int((displayLocalRect.width * effectiveScale).rounded()))
            config.height = max(2, Int((displayLocalRect.height * effectiveScale).rounded()))

        case .window(let windowID, _, _, let quartzFrame, let scaleFactor):
            guard let scWindow = content.windows.first(where: { $0.windowID == windowID }) else {
                throw ScreenshotCaptureError.windowNotFound
            }
            filter = SCContentFilter(desktopIndependentWindow: scWindow)
            config.ignoreShadowsSingleWindow = true
            let nativeScale = max(1.0, CGFloat(filter.pointPixelScale))
            let effectiveScale = nativeScale > 0 ? nativeScale : scaleFactor
            let contentSize = (filter.contentRect.width > 1 && filter.contentRect.height > 1)
                ? filter.contentRect.size
                : quartzFrame.size
            config.width = max(2, Int((contentSize.width * effectiveScale).rounded()))
            config.height = max(2, Int((contentSize.height * effectiveScale).rounded()))

        case .display(let displayID, let quartzFrame, let scaleFactor):
            guard let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first else {
                throw ScreenshotCaptureError.displayNotFound
            }
            filter = SCContentFilter(display: display, excludingWindows: excludedWindows)
            let effectiveScale = max(scaleFactor, CGFloat(filter.pointPixelScale))
            config.width = max(2, Int((quartzFrame.width * effectiveScale).rounded()))
            config.height = max(2, Int((quartzFrame.height * effectiveScale).rounded()))
        }

        do {
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        } catch {
            throw ScreenshotCaptureError.captureFailed(error.localizedDescription)
        }
    }

    /// Captures crisp full-Retina frozen snapshots of EVERY connected display BEFORE showing any
    /// selection overlay, freezing transient popups, right-click menus, dropdowns, and tooltips in place!
    public static func captureAllDisplaysFrozen() async throws -> [CGDirectDisplayID: CGImage] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let excludedIDs = await CaptureWindowFilter.internalOverlayWindowIDs()
        let excludedWindows = content.windows.filter { excludedIDs.contains($0.windowID) }

        let screenScales: [CGDirectDisplayID: CGFloat] = await MainActor.run {
            var map: [CGDirectDisplayID: CGFloat] = [:]
            for s in NSScreen.screens {
                if let did = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID {
                    map[did] = s.backingScaleFactor
                }
            }
            return map
        }

        var frozen: [CGDirectDisplayID: CGImage] = [:]
        for display in content.displays {
            let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)
            let scale = max(screenScales[display.displayID] ?? 2.0, CGFloat(filter.pointPixelScale))
            let config = SCStreamConfiguration()
            config.showsCursor = false
            config.scalesToFit = true
            config.colorSpaceName = CGColorSpace.sRGB
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.width = max(2, Int((CGFloat(display.width) * scale).rounded()))
            config.height = max(2, Int((CGFloat(display.height) * scale).rounded()))

            do {
                let img = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                frozen[display.displayID] = img
            } catch {
                throw ScreenshotCaptureError.captureFailed(error.localizedDescription)
            }
        }
        return frozen
    }

    /// Instant sub-millisecond Retina crop from a pre-captured frozen display snapshot.
    public static func cropFrozenDisplayImage(
        _ frozenImage: CGImage,
        displayLocalRect: CGRect,
        displayPointsSize: CGSize
    ) -> CGImage? {
        let sx = CGFloat(frozenImage.width) / max(1, displayPointsSize.width)
        let sy = CGFloat(frozenImage.height) / max(1, displayPointsSize.height)
        let pixelRect = CGRect(
            x: (displayLocalRect.origin.x * sx).rounded(),
            y: (displayLocalRect.origin.y * sy).rounded(),
            width: max(2, (displayLocalRect.width * sx).rounded()),
            height: max(2, (displayLocalRect.height * sy).rounded())
        ).intersection(CGRect(x: 0, y: 0, width: frozenImage.width, height: frozenImage.height))
        guard !pixelRect.isNull, pixelRect.width >= 2, pixelRect.height >= 2 else { return nil }
        return frozenImage.cropping(to: pixelRect)
    }

    /// Fallback crop for transient popups/menus that closed between window hover and click.
    @MainActor
    public static func cropFrozenWindow(
        from frozenDisplays: [CGDirectDisplayID: CGImage],
        quartzFrame: CGRect
    ) -> CGImage? {
        let primaryH = CoordinateConverter.primaryScreenHeight()
        for screen in NSScreen.screens {
            let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? CGMainDisplayID()
            guard let frozen = frozenDisplays[displayID] else { continue }
            let displayQuartz = CoordinateConverter.appKitToQuartz(screen.frame, primaryHeight: primaryH)
            if displayQuartz.intersects(quartzFrame) {
                let local = CoordinateConverter.quartzToDisplayLocal(quartzFrame, displayQuartzBounds: displayQuartz)
                return cropFrozenDisplayImage(frozen, displayLocalRect: local, displayPointsSize: screen.frame.size)
            }
        }
        return nil
    }
}
