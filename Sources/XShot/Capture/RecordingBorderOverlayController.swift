import AppKit
import CoreGraphics
import QuartzCore

/// Click-through, ScreenCaptureKit-excluded visual boundary overlay drawn strictly OUTSIDE
/// the recording region so the user always sees exact recording edges without polluting the video.
@MainActor
public final class RecordingBorderOverlayController {
    private var panel: NSPanel?
    private var borderView: RecordingBorderView?

    public init() {}

    /// Shows a crisp glowing recording border around `target` (Area / Window / Fullscreen).
    public func show(for target: SelectedCaptureTarget) {
        dismiss()

        let primaryH = CoordinateConverter.primaryScreenHeight()
        let appKitRect: CGRect
        let isFullscreen: Bool
        let pixelWidth: Int
        let pixelHeight: Int

        switch target {
        case .area(_, let rect, _, _, let scale):
            appKitRect = rect
            isFullscreen = false
            pixelWidth = CoordinateConverter.evenPixelDimension(rect.width * scale)
            pixelHeight = CoordinateConverter.evenPixelDimension(rect.height * scale)

        case .window(_, _, _, let qFrame, let scale):
            appKitRect = CoordinateConverter.quartzToAppKit(qFrame, primaryHeight: primaryH)
            isFullscreen = false
            pixelWidth = CoordinateConverter.evenPixelDimension(qFrame.width * scale)
            pixelHeight = CoordinateConverter.evenPixelDimension(qFrame.height * scale)

        case .display(_, let qFrame, let scale):
            appKitRect = CoordinateConverter.quartzToAppKit(qFrame, primaryHeight: primaryH)
            isFullscreen = true
            pixelWidth = CoordinateConverter.evenPixelDimension(qFrame.width * scale)
            pixelHeight = CoordinateConverter.evenPixelDimension(qFrame.height * scale)
        }

        // Expand window outward around recording area so border & top badge sit OUTSIDE captured pixels!
        let outerPad: CGFloat = isFullscreen ? 0 : 12
        let topBadgeExtra: CGFloat = isFullscreen ? 0 : 24
        let screenFrame = NSScreen.screens.first(where: { $0.frame.intersects(appKitRect) })?.frame
            ?? NSScreen.main?.frame
            ?? appKitRect

        let desiredFrame = CGRect(
            x: appKitRect.origin.x - outerPad,
            y: appKitRect.origin.y - outerPad,
            width: appKitRect.width + outerPad * 2,
            height: appKitRect.height + outerPad * 2 + topBadgeExtra
        )
        let windowFrame = desiredFrame.intersection(screenFrame)
        guard !windowFrame.isNull, !windowFrame.isEmpty else { return }

        // Recording rect in window-local coordinates
        let localRecordingRect = CGRect(
            x: appKitRect.origin.x - windowFrame.origin.x,
            y: appKitRect.origin.y - windowFrame.origin.y,
            width: appKitRect.width,
            height: appKitRect.height
        )

        let p = NSPanel(
            contentRect: windowFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isReleasedWhenClosed = false
        p.level = .floating
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.ignoresMouseEvents = true // 100% click-through!
        p.sharingType = .none       // Invisible to ScreenCaptureKit!
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let view = RecordingBorderView(
            frame: CGRect(origin: .zero, size: windowFrame.size),
            recordingRect: localRecordingRect,
            isFullscreen: isFullscreen,
            resolutionText: "\(pixelWidth)×\(pixelHeight)"
        )
        p.contentView = view
        p.orderFrontRegardless()

        self.panel = p
        self.borderView = view
    }

    public func setPaused(_ paused: Bool) {
        borderView?.setPaused(paused)
    }

    public func dismiss() {
        guard let p = panel else { return }
        p.orderOut(nil)
        p.contentView = nil
        panel = nil
        borderView = nil
    }
}

private final class RecordingBorderView: NSView {
    private let recordingRect: CGRect
    private let isFullscreen: Bool
    private let resolutionText: String
    private var isPaused: Bool = false

    private let pulseLayer = CAShapeLayer()

    init(frame: CGRect, recordingRect: CGRect, isFullscreen: Bool, resolutionText: String) {
        self.recordingRect = recordingRect
        self.isFullscreen = isFullscreen
        self.resolutionText = resolutionText
        super.init(frame: frame)
        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor.clear.cgColor
        setupPulseAnimationLayer()
    }

    required init?(coder: NSCoder) { fatalError() }

    func setPaused(_ paused: Bool) {
        self.isPaused = paused
        updatePulseLayerStyle()
        needsDisplay = true
    }

    private func borderRect() -> CGRect {
        if isFullscreen {
            return bounds.insetBy(dx: 3, dy: 3)
        }
        // Strictly outside the recorded region by 2pt so ZERO border pixels bleed inside!
        return recordingRect.insetBy(dx: -2.0, dy: -2.0)
    }

    private func setupPulseAnimationLayer() {
        let rect = borderRect()
        let path = CGPath(roundedRect: rect, cornerWidth: isFullscreen ? 0 : 4, cornerHeight: isFullscreen ? 0 : 4, transform: nil)
        pulseLayer.path = path
        pulseLayer.fillColor = NSColor.clear.cgColor
        pulseLayer.lineWidth = 2.5
        pulseLayer.lineDashPattern = [10, 6]
        pulseLayer.shadowOpacity = 0.75
        pulseLayer.shadowRadius = 4
        pulseLayer.shadowOffset = .zero
        updatePulseLayerStyle()

        // Smooth subtle marching-ants animation on GPU (zero CPU cost!)
        let dashAnim = CABasicAnimation(keyPath: "lineDashPhase")
        dashAnim.fromValue = 0
        dashAnim.toValue = -32
        dashAnim.duration = 1.4
        dashAnim.repeatCount = .infinity
        pulseLayer.add(dashAnim, forKey: "marchingAnts")

        layer?.addSublayer(pulseLayer)
    }

    private func updatePulseLayerStyle() {
        let accent = isPaused
            ? NSColor(srgbRed: 0.98, green: 0.62, blue: 0.14, alpha: 0.95)
            : NSColor(srgbRed: 0.96, green: 0.24, blue: 0.36, alpha: 0.96)
        pulseLayer.strokeColor = accent.cgColor
        pulseLayer.shadowColor = accent.cgColor
        if isPaused {
            pulseLayer.speed = 0
        } else {
            pulseLayer.speed = 1
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let rect = borderRect()

        // 1. Crisp outer dark halo so the border stands out clearly on pure white AND dark backgrounds!
        ctx.saveGState()
        ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.55).cgColor)
        ctx.setLineWidth(4.5)
        let outerPath = CGPath(roundedRect: rect, cornerWidth: isFullscreen ? 0 : 4, cornerHeight: isFullscreen ? 0 : 4, transform: nil)
        ctx.addPath(outerPath)
        ctx.strokePath()
        ctx.restoreGState()

        // 2. Cinema-style bright L-shaped corner brackets for unmistakable recording boundary
        let accent = isPaused
            ? NSColor(srgbRed: 0.98, green: 0.65, blue: 0.18, alpha: 1.0)
            : NSColor(srgbRed: 0.98, green: 0.26, blue: 0.38, alpha: 1.0)
        let armLen: CGFloat = min(22, min(rect.width, rect.height) * 0.22)

        ctx.saveGState()
        ctx.setStrokeColor(accent.cgColor)
        ctx.setLineWidth(3.5)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        let corners: [(CGPoint, CGPoint, CGPoint)] = [
            // Bottom-left
            (CGPoint(x: rect.minX, y: rect.minY + armLen), CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.minX + armLen, y: rect.minY)),
            // Bottom-right
            (CGPoint(x: rect.maxX - armLen, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY + armLen)),
            // Top-left
            (CGPoint(x: rect.minX, y: rect.maxY - armLen), CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.minX + armLen, y: rect.maxY)),
            // Top-right
            (CGPoint(x: rect.maxX - armLen, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY - armLen))
        ]
        for (p1, corner, p2) in corners {
            ctx.move(to: p1)
            ctx.addLine(to: corner)
            ctx.addLine(to: p2)
        }
        ctx.strokePath()
        ctx.restoreGState()

        // 3. Compact outer status pill tucked right above top-left corner (when room exists outside rect)
        let availableTop = bounds.maxY - rect.maxY
        if !isFullscreen && availableTop >= 20 {
            let statusText = isPaused ? "PAUSED · \(resolutionText)" : "REC · \(resolutionText)"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .bold),
                .foregroundColor: NSColor.white
            ]
            let attrStr = NSAttributedString(string: statusText, attributes: attrs)
            let sz = attrStr.size()
            let pillW = sz.width + 22
            let pillH: CGFloat = 18
            let pillX = min(max(2, rect.minX), max(2, bounds.maxX - pillW - 2))
            let pillY = min(bounds.maxY - pillH - 2, rect.maxY + 4)
            let pillRect = CGRect(x: pillX, y: pillY, width: pillW, height: pillH)

            let pillPath = NSBezierPath(roundedRect: pillRect, xRadius: 5, yRadius: 5)
            NSColor(red: 0.06, green: 0.07, blue: 0.10, alpha: 0.90).setFill()
            pillPath.fill()
            accent.withAlphaComponent(0.75).setStroke()
            pillPath.lineWidth = 1
            pillPath.stroke()

            // Dot inside badge
            let dotRect = CGRect(x: pillRect.minX + 6, y: pillRect.midY - 3, width: 6, height: 6)
            accent.setFill()
            NSBezierPath(ovalIn: dotRect).fill()

            attrStr.draw(at: CGPoint(x: pillRect.minX + 15, y: pillRect.midY - sz.height / 2))
        }
    }
}
