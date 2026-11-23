import AppKit
import CoreGraphics
import SwiftUI
import UniformTypeIdentifiers

@MainActor
public final class QuickOverlayController {
    private var panel: NSPanel?
    private var dismissTimer: Timer?
    private var isHovered = false

    public init() {}

    public func showScreenshot(
        image: CGImage,
        fileURL: URL?,
        copiedToClipboard: Bool,
        isMultiImageCollectOn: Bool = false,
        collectedCount: Int = 1,
        onCopy: @escaping () -> Void,
        onEdit: @escaping () -> Void,
        onPin: @escaping () -> Void,
        onReveal: @escaping () -> Void,
        onExtractText: (() -> Void)? = nil,
        onToggleMultiCollect: (() -> Void)? = nil
    ) {
        let previewNS = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        let meta = isMultiImageCollectOn
            ? "\(collectedCount)/6 · \(image.width)×\(image.height)"
            : "\(image.width)×\(image.height) PNG"
        let purpleAccent = Color(red: 0.64, green: 0.44, blue: 0.98)
        let title = isMultiImageCollectOn
            ? L10n.format(.quickMultiCollectTitleFormat, collectedCount)
            : (copiedToClipboard ? L10n.t(.quickCopiedTitle) : L10n.t(.quickShotDoneTitle))
        let primaryTitle = isMultiImageCollectOn
            ? L10n.format(.quickMultiArrangeFormat, collectedCount)
            : L10n.t(.quickBeautifyEdit)

        let content = QuickOverlayCardView(
            titleText: title,
            metaBadge: meta,
            badgeIcon: isMultiImageCollectOn ? "rectangle.stack.fill" : "photo.fill",
            badgeColor: isMultiImageCollectOn ? purpleAccent : .cyan,
            previewImage: previewNS,
            fileURL: fileURL,
            primaryActionTitle: primaryTitle,
            primaryActionIcon: isMultiImageCollectOn ? "rectangle.3.group.fill" : "wand.and.stars",
            isMultiImageCollectOn: isMultiImageCollectOn,
            onPrimaryAction: { [weak self] in
                self?.dismiss()
                onEdit()
            },
            onCopy: onCopy,
            onExtractText: onExtractText.map { cb in
                { [weak self] in
                    self?.dismiss()
                    cb()
                }
            },
            onToggleMultiCollect: onToggleMultiCollect,
            onPin: { [weak self] in
                self?.dismiss()
                onPin()
            },
            onReveal: onReveal,
            onClose: { [weak self] in self?.dismiss() },
            onHoverChange: { [weak self] hovering in
                self?.isHovered = hovering
                if !hovering { self?.scheduleAutoDismiss(seconds: isMultiImageCollectOn ? 10 : 6) }
            }
        )
        presentPanel(rootView: content, autoDismissSeconds: isMultiImageCollectOn ? 16 : 12)
    }

    public func showExportedVideo(
        fileURL: URL,
        thumbnail: CGImage?,
        onCopyFile: @escaping () -> Void,
        onReveal: @escaping () -> Void
    ) {
        let previewNS = thumbnail.map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
        let extLabel = fileURL.pathExtension.uppercased()
        let bytes = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64) ?? 0
        let mb = Double(bytes) / (1024.0 * 1024.0)
        let meta = String(format: "%.1f MB · %@", mb, extLabel)

        let content = QuickOverlayCardView(
            titleText: L10n.format(.quickVideoReadyTitle, extLabel),
            metaBadge: meta,
            badgeIcon: "film.fill",
            badgeColor: .green,
            previewImage: previewNS,
            fileURL: fileURL,
            primaryActionTitle: L10n.t(.quickRevealFinder),
            primaryActionIcon: "folder.fill",
            isMultiImageCollectOn: false,
            onPrimaryAction: {
                onReveal()
            },
            onCopy: onCopyFile,
            onExtractText: nil,
            onToggleMultiCollect: nil,
            onPin: nil,
            onReveal: onReveal,
            onClose: { [weak self] in self?.dismiss() },
            onHoverChange: { [weak self] hovering in
                self?.isHovered = hovering
                if !hovering { self?.scheduleAutoDismiss(seconds: 8) }
            }
        )
        presentPanel(rootView: content, autoDismissSeconds: 12)
    }

    private func presentPanel<V: View>(rootView: V, autoDismissSeconds: TimeInterval = 12) {
        dismiss()

        let size = NSSize(width: 320, height: 236)
        let hosting = NSHostingView(rootView: rootView)
        hosting.frame = NSRect(origin: .zero, size: size)

        let screen = NSScreen.main ?? NSScreen.screens.first
        let originX = (screen?.visibleFrame.minX ?? 20) + 20
        let originY = (screen?.visibleFrame.minY ?? 20) + 20

        let p = NSPanel(
            contentRect: NSRect(x: originX, y: originY - 12, width: size.width, height: size.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isReleasedWhenClosed = false
        p.title = "XShot Preview"
        p.appearance = ThemeLocaleStore.shared.appearanceMode.nsAppearance
        p.level = .floating
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.isMovableByWindowBackground = true
        // Keep default `.readOnly` sharingType so users can freely screenshot the quick preview popup itself!
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = hosting
        p.alphaValue = 0
        p.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.24
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            p.animator().alphaValue = 1
            p.animator().setFrameOrigin(NSPoint(x: originX, y: originY))
        }

        self.panel = p
        scheduleAutoDismiss(seconds: autoDismissSeconds)
    }

    private func scheduleAutoDismiss(seconds: TimeInterval) {
        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.isHovered else { return }
                self.dismiss()
            }
        }
    }

    public func dismiss() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        if let p = panel {
            p.orderOut(nil)
            p.contentView = nil
        }
        panel = nil
    }
}

private struct QuickOverlayCardView: View {
    let titleText: String
    let metaBadge: String
    let badgeIcon: String
    let badgeColor: Color
    let previewImage: NSImage?
    let fileURL: URL?
    let primaryActionTitle: String
    let primaryActionIcon: String
    let isMultiImageCollectOn: Bool
    let onPrimaryAction: () -> Void
    let onCopy: () -> Void
    let onExtractText: (() -> Void)?
    let onToggleMultiCollect: (() -> Void)?
    let onPin: (() -> Void)?
    let onReveal: () -> Void
    let onClose: () -> Void
    let onHoverChange: (Bool) -> Void

    @ObservedObject private var uiStore = ThemeLocaleStore.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var copiedFeedback = false

    private var resolvedScheme: ColorScheme {
        uiStore.appearanceMode.resolvedColorScheme(environment: colorScheme)
    }

    private var palette: StudioPalette {
        StudioPalette.resolved(mode: uiStore.appearanceMode, environment: colorScheme)
    }

    var body: some View {
        VStack(spacing: 9) {
            // Header
            HStack(spacing: 7) {
                Image(systemName: badgeIcon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(badgeColor)
                Text(titleText)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.primaryText)
                    .lineLimit(1)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(palette.secondaryText)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(TactilePillButtonStyle(
                    background: palette.controlFill,
                    hoverBackground: palette.controlHoverFill,
                    cornerRadius: 11
                ))
            }

            // Draggable Thumbnail
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(palette.isDark ? Color.black.opacity(0.45) : Color.black.opacity(0.06))

                if let img = previewImage {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding(5)
                } else {
                    Image(systemName: "film")
                        .font(.system(size: 32))
                        .foregroundStyle(palette.tertiaryText)
                }

                VStack {
                    HStack {
                        Text(metaBadge)
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.92))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.black.opacity(0.68), in: Capsule())
                        Spacer()
                    }
                    Spacer()
                    HStack {
                        Spacer()
                        Label(uiStore.t(.quickDragToX), systemImage: "hand.draw.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(palette.accentTextOnAccent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(palette.accent, in: Capsule())
                    }
                }
                .padding(7)
            }
            .frame(height: 138)
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(palette.cardBorder, lineWidth: 0.7))
            .onDrag {
                if let url = fileURL {
                    return NSItemProvider(contentsOf: url) ?? NSItemProvider(object: url as NSURL)
                }
                if let img = previewImage {
                    return NSItemProvider(object: img)
                }
                return NSItemProvider()
            }

            // Action Buttons
            HStack(spacing: 6) {
                Button(action: onPrimaryAction) {
                    Label(primaryActionTitle, systemImage: primaryActionIcon)
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                }
                .buttonStyle(TactilePrimaryButtonStyle(cornerRadius: 8))

                Button {
                    onCopy()
                    copiedFeedback = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
                        copiedFeedback = false
                    }
                } label: {
                    Label(copiedFeedback ? uiStore.t(.quickCopied) : uiStore.t(.quickCopy), systemImage: copiedFeedback ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(copiedFeedback ? .green : palette.primaryText)
                        .padding(.horizontal, 8)
                        .frame(height: 28)
                }
                .buttonStyle(TactilePillButtonStyle(
                    background: palette.controlFill,
                    hoverBackground: palette.controlHoverFill,
                    borderColor: palette.controlBorder,
                    cornerRadius: 8
                ))

                if let onExtractText {
                    Button(action: onExtractText) {
                        Image(systemName: "text.viewfinder")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(palette.accent)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(TactilePillButtonStyle(
                        background: palette.accentSoftFill,
                        hoverBackground: palette.accentHoverFill,
                        borderColor: palette.accentBorder,
                        cornerRadius: 8
                    ))
                    .help(uiStore.t(.quickOCRTooltip))
                }

                if let onToggleMultiCollect {
                    let purple = Color(red: 0.64, green: 0.44, blue: 0.98)
                    Button(action: onToggleMultiCollect) {
                        Image(systemName: isMultiImageCollectOn ? "rectangle.stack.fill" : "rectangle.stack.badge.plus")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(isMultiImageCollectOn ? .white : purple)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(TactilePillButtonStyle(
                        background: isMultiImageCollectOn ? purple : purple.opacity(palette.isDark ? 0.20 : 0.12),
                        hoverBackground: isMultiImageCollectOn ? purple.opacity(0.85) : purple.opacity(palette.isDark ? 0.30 : 0.22),
                        borderColor: purple.opacity(isMultiImageCollectOn ? 0.9 : 0.45),
                        cornerRadius: 8
                    ))
                    .help(isMultiImageCollectOn ? uiStore.t(.quickMultiCollectStopTooltip) : uiStore.t(.quickMultiCollectTooltip))
                }

                if let onPin {
                    Button(action: onPin) {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.primaryText)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(TactilePillButtonStyle(
                        background: palette.controlFill,
                        hoverBackground: palette.controlHoverFill,
                        borderColor: palette.controlBorder,
                        cornerRadius: 8
                    ))
                    .help(uiStore.t(.quickPin))
                }

                Button(action: onReveal) {
                    Image(systemName: "folder")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.primaryText)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(TactilePillButtonStyle(
                    background: palette.controlFill,
                    hoverBackground: palette.controlHoverFill,
                    borderColor: palette.controlBorder,
                    cornerRadius: 8
                ))
                .help(uiStore.t(.revealInFinder))

                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .frame(width: 320, height: 236)
        .background(
            RoundedRectangle(cornerRadius: 15)
                .fill(palette.hudSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 15)
                        .strokeBorder(
                            isMultiImageCollectOn ? Color(red: 0.64, green: 0.44, blue: 0.98).opacity(0.68) : palette.hudBorder,
                            lineWidth: isMultiImageCollectOn ? 1.2 : 0.9
                        )
                )
        )
        .environment(\.colorScheme, resolvedScheme)
        .preferredColorScheme(uiStore.appearanceMode.swiftUIColorScheme)
        .onHover(perform: onHoverChange)
    }
}
