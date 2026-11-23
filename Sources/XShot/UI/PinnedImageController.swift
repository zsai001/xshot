import AppKit
import CoreGraphics
import SwiftUI

@MainActor
public final class PinnedImageController {
    private let image: CGImage
    private let onClosed: (PinnedImageController) -> Void
    private var panel: NSPanel?

    public init(image: CGImage, onClosed: @escaping (PinnedImageController) -> Void) {
        self.image = image
        self.onClosed = onClosed
    }

    public func show() {
        let maxW: CGFloat = 520
        let maxH: CGFloat = 380
        let rawW = CGFloat(image.width) / 2.0
        let rawH = CGFloat(image.height) / 2.0
        let scale = min(1.0, min(maxW / max(1, rawW), maxH / max(1, rawH)))
        let size = NSSize(width: max(140, rawW * scale), height: max(100, rawH * scale))

        let nsImg = NSImage(cgImage: image, size: size)
        let view = PinnedImageView(
            image: nsImg,
            onCopy: { [image] in ExportHelpers.copyImageToPasteboard(image) },
            onClose: { [weak self] in self?.close() }
        )

        let p = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isReleasedWhenClosed = false
        p.level = .floating
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.isMovableByWindowBackground = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = NSHostingView(rootView: view)
        p.center()
        p.orderFrontRegardless()
        self.panel = p
    }

    public func close() {
        if let p = panel {
            p.orderOut(nil)
            p.contentView = nil
        }
        panel = nil
        onClosed(self)
    }
}

private struct PinnedImageView: View {
    let image: NSImage
    let onCopy: () -> Void
    let onClose: () -> Void
    @State private var isHovered = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.22), lineWidth: 1))

            if isHovered {
                HStack(spacing: 6) {
                    Button(action: onCopy) {
                        Image(systemName: "doc.on.doc.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(.black.opacity(0.72), in: Circle())
                    }
                    .buttonStyle(.plain)

                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(.black.opacity(0.72), in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(8)
            }
        }
        .onHover { isHovered = $0 }
    }
}
