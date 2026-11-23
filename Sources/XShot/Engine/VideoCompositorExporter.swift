import AppKit
@preconcurrency import AVFoundation
import CoreGraphics
@preconcurrency import CoreImage
import CoreMedia
import CoreVideo
import Foundation
@preconcurrency import ImageIO
import Metal
import UniformTypeIdentifiers
import VideoToolbox

public struct VideoCompositeOptions: Sendable {
    public var style: BeautifyStyle
    public var zoomSegments: [ZoomSegment]
    public var enableAutoZoom: Bool
    public var enableSmoothCursor: Bool
    public var enableClickRipples: Bool
    public var enableKeystrokes: Bool
    public var keystrokeStyle: KeystrokeStyleConfig
    /// Preview-only sample keystroke so Studio lets users visually adjust style/position on any frame (never set during export).
    public var previewSampleKeystroke: KeystrokeEvent?
    public var cursorScale: Double
    public var trimStart: Double
    public var trimEnd: Double
    /// Non-destructive kept source clips (supports middle cuts & per-clip speed!).
    /// When empty, falls back seamlessly to a single `1.0x` clip covering `trimStart...trimEnd`.
    public var clipSegments: [VideoClipSegment]
    public var audioVolume: Double
    public var fadeConfig: VideoFadeConfig
    public var exportPreset: VideoExportPreset
    public var includeAudio: Bool
    public var telemetry: RecordingTelemetry
    public var webcamVideoURL: URL?
    public var webcamPiP: WebcamPiPConfig

    public init(session: RecordingSession, previewSampleKeystroke: KeystrokeEvent? = nil) {
        self.style = session.style
        self.zoomSegments = session.zoomSegments
        self.enableAutoZoom = session.enableAutoZoom
        self.enableSmoothCursor = session.enableSmoothCursor
        self.enableClickRipples = session.enableClickRipples
        self.enableKeystrokes = session.enableKeystrokes
        self.keystrokeStyle = session.keystrokeStyle
        self.previewSampleKeystroke = previewSampleKeystroke
        self.cursorScale = session.cursorScale
        self.trimStart = session.trimStart
        self.trimEnd = session.trimEnd
        self.clipSegments = session.clipSegments
        self.audioVolume = session.audioVolume
        self.fadeConfig = session.fadeConfig
        self.exportPreset = session.exportPreset
        self.includeAudio = session.includeAudio
        self.telemetry = session.telemetry
        self.webcamVideoURL = session.webcamVideoURL
        self.webcamPiP = session.webcamPiP
    }

    public init(
        style: BeautifyStyle,
        zoomSegments: [ZoomSegment] = [],
        enableAutoZoom: Bool = true,
        enableSmoothCursor: Bool = true,
        enableClickRipples: Bool = true,
        enableKeystrokes: Bool = false,
        keystrokeStyle: KeystrokeStyleConfig = .default,
        previewSampleKeystroke: KeystrokeEvent? = nil,
        cursorScale: Double = 1.25,
        trimStart: Double = 0,
        trimEnd: Double,
        clipSegments: [VideoClipSegment] = [],
        audioVolume: Double = 1.0,
        fadeConfig: VideoFadeConfig = .none,
        exportPreset: VideoExportPreset = .xOptimal1080p60,
        includeAudio: Bool = true,
        telemetry: RecordingTelemetry = RecordingTelemetry(),
        webcamVideoURL: URL? = nil,
        webcamPiP: WebcamPiPConfig = .default
    ) {
        self.style = style
        self.zoomSegments = zoomSegments
        self.enableAutoZoom = enableAutoZoom
        self.enableSmoothCursor = enableSmoothCursor
        self.enableClickRipples = enableClickRipples
        self.enableKeystrokes = enableKeystrokes
        self.keystrokeStyle = keystrokeStyle
        self.previewSampleKeystroke = previewSampleKeystroke
        self.cursorScale = cursorScale
        self.trimStart = trimStart
        self.trimEnd = trimEnd
        self.clipSegments = clipSegments
        self.audioVolume = audioVolume
        self.fadeConfig = fadeConfig
        self.exportPreset = exportPreset
        self.includeAudio = includeAudio
        self.telemetry = telemetry
        self.webcamVideoURL = webcamVideoURL
        self.webcamPiP = webcamPiP
    }
}

public struct ExportProgressUpdate: Sendable {
    public let progress: Double
    public let framesPerSecond: Double
    public let estimatedRemainingSeconds: Double

    public init(progress: Double, framesPerSecond: Double = 0, estimatedRemainingSeconds: Double = 0) {
        self.progress = progress
        self.framesPerSecond = framesPerSecond
        self.estimatedRemainingSeconds = estimatedRemainingSeconds
    }
}

public enum VideoExportError: LocalizedError {
    case noVideoTrack
    case failedToCreateReader(String)
    case failedToCreateWriter(String)
    case failedToRenderFrame
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .noVideoTrack: return L10n.t(.errNoVideoTrack)
        case .failedToCreateReader(let msg): return L10n.format(.errReadVideoFailedFormat, msg)
        case .failedToCreateWriter(let msg): return L10n.format(.errWriteVideoFailedFormat, msg)
        case .failedToRenderFrame: return L10n.t(.errRenderFrameFailed)
        case .cancelled: return L10n.t(.errExportCancelled)
        }
    }
}

/// High-speed Metal GPU + Zero-Copy IOSurface VideoToolbox compositor & X/Twitter MP4 / GIF exporter.
/// All static layers (background, drop shadow, rounded mask, chrome bar) AND dynamic sprites (vector cursor,
/// click ripple ring, keystroke pill) are pre-baked into GPU-resident textures for zero per-frame CPU allocation.
public final class VideoCompositorExporter: @unchecked Sendable {
    private let mtlDevice: MTLDevice?
    private let ciContext: CIContext
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    // Cached GPU sprites (rendered once on init — tiny textures, zero per-frame allocation!)
    private let cursorSpriteCI: CIImage?
    private let cursorSpriteTipOffset: CGPoint // In sprite's bottom-left CI coords
    private let cursorSpriteBaseHeight: CGFloat = 96.0
    private let rippleSpriteCI: CIImage?
    private let rippleSpriteSize: CGFloat = 192.0

    // Preview cache so scrubbing & playback never rebuild static canvas layers
    private let cacheLock = NSLock()
    private var cachedPreviewKey: PreviewCacheKey?
    private var cachedPreviewCanvas: PreparedCanvas?
    private var cachedKeystrokeText: String = ""
    private var cachedKeystrokeCI: CIImage?
    private var cachedWebcamOverlayKey: WebcamOverlayKey?
    private var cachedWebcamOverlay: PreparedWebcamOverlay?

    private struct PreviewCacheKey: Equatable {
        let sourceW: Int
        let sourceH: Int
        let style: BeautifyStyle
        let maxLongEdge: Int
    }

    private struct WebcamOverlayKey: Equatable {
        let canvasW: Int
        let canvasH: Int
        let config: WebcamPiPConfig
    }

    private struct PreparedWebcamOverlay {
        let pipRect: CGRect
        let shadowCI: CIImage
        let maskCI: CIImage
        let borderCI: CIImage?
    }

    public init() {
        let device = MTLCreateSystemDefaultDevice()
        self.mtlDevice = device
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx: CIContext
        if let device {
            ctx = CIContext(
                mtlDevice: device,
                options: [
                    .workingColorSpace: cs,
                    .outputColorSpace: cs,
                    .cacheIntermediates: true,
                    .priorityRequestLow: false
                ]
            )
        } else {
            ctx = CIContext(options: [
                .workingColorSpace: cs,
                .outputColorSpace: cs,
                .cacheIntermediates: true
            ])
        }
        self.ciContext = ctx

        // Pre-bake crisp high-DPI cursor & ripple sprites once!
        let cursorRes = Self.makeCursorSprite(baseSize: 96, colorSpace: cs)
        self.cursorSpriteCI = cursorRes.image.map { Self.bakeToMetalIfPossible($0, device: device, ciContext: ctx, colorSpace: cs) }
        self.cursorSpriteTipOffset = cursorRes.tipInCI

        let rippleCG = Self.makeRippleSprite(size: 192, colorSpace: cs)
        self.rippleSpriteCI = rippleCG.map { Self.bakeToMetalIfPossible(CIImage(cgImage: $0), device: device, ciContext: ctx, colorSpace: cs) }
    }

    /// Uploads a static CIImage once into a persistent Metal texture so per-frame compositing does 0 CPU->GPU uploads.
    private static func bakeToMetalIfPossible(_ image: CIImage, device: MTLDevice?, ciContext: CIContext, colorSpace: CGColorSpace) -> CIImage {
        let w = Int(image.extent.width.rounded())
        let h = Int(image.extent.height.rounded())
        guard let device, w > 0, h > 0 else { return image }

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: w,
            height: h,
            mipmapped: false
        )
        desc.usage = [.shaderRead, .shaderWrite]
        desc.storageMode = .private

        guard let texture = device.makeTexture(descriptor: desc) else { return image }
        ciContext.render(
            image,
            to: texture,
            commandBuffer: nil,
            bounds: CGRect(x: 0, y: 0, width: w, height: h),
            colorSpace: colorSpace
        )
        return CIImage(mtlTexture: texture, options: [.colorSpace: colorSpace]) ?? image
    }

    private static func makeCursorSprite(baseSize: Int, colorSpace: CGColorSpace) -> (image: CIImage?, tipInCI: CGPoint) {
        let pad = 16
        let dim = baseSize + pad * 2
        guard let ctx = CGContext(
            data: nil,
            width: dim,
            height: dim,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return (nil, .zero) }

        ctx.clear(CGRect(x: 0, y: 0, width: dim, height: dim))
        ctx.translateBy(x: 0, y: CGFloat(dim))
        ctx.scaleBy(x: 1, y: -1)

        let tipTopLeft = CGPoint(x: CGFloat(pad), y: CGFloat(pad))
        let s = CGFloat(baseSize) / 24.0
        ctx.saveGState()
        ctx.translateBy(x: tipTopLeft.x, y: tipTopLeft.y)
        ctx.scaleBy(x: s, y: s)

        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: 0, y: 21.5))
        path.addLine(to: CGPoint(x: 5.2, y: 16.5))
        path.addLine(to: CGPoint(x: 9.2, y: 24.5))
        path.addLine(to: CGPoint(x: 12.6, y: 22.8))
        path.addLine(to: CGPoint(x: 8.6, y: 14.8))
        path.addLine(to: CGPoint(x: 15.5, y: 14.8))
        path.closeSubpath()

        ctx.setShadow(offset: CGSize(width: 0, height: 1.8), blur: 3.5, color: CGColor(gray: 0, alpha: 0.45))
        ctx.setFillColor(CGColor(srgbRed: 0.05, green: 0.06, blue: 0.08, alpha: 1.0))
        ctx.addPath(path)
        ctx.fillPath()

        ctx.setShadow(offset: .zero, blur: 0, color: nil)
        ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.98))
        ctx.setLineWidth(1.9)
        ctx.setLineJoin(.round)
        ctx.addPath(path)
        ctx.strokePath()
        ctx.restoreGState()

        guard let cg = ctx.makeImage() else { return (nil, .zero) }
        // In CI coordinates (bottom-left origin), tip is at (pad, dim - pad)
        return (CIImage(cgImage: cg), CGPoint(x: CGFloat(pad), y: CGFloat(dim - pad)))
    }

    private static func makeRippleSprite(size: Int, colorSpace: CGColorSpace) -> CGImage? {
        guard let ctx = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.clear(CGRect(x: 0, y: 0, width: size, height: size))
        let inset: CGFloat = 10
        let ringRect = CGRect(x: inset, y: inset, width: CGFloat(size) - inset * 2, height: CGFloat(size) - inset * 2)
        ctx.setFillColor(CGColor(srgbRed: 0.22, green: 0.74, blue: 0.97, alpha: 0.24))
        ctx.fillEllipse(in: ringRect)
        ctx.setStrokeColor(CGColor(srgbRed: 0.22, green: 0.78, blue: 1.0, alpha: 0.95))
        ctx.setLineWidth(7.0)
        ctx.strokeEllipse(in: ringRect)
        return ctx.makeImage()
    }

    /// Precomputed GPU-resident static layers for a render session.
    private struct PreparedCanvas: @unchecked Sendable {
        let canvasSize: CGSize
        let contentRectTopLeft: CGRect
        let contentRectCG: CGRect      // bottom-left origin (CoreImage)
        let fullFrameCG: CGRect
        let chromeHeight: CGFloat
        let cornerRadius: CGFloat
        let scaleFactor: CGFloat
        let backgroundWithShadowCI: CIImage
        let roundedMaskCI: CIImage
        let chromeAndStrokeOverlayCI: CIImage?
        let isSimpleFullBleed: Bool
    }

    private func getOrPrepareCanvas(sourceSize: CGSize, style: BeautifyStyle, maxLongEdge: Int, useCache: Bool) -> PreparedCanvas? {
        let key = PreviewCacheKey(
            sourceW: Int(sourceSize.width.rounded()),
            sourceH: Int(sourceSize.height.rounded()),
            style: style,
            maxLongEdge: maxLongEdge
        )
        if useCache {
            cacheLock.lock()
            if cachedPreviewKey == key, let existing = cachedPreviewCanvas {
                cacheLock.unlock()
                return existing
            }
            cacheLock.unlock()
        }

        guard let prepared = prepareCanvas(sourceSize: sourceSize, style: style, maxLongEdge: maxLongEdge) else {
            return nil
        }

        if useCache {
            cacheLock.lock()
            cachedPreviewKey = key
            cachedPreviewCanvas = prepared
            cacheLock.unlock()
        }
        return prepared
    }

    private func prepareCanvas(sourceSize: CGSize, style: BeautifyStyle, maxLongEdge: Int) -> PreparedCanvas? {
        let layout = CoordinateConverter.computeCanvasLayout(
            sourceSize: sourceSize,
            style: style,
            maxLongEdge: maxLongEdge,
            evenDimensions: true
        )

        let canvasW = Int(layout.canvasSize.width)
        let canvasH = Int(layout.canvasSize.height)
        let scaleFactor = max(1.0, min(layout.contentRect.width, layout.contentRect.height) / 720.0)
        let cornerRadius = min(style.cornerRadius * scaleFactor, min(layout.contentRect.width, layout.contentRect.height) * 0.25)

        let fullFrameTopLeft = CGRect(
            x: layout.contentRect.origin.x,
            y: layout.contentRect.origin.y - layout.chromeHeight,
            width: layout.contentRect.width,
            height: layout.contentRect.height + layout.chromeHeight
        )
        let fullFrameCG = CGRect(
            x: fullFrameTopLeft.origin.x,
            y: layout.canvasSize.height - fullFrameTopLeft.origin.y - fullFrameTopLeft.height,
            width: fullFrameTopLeft.width,
            height: fullFrameTopLeft.height
        )
        let contentCG = CGRect(
            x: layout.contentRect.origin.x,
            y: layout.canvasSize.height - layout.contentRect.origin.y - layout.contentRect.height,
            width: layout.contentRect.width,
            height: layout.contentRect.height
        )

        let isSimpleFullBleed =
            style.background.kind == .transparent &&
            cornerRadius < 1 &&
            layout.chromeHeight == 0 &&
            !style.insetStroke &&
            contentCG.size == layout.canvasSize

        // 1. Background + drop shadow baked ONCE directly into GPU VRAM texture
        guard let bgCtx = CGContext(
            data: nil,
            width: canvasW,
            height: canvasH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ScreenshotRenderer.drawBackground(in: bgCtx, size: layout.canvasSize, preset: style.background)
        let cardPath = CGPath(roundedRect: fullFrameCG, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        if style.shadowRadius > 0 && style.shadowOpacity > 0.01 && style.background.kind != .transparent {
            let shadowBlur = style.shadowRadius * scaleFactor
            bgCtx.saveGState()
            bgCtx.setShadow(
                offset: CGSize(width: 0, height: -shadowBlur * 0.28),
                blur: shadowBlur,
                color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: style.shadowOpacity)
            )
            bgCtx.setFillColor(CGColor(srgbRed: 0.05, green: 0.05, blue: 0.08, alpha: 1.0))
            bgCtx.addPath(cardPath)
            bgCtx.fillPath()
            bgCtx.restoreGState()
        }
        guard let bgCG = bgCtx.makeImage() else { return nil }
        let bgGPU = Self.bakeToMetalIfPossible(CIImage(cgImage: bgCG), device: mtlDevice, ciContext: ciContext, colorSpace: colorSpace)

        // 2. Rounded card alpha mask baked ONCE into GPU VRAM texture
        guard let maskCtx = CGContext(
            data: nil,
            width: canvasW,
            height: canvasH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        maskCtx.clear(CGRect(origin: .zero, size: layout.canvasSize))
        maskCtx.saveGState()
        maskCtx.addPath(cardPath)
        maskCtx.clip()
        maskCtx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        maskCtx.fill(contentCG)
        maskCtx.restoreGState()
        guard let maskCG = maskCtx.makeImage() else { return nil }
        let maskGPU = Self.bakeToMetalIfPossible(CIImage(cgImage: maskCG), device: mtlDevice, ciContext: ciContext, colorSpace: colorSpace)

        // 3. Optional window chrome bar + crisp inner stroke + custom watermark baked ONCE into GPU VRAM texture
        var overlayGPU: CIImage?
        if layout.chromeHeight > 0 || style.insetStroke || style.watermark.isEffectivelyVisible {
            if let ovCtx = CGContext(
                data: nil,
                width: canvasW,
                height: canvasH,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) {
                ovCtx.clear(CGRect(origin: .zero, size: layout.canvasSize))
                if layout.chromeHeight > 0 {
                    ovCtx.saveGState()
                    ovCtx.addPath(cardPath)
                    ovCtx.clip()
                    let chromeCG = CGRect(
                        x: fullFrameCG.origin.x,
                        y: contentCG.maxY,
                        width: fullFrameCG.width,
                        height: layout.chromeHeight
                    )
                    ScreenshotRenderer.drawWindowChromeBar(in: ovCtx, rect: chromeCG, style: style.windowChrome, title: style.windowTitle)
                    ovCtx.restoreGState()
                }
                if style.insetStroke {
                    let strokeWidth = max(1.0, 1.2 * scaleFactor)
                    let insetRect = fullFrameCG.insetBy(dx: strokeWidth / 2.0, dy: strokeWidth / 2.0)
                    let insetPath = CGPath(
                        roundedRect: insetRect,
                        cornerWidth: max(0, cornerRadius - strokeWidth / 2.0),
                        cornerHeight: max(0, cornerRadius - strokeWidth / 2.0),
                        transform: nil
                    )
                    ovCtx.addPath(insetPath)
                    ovCtx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.22))
                    ovCtx.setLineWidth(strokeWidth)
                    ovCtx.strokePath()
                }
                if style.watermark.isEffectivelyVisible {
                    ScreenshotRenderer.drawWatermark(in: ovCtx, canvasSize: layout.canvasSize, config: style.watermark)
                }
                if let ovCG = ovCtx.makeImage() {
                    overlayGPU = Self.bakeToMetalIfPossible(CIImage(cgImage: ovCG), device: mtlDevice, ciContext: ciContext, colorSpace: colorSpace)
                }
            }
        }

        return PreparedCanvas(
            canvasSize: layout.canvasSize,
            contentRectTopLeft: layout.contentRect,
            contentRectCG: contentCG,
            fullFrameCG: fullFrameCG,
            chromeHeight: layout.chromeHeight,
            cornerRadius: cornerRadius,
            scaleFactor: scaleFactor,
            backgroundWithShadowCI: bgGPU,
            roundedMaskCI: maskGPU,
            chromeAndStrokeOverlayCI: overlayGPU,
            isSimpleFullBleed: isSimpleFullBleed
        )
    }

    /// 100% pure Metal GPU per-frame compositor — ZERO CPU bitmap allocations per frame!
    private func composeFrameCI(
        sourceImage: CIImage,
        time: Double,
        canvas: PreparedCanvas,
        options: VideoCompositeOptions,
        smoothedCursorPath: [CursorSample],
        fadeOpacity: Double = 1.0,
        webcamImage: CIImage? = nil
    ) -> CIImage {
        let srcExtent = sourceImage.extent
        let srcSize = srcExtent.size

        // 1. Evaluate smooth camera zoom viewport (tracks clicks AND moving typing caret!)
        let camera = AutoZoomEngine.evaluateCamera(
            at: time,
            segments: options.zoomSegments,
            smoothedCursorPath: smoothedCursorPath,
            typingFocusEvents: options.telemetry.typingFocusEvents,
            enabled: options.enableAutoZoom
        )
        let cropTopLeft = camera.sourceCropRect(for: srcSize)

        let cropCI = CGRect(
            x: srcExtent.origin.x + cropTopLeft.origin.x,
            y: srcExtent.origin.y + (srcSize.height - cropTopLeft.origin.y - cropTopLeft.height),
            width: cropTopLeft.width,
            height: cropTopLeft.height
        )

        // 2. Crop + GPU scale into contentRectCG
        let cropped = sourceImage.cropped(to: cropCI)
        let scaleX = canvas.contentRectCG.width / max(1, cropCI.width)
        let scaleY = canvas.contentRectCG.height / max(1, cropCI.height)

        var videoLayer = cropped
            .transformed(by: CGAffineTransform(translationX: -cropCI.origin.x, y: -cropCI.origin.y))
            .samplingLinear()
            .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
            .transformed(by: CGAffineTransform(translationX: canvas.contentRectCG.origin.x, y: canvas.contentRectCG.origin.y))
            .cropped(to: canvas.contentRectCG)

        // 3. Composite GPU click ripples & GPU cursor sprite DIRECTLY onto videoLayer before rounded mask!
        let cursorState = AutoZoomEngine.evaluateCursorState(
            at: time,
            smoothedSamples: smoothedCursorPath,
            clicks: options.telemetry.clickEvents
        )

        func mapSourceToCanvasCI(normX: Double, normY: Double) -> CGPoint {
            let srcX = normX * srcSize.width
            let srcY = normY * srcSize.height
            let relX = (srcX - cropTopLeft.origin.x) / max(1, cropTopLeft.width)
            let relY = (srcY - cropTopLeft.origin.y) / max(1, cropTopLeft.height)
            // Bottom-left CI coordinates
            let x = canvas.contentRectCG.origin.x + relX * canvas.contentRectCG.width
            let y = canvas.contentRectCG.maxY - relY * canvas.contentRectCG.height
            return CGPoint(x: x, y: y)
        }

        let zoomBoost = 1.0 + (camera.scale - 1.0) * 0.25

        if options.enableClickRipples, let rippleBase = rippleSpriteCI {
            for ripple in cursorState.activeRipples {
                let pt = mapSourceToCanvasCI(normX: ripple.x, normY: ripple.y)
                let eased = 1.0 - pow(1.0 - ripple.progress, 3.0)
                let diameter = (10.0 + eased * 54.0) * canvas.scaleFactor * zoomBoost
                let s = diameter / rippleSpriteSize
                let alpha = CGFloat(max(0, (1.0 - ripple.progress) * 0.80))

                let placedRipple = rippleBase
                    .applyingFilter("CIColorMatrix", parameters: [
                        "inputAVector": CIVector(x: 0, y: 0, z: 0, w: alpha)
                    ])
                    .transformed(by: CGAffineTransform(translationX: -rippleSpriteSize / 2, y: -rippleSpriteSize / 2))
                    .transformed(by: CGAffineTransform(scaleX: s, y: s))
                    .transformed(by: CGAffineTransform(translationX: pt.x, y: pt.y))
                    .cropped(to: canvas.contentRectCG)

                videoLayer = placedRipple.composited(over: videoLayer)
            }
        }

        if options.enableSmoothCursor, cursorState.isVisible, let cursorBase = cursorSpriteCI {
            let pt = mapSourceToCanvasCI(normX: cursorState.x, normY: cursorState.y)
            let pressScale = cursorState.isPressed ? 0.88 : 1.0
            let targetCursorSize = 24.0 * canvas.scaleFactor * options.cursorScale * zoomBoost * pressScale
            let s = targetCursorSize / cursorSpriteBaseHeight

            let placedCursor = cursorBase
                .transformed(by: CGAffineTransform(translationX: -cursorSpriteTipOffset.x, y: -cursorSpriteTipOffset.y))
                .transformed(by: CGAffineTransform(scaleX: s, y: s))
                .transformed(by: CGAffineTransform(translationX: pt.x, y: pt.y))
                .cropped(to: canvas.contentRectCG)

            videoLayer = placedCursor.composited(over: videoLayer)
        }

        // 4. Composite rounded card onto GPU-resident background + shadow
        var composed: CIImage
        if canvas.isSimpleFullBleed {
            composed = videoLayer
        } else {
            composed = videoLayer.applyingFilter("CIBlendWithAlphaMask", parameters: [
                kCIInputBackgroundImageKey: canvas.backgroundWithShadowCI,
                kCIInputMaskImageKey: canvas.roundedMaskCI
            ])
        }

        // 5. Optional window chrome, glass stroke & baked custom watermark
        if let chromeOverlay = canvas.chromeAndStrokeOverlayCI {
            composed = chromeOverlay.composited(over: composed)
        }

        // 5b. Optional GPU-composited Picture-in-Picture Webcam Overlay
        if options.webcamPiP.enabled,
           let camSrc = webcamImage,
           let camOverlay = getOrPrepareWebcamOverlay(canvasSize: canvas.canvasSize, config: options.webcamPiP) {
            let pipRect = camOverlay.pipRect
            let camExtent = camSrc.extent
            if camExtent.width > 1 && camExtent.height > 1 {
                let fillScale = max(pipRect.width / camExtent.width, pipRect.height / camExtent.height)
                let scaledW = camExtent.width * fillScale
                let scaledH = camExtent.height * fillScale

                var camLayer = camSrc
                    .transformed(by: CGAffineTransform(translationX: -camExtent.origin.x, y: -camExtent.origin.y))
                    .samplingLinear()
                    .transformed(by: CGAffineTransform(scaleX: fillScale, y: fillScale))
                    .transformed(by: CGAffineTransform(
                        translationX: pipRect.midX - scaledW / 2.0,
                        y: pipRect.midY - scaledH / 2.0
                    ))

                if options.webcamPiP.mirrored {
                    let flip = CGAffineTransform(translationX: pipRect.midX, y: 0)
                        .scaledBy(x: -1, y: 1)
                        .translatedBy(x: -pipRect.midX, y: 0)
                    camLayer = camLayer.transformed(by: flip)
                }

                camLayer = camLayer.cropped(to: pipRect)

                let withShadow = camOverlay.shadowCI.composited(over: composed)
                composed = camLayer.applyingFilter("CIBlendWithAlphaMask", parameters: [
                    kCIInputBackgroundImageKey: withShadow,
                    kCIInputMaskImageKey: camOverlay.maskCI
                ])
                if let border = camOverlay.borderCI {
                    composed = border.composited(over: composed)
                }
            }
        }

        // 6. Optional cached macOS Keycap / Live Typing HUD pill (customizable style, position & size!)
        let activeKeystrokeVisual: ActiveKeystrokeVisual? = {
            if options.enableKeystrokes,
               let live = AutoZoomEngine.activeKeystroke(
                    at: time,
                    keystrokes: options.telemetry.keystrokeEvents,
                    filterMode: options.keystrokeStyle.filterMode
               ) {
                return live
            }
            if options.enableKeystrokes, let sample = options.previewSampleKeystroke {
                return ActiveKeystrokeVisual(event: sample, opacity: 1.0, popScale: 1.0)
            }
            return nil
        }()

        if let ks = activeKeystrokeVisual,
           !ks.event.text.isEmpty,
           let pillBase = cachedKeystrokePillCI(
                event: ks.event,
                styleConfig: options.keystrokeStyle,
                scaleFactor: canvas.scaleFactor
           ) {
            let pillSize = pillBase.extent.size
            let pop = CGFloat(ks.popScale)
            let originCI = Self.keystrokeOriginInCI(
                pillSize: pillSize,
                popScale: pop,
                canvasSize: canvas.canvasSize,
                scaleFactor: canvas.scaleFactor,
                styleConfig: options.keystrokeStyle
            )

            let faded = pillBase
                .transformed(by: CGAffineTransform(scaleX: pop, y: pop))
                .applyingFilter("CIColorMatrix", parameters: [
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(ks.opacity))
                ])
                .transformed(by: CGAffineTransform(translationX: originCI.x, y: originCI.y))
            composed = faded.composited(over: composed)
        }

        // 7. Optional smooth Fade-In / Fade-Out to cinematic dark backdrop
        if fadeOpacity < 0.999 {
            let f = CGFloat(min(max(fadeOpacity, 0), 1))
            composed = composed.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: f, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: f, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: f, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
            ])
        }

        return composed.cropped(to: CGRect(origin: .zero, size: canvas.canvasSize))
    }

    /// Single source of truth for keystroke HUD bottom-left placement in CoreImage coordinates.
    public static func keystrokeOriginInCI(
        pillSize: CGSize,
        popScale: CGFloat = 1.0,
        canvasSize: CGSize,
        scaleFactor: CGFloat,
        styleConfig: KeystrokeStyleConfig
    ) -> CGPoint {
        let scaledW = pillSize.width * popScale
        let scaledH = pillSize.height * popScale
        let edgeMarginX = 22.0 * scaleFactor
        let edgeMarginY = 18.0 * scaleFactor

        switch styleConfig.position {
        case .topLeft:
            return CGPoint(x: edgeMarginX, y: canvasSize.height - scaledH - edgeMarginY - (pillSize.height - scaledH) / 2.0)
        case .topCenter:
            return CGPoint(x: (canvasSize.width - scaledW) / 2.0, y: canvasSize.height - scaledH - edgeMarginY - (pillSize.height - scaledH) / 2.0)
        case .topRight:
            return CGPoint(x: canvasSize.width - scaledW - edgeMarginX, y: canvasSize.height - scaledH - edgeMarginY - (pillSize.height - scaledH) / 2.0)
        case .bottomLeft:
            return CGPoint(x: edgeMarginX, y: edgeMarginY + (pillSize.height - scaledH) / 2.0)
        case .bottomCenter:
            return CGPoint(x: (canvasSize.width - scaledW) / 2.0, y: edgeMarginY + (pillSize.height - scaledH) / 2.0)
        case .bottomRight:
            return CGPoint(x: canvasSize.width - scaledW - edgeMarginX, y: edgeMarginY + (pillSize.height - scaledH) / 2.0)
        case .custom:
            let pad: CGFloat = 6.0 * scaleFactor
            let rawCenterX = CGFloat(styleConfig.customX) * canvasSize.width
            let rawCenterYCI = (1.0 - CGFloat(styleConfig.customY)) * canvasSize.height
            let minX = pad
            let maxX = max(minX, canvasSize.width - scaledW - pad)
            let minY = pad
            let maxY = max(minY, canvasSize.height - scaledH - pad)
            return CGPoint(
                x: min(max(rawCenterX - scaledW / 2.0, minX), maxX),
                y: min(max(rawCenterYCI - scaledH / 2.0, minY), maxY)
            )
        }
    }

    /// Renders the exact keystroke pill CGImage + its exact top-left normalized rect inside the preview canvas
    /// so VideoStudioView can drag it natively at 120Hz with ZERO latency and 1:1 pixel match!
    public func renderKeystrokeOverlayForPreview(
        sourceSize: CGSize,
        event: KeystrokeEvent,
        style: BeautifyStyle,
        keystrokeStyle: KeystrokeStyleConfig,
        maxPreviewEdge: Int = 1120
    ) -> (image: CGImage, normalizedRectTopLeft: CGRect)? {
        guard let canvas = getOrPrepareCanvas(
            sourceSize: sourceSize,
            style: style,
            maxLongEdge: maxPreviewEdge,
            useCache: true
        ),
              let pillCI = cachedKeystrokePillCI(event: event, styleConfig: keystrokeStyle, scaleFactor: canvas.scaleFactor),
              let pillCG = ciContext.createCGImage(pillCI, from: pillCI.extent) else {
            return nil
        }

        let pillSize = pillCI.extent.size
        let originCI = Self.keystrokeOriginInCI(
            pillSize: pillSize,
            popScale: 1.0,
            canvasSize: canvas.canvasSize,
            scaleFactor: canvas.scaleFactor,
            styleConfig: keystrokeStyle
        )
        // Convert bottom-left CI origin -> top-left normalized rect [0...1]
        let topLeftY = canvas.canvasSize.height - (originCI.y + pillSize.height)
        let normRect = CGRect(
            x: originCI.x / max(1, canvas.canvasSize.width),
            y: topLeftY / max(1, canvas.canvasSize.height),
            width: pillSize.width / max(1, canvas.canvasSize.width),
            height: pillSize.height / max(1, canvas.canvasSize.height)
        )
        return (pillCG, normRect)
    }

    private func cachedKeystrokePillCI(
        event: KeystrokeEvent,
        styleConfig: KeystrokeStyleConfig,
        scaleFactor: CGFloat
    ) -> CIImage? {
        let effectiveScale = scaleFactor * CGFloat(max(0.65, min(1.8, styleConfig.sizeScale)))
        let key = "\(styleConfig.visualStyle.rawValue):\(event.isTypingText ? "T" : "K"):\(event.keycaps.joined(separator: "|"))@\(Int((effectiveScale * 100).rounded()))"
        cacheLock.lock()
        if cachedKeystrokeText == key, let img = cachedKeystrokeCI {
            cacheLock.unlock()
            return img
        }
        cacheLock.unlock()

        let margin: CGFloat = 14 * effectiveScale
        let fontSize = max(14, 19 * effectiveScale)

        // Palette resolved by chosen KeystrokeVisualStyle
        let isLight = (styleConfig.visualStyle == .macKeycapLight)
        let isMinimal = (styleConfig.visualStyle == .minimalGlass)
        let isNeon = (styleConfig.visualStyle == .neonAccent)

        let trayFill: CGColor
        let trayStroke: CGColor
        let keycapFill: CGColor
        let keycapBevel: CGColor
        let keycapStroke: CGColor
        let textColor: NSColor
        let accentDotColor: CGColor

        switch styleConfig.visualStyle {
        case .macKeycapDark:
            trayFill = CGColor(srgbRed: 0.06, green: 0.07, blue: 0.10, alpha: 0.86)
            trayStroke = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.18)
            keycapFill = CGColor(srgbRed: 0.16, green: 0.18, blue: 0.24, alpha: 0.96)
            keycapBevel = CGColor(srgbRed: 0.02, green: 0.03, blue: 0.05, alpha: 0.92)
            keycapStroke = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.26)
            textColor = .white
            accentDotColor = CGColor(srgbRed: 0.16, green: 0.84, blue: 0.62, alpha: 1.0)

        case .macKeycapLight:
            trayFill = CGColor(srgbRed: 0.92, green: 0.93, blue: 0.96, alpha: 0.88)
            trayStroke = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.9)
            keycapFill = CGColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.98)
            keycapBevel = CGColor(srgbRed: 0.72, green: 0.74, blue: 0.80, alpha: 0.95)
            keycapStroke = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.12)
            textColor = NSColor(srgbRed: 0.10, green: 0.11, blue: 0.15, alpha: 1.0)
            accentDotColor = CGColor(srgbRed: 0.06, green: 0.58, blue: 0.90, alpha: 1.0)

        case .minimalGlass:
            trayFill = CGColor(srgbRed: 0.05, green: 0.06, blue: 0.09, alpha: 0.78)
            trayStroke = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.22)
            keycapFill = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.08)
            keycapBevel = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.0)
            keycapStroke = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.14)
            textColor = .white
            accentDotColor = CGColor(srgbRed: 0.22, green: 0.78, blue: 0.98, alpha: 1.0)

        case .neonAccent:
            trayFill = CGColor(srgbRed: 0.05, green: 0.06, blue: 0.12, alpha: 0.92)
            trayStroke = CGColor(srgbRed: 0.20, green: 0.82, blue: 1.0, alpha: 0.82)
            keycapFill = CGColor(srgbRed: 0.11, green: 0.14, blue: 0.26, alpha: 0.96)
            keycapBevel = CGColor(srgbRed: 0.38, green: 0.22, blue: 0.88, alpha: 0.85)
            keycapStroke = CGColor(srgbRed: 0.26, green: 0.84, blue: 1.0, alpha: 0.55)
            textColor = NSColor(srgbRed: 0.90, green: 0.98, blue: 1.0, alpha: 1.0)
            accentDotColor = CGColor(srgbRed: 0.22, green: 0.85, blue: 1.0, alpha: 1.0)
        }

        if !event.isTypingText && !isMinimal {
            // Render crisp physical macOS Keycaps: [ ⌘ ] [ ⇧ ] [ P ]
            let tokens = event.keycaps.isEmpty ? [event.text] : event.keycaps
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
                .foregroundColor: textColor
            ]
            let attrTokens = tokens.map { NSAttributedString(string: $0, attributes: attrs) }
            let keyPadX = 12 * effectiveScale
            let keyH = ceil(fontSize * 1.85)
            let minKeyW = keyH
            let keyGap = 7 * effectiveScale
            let trayPadX = 10 * effectiveScale
            let trayPadY = 8 * effectiveScale

            let keyWidths = attrTokens.map { max(minKeyW, ceil($0.size().width + keyPadX * 2)) }
            let totalKeysW = keyWidths.reduce(0, +) + keyGap * CGFloat(max(0, tokens.count - 1))
            let trayW = totalKeysW + trayPadX * 2
            let trayH = keyH + trayPadY * 2
            let w = Int(ceil(trayW + margin * 2))
            let h = Int(ceil(trayH + margin * 2))

            guard let ctx = CGContext(
                data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }

            ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))
            let trayRect = CGRect(x: margin, y: margin, width: trayW, height: trayH)
            let trayPath = CGPath(roundedRect: trayRect, cornerWidth: 14 * effectiveScale, cornerHeight: 14 * effectiveScale, transform: nil)

            ctx.saveGState()
            let shadowColor = isNeon
                ? CGColor(srgbRed: 0.14, green: 0.74, blue: 0.98, alpha: 0.42)
                : CGColor(gray: 0, alpha: isLight ? 0.30 : 0.48)
            ctx.setShadow(offset: CGSize(width: 0, height: -5 * effectiveScale), blur: 14 * effectiveScale, color: shadowColor)
            ctx.setFillColor(trayFill)
            ctx.addPath(trayPath)
            ctx.fillPath()
            ctx.setShadow(offset: .zero, blur: 0, color: nil)
            ctx.setStrokeColor(trayStroke)
            ctx.setLineWidth((isNeon ? 1.8 : 1.1) * effectiveScale)
            ctx.addPath(trayPath)
            ctx.strokePath()
            ctx.restoreGState()

            var cursorX = trayRect.minX + trayPadX
            let keyY = trayRect.minY + trayPadY
            for (idx, attrStr) in attrTokens.enumerated() {
                let kw = keyWidths[idx]
                let keyRect = CGRect(x: cursorX, y: keyY, width: kw, height: keyH)
                let keyRadius = 8.5 * effectiveScale
                let keyPath = CGPath(roundedRect: keyRect, cornerWidth: keyRadius, cornerHeight: keyRadius, transform: nil)

                let bevelRect = CGRect(x: keyRect.minX, y: keyRect.minY - 2.2 * effectiveScale, width: kw, height: keyH)
                let bevelPath = CGPath(roundedRect: bevelRect, cornerWidth: keyRadius, cornerHeight: keyRadius, transform: nil)
                ctx.setFillColor(keycapBevel)
                ctx.addPath(bevelPath)
                ctx.fillPath()

                ctx.setFillColor(keycapFill)
                ctx.addPath(keyPath)
                ctx.fillPath()

                ctx.setStrokeColor(keycapStroke)
                ctx.setLineWidth(1.0 * effectiveScale)
                ctx.addPath(keyPath)
                ctx.strokePath()

                let sz = attrStr.size()
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
                attrStr.draw(at: CGPoint(x: keyRect.midX - sz.width / 2, y: keyRect.midY - sz.height / 2))
                NSGraphicsContext.restoreGraphicsState()

                cursorX += kw + keyGap
            }

            guard let cg = ctx.makeImage() else { return nil }
            let baked = Self.bakeToMetalIfPossible(CIImage(cgImage: cg), device: mtlDevice, ciContext: ciContext, colorSpace: colorSpace)
            cacheLock.lock()
            cachedKeystrokeText = key
            cachedKeystrokeCI = baked
            cacheLock.unlock()
            return baked
        }

        // Sleek capsule pill (used for Minimal Glass shortcuts AND all Live Typing text bursts!)
        let displayStr = event.isTypingText ? event.text : event.keycaps.joined(separator: " ")
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: max(14, 17 * effectiveScale), weight: .semibold),
            .foregroundColor: textColor
        ]
        let attrStr = NSAttributedString(string: displayStr, attributes: attrs)
        let strSize = attrStr.size()
        let showDot = event.isTypingText
        let iconSpace: CGFloat = showDot ? (22 * effectiveScale) : 0
        let padX = 16 * effectiveScale
        let padY = 10 * effectiveScale
        let pillW = ceil(strSize.width + iconSpace + padX * 2)
        let pillH = ceil(strSize.height + padY * 2)
        let w = Int(ceil(pillW + margin * 2))
        let h = Int(ceil(pillH + margin * 2))

        guard let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))
        let pillRect = CGRect(x: margin, y: margin, width: pillW, height: pillH)
        let path = CGPath(roundedRect: pillRect, cornerWidth: pillH / 2, cornerHeight: pillH / 2, transform: nil)

        ctx.saveGState()
        let shadowColor = isNeon
            ? CGColor(srgbRed: 0.14, green: 0.74, blue: 0.98, alpha: 0.40)
            : CGColor(gray: 0, alpha: isLight ? 0.25 : 0.45)
        ctx.setShadow(offset: CGSize(width: 0, height: -4 * effectiveScale), blur: 12 * effectiveScale, color: shadowColor)
        ctx.setFillColor(trayFill)
        ctx.addPath(path)
        ctx.fillPath()
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
        ctx.setStrokeColor(trayStroke)
        ctx.setLineWidth((isNeon ? 1.8 : 1.2) * effectiveScale)
        ctx.addPath(path)
        ctx.strokePath()

        if showDot {
            let dotR = 4.2 * effectiveScale
            ctx.setFillColor(accentDotColor)
            ctx.fillEllipse(in: CGRect(x: pillRect.minX + padX, y: pillRect.midY - dotR, width: dotR * 2, height: dotR * 2))
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        attrStr.draw(at: CGPoint(x: pillRect.minX + padX + iconSpace * 0.75, y: pillRect.midY - strSize.height / 2))
        NSGraphicsContext.restoreGraphicsState()
        ctx.restoreGState()

        guard let cg = ctx.makeImage() else { return nil }
        let baked = Self.bakeToMetalIfPossible(CIImage(cgImage: cg), device: mtlDevice, ciContext: ciContext, colorSpace: colorSpace)
        cacheLock.lock()
        cachedKeystrokeText = key
        cachedKeystrokeCI = baked
        cacheLock.unlock()
        return baked
    }

    private func getOrPrepareWebcamOverlay(canvasSize: CGSize, config: WebcamPiPConfig) -> PreparedWebcamOverlay? {
        let cw = max(2, Int(canvasSize.width.rounded()))
        let ch = max(2, Int(canvasSize.height.rounded()))
        let key = WebcamOverlayKey(canvasW: cw, canvasH: ch, config: config)

        cacheLock.lock()
        if cachedWebcamOverlayKey == key, let cached = cachedWebcamOverlay {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        let pipRect = config.frameRectCI(in: canvasSize)
        let cr = config.cornerRadius(for: pipRect)
        let pipPath = CGPath(roundedRect: pipRect, cornerWidth: cr, cornerHeight: cr, transform: nil)
        let fullBounds = CGRect(origin: .zero, size: canvasSize)

        func makeCtx() -> CGContext? {
            CGContext(
                data: nil,
                width: cw,
                height: ch,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        }

        guard let shadowCtx = makeCtx(), let maskCtx = makeCtx() else { return nil }
        shadowCtx.clear(fullBounds)
        shadowCtx.saveGState()
        let shadowBlur = max(12.0, min(canvasSize.width, canvasSize.height) * 0.024)
        shadowCtx.setShadow(
            offset: CGSize(width: 0, height: -shadowBlur * 0.28),
            blur: shadowBlur,
            color: CGColor(gray: 0, alpha: 0.50)
        )
        shadowCtx.setFillColor(CGColor(srgbRed: 0.05, green: 0.05, blue: 0.07, alpha: 1.0))
        shadowCtx.addPath(pipPath)
        shadowCtx.fillPath()
        shadowCtx.restoreGState()

        maskCtx.clear(fullBounds)
        maskCtx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        maskCtx.addPath(pipPath)
        maskCtx.fillPath()

        guard let shadowCG = shadowCtx.makeImage(), let maskCG = maskCtx.makeImage() else { return nil }
        let shadowGPU = Self.bakeToMetalIfPossible(CIImage(cgImage: shadowCG), device: mtlDevice, ciContext: ciContext, colorSpace: colorSpace)
        let maskGPU = Self.bakeToMetalIfPossible(CIImage(cgImage: maskCG), device: mtlDevice, ciContext: ciContext, colorSpace: colorSpace)

        var borderGPU: CIImage?
        if config.showBorder, let borderCtx = makeCtx() {
            borderCtx.clear(fullBounds)
            let sw = max(2.2, min(canvasSize.width, canvasSize.height) * 0.0042)
            let insetRect = pipRect.insetBy(dx: sw / 2.0, dy: sw / 2.0)
            let insetCR = max(0, cr - sw / 2.0)
            let insetPath = CGPath(roundedRect: insetRect, cornerWidth: insetCR, cornerHeight: insetCR, transform: nil)
            borderCtx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.90))
            borderCtx.setLineWidth(sw)
            borderCtx.addPath(insetPath)
            borderCtx.strokePath()
            if let borderCG = borderCtx.makeImage() {
                borderGPU = Self.bakeToMetalIfPossible(CIImage(cgImage: borderCG), device: mtlDevice, ciContext: ciContext, colorSpace: colorSpace)
            }
        }

        let built = PreparedWebcamOverlay(
            pipRect: pipRect,
            shadowCI: shadowGPU,
            maskCI: maskGPU,
            borderCI: borderGPU
        )
        cacheLock.lock()
        cachedWebcamOverlayKey = key
        cachedWebcamOverlay = built
        cacheLock.unlock()
        return built
    }

    // MARK: - Live Studio Preview Frame (Cached GPU Canvas -> Ultra-Fast!)

    public func renderPreviewFrame(
        sourceCGImage: CGImage,
        time: Double,
        options: VideoCompositeOptions,
        smoothedCursorPath: [CursorSample],
        maxPreviewEdge: Int = 1280,
        fadeOpacity: Double = 1.0,
        webcamCGImage: CGImage? = nil
    ) -> CGImage? {
        let srcSize = CGSize(width: sourceCGImage.width, height: sourceCGImage.height)
        guard let canvas = getOrPrepareCanvas(
            sourceSize: srcSize,
            style: options.style,
            maxLongEdge: maxPreviewEdge,
            useCache: true
        ) else {
            return nil
        }
        let ciSource = CIImage(cgImage: sourceCGImage)
        let ciCam = webcamCGImage.map { CIImage(cgImage: $0) }
        let composed = composeFrameCI(
            sourceImage: ciSource,
            time: time,
            canvas: canvas,
            options: options,
            smoothedCursorPath: smoothedCursorPath,
            fadeOpacity: fadeOpacity,
            webcamImage: ciCam
        )
        return ciContext.createCGImage(composed, from: CGRect(origin: .zero, size: canvas.canvasSize))
    }

    // MARK: - Full X-Optimized Export (Zero-Copy IOSurface Metal -> VideoToolbox Hardware H.264)

    public func exportVideo(
        sourceURL: URL,
        outputURL: URL,
        options: VideoCompositeOptions,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        try await exportVideoWithMetrics(
            sourceURL: sourceURL,
            outputURL: outputURL,
            options: options,
            progressHandler: { update in
                progressHandler(update.progress)
            }
        )
    }

    public func exportVideoWithMetrics(
        sourceURL: URL,
        outputURL: URL,
        options: VideoCompositeOptions,
        progressHandler: @escaping @Sendable (ExportProgressUpdate) -> Void
    ) async throws -> URL {
        if options.exportPreset.isGIF {
            return try await exportGIF(
                sourceURL: sourceURL,
                outputURL: outputURL,
                options: options,
                progressHandler: progressHandler
            )
        } else {
            return try await exportMP4(
                sourceURL: sourceURL,
                outputURL: outputURL,
                options: options,
                progressHandler: progressHandler
            )
        }
    }

    private func exportMP4(
        sourceURL: URL,
        outputURL: URL,
        options: VideoCompositeOptions,
        progressHandler: @escaping @Sendable (ExportProgressUpdate) -> Void
    ) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else {
            throw VideoExportError.noVideoTrack
        }

        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        let transformedSize = naturalSize.applying(preferredTransform)
        let sourceSize = CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height))

        let assetDuration = try await asset.load(.duration).seconds
        let clips = VideoTimelineMapper.normalizedClips(
            options.clipSegments,
            fallbackStart: options.trimStart,
            fallbackEnd: options.trimEnd,
            assetDuration: assetDuration
        )
        let exportDuration = VideoTimelineMapper.totalOutputDuration(of: clips)
        let sourceSpanStart = clips.first?.sourceStart ?? 0
        let sourceSpanEnd = clips.last?.sourceEnd ?? assetDuration
        let targetFPS = options.exportPreset.fps

        guard let canvas = prepareCanvas(
            sourceSize: sourceSize,
            style: options.style,
            maxLongEdge: options.exportPreset.maxLongEdge
        ) else {
            throw VideoExportError.failedToRenderFrame
        }

        let smoothedCursor = AutoZoomEngine.smoothCursorSamples(options.telemetry.cursorSamples, fps: Double(targetFPS))
        try? FileManager.default.removeItem(at: outputURL)

        let videoReadRange = CMTimeRange(
            start: CMTime(seconds: sourceSpanStart, preferredTimescale: 600),
            duration: CMTime(seconds: max(0.1, sourceSpanEnd - sourceSpanStart), preferredTimescale: 600)
        )

        // Dedicated video AVAssetReader (Zero-Copy IOSurface + Metal compatible)
        let videoReader: AVAssetReader
        do {
            videoReader = try AVAssetReader(asset: asset)
        } catch {
            throw VideoExportError.failedToCreateReader(error.localizedDescription)
        }
        videoReader.timeRange = videoReadRange

        let videoReaderOutput = AVAssetReaderTrackOutput(
            track: videoTrack,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferMetalCompatibilityKey as String: true,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]
            ]
        )
        videoReaderOutput.alwaysCopiesSampleData = false
        videoReader.add(videoReaderOutput)

        // Optional synchronized companion Webcam PiP reader
        let webcamReader: SynchronizedWebcamTrackReader? = if options.webcamPiP.enabled, let camURL = options.webcamVideoURL {
            await SynchronizedWebcamTrackReader.create(url: camURL, timeRange: videoReadRange)
        } else {
            nil
        }

        // Separate dedicated audio AVAssetReader built from stitched & speed-scaled AVMutableComposition
        // (supports middle cuts, per-clip speed with pitch preservation, volume gain & fade-in/out!)
        var audioReader: AVAssetReader?
        var audioReaderOutput: AVAssetReaderAudioMixOutput?
        if options.includeAudio && options.audioVolume > 0.001,
           let builtAudio = try await VideoTimelineMapper.buildAudioComposition(
               from: asset,
               clips: clips,
               fade: options.fadeConfig,
               volume: Float(options.audioVolume)
           ) {
            let compTracks = try await builtAudio.composition.loadTracks(withMediaType: .audio)
            if !compTracks.isEmpty {
                let aReader = try AVAssetReader(asset: builtAudio.composition)
                let mixOutput = AVAssetReaderAudioMixOutput(
                    audioTracks: compTracks,
                    audioSettings: [
                        AVFormatIDKey: kAudioFormatLinearPCM,
                        AVSampleRateKey: 48_000,
                        AVNumberOfChannelsKey: 2,
                        AVLinearPCMBitDepthKey: 16,
                        AVLinearPCMIsFloatKey: false,
                        AVLinearPCMIsBigEndianKey: false,
                        AVLinearPCMIsNonInterleaved: false
                    ]
                )
                mixOutput.audioMix = builtAudio.audioMix
                mixOutput.audioTimePitchAlgorithm = .timeDomain
                mixOutput.alwaysCopiesSampleData = false
                aReader.add(mixOutput)
                audioReader = aReader
                audioReaderOutput = mixOutput
            }
        }

        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        } catch {
            throw VideoExportError.failedToCreateWriter(error.localizedDescription)
        }
        writer.shouldOptimizeForNetworkUse = true

        let outW = Int(canvas.canvasSize.width)
        let outH = Int(canvas.canvasSize.height)

        // Hardware VideoToolbox H.264 High Profile — zero B-frame stall + Rec.709 sRGB for X!
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: outW,
            AVVideoHeightKey: outH,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
            ],
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: options.exportPreset.targetBitrate,
                AVVideoExpectedSourceFrameRateKey: targetFPS,
                AVVideoMaxKeyFrameIntervalKey: targetFPS * 2,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoAllowFrameReorderingKey: false
            ]
        ]

        let videoWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoWriterInput.expectsMediaDataInRealTime = false

        // CRITICAL FOR SPEED: IOSurfaceProperties enables zero-copy Metal GPU -> VideoToolbox Unified Memory sharing!
        let pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoWriterInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: outW,
                kCVPixelBufferHeightKey as String: outH,
                kCVPixelBufferMetalCompatibilityKey as String: true,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]
            ]
        )
        writer.add(videoWriterInput)

        var audioWriterInput: AVAssetWriterInput?
        if audioReaderOutput != nil {
            let aInput = AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: 48_000,
                    AVNumberOfChannelsKey: 2,
                    AVEncoderBitRateKey: 192_000
                ]
            )
            aInput.expectsMediaDataInRealTime = false
            writer.add(aInput)
            audioWriterInput = aInput
        }

        guard videoReader.startReading() else {
            throw VideoExportError.failedToCreateReader(videoReader.error?.localizedDescription ?? "Unknown")
        }
        if let aReader = audioReader, !aReader.startReading() {
            videoReader.cancelReading()
            throw VideoExportError.failedToCreateReader(aReader.error?.localizedDescription ?? "Audio read failed")
        }
        guard writer.startWriting() else {
            videoReader.cancelReading()
            audioReader?.cancelReading()
            throw VideoExportError.failedToCreateWriter(writer.error?.localizedDescription ?? "Unknown")
        }
        writer.startSession(atSourceTime: .zero)

        let totalFrames = max(1, Int(ceil(exportDuration * Double(targetFPS))))
        let frameTimescale = CMTimeScale(targetFPS)

        final class ExportCoordinator: @unchecked Sendable {
            let videoReader: AVAssetReader
            let audioReader: AVAssetReader?
            let writer: AVAssetWriter
            let videoReaderOutput: AVAssetReaderTrackOutput
            let videoWriterInput: AVAssetWriterInput
            let pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor
            let audioReaderOutput: AVAssetReaderAudioMixOutput?
            let audioWriterInput: AVAssetWriterInput?

            let stateLock = NSLock()
            var videoFinished = false
            var audioFinished = false
            var resumed = false
            var firstError: Error?

            // Video pipeline state (accessed exclusively on videoQueue)
            var frameIndex = 0
            var initializedSamples = false
            var currentSample: CMSampleBuffer?
            var nextSample: CMSampleBuffer?
            var latestCI: CIImage?
            let startWall = ProcessInfo.processInfo.systemUptime

            // Audio pipeline state (accessed exclusively on audioQueue)
            var lastAudioPTS: CMTime = .invalid

            init(
                videoReader: AVAssetReader,
                audioReader: AVAssetReader?,
                writer: AVAssetWriter,
                videoReaderOutput: AVAssetReaderTrackOutput,
                videoWriterInput: AVAssetWriterInput,
                pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor,
                audioReaderOutput: AVAssetReaderAudioMixOutput?,
                audioWriterInput: AVAssetWriterInput?
            ) {
                self.videoReader = videoReader
                self.audioReader = audioReader
                self.writer = writer
                self.videoReaderOutput = videoReaderOutput
                self.videoWriterInput = videoWriterInput
                self.pixelBufferAdaptor = pixelBufferAdaptor
                self.audioReaderOutput = audioReaderOutput
                self.audioWriterInput = audioWriterInput
                self.audioFinished = (audioWriterInput == nil)
            }
        }

        let coord = ExportCoordinator(
            videoReader: videoReader,
            audioReader: audioReader,
            writer: writer,
            videoReaderOutput: videoReaderOutput,
            videoWriterInput: videoWriterInput,
            pixelBufferAdaptor: pixelBufferAdaptor,
            audioReaderOutput: audioReaderOutput,
            audioWriterInput: audioWriterInput
        )

        let outBounds = CGRect(origin: .zero, size: canvas.canvasSize)

        // Drive BOTH video & audio inputs concurrently via AVAssetWriter's native pull callbacks!
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let videoQueue = DispatchQueue(label: "top.xtags.xshot.video.export.video", qos: .userInitiated)
                let audioQueue = DispatchQueue(label: "top.xtags.xshot.video.export.audio", qos: .userInitiated)

                func checkCompletion(error: Error? = nil) {
                    coord.stateLock.lock()
                    if let error, coord.firstError == nil {
                        coord.firstError = error
                    }
                    let shouldResume: Bool
                    let finalError: Error?
                    if let err = coord.firstError, !coord.resumed {
                        coord.resumed = true
                        shouldResume = true
                        finalError = err
                    } else if coord.videoFinished && coord.audioFinished && !coord.resumed {
                        coord.resumed = true
                        shouldResume = true
                        finalError = nil
                    } else {
                        shouldResume = false
                        finalError = nil
                    }
                    coord.stateLock.unlock()

                    if shouldResume {
                        if let finalError {
                            coord.videoReader.cancelReading()
                            coord.audioReader?.cancelReading()
                            coord.writer.cancelWriting()
                            continuation.resume(throwing: finalError)
                        } else {
                            progressHandler(ExportProgressUpdate(progress: 0.99, framesPerSecond: 0, estimatedRemainingSeconds: 0))
                            continuation.resume()
                        }
                    }
                }

                // 1. Video pull callback
                coord.videoWriterInput.requestMediaDataWhenReady(on: videoQueue) {
                    while coord.videoWriterInput.isReadyForMoreMediaData {
                        coord.stateLock.lock()
                        let alreadyFailed = (coord.firstError != nil) || coord.videoFinished
                        coord.stateLock.unlock()
                        if alreadyFailed { return }

                        if Task.isCancelled {
                            coord.videoWriterInput.markAsFinished()
                            checkCompletion(error: VideoExportError.cancelled)
                            return
                        }

                        if coord.writer.status == .failed || coord.writer.status == .cancelled {
                            coord.videoWriterInput.markAsFinished()
                            checkCompletion(error: VideoExportError.failedToCreateWriter(coord.writer.error?.localizedDescription ?? "Writer aborted"))
                            return
                        }

                        if !coord.initializedSamples {
                            coord.initializedSamples = true
                            coord.currentSample = coord.videoReaderOutput.copyNextSampleBuffer()
                            coord.nextSample = coord.videoReaderOutput.copyNextSampleBuffer()
                            if let firstBuf = coord.currentSample, let pb = CMSampleBufferGetImageBuffer(firstBuf) {
                                coord.latestCI = CIImage(cvPixelBuffer: pb)
                            }
                        }

                        if coord.frameIndex >= totalFrames {
                            coord.videoWriterInput.markAsFinished()
                            coord.stateLock.lock()
                            coord.videoFinished = true
                            coord.stateLock.unlock()
                            checkCompletion()
                            return
                        }

                        let idx = coord.frameIndex
                        coord.frameIndex += 1

                        let outTimeSec = Double(idx) / Double(targetFPS)
                        let mapped = VideoTimelineMapper.mapOutputTimeToSource(outTimeSec, clips: clips)
                        let sourceTimeSec = mapped?.sourceTime ?? (sourceSpanStart + outTimeSec)
                        let clipSpeed = mapped?.speed ?? 1.0
                        let fadeAlpha = VideoTimelineMapper.fadeOpacity(
                            atOutputTime: outTimeSec,
                            totalDuration: exportDuration,
                            fade: options.fadeConfig
                        )

                        while let next = coord.nextSample {
                            let nextPTS = CMSampleBufferGetPresentationTimeStamp(next).seconds
                            if nextPTS <= sourceTimeSec + (0.5 * clipSpeed / Double(targetFPS)) {
                                coord.currentSample = next
                                if let pb = CMSampleBufferGetImageBuffer(next) {
                                    coord.latestCI = CIImage(cvPixelBuffer: pb)
                                }
                                coord.nextSample = coord.videoReaderOutput.copyNextSampleBuffer()
                            } else {
                                break
                            }
                        }

                        guard let baseFrame = coord.latestCI else { continue }
                        guard let pool = coord.pixelBufferAdaptor.pixelBufferPool else {
                            coord.videoWriterInput.markAsFinished()
                            checkCompletion(error: VideoExportError.failedToRenderFrame)
                            return
                        }

                        var renderErr: Error?
                        autoreleasepool {
                            var outBufferOpt: CVPixelBuffer?
                            let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &outBufferOpt)
                            guard status == kCVReturnSuccess, let outBuffer = outBufferOpt else {
                                renderErr = VideoExportError.failedToRenderFrame
                                return
                            }

                            let camFrame = webcamReader?.frame(
                                atSourceTime: sourceTimeSec,
                                tolerance: 0.5 * clipSpeed / Double(targetFPS)
                            )

                            let composed = self.composeFrameCI(
                                sourceImage: baseFrame,
                                time: sourceTimeSec,
                                canvas: canvas,
                                options: options,
                                smoothedCursorPath: smoothedCursor,
                                fadeOpacity: fadeAlpha,
                                webcamImage: camFrame
                            )

                            self.ciContext.render(
                                composed,
                                to: outBuffer,
                                bounds: outBounds,
                                colorSpace: self.colorSpace
                            )

                            let pts = CMTime(value: CMTimeValue(idx), timescale: frameTimescale)
                            if !coord.pixelBufferAdaptor.append(outBuffer, withPresentationTime: pts) {
                                renderErr = VideoExportError.failedToCreateWriter(coord.writer.error?.localizedDescription ?? "Append video frame failed")
                            }
                        }

                        if let renderErr {
                            coord.videoWriterInput.markAsFinished()
                            checkCompletion(error: renderErr)
                            return
                        }

                        if idx % 6 == 0 || idx == totalFrames - 1 {
                            let elapsed = max(0.01, ProcessInfo.processInfo.systemUptime - coord.startWall)
                            let fps = Double(idx + 1) / elapsed
                            let remainingFrames = max(0, totalFrames - (idx + 1))
                            let eta = Double(remainingFrames) / max(1, fps)
                            let progress = Double(idx + 1) / Double(totalFrames) * 0.97
                            progressHandler(ExportProgressUpdate(
                                progress: progress,
                                framesPerSecond: fps,
                                estimatedRemainingSeconds: eta
                            ))
                        }
                    }
                }

                // 2. Audio pull callback (runs concurrently from stitched speed-scaled AVMutableComposition!)
                if coord.audioReaderOutput != nil, coord.audioWriterInput != nil {
                    coord.audioWriterInput?.requestMediaDataWhenReady(on: audioQueue) {
                        guard let aOutput = coord.audioReaderOutput, let aInput = coord.audioWriterInput else { return }
                        while aInput.isReadyForMoreMediaData {
                            coord.stateLock.lock()
                            let alreadyDone = (coord.firstError != nil) || coord.audioFinished
                            coord.stateLock.unlock()
                            if alreadyDone { return }

                            if Task.isCancelled {
                                aInput.markAsFinished()
                                checkCompletion(error: VideoExportError.cancelled)
                                return
                            }

                            if coord.writer.status == .failed || coord.writer.status == .cancelled {
                                aInput.markAsFinished()
                                checkCompletion(error: VideoExportError.failedToCreateWriter(coord.writer.error?.localizedDescription ?? "Audio writer aborted"))
                                return
                            }

                            guard let sample = aOutput.copyNextSampleBuffer() else {
                                aInput.markAsFinished()
                                coord.stateLock.lock()
                                coord.audioFinished = true
                                coord.stateLock.unlock()
                                checkCompletion()
                                return
                            }

                            let pts = CMSampleBufferGetPresentationTimeStamp(sample)
                            if pts.seconds < 0 { continue }
                            if coord.lastAudioPTS.isValid && pts <= coord.lastAudioPTS { continue }
                            coord.lastAudioPTS = pts

                            if !aInput.append(sample) {
                                aInput.markAsFinished()
                                checkCompletion(error: VideoExportError.failedToCreateWriter(coord.writer.error?.localizedDescription ?? "Append audio failed"))
                                return
                            }
                        }
                    }
                }
            }
        } onCancel: {
            coord.videoReader.cancelReading()
            coord.audioReader?.cancelReading()
            coord.writer.cancelWriting()
        }

        await writer.finishWriting()
        if writer.status == .failed {
            throw VideoExportError.failedToCreateWriter(writer.error?.localizedDescription ?? "Writer failed")
        }
        progressHandler(ExportProgressUpdate(progress: 1.0, framesPerSecond: 0, estimatedRemainingSeconds: 0))
        return outputURL
    }

    private func exportGIF(
        sourceURL: URL,
        outputURL: URL,
        options: VideoCompositeOptions,
        progressHandler: @escaping @Sendable (ExportProgressUpdate) -> Void
    ) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else {
            throw VideoExportError.noVideoTrack
        }

        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        let transformedSize = naturalSize.applying(preferredTransform)
        let sourceSize = CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height))

        let assetDuration = try await asset.load(.duration).seconds
        let clips = VideoTimelineMapper.normalizedClips(
            options.clipSegments,
            fallbackStart: options.trimStart,
            fallbackEnd: options.trimEnd,
            assetDuration: assetDuration
        )
        let exportDuration = VideoTimelineMapper.totalOutputDuration(of: clips)
        let sourceSpanStart = clips.first?.sourceStart ?? 0
        let sourceSpanEnd = clips.last?.sourceEnd ?? assetDuration
        let targetFPS = 18 // Sweet spot: crisp motion, fast export, stays well under X's 15MB GIF limit

        guard let canvas = prepareCanvas(
            sourceSize: sourceSize,
            style: options.style,
            maxLongEdge: min(840, options.exportPreset.maxLongEdge)
        ) else {
            throw VideoExportError.failedToRenderFrame
        }

        let smoothedCursor = AutoZoomEngine.smoothCursorSamples(options.telemetry.cursorSamples, fps: Double(targetFPS))
        try? FileManager.default.removeItem(at: outputURL)

        let totalFrames = max(1, Int(ceil(exportDuration * Double(targetFPS))))
        let frameDelay = 1.0 / Double(targetFPS)

        guard let destination = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            UTType.gif.identifier as CFString,
            totalFrames,
            nil
        ) else {
            throw VideoExportError.failedToCreateWriter(L10n.t(.errGIFInitFailed))
        }

        let gifFileProps: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFLoopCount as String: 0
            ]
        ]
        CGImageDestinationSetProperties(destination, gifFileProps as CFDictionary)

        let frameProps: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFUnclampedDelayTime as String: frameDelay,
                kCGImagePropertyGIFDelayTime as String: frameDelay
            ]
        ]

        let reader = try AVAssetReader(asset: asset)
        let gifReadRange = CMTimeRange(
            start: CMTime(seconds: sourceSpanStart, preferredTimescale: 600),
            duration: CMTime(seconds: max(0.1, sourceSpanEnd - sourceSpanStart), preferredTimescale: 600)
        )
        reader.timeRange = gifReadRange
        let output = AVAssetReaderTrackOutput(
            track: videoTrack,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]
            ]
        )
        reader.add(output)
        guard reader.startReading() else {
            throw VideoExportError.failedToCreateReader(reader.error?.localizedDescription ?? "GIF read failed")
        }

        let webcamReader: SynchronizedWebcamTrackReader? = if options.webcamPiP.enabled, let camURL = options.webcamVideoURL {
            await SynchronizedWebcamTrackReader.create(url: camURL, timeRange: gifReadRange)
        } else {
            nil
        }

        final class GIFHandles: @unchecked Sendable {
            let output: AVAssetReaderTrackOutput
            let destination: CGImageDestination
            let frameProps: CFDictionary
            init(output: AVAssetReaderTrackOutput, destination: CGImageDestination, frameProps: CFDictionary) {
                self.output = output
                self.destination = destination
                self.frameProps = frameProps
            }
        }
        let gifHandles = GIFHandles(output: output, destination: destination, frameProps: frameProps as CFDictionary)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let startWall = ProcessInfo.processInfo.systemUptime
                var currentSample = gifHandles.output.copyNextSampleBuffer()
                var nextSample = gifHandles.output.copyNextSampleBuffer()
                var latestCI: CIImage?
                if let firstBuf = currentSample, let pb = CMSampleBufferGetImageBuffer(firstBuf) {
                    latestCI = CIImage(cvPixelBuffer: pb)
                }

                for i in 0..<totalFrames {
                    if Task.isCancelled {
                        continuation.resume(throwing: VideoExportError.cancelled)
                        return
                    }
                    let outTime = Double(i) * frameDelay
                    let mapped = VideoTimelineMapper.mapOutputTimeToSource(outTime, clips: clips)
                    let sourceTime = mapped?.sourceTime ?? (sourceSpanStart + outTime)
                    let clipSpeed = mapped?.speed ?? 1.0
                    let fadeAlpha = VideoTimelineMapper.fadeOpacity(
                        atOutputTime: outTime,
                        totalDuration: exportDuration,
                        fade: options.fadeConfig
                    )
                    while let next = nextSample {
                        let pts = CMSampleBufferGetPresentationTimeStamp(next).seconds
                        if pts <= sourceTime + frameDelay * 0.5 * clipSpeed {
                            currentSample = next
                            if let pb = CMSampleBufferGetImageBuffer(next) {
                                latestCI = CIImage(cvPixelBuffer: pb)
                            }
                            nextSample = gifHandles.output.copyNextSampleBuffer()
                        } else {
                            break
                        }
                    }

                    guard let baseFrame = latestCI else { continue }
                    let camFrame = webcamReader?.frame(atSourceTime: sourceTime, tolerance: frameDelay * 0.5 * clipSpeed)
                    autoreleasepool {
                        let composed = self.composeFrameCI(
                            sourceImage: baseFrame,
                            time: sourceTime,
                            canvas: canvas,
                            options: options,
                            smoothedCursorPath: smoothedCursor,
                            fadeOpacity: fadeAlpha,
                            webcamImage: camFrame
                        )
                        if let cgFrame = self.ciContext.createCGImage(composed, from: CGRect(origin: .zero, size: canvas.canvasSize)) {
                            CGImageDestinationAddImage(gifHandles.destination, cgFrame, gifHandles.frameProps)
                        }
                    }

                    if i % 3 == 0 || i == totalFrames - 1 {
                        let elapsed = max(0.01, ProcessInfo.processInfo.systemUptime - startWall)
                        let fps = Double(i + 1) / elapsed
                        let eta = Double(max(0, totalFrames - (i + 1))) / max(1, fps)
                        progressHandler(ExportProgressUpdate(
                            progress: Double(i + 1) / Double(totalFrames) * 0.96,
                            framesPerSecond: fps,
                            estimatedRemainingSeconds: eta
                        ))
                    }
                }

                if CGImageDestinationFinalize(gifHandles.destination) {
                    progressHandler(ExportProgressUpdate(progress: 1.0, framesPerSecond: 0, estimatedRemainingSeconds: 0))
                    continuation.resume()
                } else {
                    continuation.resume(throwing: VideoExportError.failedToCreateWriter(L10n.t(.errGIFWriteFailed)))
                }
            }
        }

        return outputURL
    }
}

/// Synchronized single-pass `AVAssetReader` wrapper for companion Webcam PiP video tracks during export.
private final class SynchronizedWebcamTrackReader: @unchecked Sendable {
    private let reader: AVAssetReader
    private let output: AVAssetReaderTrackOutput
    private var initialized = false
    private var currentSample: CMSampleBuffer?
    private var nextSample: CMSampleBuffer?
    private var latestCI: CIImage?

    private init(reader: AVAssetReader, output: AVAssetReaderTrackOutput) {
        self.reader = reader
        self.output = output
    }

    static func create(url: URL, timeRange: CMTimeRange) async -> SynchronizedWebcamTrackReader? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let asset = AVURLAsset(url: url)
        guard let tracks = try? await asset.loadTracks(withMediaType: .video),
              let track = tracks.first,
              let reader = try? AVAssetReader(asset: asset) else {
            return nil
        }
        reader.timeRange = timeRange
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferMetalCompatibilityKey as String: true,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]
            ]
        )
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        guard reader.startReading() else { return nil }
        return SynchronizedWebcamTrackReader(reader: reader, output: output)
    }

    func frame(atSourceTime sourceTime: Double, tolerance: Double) -> CIImage? {
        if !initialized {
            initialized = true
            currentSample = output.copyNextSampleBuffer()
            nextSample = output.copyNextSampleBuffer()
            if let first = currentSample, let pb = CMSampleBufferGetImageBuffer(first) {
                latestCI = CIImage(cvPixelBuffer: pb)
            }
        }
        while let next = nextSample {
            let pts = CMSampleBufferGetPresentationTimeStamp(next).seconds
            if pts <= sourceTime + tolerance {
                currentSample = next
                if let pb = CMSampleBufferGetImageBuffer(next) {
                    latestCI = CIImage(cvPixelBuffer: pb)
                }
                nextSample = output.copyNextSampleBuffer()
            } else {
                break
            }
        }
        return latestCI
    }

    func cancel() {
        reader.cancelReading()
    }
}
