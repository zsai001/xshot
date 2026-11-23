import AppKit
@preconcurrency import AVFoundation
import QuartzCore
import SwiftUI

/// Draggable, zero-copy GPU floating webcam self-preview bubble displayed during screen recording.
/// Marked with `sharingType = .none` so it is excluded from raw screen capture and composited
/// cleanly & non-destructively inside Video Studio afterwards!
@MainActor
public final class WebcamPreviewBubbleController {
    private var panel: NSPanel?

    public init() {}

    public func show(session: AVCaptureSession, config: WebcamPiPConfig) {
        dismiss()

        let screen = NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let baseDim: CGFloat = 176
        let w: CGFloat
        let h: CGFloat
        switch config.shape {
        case .circle:
            w = baseDim
            h = baseDim
        case .roundedRect:
            w = baseDim * 1.18
            h = w / config.shape.aspectRatio
        case .vertical:
            h = baseDim * 1.10
            w = h * config.shape.aspectRatio
        }

        let margin: CGFloat = 24
        let originX: CGFloat
        let originY: CGFloat
        switch config.corner {
        case .bottomLeft:
            originX = visible.minX + margin
            originY = visible.minY + margin
        case .bottomRight:
            originX = visible.maxX - w - margin
            originY = visible.minY + margin
        case .topLeft:
            originX = visible.minX + margin
            originY = visible.maxY - h - margin
        case .topRight:
            originX = visible.maxX - w - margin
            originY = visible.maxY - h - margin
        }

        let win = NSPanel(
            contentRect: NSRect(x: originX, y: originY, width: w, height: h),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        win.isReleasedWhenClosed = false
        win.backgroundColor = .clear
        win.isOpaque = false
        win.hasShadow = true
        win.isMovableByWindowBackground = true
        win.sharingType = .none
        win.level = .floating
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let root = WebcamBubbleContentView(session: session, config: config, size: CGSize(width: w, height: h))
        win.contentView = NSHostingView(rootView: root)
        win.orderFrontRegardless()
        self.panel = win
    }

    public func dismiss() {
        panel?.orderOut(nil)
        panel = nil
    }
}

private struct WebcamBubbleContentView: View {
    let session: AVCaptureSession
    let config: WebcamPiPConfig
    let size: CGSize

    var body: some View {
        let cr = config.cornerRadius(for: CGRect(origin: .zero, size: size))
        ZStack(alignment: .topTrailing) {
            CameraPreviewLayerRepresentable(session: session, mirrored: config.mirrored)
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: cr, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cr, style: .continuous)
                        .strokeBorder(Color.white.opacity(config.showBorder ? 0.88 : 0.25), lineWidth: config.showBorder ? 3.0 : 1.0)
                )

            // Subtle live camera dot
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
                .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                .padding(config.shape == .circle ? 24 : 12)
        }
        .frame(width: size.width, height: size.height)
    }
}

private struct CameraPreviewLayerRepresentable: NSViewRepresentable {
    let session: AVCaptureSession
    let mirrored: Bool

    func makeNSView(context: Context) -> CameraHostNSView {
        let view = CameraHostNSView()
        view.attach(session: session, mirrored: mirrored)
        return view
    }

    func updateNSView(_ nsView: CameraHostNSView, context: Context) {
        nsView.setMirrored(mirrored)
    }
}

private final class CameraHostNSView: NSView {
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    func attach(session: AVCaptureSession, mirrored: Bool) {
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = bounds
        preview.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        layer?.addSublayer(preview)
        self.previewLayer = preview
        setMirrored(mirrored)
    }

    func setMirrored(_ mirrored: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer?.setAffineTransform(mirrored ? CGAffineTransform(scaleX: -1, y: 1) : .identity)
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer?.frame = bounds
        CATransaction.commit()
    }
}
