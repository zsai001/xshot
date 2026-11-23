import AppKit
import CoreGraphics
import CoreImage
import Foundation

public enum ScreenshotRenderer {
    private static let sharedCIContext: CIContext = {
        if let device = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: device, options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
        }
        return CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
    }()

    /// Renders a curated background preset into a CGContext (expects top-left flipped OR standard CoreGraphics coordinates).
    public static func drawBackground(in ctx: CGContext, size: CGSize, preset: BackgroundPreset) {
        let rect = CGRect(origin: .zero, size: size)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

        switch preset.kind {
        case .transparent:
            ctx.clear(rect)

        case .solid:
            let color = preset.colors.first ?? RGBAColor(hex: 0x000000)
            ctx.setFillColor(color.cgColor)
            ctx.fill(rect)

        case .gradient:
            let cgColors = (preset.colors.isEmpty ? [RGBAColor(hex: 0x0F172A), RGBAColor(hex: 0x1E293B)] : preset.colors)
                .map(\.cgColor) as CFArray
            if let gradient = CGGradient(colorsSpace: colorSpace, colors: cgColors, locations: nil) {
                let rad = preset.angleDegrees * .pi / 180.0
                let cx = size.width / 2.0
                let cy = size.height / 2.0
                let halfDiag = hypot(size.width, size.height) / 2.0
                let dx = cos(rad) * halfDiag
                let dy = sin(rad) * halfDiag
                ctx.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: cx - dx, y: cy - dy),
                    end: CGPoint(x: cx + dx, y: cy + dy),
                    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
                )
            }

        case .meshLike:
            // Rich base linear gradient + layered soft radial color orbs for a lush Studio mesh wallpaper look
            let baseColors = Array(preset.colors.prefix(2))
            let cgBase = (baseColors.count >= 2 ? baseColors : [RGBAColor(hex: 0x0F172A), RGBAColor(hex: 0x1E1B4B)])
                .map(\.cgColor) as CFArray
            if let baseGrad = CGGradient(colorsSpace: colorSpace, colors: cgBase, locations: nil) {
                ctx.drawLinearGradient(
                    baseGrad,
                    start: CGPoint(x: 0, y: 0),
                    end: CGPoint(x: size.width, y: size.height),
                    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
                )
            }

            let orbAnchors: [(CGFloat, CGFloat, CGFloat)] = [
                (0.18, 0.22, 0.72),
                (0.84, 0.78, 0.78),
                (0.82, 0.18, 0.58),
                (0.20, 0.84, 0.62)
            ]

            ctx.saveGState()
            for (idx, color) in preset.colors.enumerated() {
                let anchor = orbAnchors[idx % orbAnchors.count]
                let center = CGPoint(x: size.width * anchor.0, y: size.height * anchor.1)
                let radius = max(size.width, size.height) * anchor.2
                let c1 = RGBAColor(r: color.r, g: color.g, b: color.b, a: 0.62).cgColor
                let c2 = RGBAColor(r: color.r, g: color.g, b: color.b, a: 0.0).cgColor
                    if let radGrad = CGGradient(colorsSpace: colorSpace, colors: [c1, c2] as CFArray, locations: [0.0, 1.0]) {
                        ctx.drawRadialGradient(
                            radGrad,
                            startCenter: center,
                            startRadius: 0,
                            endCenter: center,
                            endRadius: radius,
                            options: [.drawsAfterEndLocation]
                        )
                    }
                }
                ctx.restoreGState()

            case .image:
                let targetEdge = max(1280, Int(max(size.width, size.height).rounded()))
                if let path = preset.imagePath,
                   let img = SystemWallpaperManager.shared.fullResolutionImage(forPath: path, targetLongEdge: targetEdge) {
                    let imgW = CGFloat(img.width)
                    let imgH = CGFloat(img.height)
                    let scale = max(size.width / max(1, imgW), size.height / max(1, imgH))
                    let drawW = imgW * scale
                    let drawH = imgH * scale
                    let drawRect = CGRect(
                        x: (size.width - drawW) / 2.0,
                        y: (size.height - drawH) / 2.0,
                        width: drawW,
                        height: drawH
                    )
                    ctx.saveGState()
                    ctx.clip(to: rect)
                    ctx.interpolationQuality = .high
                    ctx.draw(img, in: drawRect)
                    ctx.restoreGState()
                } else {
                    ctx.setFillColor(RGBAColor(hex: 0x0F172A).cgColor)
                    ctx.fill(rect)
                }
        }
    }

    /// Creates a reusable background `CGImage` at exact target size (used by VideoCompositorExporter for fast 60fps compositing).
    public static func renderBackgroundImage(size: CGSize, preset: BackgroundPreset) -> CGImage? {
        let w = max(2, Int(size.width.rounded()))
        let h = max(2, Int(size.height.rounded()))
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        drawBackground(in: ctx, size: CGSize(width: w, height: h), preset: preset)
        return ctx.makeImage()
    }

    /// Renders raw image + all vector/pixel annotations at native 1:1 pixel resolution.
    public static func renderAnnotatedRawImage(rawImage: CGImage, annotations: [AnnotationItem]) -> CGImage? {
        let w = rawImage.width
        let h = rawImage.height
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.interpolationQuality = .high
        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)

        // Draw base image in standard CG coords (origin bottom-left)
        ctx.draw(rawImage, in: CGRect(x: 0, y: 0, width: w, height: h))

        guard !annotations.isEmpty else {
            return ctx.makeImage()
        }

        // Apply pixel effects (mosaic & blur) first so vector markup can sit on top
        let ciBase = CIImage(cgImage: rawImage)
        for item in annotations where item.toolKind == .mosaic || item.toolKind == .blur {
            let rectTopLeft = item.normalizedRect
            guard rectTopLeft.width >= 2, rectTopLeft.height >= 2 else { continue }
            let cgRect = CGRect(
                x: rectTopLeft.origin.x,
                y: CGFloat(h) - rectTopLeft.origin.y - rectTopLeft.height,
                width: rectTopLeft.width,
                height: rectTopLeft.height
            ).intersection(CGRect(x: 0, y: 0, width: w, height: h))
            guard !cgRect.isNull, !cgRect.isEmpty else { continue }

            let filtered: CIImage
            if item.toolKind == .mosaic {
                let scale = max(10.0, min(36.0, max(cgRect.width, cgRect.height) * 0.06))
                filtered = ciBase
                    .clampedToExtent()
                    .applyingFilter("CIPixellate", parameters: [kCIInputScaleKey: scale])
                    .cropped(to: cgRect)
            } else {
                let radius = max(12.0, min(32.0, max(cgRect.width, cgRect.height) * 0.05))
                filtered = ciBase
                    .clampedToExtent()
                    .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
                    .cropped(to: cgRect)
            }

            if let patch = sharedCIContext.createCGImage(filtered, from: cgRect) {
                ctx.saveGState()
                let clipPath = CGPath(roundedRect: cgRect, cornerWidth: 6, cornerHeight: 6, transform: nil)
                ctx.addPath(clipPath)
                ctx.clip()
                ctx.draw(patch, in: cgRect)
                ctx.restoreGState()
            }
        }

        // Now flip to top-left origin for crisp vector annotations (matches annotation coordinate space!)
        ctx.saveGState()
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)

        for item in annotations {
            switch item.toolKind {
            case .mosaic, .blur, .select:
                continue

            case .highlighter:
                let rect = item.normalizedRect
                guard rect.width >= 2, rect.height >= 2 else { continue }
                ctx.saveGState()
                let fill = RGBAColor(r: item.color.r, g: item.color.g, b: item.color.b, a: 0.34).cgColor
                ctx.setFillColor(fill)
                let path = CGPath(roundedRect: rect, cornerWidth: 6, cornerHeight: 6, transform: nil)
                ctx.addPath(path)
                ctx.fillPath()
                ctx.restoreGState()

            case .rectangle:
                let rect = item.normalizedRect
                guard rect.width >= 2, rect.height >= 2 else { continue }
                ctx.saveGState()
                ctx.setShadow(offset: CGSize(width: 0, height: 2), blur: 6, color: CGColor(gray: 0, alpha: 0.35))
                ctx.setStrokeColor(item.color.cgColor)
                ctx.setLineWidth(item.lineWidth)
                ctx.setLineJoin(.round)
                let radius = min(10, min(rect.width, rect.height) * 0.2)
                let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
                ctx.addPath(path)
                ctx.strokePath()
                ctx.restoreGState()

            case .ellipse:
                let rect = item.normalizedRect
                guard rect.width >= 2, rect.height >= 2 else { continue }
                ctx.saveGState()
                ctx.setShadow(offset: CGSize(width: 0, height: 2), blur: 6, color: CGColor(gray: 0, alpha: 0.35))
                ctx.setStrokeColor(item.color.cgColor)
                ctx.setLineWidth(item.lineWidth)
                ctx.strokeEllipse(in: rect)
                ctx.restoreGState()

            case .arrow:
                drawModernArrow(in: ctx, from: item.startPoint, to: item.endPoint, color: item.color.cgColor, lineWidth: item.lineWidth)

            case .step:
                drawStepBadge(in: ctx, at: item.startPoint, number: item.stepNumber, color: item.color.cgColor, radius: max(18, item.lineWidth * 3.2))

            case .text:
                drawTextAnnotation(in: ctx, text: item.text, at: item.startPoint, color: item.color.nsColor, fontSize: item.fontSize)
            }
        }

        ctx.restoreGState()
        return ctx.makeImage()
    }

    /// Full pipeline: renders annotations + optional X/Twitter Beautify background, window chrome, rounded corners, and drop shadow.
    public static func renderScreenshot(
        rawImage: CGImage,
        annotations: [AnnotationItem],
        style: BeautifyStyle,
        enableBeautify: Bool,
        maxLongEdge: Int? = nil
    ) -> CGImage? {
        guard let annotated = renderAnnotatedRawImage(rawImage: rawImage, annotations: annotations) else {
            return nil
        }

        if !enableBeautify {
            if style.watermark.isEffectivelyVisible {
                return applyWatermark(to: annotated, config: style.watermark) ?? annotated
            }
            return annotated
        }

        let sourceSize = CGSize(width: annotated.width, height: annotated.height)
        let layout = CoordinateConverter.computeCanvasLayout(
            sourceSize: sourceSize,
            style: style,
            maxLongEdge: maxLongEdge,
            evenDimensions: false
        )

        let canvasW = Int(layout.canvasSize.width)
        let canvasH = Int(layout.canvasSize.height)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

        guard let ctx = CGContext(
            data: nil,
            width: canvasW,
            height: canvasH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.interpolationQuality = .high
        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)

        // 1. Background
        drawBackground(in: ctx, size: layout.canvasSize, preset: style.background)

        // Compute scale ratio relative to 720px design space for proportional corner radius & shadow
        let scaleFactor = max(1.0, min(layout.contentRect.width, layout.contentRect.height) / 720.0)
        let cornerRadius = min(style.cornerRadius * scaleFactor, min(layout.contentRect.width, layout.contentRect.height) * 0.25)

        // Convert top-left contentRect + chrome into standard bottom-left CG coordinates
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

        let cardPath = CGPath(roundedRect: fullFrameCG, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

        // 2. Soft studio drop shadow (two-layer realistic contact + ambient shadow)
        if style.shadowRadius > 0 && style.shadowOpacity > 0.01 && style.background.kind != .transparent {
            let shadowBlur = style.shadowRadius * scaleFactor
            ctx.saveGState()
            ctx.setShadow(
                offset: CGSize(width: 0, height: -shadowBlur * 0.28),
                blur: shadowBlur,
                color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: style.shadowOpacity)
            )
            ctx.setFillColor(CGColor(srgbRed: 0.08, green: 0.08, blue: 0.1, alpha: 1.0))
            ctx.addPath(cardPath)
            ctx.fillPath()
            ctx.restoreGState()
        }

        // 3. Clipped window card (optional macOS titlebar + Retina screenshot)
        ctx.saveGState()
        ctx.addPath(cardPath)
        ctx.clip()

        if layout.chromeHeight > 0 {
            let chromeCG = CGRect(
                x: fullFrameCG.origin.x,
                y: contentCG.maxY,
                width: fullFrameCG.width,
                height: layout.chromeHeight
            )
            drawWindowChromeBar(in: ctx, rect: chromeCG, style: style.windowChrome, title: style.windowTitle)
        }

        ctx.draw(annotated, in: contentCG)
        ctx.restoreGState()

        // 4. Subtle crisp inner glass stroke
        if style.insetStroke {
            ctx.saveGState()
            let strokeWidth = max(1.0, 1.2 * scaleFactor)
            let insetRect = fullFrameCG.insetBy(dx: strokeWidth / 2.0, dy: strokeWidth / 2.0)
            let insetPath = CGPath(
                roundedRect: insetRect,
                cornerWidth: max(0, cornerRadius - strokeWidth / 2.0),
                cornerHeight: max(0, cornerRadius - strokeWidth / 2.0),
                transform: nil
            )
            ctx.addPath(insetPath)
            ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.22))
            ctx.setLineWidth(strokeWidth)
            ctx.strokePath()
            ctx.restoreGState()
        }

        // 5. Optional Custom Watermark / Creator Signature
        if style.watermark.isEffectivelyVisible {
            drawWatermark(in: ctx, canvasSize: layout.canvasSize, config: style.watermark)
        }

        return ctx.makeImage()
    }

    /// Renders a clean `compositeSize` base image of all arranged multi-image cards (used for
    /// cross-card Apple Vision Privacy OCR and pixel mosaic/blur baking).
    public static func renderMultiImageCompositeBase(
        images: [CGImage],
        layoutMode: MultiImageLayoutMode,
        spacing: CGFloat,
        fitMode: MultiImageFitMode,
        cornerRadius: CGFloat = 0,
        annotations: [AnnotationItem] = []
    ) -> CGImage? {
        guard !images.isEmpty else { return nil }
        if images.count == 1 {
            return renderAnnotatedRawImage(rawImage: images[0], annotations: annotations)
        }

        let plan = MultiImageLayoutEngine.computeLayout(
            imageSizes: images.map { CGSize(width: $0.width, height: $0.height) },
            mode: layoutMode,
            spacing: spacing,
            fitMode: fitMode
        )
        let cw = max(2, Int(plan.compositeSize.width.rounded()))
        let ch = max(2, Int(plan.compositeSize.height.rounded()))
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(
            data: nil,
            width: cw,
            height: ch,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.interpolationQuality = .high
        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)

        for slot in plan.slots where slot.index < images.count {
            let img = images[slot.index]
            let cardTopLeft = MultiImageLayoutEngine.resolvedCardRect(
                for: CGSize(width: img.width, height: img.height),
                in: slot
            )
            let cardCG = CGRect(
                x: cardTopLeft.origin.x,
                y: CGFloat(ch) - cardTopLeft.origin.y - cardTopLeft.height,
                width: cardTopLeft.width,
                height: cardTopLeft.height
            )
            let cr = min(cornerRadius, min(cardCG.width, cardCG.height) * 0.25)
            ctx.saveGState()
            if cr > 0.5 {
                let path = CGPath(roundedRect: cardCG, cornerWidth: cr, cornerHeight: cr, transform: nil)
                ctx.addPath(path)
                ctx.clip()
            } else {
                ctx.clip(to: cardCG)
            }
            drawImageAspectFillOrFit(img, in: cardCG, aspectFill: slot.aspectFill, ctx: ctx)
            ctx.restoreGState()
        }

        guard let base = ctx.makeImage() else { return nil }
        if annotations.isEmpty {
            return base
        }
        return renderAnnotatedRawImage(rawImage: base, annotations: annotations)
    }

    /// Full multi-image collage pipeline: renders wallpaper, individual floating rounded cards with
    /// studio shadows + optional glass strokes, and cross-card annotations/redactions at full Retina resolution.
    public static func renderMultiImageScreenshot(
        images: [CGImage],
        layoutMode: MultiImageLayoutMode,
        spacing: CGFloat,
        fitMode: MultiImageFitMode,
        annotations: [AnnotationItem],
        style: BeautifyStyle,
        enableBeautify: Bool,
        maxLongEdge: Int? = nil
    ) -> CGImage? {
        guard !images.isEmpty else { return nil }
        if images.count == 1 {
            return renderScreenshot(
                rawImage: images[0],
                annotations: annotations,
                style: style,
                enableBeautify: enableBeautify,
                maxLongEdge: maxLongEdge
            )
        }

        let plan = MultiImageLayoutEngine.computeLayout(
            imageSizes: images.map { CGSize(width: $0.width, height: $0.height) },
            mode: layoutMode,
            spacing: spacing,
            fitMode: fitMode
        )

        if !enableBeautify {
            guard let base = renderMultiImageCompositeBase(
                images: images,
                layoutMode: layoutMode,
                spacing: spacing,
                fitMode: fitMode,
                cornerRadius: 0,
                annotations: annotations
            ) else { return nil }
            if style.watermark.isEffectivelyVisible {
                return applyWatermark(to: base, config: style.watermark) ?? base
            }
            return base
        }

        // Disable outer window chrome on multi-card compositions (individual floating cards look much cleaner!)
        var collageStyle = style
        collageStyle.windowChrome = .none
        let layout = CoordinateConverter.computeCanvasLayout(
            sourceSize: plan.compositeSize,
            style: collageStyle,
            maxLongEdge: maxLongEdge,
            evenDimensions: false
        )

        let canvasW = Int(layout.canvasSize.width)
        let canvasH = Int(layout.canvasSize.height)
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(
            data: nil,
            width: canvasW,
            height: canvasH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.interpolationQuality = .high
        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)

        // 1. Background (Gradient / Mesh / macOS System Wallpaper / Custom Image)
        drawBackground(in: ctx, size: layout.canvasSize, preset: style.background)

        let scaleToContentX = layout.contentRect.width / max(1, plan.compositeSize.width)
        let scaleToContentY = layout.contentRect.height / max(1, plan.compositeSize.height)
        let designScale = max(1.0, min(layout.contentRect.width, layout.contentRect.height) / 720.0)
        let pixelEffects = annotations.filter { $0.toolKind == .mosaic || $0.toolKind == .blur }
        let vectorAnnotations = annotations.filter { $0.toolKind != .mosaic && $0.toolKind != .blur }

        // If user added pixel effects (mosaic/blur / privacy redact), bake them cleanly onto the composite card layer
        let bakedPixelComposite: CGImage? = pixelEffects.isEmpty ? nil : renderMultiImageCompositeBase(
            images: images,
            layoutMode: layoutMode,
            spacing: spacing,
            fitMode: fitMode,
            cornerRadius: 0,
            annotations: pixelEffects
        )

        // 2. Draw each card with its own crisp studio drop shadow, rounded corners, and inner glass stroke
        for slot in plan.slots where slot.index < images.count {
            let img = images[slot.index]
            let cardLocalTopLeft = MultiImageLayoutEngine.resolvedCardRect(
                for: CGSize(width: img.width, height: img.height),
                in: slot
            )
            let cardTopLeft = CGRect(
                x: layout.contentRect.origin.x + cardLocalTopLeft.origin.x * scaleToContentX,
                y: layout.contentRect.origin.y + cardLocalTopLeft.origin.y * scaleToContentY,
                width: cardLocalTopLeft.width * scaleToContentX,
                height: cardLocalTopLeft.height * scaleToContentY
            )
            let cardCG = CGRect(
                x: cardTopLeft.origin.x,
                y: layout.canvasSize.height - cardTopLeft.origin.y - cardTopLeft.height,
                width: cardTopLeft.width,
                height: cardTopLeft.height
            )
            let cr = min(style.cornerRadius * designScale * 0.85, min(cardCG.width, cardCG.height) * 0.25)
            let cardPath = CGPath(roundedRect: cardCG, cornerWidth: cr, cornerHeight: cr, transform: nil)

            // Individual card drop shadow
            if style.shadowRadius > 0 && style.shadowOpacity > 0.01 && style.background.kind != .transparent {
                let shadowBlur = style.shadowRadius * designScale * 0.85
                ctx.saveGState()
                ctx.setShadow(
                    offset: CGSize(width: 0, height: -shadowBlur * 0.28),
                    blur: shadowBlur,
                    color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: style.shadowOpacity)
                )
                ctx.setFillColor(CGColor(srgbRed: 0.08, green: 0.08, blue: 0.10, alpha: 1.0))
                ctx.addPath(cardPath)
                ctx.fillPath()
                ctx.restoreGState()
            }

            // Clipped image content (or pixel-redacted slice if mosaic/blur applied)
            ctx.saveGState()
            ctx.addPath(cardPath)
            ctx.clip()
            if let baked = bakedPixelComposite,
               let cropped = baked.cropping(to: cardLocalTopLeft.integral.intersection(CGRect(x: 0, y: 0, width: baked.width, height: baked.height))) {
                ctx.draw(cropped, in: cardCG)
            } else {
                drawImageAspectFillOrFit(img, in: cardCG, aspectFill: slot.aspectFill, ctx: ctx)
            }
            ctx.restoreGState()

            // Crisp inner glass stroke
            if style.insetStroke {
                ctx.saveGState()
                let sw = max(1.0, 1.15 * designScale)
                let insetRect = cardCG.insetBy(dx: sw / 2.0, dy: sw / 2.0)
                let insetPath = CGPath(
                    roundedRect: insetRect,
                    cornerWidth: max(0, cr - sw / 2.0),
                    cornerHeight: max(0, cr - sw / 2.0),
                    transform: nil
                )
                ctx.addPath(insetPath)
                ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.22))
                ctx.setLineWidth(sw)
                ctx.strokePath()
                ctx.restoreGState()
            }
        }

        // 3. Draw cross-card vector annotations cleanly on top!
        if !vectorAnnotations.isEmpty {
            ctx.saveGState()
            ctx.translateBy(x: layout.contentRect.origin.x, y: layout.canvasSize.height - layout.contentRect.origin.y)
            ctx.scaleBy(x: scaleToContentX, y: -scaleToContentY)

            for item in vectorAnnotations {
                switch item.toolKind {
                case .mosaic, .blur, .select:
                    continue
                case .highlighter:
                    let r = item.normalizedRect
                    guard r.width >= 2, r.height >= 2 else { continue }
                    ctx.saveGState()
                    ctx.setFillColor(RGBAColor(r: item.color.r, g: item.color.g, b: item.color.b, a: 0.34).cgColor)
                    ctx.addPath(CGPath(roundedRect: r, cornerWidth: 6, cornerHeight: 6, transform: nil))
                    ctx.fillPath()
                    ctx.restoreGState()
                case .rectangle:
                    let r = item.normalizedRect
                    guard r.width >= 2, r.height >= 2 else { continue }
                    ctx.saveGState()
                    ctx.setShadow(offset: CGSize(width: 0, height: 2), blur: 6, color: CGColor(gray: 0, alpha: 0.35))
                    ctx.setStrokeColor(item.color.cgColor)
                    ctx.setLineWidth(item.lineWidth)
                    ctx.setLineJoin(.round)
                    let rad = min(10, min(r.width, r.height) * 0.2)
                    ctx.addPath(CGPath(roundedRect: r, cornerWidth: rad, cornerHeight: rad, transform: nil))
                    ctx.strokePath()
                    ctx.restoreGState()
                case .ellipse:
                    let r = item.normalizedRect
                    guard r.width >= 2, r.height >= 2 else { continue }
                    ctx.saveGState()
                    ctx.setShadow(offset: CGSize(width: 0, height: 2), blur: 6, color: CGColor(gray: 0, alpha: 0.35))
                    ctx.setStrokeColor(item.color.cgColor)
                    ctx.setLineWidth(item.lineWidth)
                    ctx.strokeEllipse(in: r)
                    ctx.restoreGState()
                case .arrow:
                    drawModernArrow(in: ctx, from: item.startPoint, to: item.endPoint, color: item.color.cgColor, lineWidth: item.lineWidth)
                case .step:
                    drawStepBadge(in: ctx, at: item.startPoint, number: item.stepNumber, color: item.color.cgColor, radius: max(18, item.lineWidth * 3.2))
                case .text:
                    drawTextAnnotation(in: ctx, text: item.text, at: item.startPoint, color: item.color.nsColor, fontSize: item.fontSize)
                }
            }
            ctx.restoreGState()
        }

        // 4. Optional Custom Watermark / Creator Signature
        if style.watermark.isEffectivelyVisible {
            drawWatermark(in: ctx, canvasSize: layout.canvasSize, config: style.watermark)
        }

        return ctx.makeImage()
    }

    private static func drawImageAspectFillOrFit(_ img: CGImage, in rect: CGRect, aspectFill: Bool, ctx: CGContext) {
        let imgW = CGFloat(img.width)
        let imgH = CGFloat(img.height)
        guard imgW > 0, imgH > 0 else { return }
        let scale = aspectFill
            ? max(rect.width / imgW, rect.height / imgH)
            : min(rect.width / imgW, rect.height / imgH)
        let drawW = imgW * scale
        let drawH = imgH * scale
        let drawRect = CGRect(
            x: rect.midX - drawW / 2.0,
            y: rect.midY - drawH / 2.0,
            width: drawW,
            height: drawH
        )
        ctx.draw(img, in: drawRect)
    }

    public static func drawWindowChromeBar(in ctx: CGContext, rect: CGRect, style: WindowChromeStyle, title: String) {
        let isDark = (style == .macOSDark)
        let bgColor = isDark
            ? CGColor(srgbRed: 0.14, green: 0.14, blue: 0.16, alpha: 1.0)
            : CGColor(srgbRed: 0.94, green: 0.94, blue: 0.96, alpha: 1.0)
        ctx.setFillColor(bgColor)
        ctx.fill(rect)

        // Subtle separator line at bottom of chrome bar
        ctx.setFillColor(isDark ? CGColor(gray: 1, alpha: 0.08) : CGColor(gray: 0, alpha: 0.08))
        ctx.fill(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 1))

        // Traffic light dots
        let dotDiameter = rect.height * 0.34
        let dotSpacing = dotDiameter * 1.65
        let startX = rect.minX + rect.height * 0.45
        let centerY = rect.midY

        let dotColors: [CGColor] = [
            RGBAColor(hex: 0xFF5F56).cgColor,
            RGBAColor(hex: 0xFFBD2E).cgColor,
            RGBAColor(hex: 0x27C93F).cgColor
        ]

        for (index, dotColor) in dotColors.enumerated() {
            let cx = startX + CGFloat(index) * dotSpacing
            let dotRect = CGRect(
                x: cx - dotDiameter / 2,
                y: centerY - dotDiameter / 2,
                width: dotDiameter,
                height: dotDiameter
            )
            ctx.setFillColor(dotColor)
            ctx.fillEllipse(in: dotRect)
        }

        if !title.isEmpty {
            let fontSize = max(11, rect.height * 0.38)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fontSize, weight: .medium),
                .foregroundColor: isDark ? NSColor(white: 0.85, alpha: 1) : NSColor(white: 0.25, alpha: 1)
            ]
            let attrStr = NSAttributedString(string: title, attributes: attrs)
            let strSize = attrStr.size()
            let drawPt = CGPoint(x: rect.midX - strSize.width / 2, y: rect.midY - strSize.height / 2)

            NSGraphicsContext.saveGraphicsState()
            let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
            NSGraphicsContext.current = nsCtx
            attrStr.draw(at: drawPt)
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    // MARK: - Vector Annotation Primitives (drawn in top-left flipped CGContext)

    private static func drawModernArrow(in ctx: CGContext, from start: CGPoint, to end: CGPoint, color: CGColor, lineWidth: CGFloat) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length > 4 else { return }

        let angle = atan2(dy, dx)
        let headLength = min(length * 0.45, max(20, lineWidth * 4.2))
        let headHalfWidth = headLength * 0.46
        let tailHalfWidth = max(1.5, lineWidth * 0.28)
        let neckHalfWidth = max(3.0, lineWidth * 0.65)
        let neckLength = max(0, length - headLength * 0.78)

        ctx.saveGState()
        ctx.translateBy(x: start.x, y: start.y)
        ctx.rotate(by: angle)
        ctx.setShadow(offset: CGSize(width: 0, height: 2), blur: 6, color: CGColor(gray: 0, alpha: 0.35))
        ctx.setFillColor(color)

        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: -tailHalfWidth))
        path.addLine(to: CGPoint(x: neckLength, y: -neckHalfWidth))
        path.addLine(to: CGPoint(x: length - headLength, y: -headHalfWidth))
        path.addLine(to: CGPoint(x: length, y: 0))
        path.addLine(to: CGPoint(x: length - headLength, y: headHalfWidth))
        path.addLine(to: CGPoint(x: neckLength, y: neckHalfWidth))
        path.addLine(to: CGPoint(x: 0, y: tailHalfWidth))
        path.closeSubpath()

        ctx.addPath(path)
        ctx.fillPath()
        ctx.restoreGState()
    }

    private static func drawStepBadge(in ctx: CGContext, at center: CGPoint, number: Int, color: CGColor, radius: CGFloat) {
        let circleRect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 3), blur: 8, color: CGColor(gray: 0, alpha: 0.4))
        ctx.setFillColor(color)
        ctx.fillEllipse(in: circleRect)
        ctx.restoreGState()

        ctx.saveGState()
        ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.92))
        ctx.setLineWidth(max(2, radius * 0.12))
        ctx.strokeEllipse(in: circleRect)

        let fontSize = radius * 1.15
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        let str = NSAttributedString(string: "\(number)", attributes: attrs)
        let strSize = str.size()

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        str.draw(at: CGPoint(x: center.x - strSize.width / 2, y: center.y - strSize.height / 2))
        NSGraphicsContext.restoreGraphicsState()
        ctx.restoreGState()
    }

    private static func drawTextAnnotation(in ctx: CGContext, text: String, at origin: CGPoint, color: NSColor, fontSize: CGFloat) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: max(14, fontSize), weight: .bold),
            .foregroundColor: color
        ]
        let attrStr = NSAttributedString(string: text, attributes: attrs)
        let strSize = attrStr.size()
        let padX: CGFloat = fontSize * 0.35
        let padY: CGFloat = fontSize * 0.18
        let pillRect = CGRect(
            x: origin.x - padX,
            y: origin.y - padY,
            width: strSize.width + padX * 2,
            height: strSize.height + padY * 2
        )

        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 3), blur: 8, color: CGColor(gray: 0, alpha: 0.35))
        ctx.setFillColor(CGColor(srgbRed: 0.08, green: 0.09, blue: 0.12, alpha: 0.82))
        let pill = CGPath(roundedRect: pillRect, cornerWidth: 10, cornerHeight: 10, transform: nil)
        ctx.addPath(pill)
        ctx.fillPath()
        ctx.restoreGState()

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        attrStr.draw(at: origin)
        NSGraphicsContext.restoreGraphicsState()
    }

    // MARK: - Custom Watermark / Brand Signature Renderer (Standard Bottom-Left CG Coordinates)

    public static func applyWatermark(to image: CGImage, config: WatermarkConfig) -> CGImage? {
        guard config.isEffectivelyVisible else { return image }
        let w = image.width
        let h = image.height
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .high
        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)
        let size = CGSize(width: w, height: h)
        ctx.draw(image, in: CGRect(origin: .zero, size: size))
        drawWatermark(in: ctx, canvasSize: size, config: config)
        return ctx.makeImage()
    }

    /// Renders a crisp creator watermark badge or subtle diagonal anti-theft tile pattern in bottom-left CG coordinates.
    public static func drawWatermark(in ctx: CGContext, canvasSize: CGSize, config: WatermarkConfig) {
        let trimmed = config.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard config.enabled, !trimmed.isEmpty, config.opacity > 0.02 else { return }

        let shortEdge = min(canvasSize.width, canvasSize.height)
        let designScale = max(0.85, shortEdge / 760.0) * CGFloat(min(max(config.scale, 0.55), 2.2))
        let alpha = CGFloat(min(max(config.opacity, 0.05), 1.0))

        let displayText = config.showBrandGlyph ? "✦  \(trimmed)" : trimmed
        let fontSize = max(13.0, 15.5 * designScale)
        let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]
        let attrStr = NSAttributedString(string: displayText, attributes: attrs)
        let textSize = attrStr.size()

        if config.position == .tiled {
            ctx.saveGState()
            ctx.setAlpha(alpha * 0.42)
            let tileW = max(210 * designScale, textSize.width + 110 * designScale)
            let tileH = max(135 * designScale, textSize.height + 90 * designScale)
            let diag = hypot(canvasSize.width, canvasSize.height)
            ctx.translateBy(x: canvasSize.width / 2.0, y: canvasSize.height / 2.0)
            ctx.rotate(by: CGFloat(-26.0 * .pi / 180.0))

            var rowIdx = 0
            var y = -diag / 2.0
            while y < diag / 2.0 {
                let xOffset = (rowIdx % 2 == 0) ? 0 : tileW * 0.5
                var x = -diag / 2.0 - tileW + xOffset
                while x < diag / 2.0 + tileW {
                    ctx.saveGState()
                    ctx.setShadow(offset: CGSize(width: 0, height: -1.5), blur: 4 * designScale, color: CGColor(gray: 0, alpha: 0.45))
                    NSGraphicsContext.saveGraphicsState()
                    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
                    attrStr.draw(at: CGPoint(x: x, y: y))
                    NSGraphicsContext.restoreGraphicsState()
                    ctx.restoreGState()
                    x += tileW
                }
                y += tileH
                rowIdx += 1
            }
            ctx.restoreGState()
            return
        }

        let padX: CGFloat = (config.visualStyle == .minimalText) ? (6 * designScale) : (14 * designScale)
        let padY: CGFloat = (config.visualStyle == .minimalText) ? (4 * designScale) : (7.5 * designScale)
        let boxW = ceil(textSize.width + padX * 2)
        let boxH = ceil(textSize.height + padY * 2)
        let margin = max(16.0, shortEdge * 0.028)

        let boxOrigin: CGPoint
        switch config.position {
        case .bottomRight:
            boxOrigin = CGPoint(x: canvasSize.width - boxW - margin, y: margin)
        case .bottomLeft:
            boxOrigin = CGPoint(x: margin, y: margin)
        case .topRight:
            boxOrigin = CGPoint(x: canvasSize.width - boxW - margin, y: canvasSize.height - boxH - margin)
        case .topLeft:
            boxOrigin = CGPoint(x: margin, y: canvasSize.height - boxH - margin)
        case .bottomCenter:
            boxOrigin = CGPoint(x: (canvasSize.width - boxW) / 2.0, y: margin)
        case .tiled:
            boxOrigin = CGPoint(x: margin, y: margin)
        }

        let boxRect = CGRect(origin: boxOrigin, size: CGSize(width: boxW, height: boxH))
        ctx.saveGState()
        ctx.setAlpha(alpha)

        switch config.visualStyle {
        case .glassPill:
            let pill = CGPath(roundedRect: boxRect, cornerWidth: boxH / 2.0, cornerHeight: boxH / 2.0, transform: nil)
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -3 * designScale), blur: 10 * designScale, color: CGColor(gray: 0, alpha: 0.42))
            ctx.setFillColor(CGColor(srgbRed: 0.06, green: 0.07, blue: 0.11, alpha: 0.72))
            ctx.addPath(pill)
            ctx.fillPath()
            ctx.restoreGState()

            ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.24))
            ctx.setLineWidth(max(1.0, 1.1 * designScale))
            ctx.addPath(pill)
            ctx.strokePath()

        case .badgeAccent:
            let radius = min(10 * designScale, boxH / 2.0)
            let pill = CGPath(roundedRect: boxRect, cornerWidth: radius, cornerHeight: radius, transform: nil)
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -3 * designScale), blur: 12 * designScale, color: CGColor(srgbRed: 0.06, green: 0.56, blue: 0.94, alpha: 0.42))
            ctx.setFillColor(CGColor(srgbRed: 0.05, green: 0.09, blue: 0.16, alpha: 0.86))
            ctx.addPath(pill)
            ctx.fillPath()
            ctx.restoreGState()

            ctx.setStrokeColor(CGColor(srgbRed: 0.12, green: 0.72, blue: 1.0, alpha: 0.78))
            ctx.setLineWidth(max(1.2, 1.5 * designScale))
            ctx.addPath(pill)
            ctx.strokePath()

        case .minimalText:
            ctx.setShadow(offset: CGSize(width: 0, height: -1.5 * designScale), blur: 5 * designScale, color: CGColor(gray: 0, alpha: 0.65))
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        attrStr.draw(at: CGPoint(x: boxRect.midX - textSize.width / 2.0, y: boxRect.midY - textSize.height / 2.0))
        NSGraphicsContext.restoreGraphicsState()
        ctx.restoreGState()
    }
}
