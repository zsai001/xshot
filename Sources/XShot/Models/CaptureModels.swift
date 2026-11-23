import AppKit
@preconcurrency import AVFoundation
import CoreGraphics
import Foundation

public enum CaptureMode: String, CaseIterable, Identifiable {
    case area
    case window
    case fullscreen

    public var id: String { rawValue }
}

public enum CaptureIntent: String, Equatable {
    case screenshot
    case recording
}

public enum SelectedCaptureTarget: Equatable {
    case area(
        displayID: CGDirectDisplayID,
        appKitRect: CGRect,
        quartzRect: CGRect,
        displayLocalRect: CGRect,
        scaleFactor: CGFloat
    )
    case window(
        windowID: CGWindowID,
        title: String,
        appName: String,
        quartzFrame: CGRect,
        scaleFactor: CGFloat
    )
    case display(
        displayID: CGDirectDisplayID,
        quartzFrame: CGRect,
        scaleFactor: CGFloat
    )

    public var quartzRect: CGRect {
        switch self {
        case .area(_, _, let quartzRect, _, _): return quartzRect
        case .window(_, _, _, let quartzFrame, _): return quartzFrame
        case .display(_, let quartzFrame, _): return quartzFrame
        }
    }

    public var scaleFactor: CGFloat {
        switch self {
        case .area(_, _, _, _, let s): return s
        case .window(_, _, _, _, let s): return s
        case .display(_, _, let s): return s
        }
    }
}

public enum AnnotationTool: String, CaseIterable, Identifiable {
    case select
    case arrow
    case rectangle
    case ellipse
    case highlighter
    case text
    case step
    case mosaic
    case blur

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .select: return L10n.t(.toolSelect)
        case .arrow: return L10n.t(.toolArrow)
        case .rectangle: return L10n.t(.toolRectangle)
        case .ellipse: return L10n.t(.toolEllipse)
        case .highlighter: return L10n.t(.toolHighlighter)
        case .text: return L10n.t(.toolText)
        case .step: return L10n.t(.toolStep)
        case .mosaic: return L10n.t(.toolMosaic)
        case .blur: return L10n.t(.toolBlur)
        }
    }

    public var systemImage: String {
        switch self {
        case .select: return "cursorarrow"
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .highlighter: return "highlighter"
        case .text: return "textformat"
        case .step: return "1.circle.fill"
        case .mosaic: return "checkerboard.rectangle"
        case .blur: return "drop.halffull"
        }
    }
}

public struct AnnotationItem: Identifiable, Codable, Equatable {
    public var id: UUID
    public var tool: String // AnnotationTool.rawValue
    /// Coordinates in image pixel space (top-left origin: 0..imageWidth, 0..imageHeight)
    public var startX: CGFloat
    public var startY: CGFloat
    public var endX: CGFloat
    public var endY: CGFloat
    public var color: RGBAColor
    public var lineWidth: CGFloat
    public var text: String
    public var stepNumber: Int
    public var fontSize: CGFloat

    public init(
        id: UUID = UUID(),
        tool: AnnotationTool,
        start: CGPoint,
        end: CGPoint,
        color: RGBAColor = RGBAColor(hex: 0xEF4444),
        lineWidth: CGFloat = 6,
        text: String = "",
        stepNumber: Int = 1,
        fontSize: CGFloat = 34
    ) {
        self.id = id
        self.tool = tool.rawValue
        self.startX = start.x
        self.startY = start.y
        self.endX = end.x
        self.endY = end.y
        self.color = color
        self.lineWidth = lineWidth
        self.text = text
        self.stepNumber = stepNumber
        self.fontSize = fontSize
    }

    public var toolKind: AnnotationTool {
        AnnotationTool(rawValue: tool) ?? .arrow
    }

    public var startPoint: CGPoint {
        get { CGPoint(x: startX, y: startY) }
        set { startX = newValue.x; startY = newValue.y }
    }

    public var endPoint: CGPoint {
        get { CGPoint(x: endX, y: endY) }
        set { endX = newValue.x; endY = newValue.y }
    }

    public var normalizedRect: CGRect {
        CGRect(
            x: min(startX, endX),
            y: min(startY, endY),
            width: abs(endX - startX),
            height: abs(endY - startY)
        )
    }
}

public struct CollageImageItem: Identifiable {
    public let id: UUID
    public let image: CGImage

    public init(id: UUID = UUID(), image: CGImage) {
        self.id = id
        self.image = image
    }

    public var pixelSize: CGSize {
        CGSize(width: image.width, height: image.height)
    }
}

public final class ScreenshotDocument: Identifiable, ObservableObject {
    public let id: UUID
    public let capturedAt: Date
    @Published public var rawImage: CGImage {
        didSet {
            if collageImages.isEmpty {
                collageImages = [CollageImageItem(image: rawImage)]
            } else if collageImages[0].image !== rawImage {
                collageImages[0] = CollageImageItem(id: collageImages[0].id, image: rawImage)
            }
        }
    }
    @Published public var collageImages: [CollageImageItem]
    @Published public var collageLayout: MultiImageLayoutMode
    @Published public var collageFitMode: MultiImageFitMode
    @Published public var collageSpacing: CGFloat
    @Published public var savedURL: URL?
    @Published public var style: BeautifyStyle
    @Published public var annotations: [AnnotationItem]
    @Published public var enableBeautify: Bool
    @Published public var privacyFindings: [PrivacyFinding]

    public init(
        id: UUID = UUID(),
        capturedAt: Date = Date(),
        rawImage: CGImage,
        extraImages: [CGImage] = [],
        collageLayout: MultiImageLayoutMode = .horizontal,
        collageFitMode: MultiImageFitMode = .fit,
        collageSpacing: CGFloat = 24,
        savedURL: URL? = nil,
        style: BeautifyStyle = .defaultScreenshot,
        annotations: [AnnotationItem] = [],
        enableBeautify: Bool = true,
        privacyFindings: [PrivacyFinding] = []
    ) {
        self.id = id
        self.capturedAt = capturedAt
        self.rawImage = rawImage
        self.collageImages = [CollageImageItem(image: rawImage)] + extraImages.map { CollageImageItem(image: $0) }
        self.collageLayout = collageLayout
        self.collageFitMode = collageFitMode
        self.collageSpacing = collageSpacing
        self.savedURL = savedURL
        self.style = style
        self.annotations = annotations
        self.enableBeautify = enableBeautify
        self.privacyFindings = privacyFindings
    }

    public var isMultiImage: Bool {
        collageImages.count > 1
    }

    public var currentCollagePlan: MultiImageLayoutResult {
        MultiImageLayoutEngine.computeLayout(
            imageSizes: collageImages.map(\.pixelSize),
            mode: collageLayout,
            spacing: collageSpacing,
            fitMode: collageFitMode
        )
    }

    public var pixelSize: CGSize {
        if isMultiImage {
            return currentCollagePlan.compositeSize
        }
        return CGSize(width: rawImage.width, height: rawImage.height)
    }

    /// Appends a new image into the multi-image collage (up to `maxCount`), baking any single-image
    /// annotations onto tile #1 before transitioning from single-image to multi-image layout so
    /// privacy redactions and vector callouts stay pixel-locked to image #1.
    @discardableResult
    public func appendCollageImage(_ image: CGImage, maxCount: Int = 6) -> Bool {
        guard collageImages.count < maxCount else { return false }
        let previousCount = collageImages.count
        if previousCount == 1, !annotations.isEmpty {
            if let bakedFirst = ScreenshotRenderer.renderAnnotatedRawImage(rawImage: rawImage, annotations: annotations) {
                rawImage = bakedFirst
            }
            annotations.removeAll()
            privacyFindings.removeAll()
        }

        collageImages.append(CollageImageItem(image: image))
        if previousCount == 1 {
            collageLayout = .horizontal
        } else if previousCount == 2 && collageLayout == .horizontal {
            collageLayout = .bentoHero
        } else if previousCount == 3 && (collageLayout == .bentoHero || collageLayout == .horizontal) {
            collageLayout = .grid2x2
        }
        enableBeautify = true
        return true
    }
}

public final class RecordingSession: Identifiable, ObservableObject {
    public let id: UUID
    public let recordedAt: Date
    public let rawVideoURL: URL
    public let videoSize: CGSize
    public let duration: Double
    public let fps: Int
    public let hasSystemAudio: Bool
    public let hasMicAudio: Bool
    public let telemetry: RecordingTelemetry
    public var webcamVideoURL: URL?

    @Published public var style: BeautifyStyle
    @Published public var webcamPiP: WebcamPiPConfig
    @Published public var zoomSegments: [ZoomSegment]
    @Published public var enableAutoZoom: Bool
    @Published public var includeClickZoom: Bool
    @Published public var includeTypingFocusZoom: Bool
    @Published public var enableSmoothCursor: Bool
    @Published public var enableClickRipples: Bool
    @Published public var enableKeystrokes: Bool
    @Published public var keystrokeStyle: KeystrokeStyleConfig
    @Published public var cursorScale: Double
    @Published public var trimStart: Double
    @Published public var trimEnd: Double
    @Published public var clipSegments: [VideoClipSegment] {
        didSet {
            if let first = clipSegments.first { trimStart = first.sourceStart }
            if let last = clipSegments.last { trimEnd = last.sourceEnd }
        }
    }
    @Published public var audioVolume: Double
    @Published public var fadeConfig: VideoFadeConfig
    @Published public var exportPreset: VideoExportPreset
    @Published public var includeAudio: Bool
    @Published public var lastExportedURL: URL?

    public init(
        id: UUID = UUID(),
        recordedAt: Date = Date(),
        rawVideoURL: URL,
        videoSize: CGSize,
        duration: Double,
        fps: Int,
        hasSystemAudio: Bool,
        hasMicAudio: Bool,
        telemetry: RecordingTelemetry,
        webcamVideoURL: URL? = nil,
        webcamPiP: WebcamPiPConfig = .default,
        style: BeautifyStyle = .defaultVideo,
        zoomSegments: [ZoomSegment] = [],
        enableKeystrokesByDefault: Bool = true,
        keystrokeStyle: KeystrokeStyleConfig = .default,
        enableTypingFocusZoom: Bool = true
    ) {
        let safeDur = max(0.1, duration)
        self.id = id
        self.recordedAt = recordedAt
        self.rawVideoURL = rawVideoURL
        self.videoSize = videoSize
        self.duration = safeDur
        self.fps = fps
        self.hasSystemAudio = hasSystemAudio
        self.hasMicAudio = hasMicAudio
        self.telemetry = telemetry
        self.webcamVideoURL = webcamVideoURL
        var resolvedCam = webcamPiP
        resolvedCam.enabled = (webcamVideoURL != nil) && webcamPiP.enabled
        self.webcamPiP = resolvedCam
        self.style = style
        self.zoomSegments = zoomSegments
        self.enableAutoZoom = !zoomSegments.isEmpty
        self.includeClickZoom = true
        self.includeTypingFocusZoom = enableTypingFocusZoom
        self.enableSmoothCursor = telemetry.hidNativeCursor && !telemetry.cursorSamples.isEmpty
        self.enableClickRipples = !telemetry.clickEvents.isEmpty
        self.enableKeystrokes = enableKeystrokesByDefault && !telemetry.keystrokeEvents.isEmpty
        self.keystrokeStyle = keystrokeStyle
        self.cursorScale = 1.25
        self.trimStart = 0
        self.trimEnd = safeDur
        self.clipSegments = [VideoClipSegment(sourceStart: 0, sourceEnd: safeDur, speed: 1.0)]
        self.audioVolume = 1.0
        self.fadeConfig = .none
        self.exportPreset = .xOptimal1080p60
        self.includeAudio = hasSystemAudio || hasMicAudio
    }

    public var outputDuration: Double {
        VideoTimelineMapper.totalOutputDuration(of: clipSegments)
    }

    public var hasTimelineEdits: Bool {
        if clipSegments.count != 1 { return true }
        guard let only = clipSegments.first else { return false }
        return only.sourceStart > 0.05 || only.sourceEnd < duration - 0.05 || abs(only.speed - 1.0) > 0.01
    }

    public func resetTimeline() {
        clipSegments = [VideoClipSegment(sourceStart: 0, sourceEnd: duration, speed: 1.0)]
    }

    /// Loads any existing local `.mp4` / `.mov` recording into a ready-to-edit `RecordingSession`!
    public static func loadLocalVideo(url: URL) async throws -> RecordingSession {
        let asset = AVURLAsset(url: url)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else {
            throw VideoExportError.noVideoTrack
        }
        let naturalSize = try await videoTrack.load(.naturalSize)
        let transform = try await videoTrack.load(.preferredTransform)
        let transformed = naturalSize.applying(transform)
        let size = CGSize(width: max(2, abs(transformed.width)), height: max(2, abs(transformed.height)))
        let durationSec = max(0.1, try await asset.load(.duration).seconds)
        let nominalFPS = try await videoTrack.load(.nominalFrameRate)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)

        return RecordingSession(
            rawVideoURL: url,
            videoSize: size,
            duration: durationSec,
            fps: max(24, Int(nominalFPS.rounded())),
            hasSystemAudio: !audioTracks.isEmpty,
            hasMicAudio: false,
            telemetry: RecordingTelemetry(),
            style: .defaultVideo,
            zoomSegments: [],
            enableKeystrokesByDefault: false
        )
    }
}

public struct CaptureHistoryItem: Identifiable {
    public enum MediaKind {
        case screenshot
        case video
    }

    public let id: UUID
    public let kind: MediaKind
    public let createdAt: Date
    public let fileURL: URL
    public let thumbnail: NSImage?
    public let title: String

    public init(id: UUID = UUID(), kind: MediaKind, createdAt: Date = Date(), fileURL: URL, thumbnail: NSImage?, title: String) {
        self.id = id
        self.kind = kind
        self.createdAt = createdAt
        self.fileURL = fileURL
        self.thumbnail = thumbnail
        self.title = title
    }
}

/// Pure, testable coordinate conversions between AppKit (bottom-left global) and Quartz / ScreenCaptureKit (top-left global).
public enum CoordinateConverter {
    /// Height of the primary display (whose origin is (0,0) in AppKit).
    public static func primaryScreenHeight() -> CGFloat {
        if let primary = NSScreen.screens.first(where: { $0.frame.origin == .zero }) {
            return primary.frame.height
        }
        return NSScreen.main?.frame.height ?? 1080
    }

    /// Converts an AppKit global rect (bottom-left origin) to Quartz global rect (top-left origin).
    public static func appKitToQuartz(_ rect: CGRect, primaryHeight: CGFloat? = nil) -> CGRect {
        let h = primaryHeight ?? primaryScreenHeight()
        return CGRect(
            x: rect.origin.x,
            y: h - rect.origin.y - rect.size.height,
            width: rect.size.width,
            height: rect.size.height
        )
    }

    /// Converts a Quartz global rect (top-left origin) to AppKit global rect (bottom-left origin).
    public static func quartzToAppKit(_ rect: CGRect, primaryHeight: CGFloat? = nil) -> CGRect {
        let h = primaryHeight ?? primaryScreenHeight()
        return CGRect(
            x: rect.origin.x,
            y: h - rect.origin.y - rect.size.height,
            width: rect.size.width,
            height: rect.size.height
        )
    }

    /// Converts an AppKit mouse point (bottom-left origin) to Quartz global point (top-left origin).
    public static func appKitPointToQuartz(_ point: CGPoint, primaryHeight: CGFloat? = nil) -> CGPoint {
        let h = primaryHeight ?? primaryScreenHeight()
        return CGPoint(x: point.x, y: h - point.y)
    }

    /// Converts a global Quartz rect to display-local top-left coordinates for `SCStreamConfiguration.sourceRect`.
    public static func quartzToDisplayLocal(_ quartzRect: CGRect, displayQuartzBounds: CGRect) -> CGRect {
        let clamped = quartzRect.intersection(displayQuartzBounds)
        guard !clamped.isNull, !clamped.isEmpty else {
            return CGRect(origin: .zero, size: displayQuartzBounds.size)
        }
        return CGRect(
            x: clamped.origin.x - displayQuartzBounds.origin.x,
            y: clamped.origin.y - displayQuartzBounds.origin.y,
            width: clamped.width,
            height: clamped.height
        )
    }

    /// Ensures even integer dimensions >= 2 for H.264 / HEVC hardware video encoders.
    public static func evenPixelDimension(_ value: CGFloat) -> Int {
        let rounded = max(2, Int(value.rounded()))
        return rounded % 2 == 0 ? rounded : rounded + 1
    }

    /// Computes output canvas size (even pixels) and content rect inside the canvas for a given source size and BeautifyStyle.
    public static func computeCanvasLayout(
        sourceSize: CGSize,
        style: BeautifyStyle,
        maxLongEdge: Int? = nil,
        evenDimensions: Bool = true
    ) -> (canvasSize: CGSize, contentRect: CGRect, chromeHeight: CGFloat) {
        let srcW = max(1, sourceSize.width)
        let srcH = max(1, sourceSize.height)

        let hasBackground = style.background.kind != .transparent
        let effectivePadding = hasBackground ? max(0, style.padding) : 0
        let chromeHeight: CGFloat = (style.windowChrome != .none) ? max(28, min(56, round(min(srcW, srcH) * 0.045))) : 0

        // Scale padding relative to source size so 64pt looks balanced on both 1080p and 3000px Retina captures
        let scaleFactor = max(1.0, min(srcW, srcH) / 720.0)
        let padPx = effectivePadding * scaleFactor

        let totalContentH = srcH + chromeHeight
        var canvasW = srcW + padPx * 2
        var canvasH = totalContentH + padPx * 2

        if let targetRatio = style.aspectRatio.ratio {
            let currentRatio = canvasW / canvasH
            if currentRatio < targetRatio {
                canvasW = canvasH * targetRatio
            } else {
                canvasH = canvasW / targetRatio
            }
        }

        var downscale: CGFloat = 1.0
        if let maxEdge = maxLongEdge {
            let longest = max(canvasW, canvasH)
            if longest > CGFloat(maxEdge) {
                downscale = CGFloat(maxEdge) / longest
            }
        }

        let finalCanvasW: CGFloat
        let finalCanvasH: CGFloat
        if evenDimensions {
            finalCanvasW = CGFloat(evenPixelDimension(canvasW * downscale))
            finalCanvasH = CGFloat(evenPixelDimension(canvasH * downscale))
        } else {
            finalCanvasW = max(2, (canvasW * downscale).rounded())
            finalCanvasH = max(2, (canvasH * downscale).rounded())
        }

        let scaledChrome = (chromeHeight * downscale).rounded()
        let scaledContentW = (srcW * downscale).rounded()
        let scaledContentH = (srcH * downscale).rounded()
        let totalFrameH = scaledContentH + scaledChrome

        let frameOriginX = ((finalCanvasW - scaledContentW) / 2.0).rounded()
        let frameOriginY = ((finalCanvasH - totalFrameH) / 2.0).rounded()

        // Content rect in top-left origin coordinates (excludes chrome bar at top)
        let contentRect = CGRect(
            x: frameOriginX,
            y: frameOriginY + scaledChrome,
            width: scaledContentW,
            height: scaledContentH
        )

        return (CGSize(width: finalCanvasW, height: finalCanvasH), contentRect, scaledChrome)
    }
}

public enum CanvasViewMode: String, CaseIterable, Identifiable, Sendable {
    case fitScreen
    case fitWidth
    case actualSize
    case custom

    public var id: String { rawValue }
}

public struct CanvasViewportLayout: Equatable, Sendable {
    public let displayScale: CGFloat
    public let zoomPercentage: Int
    public let canvasRect: CGRect
    public let documentSize: CGSize
    public let needsScroll: Bool

    public init(
        displayScale: CGFloat,
        zoomPercentage: Int,
        canvasRect: CGRect,
        documentSize: CGSize,
        needsScroll: Bool
    ) {
        self.displayScale = displayScale
        self.zoomPercentage = zoomPercentage
        self.canvasRect = canvasRect
        self.documentSize = documentSize
        self.needsScroll = needsScroll
    }
}

/// Pure, testable geometry solver for ScreenshotEditorView's multi-mode 120Hz canvas viewport
/// (Fit Screen, Fit Width for long screenshots, 1:1 Retina Actual Size, and Custom Zoom 15%–400%).
public enum CanvasViewportCalculator {
    public static let minZoom: CGFloat = 0.15
    public static let maxZoom: CGFloat = 4.00

    /// Automatically picks `.fitWidth` for tall/scrolling screenshots so text is crisp & readable immediately.
    public static func recommendedInitialMode(for canvasPixelSize: CGSize) -> CanvasViewMode {
        let ratio = canvasPixelSize.height / max(1, canvasPixelSize.width)
        return ratio >= 1.85 ? .fitWidth : .fitScreen
    }

    public static func computeLayout(
        canvasPixelSize: CGSize,
        viewportSize: CGSize,
        mode: CanvasViewMode,
        customZoom: CGFloat,
        screenBackingScale: CGFloat = 2.0,
        padTop: CGFloat = 48,
        padBottom: CGFloat = 76,
        padX: CGFloat = 28
    ) -> CanvasViewportLayout {
        let safeW = max(1, canvasPixelSize.width)
        let safeH = max(1, canvasPixelSize.height)
        let backing = max(1.0, screenBackingScale)
        let availW = max(80, viewportSize.width - padX * 2)
        let availH = max(80, viewportSize.height - padTop - padBottom)

        let rawScale: CGFloat
        switch mode {
        case .fitScreen:
            rawScale = min(availW / safeW, availH / safeH)
        case .fitWidth:
            // Fill stage width cleanly so long screenshots stay razor-sharp; avoid extreme upscaling on tiny strips
            rawScale = min(availW / safeW, 1.0)
        case .actualSize:
            rawScale = 1.0 / backing
        case .custom:
            let clamped = min(max(customZoom, minZoom), maxZoom)
            rawScale = clamped / backing
        }

        let displayScale = max(0.03, min(rawScale, maxZoom / backing * 2.0))
        let renderedW = (safeW * displayScale).rounded()
        let renderedH = (safeH * displayScale).rounded()

        let docW = max(viewportSize.width, renderedW + padX * 2)
        let docH = max(viewportSize.height, renderedH + padTop + padBottom)

        let originX = ((docW - renderedW) / 2.0).rounded()
        let originY: CGFloat
        if renderedH <= availH {
            originY = (padTop + (availH - renderedH) / 2.0).rounded()
        } else {
            originY = padTop
        }

        let zoomPct = max(1, Int((displayScale * backing * 100.0).rounded()))
        let needsScroll = (docW > viewportSize.width + 1) || (docH > viewportSize.height + 1)

        return CanvasViewportLayout(
            displayScale: displayScale,
            zoomPercentage: zoomPct,
            canvasRect: CGRect(x: originX, y: originY, width: renderedW, height: renderedH),
            documentSize: CGSize(width: docW, height: docH),
            needsScroll: needsScroll
        )
    }

    public static func steppedZoom(from currentZoom: CGFloat, zoomIn: Bool) -> CGFloat {
        let stops: [CGFloat] = [0.15, 0.25, 0.33, 0.50, 0.67, 0.75, 1.00, 1.25, 1.50, 2.00, 3.00, 4.00]
        if zoomIn {
            if let next = stops.first(where: { $0 > currentZoom + 0.02 }) {
                return next
            }
            return maxZoom
        } else {
            if let prev = stops.last(where: { $0 < currentZoom - 0.02 }) {
                return prev
            }
            return minZoom
        }
    }
}
