import AppKit
import CoreGraphics
import SwiftUI

/// Clean native macOS window presenting extracted OCR text with Keep-Lines / Join-Paragraphs toggle,
/// full text editor, per-line 1-click copy list, and quick jump into Beautify Screenshot Studio.
@MainActor
public final class OCRResultWindowController {
    private var window: NSWindow?

    public init() {}

    public func show(
        sourceImage: CGImage,
        result: TextExtractionResult,
        autoCopied: Bool,
        onOpenBeautifyEditor: @escaping () -> Void
    ) {
        if let existing = window {
            existing.orderOut(nil)
            existing.contentView = nil
            window = nil
        }

        let rootView = OCRResultView(
            sourceImage: sourceImage,
            result: result,
            autoCopied: autoCopied,
            onOpenBeautifyEditor: { [weak self] in
                self?.close()
                onOpenBeautifyEditor()
            },
            onClose: { [weak self] in
                self?.close()
            }
        )

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 470),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.isReleasedWhenClosed = false
        win.title = L10n.t(.ocrWindowTitle)
        win.titlebarAppearsTransparent = true
        win.titlebarSeparatorStyle = .none
        win.appearance = ThemeLocaleStore.shared.appearanceMode.nsAppearance
        win.backgroundColor = StudioPalette.dynamicToolbarNSColor
        win.minSize = NSSize(width: 440, height: 360)
        win.contentView = NSHostingView(rootView: rootView)
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = win
    }

    public func refreshTitle() {
        window?.title = L10n.t(.ocrWindowTitle)
    }

    public func close() {
        if let win = window {
            win.orderOut(nil)
            win.contentView = nil
        }
        window = nil
    }
}

private struct OCRResultView: View {
    let sourceImage: CGImage
    let result: TextExtractionResult
    let autoCopied: Bool
    let onOpenBeautifyEditor: () -> Void
    let onClose: () -> Void

    @ObservedObject private var uiStore = ThemeLocaleStore.shared
    @Environment(\.colorScheme) private var colorScheme

    @State private var joinParagraphs: Bool = false
    @State private var viewMode: Int = 0 // 0: Editor, 1: Line List
    @State private var editableText: String
    @State private var copiedFeedback: String?

    init(
        sourceImage: CGImage,
        result: TextExtractionResult,
        autoCopied: Bool,
        onOpenBeautifyEditor: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.sourceImage = sourceImage
        self.result = result
        self.autoCopied = autoCopied
        self.onOpenBeautifyEditor = onOpenBeautifyEditor
        self.onClose = onClose
        self._editableText = State(initialValue: result.fullText)
    }

    private var resolvedScheme: ColorScheme {
        uiStore.appearanceMode.resolvedColorScheme(environment: colorScheme)
    }

    private var palette: StudioPalette {
        StudioPalette.resolved(mode: uiStore.appearanceMode, environment: colorScheme)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top Status & Controls Header
            HStack(spacing: 10) {
                if !result.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color(red: 0.14, green: 0.84, blue: 0.56))
                        Text(
                            autoCopied
                                ? uiStore.format(.ocrAutoCopiedBannerFormat, result.lineCount, result.characterCount)
                                : uiStore.format(.ocrStatsFormat, result.lineCount, result.characterCount)
                        )
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(palette.primaryText)
                        .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(
                        Capsule()
                            .fill(Color(red: 0.14, green: 0.84, blue: 0.56).opacity(palette.isDark ? 0.18 : 0.12))
                            .overlay(Capsule().strokeBorder(Color(red: 0.14, green: 0.84, blue: 0.56).opacity(0.45), lineWidth: 0.8))
                    )
                } else {
                    Label(uiStore.t(.ocrNoTextFound), systemImage: "text.viewfinder")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.orange)
                }

                Spacer(minLength: 4)

                if !result.isEmpty {
                    // Editor vs Line-by-Line segmented switch
                    HStack(spacing: 2) {
                        modePill(uiStore.t(.ocrViewEditor), active: viewMode == 0) { viewMode = 0 }
                        modePill(uiStore.t(.ocrViewLines), active: viewMode == 1) { viewMode = 1 }
                    }
                    .padding(2)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(palette.controlFill)
                            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(palette.controlBorder, lineWidth: 0.7))
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 10)
            .background(palette.toolbarBackground)

            Divider().overlay(palette.divider)

            // Main Content Area
            if result.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "text.viewfinder")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(palette.tertiaryText)
                    Text(uiStore.t(.ocrNoTextFound))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 10) {
                    if viewMode == 0 {
                        // Line-Break Mode Toggle (Keep Lines vs Join Paragraphs)
                        HStack(spacing: 8) {
                            HStack(spacing: 2) {
                                modePill(uiStore.t(.ocrModeKeepLines), active: !joinParagraphs) {
                                    joinParagraphs = false
                                    editableText = result.fullText
                                }
                                modePill(uiStore.t(.ocrModeJoinParagraphs), active: joinParagraphs) {
                                    joinParagraphs = true
                                    editableText = result.joinedParagraphText
                                }
                            }
                            .padding(2)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(palette.controlFill)
                                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(palette.controlBorder, lineWidth: 0.7))
                            )

                            Spacer()

                            if let fb = copiedFeedback {
                                Label(fb, systemImage: "checkmark")
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundStyle(Color(red: 0.14, green: 0.84, blue: 0.56))
                                    .transition(.opacity)
                            }
                        }

                        // Selectable, Editable Multi-Line Text Box
                        TextEditor(text: $editableText)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(palette.primaryText)
                            .scrollContentBackground(.hidden)
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(palette.cardBackground)
                                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(palette.cardBorder, lineWidth: 0.9))
                            )
                    } else {
                        // Per-Line 1-Click Copy List
                        ScrollView {
                            LazyVStack(spacing: 6) {
                                ForEach(Array(result.lines.enumerated()), id: \.element.id) { idx, line in
                                    HStack(spacing: 8) {
                                        Text("\(idx + 1)")
                                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                            .foregroundStyle(palette.tertiaryText)
                                            .frame(width: 22, alignment: .trailing)

                                        Text(line.text)
                                            .font(.system(size: 12.5))
                                            .foregroundStyle(palette.primaryText)
                                            .textSelection(.enabled)
                                            .frame(maxWidth: .infinity, alignment: .leading)

                                        Button {
                                            ExportHelpers.copyTextToPasteboard(line.text)
                                            NSSound(named: NSSound.Name("Pop"))?.play()
                                            flashFeedback(uiStore.t(.ocrCopiedLineToast))
                                        } label: {
                                            Image(systemName: "doc.on.doc")
                                                .font(.system(size: 10.5, weight: .semibold))
                                                .foregroundStyle(palette.accent)
                                                .frame(width: 26, height: 24)
                                        }
                                        .buttonStyle(TactilePillButtonStyle(
                                            background: palette.accentSoftFill,
                                            hoverBackground: palette.accentHoverFill,
                                            borderColor: palette.accentBorder,
                                            cornerRadius: 6
                                        ))
                                        .help(uiStore.t(.quickCopy))
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(palette.cardBackground)
                                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.cardBorder, lineWidth: 0.7))
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(14)
            }

            Divider().overlay(palette.divider)

            // Bottom Footer Bar (Source Thumbnail + Beautify Jump + Copy All Primary CTA)
            HStack(spacing: 10) {
                Image(decorative: sourceImage, scale: 1.0, orientation: .up)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 44, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(palette.controlBorder, lineWidth: 0.7))

                Button(action: onOpenBeautifyEditor) {
                    Label(uiStore.t(.ocrOpenEditorBtn), systemImage: "wand.and.stars")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(palette.primaryText)
                        .padding(.horizontal, 11)
                        .frame(height: 30)
                }
                .buttonStyle(TactilePillButtonStyle(
                    background: palette.controlFill,
                    hoverBackground: palette.controlHoverFill,
                    borderColor: palette.controlBorder,
                    hoverBorderColor: palette.accentBorder,
                    cornerRadius: 8
                ))

                Spacer()

                if !result.isEmpty {
                    Button {
                        ExportHelpers.copyTextToPasteboard(editableText)
                        NSSound(named: NSSound.Name("Pop"))?.play()
                        flashFeedback(uiStore.t(.ocrCopiedToast))
                    } label: {
                        Label(uiStore.t(.ocrCopyAllBtn), systemImage: "doc.on.doc.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 14)
                            .frame(height: 30)
                    }
                    .buttonStyle(TactilePrimaryButtonStyle(cornerRadius: 8))
                }

                Button(action: onClose) {
                    Text(uiStore.t(.closeBtn))
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(palette.secondaryText)
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                }
                .buttonStyle(TactilePillButtonStyle(
                    background: palette.controlFill,
                    hoverBackground: palette.controlHoverFill,
                    borderColor: palette.controlBorder,
                    cornerRadius: 8
                ))
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(palette.toolbarBackground)
        }
        .background(palette.windowBackground)
        .environment(\.colorScheme, resolvedScheme)
        .preferredColorScheme(uiStore.appearanceMode.swiftUIColorScheme)
    }

    private func modePill(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10.5, weight: active ? .bold : .medium))
                .foregroundStyle(active ? palette.accent : palette.secondaryText)
                .padding(.horizontal, 9)
                .frame(height: 22)
        }
        .buttonStyle(TactilePillButtonStyle(
            background: active ? palette.accentSoftFill : .clear,
            hoverBackground: active ? palette.accentHoverFill : palette.controlHoverFill,
            borderColor: active ? palette.accentBorder : .clear,
            cornerRadius: 5.5
        ))
    }

    private func flashFeedback(_ text: String) {
        withAnimation(.easeOut(duration: 0.15)) {
            copiedFeedback = text
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            if copiedFeedback == text {
                withAnimation(.easeOut(duration: 0.18)) {
                    copiedFeedback = nil
                }
            }
        }
    }
}
