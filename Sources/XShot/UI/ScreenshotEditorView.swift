import AppKit
import CoreGraphics
import SwiftUI
import UniformTypeIdentifiers

public struct ScreenshotEditorView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var document: ScreenshotDocument
    @ObservedObject private var uiStore = ThemeLocaleStore.shared
    @Environment(\.colorScheme) private var colorScheme
    let defaultPrivacyStyle: PrivacyRedactionStyle
    let autoPrivacyOnPaste: Bool
    let onSaved: (URL, CGImage) -> Void
    let onPin: (CGImage) -> Void

    @State private var selectedTool: AnnotationTool = .arrow
    @State private var selectedAnnotationID: UUID?
    @State private var dragOriginAnnotation: AnnotationItem?
    @State private var isDraggingAnnotation: Bool = false

    @State private var strokeColor: RGBAColor = RGBAColor(hex: 0xEF4444)
    @State private var strokeWidth: CGFloat = 6
    @State private var stepCounter: Int = 1
    @State private var redoStack: [AnnotationItem] = []

    @State private var privacyStyle: PrivacyRedactionStyle
    @State private var enabledPrivacyCategories: Set<PrivacyCategory> = Set(PrivacyCategory.allCases)
    @State private var isScanningPrivacy: Bool = false

    // Single-Image Slicer state (presets + custom rows/cols + 120Hz draggable cut lines!)
    @State private var enableSlicer: Bool = false
    @State private var sliceRows: Int = 2
    @State private var sliceCols: Int = 2
    @State private var sliceRowSplits: [CGFloat] = [0.5]
    @State private var sliceColSplits: [CGFloat] = [0.5]
    @State private var sliceIncludeBeautify: Bool = false

    // On-Device Vision OCR Text Extraction state (interactive canvas click-to-copy + full editable text)
    @State private var ocrResult: TextExtractionResult?
    @State private var ocrSourceImage: CGImage?
    @State private var ocrEditableText: String = ""
    @State private var ocrJoinParagraphs: Bool = false
    @State private var isExtractingOCR: Bool = false
    @State private var showOCROverlay: Bool = false

    // Multi-mode Canvas Viewport state (Fit Screen / Fit Width for Long Screenshots / 1:1 Retina / Custom Zoom)
    @State private var viewMode: CanvasViewMode = .fitScreen
    @State private var customZoom: CGFloat = 1.0
    @State private var pinchBaseZoom: CGFloat? = nil

    @State private var activeDraft: AnnotationItem?
    @State private var pendingTextPoint: CGPoint?
    @State private var pendingTextInput: String = ""
    @State private var showTextPopover: Bool = false

    /// Base raw image (or multi-image composite) with ONLY committed pixel effects (mosaic / blur)
    /// baked asynchronously off-main-thread. All Beautify effects + cards + vector annotations render at 120Hz GPU!
    @State private var pixelPatchedImage: CGImage
    @State private var toastText: String?
    @State private var isDropTargeted: Bool = false

    private let paletteColors: [RGBAColor] = [
        RGBAColor(hex: 0xEF4444), // Red
        RGBAColor(hex: 0xF59E0B), // Amber
        RGBAColor(hex: 0x10B981), // Emerald
        RGBAColor(hex: 0x0EA5E9), // Sky
        RGBAColor(hex: 0x8B5CF6), // Violet
        RGBAColor(hex: 0xFFFFFF), // White
        RGBAColor(hex: 0x111827)  // Dark
    ]

    public init(
        appState: AppState,
        document: ScreenshotDocument,
        defaultPrivacyStyle: PrivacyRedactionStyle = .mosaic,
        autoPrivacyOnPaste: Bool = true,
        onSaved: @escaping (URL, CGImage) -> Void,
        onPin: @escaping (CGImage) -> Void
    ) {
        self.appState = appState
        self.document = document
        self.defaultPrivacyStyle = defaultPrivacyStyle
        self.autoPrivacyOnPaste = autoPrivacyOnPaste
        self.onSaved = onSaved
        self.onPin = onPin
        self._pixelPatchedImage = State(initialValue: document.rawImage)
        self._privacyStyle = State(initialValue: defaultPrivacyStyle)
    }

    private var isMultiCollectActiveForThisDoc: Bool {
        appState.multiImageCollectMode && appState.activeMultiImageDocument === document
    }

    private var resolvedScheme: ColorScheme {
        uiStore.appearanceMode.resolvedColorScheme(environment: colorScheme)
    }

    private var palette: StudioPalette {
        StudioPalette.resolved(mode: uiStore.appearanceMode, environment: colorScheme)
    }

    private var pixelEffectAnnotations: [AnnotationItem] {
        document.annotations.filter { $0.toolKind == .mosaic || $0.toolKind == .blur }
    }

    public var body: some View {
        VStack(spacing: 0) {
            topToolbar
            Divider().overlay(palette.divider)
            HStack(spacing: 0) {
                live120HzCanvasStage
                Divider().overlay(palette.divider)
                beautifyInspector
            }
        }
        .background(palette.windowBackground)
        .environment(\.colorScheme, resolvedScheme)
        .preferredColorScheme(uiStore.appearanceMode.swiftUIColorScheme)
        .onAppear {
            bakePixelEffectsAsync()
            viewMode = CanvasViewportCalculator.recommendedInitialMode(for: currentLayout().canvasSize)
        }
        .onChange(of: pixelEffectAnnotations) { _, _ in
            if !isDraggingAnnotation {
                bakePixelEffectsAsync()
            }
        }
        .onChange(of: document.collageLayout) { _, _ in
            if !pixelEffectAnnotations.isEmpty { bakePixelEffectsAsync() }
            clearOCRState()
        }
        .onChange(of: document.collageFitMode) { _, _ in
            if !pixelEffectAnnotations.isEmpty { bakePixelEffectsAsync() }
            clearOCRState()
        }
        .onChange(of: document.collageSpacing) { _, _ in
            if !pixelEffectAnnotations.isEmpty { bakePixelEffectsAsync() }
            clearOCRState()
        }
        .onChange(of: document.collageImages.map(\.id)) { _, _ in
            if !pixelEffectAnnotations.isEmpty { bakePixelEffectsAsync() }
            clearOCRState()
        }
        .onChange(of: appState.multiImageNotificationID) { _, newID in
            if newID != nil,
               appState.activeMultiImageDocument === document,
               let msg = appState.multiImageNotificationText {
                flashToast(msg)
            }
        }
        .sheet(isPresented: $showTextPopover) {
            textInputSheet
        }
    }

    // MARK: - Full-Width Spacious Top Toolbar (Uniform Pill Heights & Clean Visual Alignment)

    private var topToolbar: some View {
        HStack(spacing: 10) {
            // Left: Crisp 9-tool segmented strip
            HStack(spacing: 2) {
                ForEach(AnnotationTool.allCases) { tool in
                    let isSelected = (selectedTool == tool)
                    Button {
                        selectedTool = tool
                        if tool != .select { selectedAnnotationID = nil }
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: tool.systemImage)
                                .font(.system(size: 13, weight: .semibold))
                            Text(tool.label)
                                .font(.system(size: 9.5, weight: isSelected ? .bold : .medium))
                                .lineLimit(1)
                        }
                        .foregroundStyle(isSelected ? palette.accent : palette.secondaryText)
                        .frame(width: 40, height: 36)
                    }
                    .buttonStyle(TactilePillButtonStyle(
                        background: isSelected ? palette.accentSoftFill : .clear,
                        hoverBackground: isSelected ? palette.accentHoverFill : palette.controlHoverFill,
                        borderColor: isSelected ? palette.accentBorder : .clear,
                        cornerRadius: 8
                    ))
                    .help(tool.label)
                }
            }
            .padding(3)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(palette.controlFill)
                    .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(palette.controlBorder, lineWidth: 0.7))
            )

            // Center-left: Matching grouped utility pill (Undo / Redo / Delete / Paste Clipboard Image)
            HStack(spacing: 2) {
                groupedUtilityButton("arrow.uturn.backward", help: uiStore.t(.undo), disabled: document.annotations.isEmpty) {
                    if let last = document.annotations.popLast() {
                        redoStack.append(last)
                        if selectedAnnotationID == last.id { selectedAnnotationID = nil }
                    }
                }
                .keyboardShortcut("z", modifiers: [.command])

                groupedUtilityButton("arrow.uturn.forward", help: uiStore.t(.redo), disabled: redoStack.isEmpty) {
                    if let restored = redoStack.popLast() {
                        document.annotations.append(restored)
                    }
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])

                if let selID = selectedAnnotationID {
                    groupedUtilityButton("delete.left.fill", help: uiStore.t(.deleteSelected), tint: .red, disabled: false) {
                        document.annotations.removeAll { $0.id == selID }
                        selectedAnnotationID = nil
                    }
                    .keyboardShortcut(.delete, modifiers: [])
                } else {
                    groupedUtilityButton("trash", help: uiStore.t(.clearAll), disabled: document.annotations.isEmpty) {
                        document.annotations.removeAll()
                        redoStack.removeAll()
                        stepCounter = 1
                    }
                }

                Divider()
                    .frame(height: 18)
                    .overlay(palette.divider)
                    .padding(.horizontal, 2)

                groupedUtilityButton("doc.on.clipboard", help: uiStore.t(.pasteFromClipboard), tint: palette.accent, disabled: false) {
                    pasteFromClipboardInEditor()
                }

                // One-Click On-Device Privacy Scan & Auto-Redact Shield
                Button {
                    runPrivacyScan()
                } label: {
                    ZStack(alignment: .topTrailing) {
                        if isScanningPrivacy {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.75)
                                .frame(width: 34, height: 36)
                        } else {
                            Image(systemName: activeRedactedFindingCount > 0 ? "lock.shield.fill" : "lock.shield")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(activeRedactedFindingCount > 0 ? Color(red: 0.14, green: 0.84, blue: 0.56) : palette.primaryText)
                                .frame(width: 34, height: 36)
                        }
                        if activeRedactedFindingCount > 0 && !isScanningPrivacy {
                            Text("\(activeRedactedFindingCount)")
                                .font(.system(size: 8.5, weight: .heavy, design: .monospaced))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .frame(minWidth: 14, minHeight: 14)
                                .background(Color(red: 0.10, green: 0.72, blue: 0.48), in: Capsule())
                                .offset(x: 1, y: 2)
                        }
                    }
                }
                .buttonStyle(TactilePillButtonStyle(
                    background: activeRedactedFindingCount > 0 ? Color(red: 0.14, green: 0.84, blue: 0.56).opacity(0.16) : .clear,
                    hoverBackground: activeRedactedFindingCount > 0 ? Color(red: 0.14, green: 0.84, blue: 0.56).opacity(0.26) : palette.controlHoverFill,
                    borderColor: activeRedactedFindingCount > 0 ? Color(red: 0.14, green: 0.84, blue: 0.56).opacity(0.50) : .clear,
                    cornerRadius: 8
                ))
                .disabled(isScanningPrivacy)
                .help(uiStore.t(.privacyScanFullBtn))

                // One-Click Single-Image Slicer Preview Toggle
                Button {
                    withAnimation(.easeOut(duration: 0.16)) {
                        enableSlicer.toggle()
                    }
                } label: {
                    Image(systemName: "scissors")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(enableSlicer ? Color.orange : palette.primaryText)
                        .frame(width: 32, height: 36)
                }
                .buttonStyle(TactilePillButtonStyle(
                    background: enableSlicer ? Color.orange.opacity(0.18) : .clear,
                    hoverBackground: enableSlicer ? Color.orange.opacity(0.28) : palette.controlHoverFill,
                    borderColor: enableSlicer ? Color.orange.opacity(0.55) : .clear,
                    cornerRadius: 8
                ))
                .help(uiStore.t(.sliceCardTitle))

                // One-Click On-Device Vision OCR Text Extraction & Interactive Canvas Boxes Toggle
                let skyTint = Color(red: 0.06, green: 0.65, blue: 0.91)
                let ocrLineCount = ocrResult?.lineCount ?? 0
                let ocrActive = showOCROverlay && ocrLineCount > 0
                Button {
                    if let res = ocrResult, !res.isEmpty {
                        withAnimation(.easeOut(duration: 0.16)) {
                            showOCROverlay.toggle()
                        }
                    } else {
                        runOCRExtraction()
                    }
                } label: {
                    ZStack(alignment: .topTrailing) {
                        if isExtractingOCR {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.75)
                                .frame(width: 32, height: 36)
                        } else {
                            Image(systemName: "text.viewfinder")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(ocrActive ? skyTint : palette.primaryText)
                                .frame(width: 32, height: 36)
                        }
                        if ocrLineCount > 0 && !isExtractingOCR {
                            Text("\(ocrLineCount)")
                                .font(.system(size: 8.5, weight: .heavy, design: .monospaced))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .frame(minWidth: 14, minHeight: 14)
                                .background(skyTint, in: Capsule())
                                .offset(x: 1, y: 2)
                        }
                    }
                }
                .buttonStyle(TactilePillButtonStyle(
                    background: ocrActive ? skyTint.opacity(0.18) : .clear,
                    hoverBackground: ocrActive ? skyTint.opacity(0.28) : palette.controlHoverFill,
                    borderColor: ocrActive ? skyTint.opacity(0.55) : .clear,
                    cornerRadius: 8
                ))
                .disabled(isExtractingOCR)
                .help(uiStore.t(.ocrCardTitle))
            }
            .padding(3)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(palette.controlFill)
                    .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(palette.controlBorder, lineWidth: 0.7))
            )

            Spacer(minLength: 8)

            // Right: Tactile Action Buttons
            HStack(spacing: 8) {
                Button {
                    if let img = renderFullResolution() { onPin(img) }
                } label: {
                    Image(systemName: "pin")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(palette.primaryText)
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(TactilePillButtonStyle(
                    background: palette.controlFill,
                    hoverBackground: palette.controlHoverFill,
                    borderColor: palette.controlBorder,
                    hoverBorderColor: palette.accentBorder,
                    cornerRadius: 8
                ))
                .help(uiStore.t(.pinAction))

                Button {
                    savePNG()
                } label: {
                    Label(uiStore.t(.saveAction), systemImage: "square.and.arrow.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.primaryText)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                }
                .buttonStyle(TactilePillButtonStyle(
                    background: palette.controlFill,
                    hoverBackground: palette.controlHoverFill,
                    borderColor: palette.controlBorder,
                    hoverBorderColor: palette.accentBorder,
                    cornerRadius: 8
                ))
                .keyboardShortcut("s", modifiers: [.command])

                Button {
                    copyPNG()
                } label: {
                    Label(uiStore.t(.copyForX), systemImage: "doc.on.doc.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 15)
                        .frame(height: 34)
                }
                .buttonStyle(TactilePrimaryButtonStyle(cornerRadius: 8))
                .keyboardShortcut("c", modifiers: [.command])
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 2)
        .padding(.bottom, 8)
        .frame(height: 54)
        .background(palette.toolbarBackground)
    }

    // MARK: - 120Hz Native GPU Live Stage (Multi-Mode Scrollable Viewport + Zero-Lag Annotations)

    private var live120HzCanvasStage: some View {
        GeometryReader { geo in
            let layout = currentLayout()
            let screenBacking = max(1.0, NSScreen.main?.backingScaleFactor ?? 2.0)
            let vp = CanvasViewportCalculator.computeLayout(
                canvasPixelSize: layout.canvasSize,
                viewportSize: geo.size,
                mode: viewMode,
                customZoom: customZoom,
                screenBackingScale: screenBacking
            )
            let fitted = vp.canvasRect
            let displayScale = vp.displayScale
            let currentEffectiveZoom = displayScale * screenBacking

            // Exact view-space rects for the beautified card & raw image area inside the scrollable canvas
            let contentViewRect = CGRect(
                x: fitted.minX + layout.contentRect.minX * displayScale,
                y: fitted.minY + layout.contentRect.minY * displayScale,
                width: layout.contentRect.width * displayScale,
                height: layout.contentRect.height * displayScale
            )
            let chromeViewHeight = layout.chromeHeight * displayScale
            let cardViewRect = CGRect(
                x: contentViewRect.minX,
                y: contentViewRect.minY - chromeViewHeight,
                width: contentViewRect.width,
                height: contentViewRect.height + chromeViewHeight
            )

            let designScaleFactor = max(1.0, min(layout.contentRect.width, layout.contentRect.height) / 720.0)
            let liveCornerRadius = document.enableBeautify
                ? min(document.style.cornerRadius * designScaleFactor, min(layout.contentRect.width, layout.contentRect.height) * 0.25) * displayScale
                : 0
            let liveShadowRadius = (document.enableBeautify && document.style.background.kind != .transparent)
                ? document.style.shadowRadius * designScaleFactor * displayScale * 0.65
                : 0

            ZStack {
                // Stage Studio Backdrop (stays fixed while long screenshots scroll smoothly above it!)
                RadialGradient(
                    colors: [palette.stageInner, palette.stageOuter],
                    center: .center,
                    startRadius: 20,
                    endRadius: max(geo.size.width, geo.size.height) * 0.72
                )

                // Scrollable 120Hz GPU Document Canvas (native momentum scroll + trackpad pinch zoom!)
                ScrollView([.horizontal, .vertical], showsIndicators: vp.needsScroll) {
                    ZStack {
                        // 1. Live GPU Beautify Background (Native Metal gradients — zero offscreen reallocation!)
                        ZStack {
                            if document.enableBeautify {
                                LiveBeautifyBackgroundView(preset: document.style.background)
                            }
                        }
                        .frame(width: fitted.width, height: fitted.height)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .shadow(color: .black.opacity(palette.shadowOpacity * 0.45), radius: 14, y: 5)
                        .position(x: fitted.midX, y: fitted.midY)

                // 2. Live Screenshot Card(s) — Single Card OR Multi-Image Floating Bento Cards (120Hz GPU!)
                if document.isMultiImage {
                    let plan = document.currentCollagePlan
                    let sx = contentViewRect.width / max(1, plan.compositeSize.width)
                    let sy = contentViewRect.height / max(1, plan.compositeSize.height)
                    let hasBakedMultiPixel = !pixelEffectAnnotations.isEmpty
                        && pixelPatchedImage.width == Int(plan.compositeSize.width.rounded())
                        && pixelPatchedImage.height == Int(plan.compositeSize.height.rounded())

                    ForEach(plan.slots, id: \.index) { slot in
                        if slot.index < document.collageImages.count {
                            let item = document.collageImages[slot.index]
                            let localCard = MultiImageLayoutEngine.resolvedCardRect(for: item.pixelSize, in: slot)
                            let viewCard = CGRect(
                                x: contentViewRect.minX + localCard.origin.x * sx,
                                y: contentViewRect.minY + localCard.origin.y * sy,
                                width: localCard.width * sx,
                                height: localCard.height * sy
                            )
                            let cardCR = document.enableBeautify
                                ? min(document.style.cornerRadius * designScaleFactor * 0.85, min(localCard.width, localCard.height) * 0.25) * displayScale
                                : 0
                            let cardShadow = liveShadowRadius * 0.85

                            if document.enableBeautify && document.style.background.kind != .transparent && cardShadow > 0.5 && document.style.shadowOpacity > 0.01 {
                                RoundedRectangle(cornerRadius: cardCR, style: .continuous)
                                    .fill(Color(red: 0.08, green: 0.08, blue: 0.10))
                                    .frame(width: viewCard.width, height: viewCard.height)
                                    .shadow(
                                        color: Color.black.opacity(Double(document.style.shadowOpacity)),
                                        radius: cardShadow,
                                        y: cardShadow * 0.30
                                    )
                                    .position(x: viewCard.midX, y: viewCard.midY)
                            }

                            Group {
                                if hasBakedMultiPixel,
                                   let slice = pixelPatchedImage.cropping(
                                       to: localCard.integral.intersection(CGRect(x: 0, y: 0, width: pixelPatchedImage.width, height: pixelPatchedImage.height))
                                   ) {
                                    Image(decorative: slice, scale: 1.0, orientation: .up)
                                        .resizable()
                                        .interpolation(.high)
                                } else {
                                    Image(decorative: item.image, scale: 1.0, orientation: .up)
                                        .resizable()
                                        .interpolation(.high)
                                        .aspectRatio(contentMode: slot.aspectFill ? .fill : .fit)
                                }
                            }
                            .frame(width: viewCard.width, height: viewCard.height)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: cardCR, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: cardCR, style: .continuous)
                                    .strokeBorder(
                                        Color.white.opacity(document.enableBeautify && document.style.insetStroke ? 0.24 : 0),
                                        lineWidth: max(0.8, 1.1 * designScaleFactor * displayScale)
                                    )
                            )
                            .position(x: viewCard.midX, y: viewCard.midY)
                        }
                    }

                    // Cross-card 120Hz Vector Annotations Layer spanning the full multi-image composition!
                    LiveAnnotationsCanvas(
                        annotations: document.annotations,
                        activeDraft: activeDraft,
                        draggingPixelEffectID: isDraggingAnnotation ? selectedAnnotationID : nil,
                        selectedID: selectedTool == .select ? selectedAnnotationID : nil,
                        rawImageSize: document.pixelSize
                    )
                    .frame(width: contentViewRect.width, height: contentViewRect.height)
                    .position(x: contentViewRect.midX, y: contentViewRect.midY)
                } else {
                    // 2a. Dedicated Analytic GPU Shadow Caster (avoids offscreen alpha-masking the Retina Image -> locked 120fps!)
                    if document.enableBeautify && document.style.background.kind != .transparent && liveShadowRadius > 0.5 && document.style.shadowOpacity > 0.01 {
                        RoundedRectangle(cornerRadius: liveCornerRadius, style: .continuous)
                            .fill(Color(red: 0.08, green: 0.08, blue: 0.10))
                            .frame(width: cardViewRect.width, height: cardViewRect.height)
                            .shadow(
                                color: Color.black.opacity(Double(document.style.shadowOpacity)),
                                radius: liveShadowRadius,
                                y: liveShadowRadius * 0.30
                            )
                            .position(x: cardViewRect.midX, y: cardViewRect.midY)
                    }

                    // 2b. Live Single Screenshot Card (Zero-Copy CGImage + macOS titlebar + 120Hz Vector Canvas)
                    VStack(spacing: 0) {
                        if document.enableBeautify && chromeViewHeight > 0.5 {
                            LiveWindowChromeView(
                                style: document.style.windowChrome,
                                title: document.style.windowTitle,
                                height: chromeViewHeight
                            )
                        }

                        ZStack {
                            Image(decorative: pixelPatchedImage, scale: 1.0, orientation: .up)
                                .resizable()
                                .interpolation(.high)

                            LiveAnnotationsCanvas(
                                annotations: document.annotations,
                                activeDraft: activeDraft,
                                draggingPixelEffectID: isDraggingAnnotation ? selectedAnnotationID : nil,
                                selectedID: selectedTool == .select ? selectedAnnotationID : nil,
                                rawImageSize: document.pixelSize
                            )
                        }
                        .frame(width: contentViewRect.width, height: contentViewRect.height)
                    }
                    .frame(width: cardViewRect.width, height: cardViewRect.height)
                    .clipShape(RoundedRectangle(cornerRadius: liveCornerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: liveCornerRadius, style: .continuous)
                            .strokeBorder(
                                Color.white.opacity(document.enableBeautify && document.style.insetStroke ? 0.24 : 0),
                                lineWidth: max(0.8, 1.1 * designScaleFactor * displayScale)
                            )
                    )
                    .position(x: cardViewRect.midX, y: cardViewRect.midY)
                }

                // 3. Direct-Manipulation Gesture Layer scoped cleanly to the screenshot area (+ comfortable 18pt bleed)
                Color.clear
                    .frame(width: contentViewRect.width + 36, height: contentViewRect.height + 36)
                    .contentShape(Rectangle())
                    .position(x: contentViewRect.midX, y: contentViewRect.midY)
                    .onHover { hovering in
                        if hovering {
                            if selectedTool == .select {
                                NSCursor.arrow.set()
                            } else {
                                NSCursor.crosshair.set()
                            }
                        } else {
                            NSCursor.arrow.set()
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .named("editorStage"))
                            .onChanged { value in
                                let startPx = mapStagePointToRawPixel(value.startLocation, contentViewRect: contentViewRect)
                                let curPx = mapStagePointToRawPixel(value.location, contentViewRect: contentViewRect)

                                if selectedTool == .select {
                                    if dragOriginAnnotation == nil {
                                        if let hit = hitTestAnnotation(at: startPx) {
                                            selectedAnnotationID = hit.id
                                            dragOriginAnnotation = hit
                                            isDraggingAnnotation = true
                                            strokeColor = hit.color
                                            NSCursor.closedHand.set()
                                        } else {
                                            selectedAnnotationID = nil
                                        }
                                    }
                                    if let origin = dragOriginAnnotation,
                                       let idx = document.annotations.firstIndex(where: { $0.id == origin.id }) {
                                        let dx = curPx.x - startPx.x
                                        let dy = curPx.y - startPx.y
                                        document.annotations[idx].startX = origin.startX + dx
                                        document.annotations[idx].startY = origin.startY + dy
                                        document.annotations[idx].endX = origin.endX + dx
                                        document.annotations[idx].endY = origin.endY + dy
                                    }
                                    return
                                }

                                if selectedTool == .step || selectedTool == .text { return }

                                activeDraft = AnnotationItem(
                                    tool: selectedTool,
                                    start: startPx,
                                    end: curPx,
                                    color: strokeColor,
                                    lineWidth: strokeWidth * max(1.0, document.pixelSize.width / 1200.0)
                                )
                            }
                            .onEnded { value in
                                if selectedTool == .select {
                                    let movedPixelEffect = dragOriginAnnotation.map { $0.toolKind == .mosaic || $0.toolKind == .blur } ?? false
                                    dragOriginAnnotation = nil
                                    isDraggingAnnotation = false
                                    NSCursor.arrow.set()
                                    if movedPixelEffect {
                                        bakePixelEffectsAsync()
                                    }
                                    return
                                }

                                let startPx = mapStagePointToRawPixel(value.startLocation, contentViewRect: contentViewRect)
                                let endPx = mapStagePointToRawPixel(value.location, contentViewRect: contentViewRect)

                                if selectedTool == .step {
                                    let badge = AnnotationItem(
                                        tool: .step,
                                        start: endPx,
                                        end: endPx,
                                        color: strokeColor,
                                        lineWidth: strokeWidth * max(1.0, document.pixelSize.width / 1200.0),
                                        stepNumber: stepCounter
                                    )
                                    stepCounter += 1
                                    document.annotations.append(badge)
                                    redoStack.removeAll()
                                    return
                                }

                                if selectedTool == .text {
                                    pendingTextPoint = endPx
                                    pendingTextInput = ""
                                    showTextPopover = true
                                    return
                                }

                                if let draft = activeDraft {
                                    if hypot(endPx.x - startPx.x, endPx.y - startPx.y) >= 6 {
                                        document.annotations.append(draft)
                                        redoStack.removeAll()
                                    }
                                    activeDraft = nil
                                }
                            }
                    )

                // 3b. 120Hz Interactive Draggable Cut-Line Overlay (Single-Image Slicer!)
                if enableSlicer {
                    let sliceViewRect = (sliceIncludeBeautify && document.enableBeautify) ? fitted : contentViewRect
                    let slicePixelSize = (sliceIncludeBeautify && document.enableBeautify) ? layout.canvasSize : document.pixelSize
                    LiveSliceGridOverlay(
                        targetRect: sliceViewRect,
                        pixelSize: slicePixelSize,
                        rowSplits: $sliceRowSplits,
                        colSplits: $sliceColSplits
                    )
                }

                // 3c. Interactive 120Hz Live OCR Click-to-Copy Overlay on Canvas
                if showOCROverlay, let result = ocrResult, !result.lines.isEmpty {
                    LiveOCRTextOverlay(
                        lines: result.lines,
                        targetRect: contentViewRect,
                        pixelSize: document.pixelSize
                    ) { line in
                        ExportHelpers.copyTextToPasteboard(line.text)
                        NSSound(named: NSSound.Name("Pop"))?.play()
                        flashToast(uiStore.t(.ocrCopiedLineToast))
                    }
                }

                // 3d. 120Hz Live Custom Watermark / Brand Signature Overlay
                if document.style.watermark.isEffectivelyVisible {
                    LiveWatermarkOverlay(
                        config: document.style.watermark,
                        targetRect: document.enableBeautify ? fitted : contentViewRect,
                        canvasPixelSize: document.enableBeautify ? layout.canvasSize : document.pixelSize
                    )
                }
                    }
                    .frame(width: vp.documentSize.width, height: vp.documentSize.height)
                    .coordinateSpace(name: "editorStage")
                }
                .gesture(
                    MagnifyGesture()
                        .onChanged { value in
                            let base = pinchBaseZoom ?? currentEffectiveZoom
                            if pinchBaseZoom == nil { pinchBaseZoom = base }
                            let next = min(
                                max(base * value.magnification, CanvasViewportCalculator.minZoom),
                                CanvasViewportCalculator.maxZoom
                            )
                            customZoom = next
                            viewMode = .custom
                        }
                        .onEnded { _ in
                            pinchBaseZoom = nil
                        }
                )

                // 4. Top-Left Resolution Readout, Floating Top-Center Toast & Top-Right View Mode / Zoom Controls
                VStack {
                    ZStack {
                        HStack(spacing: 8) {
                            HStack(spacing: 5) {
                                Text("\(Int(layout.canvasSize.width)) × \(Int(layout.canvasSize.height))")
                                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                                    .monospacedDigit()
                                Text("·")
                                    .foregroundStyle(palette.tertiaryText)
                                Text("2x PNG")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(palette.secondaryText)
                            }
                            .foregroundStyle(palette.primaryText)
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .background(
                                Capsule()
                                    .fill(palette.hudSurface)
                                    .overlay(Capsule().strokeBorder(palette.hudBorder, lineWidth: 0.7))
                            )
                            .allowsHitTesting(false)

                            Spacer()

                            // Top-Right Multi-Mode Viewing & Zoom Capsule (Fit / Fit Width / 1:1 / - % +)
                            viewModeControlBar(
                                currentZoomPercentage: vp.zoomPercentage,
                                currentEffectiveZoom: currentEffectiveZoom
                            )
                        }

                        if let toastText {
                            Label(toastText, systemImage: "checkmark.circle.fill")
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(.green)
                                .padding(.horizontal, 13)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(palette.hudSurface)
                                        .overlay(Capsule().strokeBorder(.green.opacity(0.48), lineWidth: 0.9))
                                )
                                .shadow(color: .black.opacity(palette.shadowOpacity * 0.45), radius: 10, y: 4)
                                .transition(.move(edge: .top).combined(with: .opacity))
                                .allowsHitTesting(false)
                        } else if isMultiCollectActiveForThisDoc {
                            let purple = Color(red: 0.64, green: 0.44, blue: 0.98)
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(purple)
                                    .frame(width: 7, height: 7)
                                Text(uiStore.format(.multiCollectCanvasBannerFormat, document.collageImages.count))
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(palette.primaryText)
                                    .lineLimit(1)

                                if document.collageImages.count < 6 {
                                    Button {
                                        appState.startAreaScreenshot()
                                    } label: {
                                        Label(uiStore.t(.multiCollectCaptureOne), systemImage: "crop")
                                            .font(.system(size: 10.5, weight: .bold))
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 8)
                                            .frame(height: 22)
                                    }
                                    .buttonStyle(TactilePillButtonStyle(
                                        background: purple,
                                        hoverBackground: purple.opacity(0.86),
                                        cornerRadius: 11
                                    ))
                                }

                                Button {
                                    withAnimation(.easeOut(duration: 0.16)) {
                                        appState.setMultiImageCollectMode(false)
                                    }
                                } label: {
                                    Text(uiStore.t(.multiCollectStopBtn))
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(palette.secondaryText)
                                        .padding(.horizontal, 7)
                                        .frame(height: 22)
                                }
                                .buttonStyle(TactilePillButtonStyle(
                                    background: palette.controlFill,
                                    hoverBackground: palette.controlHoverFill,
                                    cornerRadius: 11
                                ))
                            }
                            .padding(.leading, 11)
                            .padding(.trailing, 6)
                            .frame(height: 30)
                            .background(
                                Capsule()
                                    .fill(palette.hudSurface)
                                    .overlay(Capsule().strokeBorder(purple.opacity(0.65), lineWidth: 1.0))
                            )
                            .shadow(color: .black.opacity(palette.shadowOpacity * 0.45), radius: 10, y: 4)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    Spacer()
                }

                // 5. Perfectly Centered Bottom Floating Drawing Style Dock + Right-Docked Drag-to-X Chip
                VStack {
                    Spacer()
                    ZStack {
                        // True dead-center floating Color + Custom Wheel + Stroke Width dock (uniform 26×26 circular alignment!)
                        HStack(spacing: 10) {
                            HStack(spacing: 4) {
                                ForEach(paletteColors, id: \.self) { c in
                                    ColorSwatchDotButton(
                                        color: c.swiftUIColor,
                                        isSelected: strokeColor == c,
                                        palette: palette
                                    ) {
                                        applyStrokeColor(c)
                                    }
                                }

                                CustomColorWheelButton(
                                    currentColor: strokeColor,
                                    isCustomActive: !paletteColors.contains(strokeColor),
                                    palette: palette,
                                    tooltip: uiStore.t(.customColorTooltip)
                                ) { picked in
                                    applyStrokeColor(picked)
                                }
                            }

                            Divider().frame(height: 18).overlay(palette.divider)

                            // Tactile S / M / L Stroke Size Pills
                            HStack(spacing: 4) {
                                ForEach([(4.0, "S"), (7.0, "M"), (11.0, "L")], id: \.0) { sizeVal, label in
                                    let isSelected = abs(strokeWidth - sizeVal) < 0.5
                                    Button {
                                        applyStrokeWidth(sizeVal)
                                    } label: {
                                        Text(label)
                                            .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                                            .foregroundStyle(isSelected ? palette.accentTextOnAccent : palette.secondaryText)
                                            .frame(width: 26, height: 24)
                                    }
                                    .buttonStyle(TactilePillButtonStyle(
                                        background: isSelected ? palette.accent : .clear,
                                        hoverBackground: isSelected ? palette.accent : palette.controlHoverFill,
                                        cornerRadius: 7
                                    ))
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 38)
                        .background(
                            Capsule()
                                .fill(palette.hudSurface)
                                .overlay(Capsule().strokeBorder(palette.hudBorder, lineWidth: 0.9))
                        )
                        .shadow(color: .black.opacity(palette.shadowOpacity * 0.42), radius: 10, y: 4)

                        // Direct Drag-to-X Chip neatly pinned bottom-right without offsetting the center dock
                        if let url = document.savedURL {
                            HStack {
                                Spacer()
                                Label(uiStore.t(.dragMeToX), systemImage: "hand.draw.fill")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(palette.accentTextOnAccent)
                                    .padding(.horizontal, 13)
                                    .frame(height: 38)
                                    .background(palette.accent, in: Capsule())
                                    .shadow(color: palette.accent.opacity(0.32), radius: 8, y: 2)
                                    .onDrag {
                                        if let img = renderFullResolution() {
                                            ExportHelpers.savePNG(img, to: url)
                                        }
                                        return NSItemProvider(contentsOf: url) ?? NSItemProvider(object: url as NSURL)
                                    }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
                }
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(palette.accent, style: StrokeStyle(lineWidth: 2.5, dash: [8, 5]))
                        .background(palette.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .padding(14)
                        .allowsHitTesting(false)
                }
            }
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                handleDroppedImageFiles(providers)
            }
        }
    }

    @ViewBuilder
    private func viewModeControlBar(currentZoomPercentage: Int, currentEffectiveZoom: CGFloat) -> some View {
        HStack(spacing: 3) {
            viewModePill(
                title: uiStore.t(.viewModeFit),
                icon: "arrow.down.right.and.arrow.up.left",
                mode: .fitScreen,
                shortcut: "0",
                tooltip: uiStore.t(.viewModeFitTooltip)
            )
            viewModePill(
                title: uiStore.t(.viewModeFitWidth),
                icon: "arrow.left.and.right",
                mode: .fitWidth,
                shortcut: "2",
                tooltip: uiStore.t(.viewModeFitWidthTooltip)
            )
            viewModePill(
                title: uiStore.t(.viewModeActual),
                icon: nil,
                mode: .actualSize,
                shortcut: "1",
                tooltip: uiStore.t(.viewModeActualTooltip)
            )

            Divider()
                .frame(height: 14)
                .overlay(palette.divider)
                .padding(.horizontal, 2)

            Button {
                withAnimation(.easeOut(duration: 0.14)) {
                    customZoom = CanvasViewportCalculator.steppedZoom(from: currentEffectiveZoom, zoomIn: false)
                    viewMode = .custom
                }
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(palette.secondaryText)
                    .frame(width: 21, height: 22)
            }
            .buttonStyle(TactilePillButtonStyle(
                background: .clear,
                hoverBackground: palette.controlHoverFill,
                cornerRadius: 6
            ))
            .keyboardShortcut("-", modifiers: [.command])
            .help(uiStore.t(.viewZoomOutTooltip))

            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    viewMode = (viewMode == .actualSize) ? .fitScreen : .actualSize
                }
            } label: {
                Text("\(currentZoomPercentage)%")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(viewMode == .custom ? palette.accent : palette.primaryText)
                    .frame(minWidth: 38)
                    .frame(height: 22)
            }
            .buttonStyle(TactilePillButtonStyle(
                background: viewMode == .custom ? palette.accentSoftFill : .clear,
                hoverBackground: palette.controlHoverFill,
                borderColor: viewMode == .custom ? palette.accentBorder : .clear,
                cornerRadius: 6
            ))
            .help(uiStore.t(.viewModeActualTooltip))

            Button {
                withAnimation(.easeOut(duration: 0.14)) {
                    customZoom = CanvasViewportCalculator.steppedZoom(from: currentEffectiveZoom, zoomIn: true)
                    viewMode = .custom
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(palette.secondaryText)
                    .frame(width: 21, height: 22)
            }
            .buttonStyle(TactilePillButtonStyle(
                background: .clear,
                hoverBackground: palette.controlHoverFill,
                cornerRadius: 6
            ))
            .keyboardShortcut("=", modifiers: [.command])
            .help(uiStore.t(.viewZoomInTooltip))
        }
        .padding(.horizontal, 5)
        .frame(height: 28)
        .background(
            Capsule()
                .fill(palette.hudSurface)
                .overlay(Capsule().strokeBorder(palette.hudBorder, lineWidth: 0.75))
        )
        .shadow(color: .black.opacity(palette.shadowOpacity * 0.25), radius: 6, y: 2)
    }

    private func viewModePill(
        title: String,
        icon: String?,
        mode: CanvasViewMode,
        shortcut: KeyEquivalent,
        tooltip: String
    ) -> some View {
        let isSelected = (viewMode == mode)
        return Button {
            withAnimation(.easeOut(duration: 0.16)) {
                viewMode = mode
            }
        } label: {
            HStack(spacing: 3) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 9, weight: .bold))
                }
                Text(title)
                    .font(.system(size: 10, weight: isSelected ? .bold : .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? palette.accent : palette.secondaryText)
            .padding(.horizontal, 7)
            .frame(height: 22)
        }
        .buttonStyle(TactilePillButtonStyle(
            background: isSelected ? palette.accentSoftFill : .clear,
            hoverBackground: isSelected ? palette.accentHoverFill : palette.controlHoverFill,
            borderColor: isSelected ? palette.accentBorder : .clear,
            cornerRadius: 11
        ))
        .keyboardShortcut(shortcut, modifiers: [.command])
        .help(tooltip)
    }

    // MARK: - Polished, Tactile Right Beautify Inspector

    private var beautifyInspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Master Beautify Toggle Card
                HStack {
                    HStack(spacing: 7) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(palette.accent)
                        Text(uiStore.t(.beautifyShell))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(palette.primaryText)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { document.enableBeautify },
                        set: { newVal in
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.86)) {
                                document.enableBeautify = newVal
                            }
                        }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(palette.cardBackground)
                        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(palette.cardBorder, lineWidth: 0.8))
                        .shadow(color: .black.opacity(palette.isDark ? 0 : 0.04), radius: 4, y: 1)
                )

                // Always-Active Privacy Detection & Auto-Redaction Card
                privacyGuardCard

                // On-Device Vision OCR Text Extraction Card
                ocrTextCard

                // Multi-Image Bento / Collage Arrangement Card
                multiImageCard

                // Single-Image Slicer Card (Grid / Long-Screenshot Split + Draggable Cut Lines!)
                imageSlicerCard

                // Custom Watermark / Creator Signature Card (works with or without Beautify!)
                WatermarkInspectorCard(
                    config: $document.style.watermark,
                    palette: palette,
                    onSaveAsDefault: {
                        appState.defaultWatermark = document.style.watermark
                        NSSound(named: NSSound.Name("Pop"))?.play()
                        flashToast(uiStore.t(.watermarkSavedDefaultToast))
                    }
                )

                Group {
                    inspectorCard(title: uiStore.t(.quickPresets)) {
                        HStack(spacing: 6) {
                            quickPresetButton(
                                uiStore.t(.presetAurora),
                                dotColors: [Color(red: 0.25, green: 0.58, blue: 0.96), Color(red: 0.56, green: 0.30, blue: 0.96)],
                                isActive: document.style.background.id == BackgroundPreset.curated[0].id && document.style.windowChrome == .none
                            ) {
                                withAnimation(.easeOut(duration: 0.16)) {
                                    var s = BeautifyStyle.defaultScreenshot
                                    s.watermark = document.style.watermark
                                    document.style = s
                                }
                            }
                            quickPresetButton(
                                uiStore.t(.presetDarkWindow),
                                dotColors: [Color(red: 0.12, green: 0.14, blue: 0.22), Color(red: 0.26, green: 0.30, blue: 0.42)],
                                isActive: document.style.background.id == BackgroundPreset.curated[6].id && document.style.windowChrome == .macOSDark
                            ) {
                                withAnimation(.easeOut(duration: 0.16)) {
                                    document.style = BeautifyStyle(
                                        background: BackgroundPreset.curated[6],
                                        padding: 56,
                                        cornerRadius: 16,
                                        shadowRadius: 36,
                                        shadowOpacity: 0.52,
                                        aspectRatio: .auto,
                                        windowChrome: .macOSDark,
                                        insetStroke: true,
                                        watermark: document.style.watermark
                                    )
                                }
                            }
                            quickPresetButton(
                                uiStore.t(.presetCleanLight),
                                dotColors: [Color(red: 0.92, green: 0.94, blue: 0.98), Color(red: 0.80, green: 0.84, blue: 0.92)],
                                isActive: document.style.background.id == BackgroundPreset.curated[7].id && document.style.windowChrome == .macOSLight
                            ) {
                                withAnimation(.easeOut(duration: 0.16)) {
                                    document.style = BeautifyStyle(
                                        background: BackgroundPreset.curated[7],
                                        padding: 52,
                                        cornerRadius: 16,
                                        shadowRadius: 28,
                                        shadowOpacity: 0.25,
                                        aspectRatio: .auto,
                                        windowChrome: .macOSLight,
                                        insetStroke: false,
                                        watermark: document.style.watermark
                                    )
                                }
                            }
                        }
                    }

                    inspectorCard(title: uiStore.t(.backgroundWallpaper)) {
                        WallpaperPickerSection(selectedBackground: $document.style.background, palette: palette)
                    }

                    // Balanced 1 + 2x2 Aspect Ratio Grid (zero orphan half-row!)
                    inspectorCard(title: uiStore.t(.canvasAspectX)) {
                        VStack(spacing: 6) {
                            aspectRatioTile(.auto, fullWidth: true)
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                                aspectRatioTile(.wide16x9)
                                aspectRatioTile(.card4x3)
                                aspectRatioTile(.square1x1)
                                aspectRatioTile(.vertical9x16)
                            }
                        }
                    }

                    inspectorCard(title: uiStore.t(.paddingAndDepth)) {
                        VStack(spacing: 12) {
                            inspectorSlider(title: uiStore.t(.paddingLabel), value: $document.style.padding, defaultValue: 64, range: 0...180, unit: "pt")
                            inspectorSlider(title: uiStore.t(.cornerRadiusLabel), value: $document.style.cornerRadius, defaultValue: 18, range: 0...42, unit: "pt")
                            inspectorSlider(title: uiStore.t(.shadowLabel), value: $document.style.shadowRadius, defaultValue: 36, range: 0...72, unit: "pt")
                        }
                    }

                    inspectorCard(title: uiStore.t(.windowChromeTitle)) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 6) {
                                ForEach(WindowChromeStyle.allCases) { style in
                                    let isSelected = (document.style.windowChrome == style)
                                    Button {
                                        withAnimation(.easeOut(duration: 0.14)) {
                                            document.style.windowChrome = style
                                        }
                                    } label: {
                                        HStack(spacing: 4) {
                                            windowChromeMiniGlyph(style)
                                            Text(style.displayName)
                                                .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                                                .foregroundStyle(isSelected ? palette.accent : palette.secondaryText)
                                                .lineLimit(1)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 30)
                                    }
                                    .buttonStyle(TactilePillButtonStyle(
                                        background: isSelected ? palette.accentSoftFill : palette.controlFill,
                                        hoverBackground: isSelected ? palette.accentHoverFill : palette.controlHoverFill,
                                        borderColor: isSelected ? palette.accentBorder : palette.controlBorder,
                                        cornerRadius: 8
                                    ))
                                }
                            }

                            if document.style.windowChrome != .none {
                                TextField(uiStore.t(.windowTitlePlaceholder), text: $document.style.windowTitle)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 12))
                            }

                            Toggle(uiStore.t(.glassStroke), isOn: $document.style.insetStroke)
                                .font(.system(size: 12))
                                .foregroundStyle(palette.primaryText)
                        }
                    }
                }
                .disabled(!document.enableBeautify)
                .opacity(document.enableBeautify ? 1 : 0.42)
            }
            .padding(12)
        }
        .frame(width: 296)
        .background(palette.inspectorBackground)
    }

    // MARK: - On-Device Privacy Detection & Auto-Redaction Inspector Card

    private var activeRedactedFindingCount: Int {
        let annIDs = Set(document.annotations.map(\.id))
        return document.privacyFindings.filter { annIDs.contains($0.annotationID) }.count
    }

    private var privacyGuardCard: some View {
        let greenTint = Color(red: 0.14, green: 0.84, blue: 0.56)
        let activeAnnIDs = Set(document.annotations.map(\.id))

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(greenTint)
                Text(uiStore.t(.privacyCardTitle))
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(palette.primaryText)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if activeRedactedFindingCount > 0 {
                    Text("\(activeRedactedFindingCount)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(greenTint)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(greenTint.opacity(0.18), in: Capsule())

                    Button {
                        clearAutoPrivacyRedactions()
                    } label: {
                        Text(uiStore.t(.privacyClearAuto))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 7)
                            .frame(height: 20)
                    }
                    .buttonStyle(TactilePillButtonStyle(
                        background: .red.opacity(0.14),
                        hoverBackground: .red.opacity(0.24),
                        cornerRadius: 6
                    ))
                }
            }

            // Primary Scan & Redact CTA + Style Picker (Mosaic / Blur)
            HStack(spacing: 6) {
                Button {
                    runPrivacyScan()
                } label: {
                    HStack(spacing: 5) {
                        if isScanningPrivacy {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.72)
                        } else {
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 11, weight: .bold))
                        }
                        Text(isScanningPrivacy ? uiStore.t(.privacyScanning) : uiStore.t(.privacyScanFullBtn))
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(greenTint)
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
                }
                .buttonStyle(TactilePillButtonStyle(
                    background: greenTint.opacity(palette.isDark ? 0.20 : 0.14),
                    hoverBackground: greenTint.opacity(palette.isDark ? 0.30 : 0.22),
                    borderColor: greenTint.opacity(0.55),
                    cornerRadius: 8
                ))
                .disabled(isScanningPrivacy || enabledPrivacyCategories.isEmpty)

                HStack(spacing: 3) {
                    ForEach(PrivacyRedactionStyle.allCases) { style in
                        let isSelected = (privacyStyle == style)
                        Button {
                            privacyStyle = style
                            updateAutoPrivacyRedactionStyle(style)
                        } label: {
                            Text(style.displayName)
                                .font(.system(size: 10, weight: isSelected ? .bold : .medium))
                                .foregroundStyle(isSelected ? palette.accent : palette.secondaryText)
                                .padding(.horizontal, 7)
                                .frame(height: 24)
                        }
                        .buttonStyle(TactilePillButtonStyle(
                            background: isSelected ? palette.accentSoftFill : .clear,
                            hoverBackground: isSelected ? palette.accentHoverFill : palette.controlHoverFill,
                            borderColor: isSelected ? palette.accentBorder : .clear,
                            cornerRadius: 6
                        ))
                    }
                }
                .padding(3)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(palette.trackFill)
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.controlBorder, lineWidth: 0.7))
                )
            }

            // 5 Toggleable Detection Categories
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 74), spacing: 5)], alignment: .leading, spacing: 5) {
                ForEach(PrivacyCategory.allCases) { cat in
                    let isOn = enabledPrivacyCategories.contains(cat)
                    Button {
                        if isOn {
                            enabledPrivacyCategories.remove(cat)
                        } else {
                            enabledPrivacyCategories.insert(cat)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: cat.systemImage)
                                .font(.system(size: 9, weight: .semibold))
                            Text(cat.displayName)
                                .font(.system(size: 10, weight: isOn ? .semibold : .medium))
                                .lineLimit(1)
                        }
                        .foregroundStyle(isOn ? palette.primaryText : palette.tertiaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 24)
                        .padding(.horizontal, 4)
                    }
                    .buttonStyle(TactilePillButtonStyle(
                        background: isOn ? palette.accentSoftFill : palette.controlFill,
                        hoverBackground: isOn ? palette.accentHoverFill : palette.controlHoverFill,
                        borderColor: isOn ? palette.accentBorder : palette.controlBorder,
                        cornerRadius: 6
                    ))
                }
            }

            // Detected Findings List (1-click toggle to un-redact or re-redact any individual item!)
            if !document.privacyFindings.isEmpty {
                VStack(spacing: 4) {
                    ForEach(document.privacyFindings) { finding in
                        let isMasked = activeAnnIDs.contains(finding.annotationID)
                        HStack(spacing: 6) {
                            Image(systemName: finding.category.systemImage)
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(isMasked ? greenTint : palette.tertiaryText)
                                .frame(width: 14)

                            Text(finding.maskedPreview)
                                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(isMasked ? palette.primaryText : palette.tertiaryText)
                                .strikethrough(!isMasked)
                                .lineLimit(1)

                            Spacer(minLength: 4)

                            Button {
                                togglePrivacyFinding(finding)
                            } label: {
                                Image(systemName: isMasked ? "eye.slash.fill" : "eye")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(isMasked ? greenTint : palette.secondaryText)
                                    .frame(width: 24, height: 22)
                            }
                            .buttonStyle(TactilePillButtonStyle(
                                background: isMasked ? greenTint.opacity(0.16) : palette.controlFill,
                                hoverBackground: isMasked ? greenTint.opacity(0.26) : palette.controlHoverFill,
                                cornerRadius: 6
                            ))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(palette.trackFill)
                        )
                    }
                }
            }

            HStack(spacing: 4) {
                Image(systemName: "checkmark.shield")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(palette.tertiaryText)
                Text(uiStore.t(.privacyOnDeviceNote))
                    .font(.system(size: 9.5))
                    .foregroundStyle(palette.tertiaryText)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(palette.cardBackground)
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(palette.cardBorder, lineWidth: 0.8))
                .shadow(color: .black.opacity(palette.isDark ? 0 : 0.04), radius: 4, y: 1)
        )
    }

    // MARK: - On-Device Vision OCR Text Extraction Card

    private var ocrTextCard: some View {
        let skyTint = Color(red: 0.06, green: 0.65, blue: 0.91)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "text.viewfinder")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(skyTint)
                Text(uiStore.t(.ocrCardTitle))
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(palette.primaryText)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let result = ocrResult, !result.isEmpty {
                    Text(uiStore.format(.ocrStatsFormat, result.lineCount, result.characterCount))
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(skyTint)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(skyTint.opacity(0.16), in: Capsule())
                        .lineLimit(1)
                }
            }

            HStack(spacing: 6) {
                Button {
                    runOCRExtraction()
                } label: {
                    HStack(spacing: 5) {
                        if isExtractingOCR {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.72)
                        } else {
                            Image(systemName: "text.viewfinder")
                                .font(.system(size: 11, weight: .bold))
                        }
                        Text(isExtractingOCR ? uiStore.t(.ocrScanning) : uiStore.t(.ocrExtractBtn))
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(skyTint)
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
                }
                .buttonStyle(TactilePillButtonStyle(
                    background: skyTint.opacity(palette.isDark ? 0.20 : 0.14),
                    hoverBackground: skyTint.opacity(palette.isDark ? 0.30 : 0.22),
                    borderColor: skyTint.opacity(0.55),
                    cornerRadius: 8
                ))
                .disabled(isExtractingOCR)

                if let result = ocrResult, !result.isEmpty {
                    Button {
                        let img = ocrSourceImage ?? document.rawImage
                        appState.presentOCRResultWindow(sourceImage: img, result: result, document: document)
                    } label: {
                        Image(systemName: "arrow.up.forward.square")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(palette.primaryText)
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(TactilePillButtonStyle(
                        background: palette.controlFill,
                        hoverBackground: palette.controlHoverFill,
                        borderColor: palette.controlBorder,
                        hoverBorderColor: skyTint.opacity(0.65),
                        cornerRadius: 8
                    ))
                    .help(uiStore.t(.ocrWindowTitle))
                }
            }

            if let result = ocrResult {
                if result.isEmpty {
                    Text(uiStore.t(.ocrNoTextFound))
                        .font(.system(size: 10.5))
                        .foregroundStyle(palette.tertiaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    // Keep Lines vs Join Paragraphs segmented toggle
                    HStack(spacing: 4) {
                        ocrParagraphModePill(title: uiStore.t(.ocrModeKeepLines), joinParagraphs: false)
                        ocrParagraphModePill(title: uiStore.t(.ocrModeJoinParagraphs), joinParagraphs: true)
                    }
                    .padding(3)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(palette.trackFill)
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.controlBorder, lineWidth: 0.7))
                    )

                    // Toggle Interactive Canvas Click-to-Copy Boxes
                    Toggle(uiStore.t(.ocrCanvasOverlayToggle), isOn: Binding(
                        get: { showOCROverlay },
                        set: { newVal in
                            withAnimation(.easeOut(duration: 0.14)) {
                                showOCROverlay = newVal
                            }
                        }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(palette.secondaryText)

                    // Selectable & Editable Recognized Text Preview
                    TextEditor(text: $ocrEditableText)
                        .font(.system(size: 11.5))
                        .foregroundStyle(palette.primaryText)
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .frame(height: 118)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(palette.trackFill)
                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.controlBorder, lineWidth: 0.7))
                        )

                    // Primary Copy All CTA
                    Button {
                        copyAllOCRText()
                    } label: {
                        Label(uiStore.t(.ocrCopyAllBtn), systemImage: "doc.on.doc.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 30)
                    }
                    .buttonStyle(TactilePrimaryButtonStyle(cornerRadius: 8))
                    .disabled(ocrEditableText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(palette.cardBackground)
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(palette.cardBorder, lineWidth: 0.8))
                .shadow(color: .black.opacity(palette.isDark ? 0 : 0.04), radius: 4, y: 1)
        )
    }

    private func ocrParagraphModePill(title: String, joinParagraphs: Bool) -> some View {
        let isSelected = (ocrJoinParagraphs == joinParagraphs)
        return Button {
            ocrJoinParagraphs = joinParagraphs
            if let res = ocrResult {
                ocrEditableText = joinParagraphs ? res.joinedParagraphText : res.fullText
            }
        } label: {
            Text(title)
                .font(.system(size: 10, weight: isSelected ? .bold : .medium))
                .foregroundStyle(isSelected ? palette.accent : palette.secondaryText)
                .frame(maxWidth: .infinity)
                .frame(height: 23)
        }
        .buttonStyle(TactilePillButtonStyle(
            background: isSelected ? palette.accentSoftFill : .clear,
            hoverBackground: isSelected ? palette.accentHoverFill : palette.controlHoverFill,
            borderColor: isSelected ? palette.accentBorder : .clear,
            cornerRadius: 6
        ))
    }

    private func runOCRExtraction() {
        guard !isExtractingOCR else { return }
        isExtractingOCR = true
        let isMulti = document.isMultiImage
        let images = document.collageImages.map(\.image)
        let layoutMode = document.collageLayout
        let spacing = document.collageSpacing
        let fitMode = document.collageFitMode
        let raw = document.rawImage
        let joinMode = ocrJoinParagraphs

        Task {
            let sourceImage: CGImage = await Task.detached(priority: .userInitiated) {
                if isMulti,
                   let comp = ScreenshotRenderer.renderMultiImageCompositeBase(
                       images: images,
                       layoutMode: layoutMode,
                       spacing: spacing,
                       fitMode: fitMode
                   ) {
                    return comp
                }
                return raw
            }.value

            let result = await TextExtractionEngine.extractText(from: sourceImage)
            await MainActor.run {
                self.isExtractingOCR = false
                self.ocrSourceImage = sourceImage
                self.ocrResult = result
                let text = joinMode ? result.joinedParagraphText : result.fullText
                self.ocrEditableText = text
                withAnimation(.easeOut(duration: 0.16)) {
                    self.showOCROverlay = !result.isEmpty
                }
                if !result.isEmpty {
                    ExportHelpers.copyTextToPasteboard(text)
                    NSSound(named: NSSound.Name("Pop"))?.play()
                    self.flashToast(self.uiStore.format(.ocrAutoCopiedBannerFormat, result.lineCount, result.characterCount))
                } else {
                    NSSound.beep()
                    self.flashToast(self.uiStore.t(.ocrNoTextFound))
                }
            }
        }
    }

    private func copyAllOCRText() {
        let trimmed = ocrEditableText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        ExportHelpers.copyTextToPasteboard(ocrEditableText)
        NSSound(named: NSSound.Name("Pop"))?.play()
        flashToast(uiStore.t(.ocrCopiedToast))
    }

    private func clearOCRState() {
        ocrResult = nil
        ocrSourceImage = nil
        ocrEditableText = ""
        showOCROverlay = false
    }

    // MARK: - Multi-Image Bento & Collage Arrangement Inspector Card

    private var multiImageCard: some View {
        let purpleTint = Color(red: 0.64, green: 0.44, blue: 0.98)
        let canAddMore = document.collageImages.count < 6

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "rectangle.3.group.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(purpleTint)
                Text(uiStore.t(.collageCardTitle))
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(palette.primaryText)
                Spacer()
                if document.isMultiImage {
                    Text(uiStore.format(.collageCountBadgeFormat, document.collageImages.count))
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(purpleTint)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(purpleTint.opacity(0.18), in: Capsule())
                }
            }

            // One-Click Auto-Collect Toggle: subsequent screenshots & copied images automatically append here!
            HStack(spacing: 7) {
                Button {
                    withAnimation(.easeOut(duration: 0.16)) {
                        appState.setMultiImageCollectMode(!isMultiCollectActiveForThisDoc, attaching: document)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isMultiCollectActiveForThisDoc ? "rectangle.stack.fill" : "rectangle.stack.badge.plus")
                            .font(.system(size: 11, weight: .bold))
                        Text(uiStore.t(.multiCollectCardToggle))
                            .font(.system(size: 10.5, weight: .semibold))
                            .lineLimit(1)
                        Spacer(minLength: 2)
                        Circle()
                            .fill(isMultiCollectActiveForThisDoc ? Color.white : palette.tertiaryText.opacity(0.45))
                            .frame(width: 6, height: 6)
                    }
                    .foregroundStyle(isMultiCollectActiveForThisDoc ? .white : purpleTint)
                    .padding(.horizontal, 9)
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
                }
                .buttonStyle(TactilePillButtonStyle(
                    background: isMultiCollectActiveForThisDoc ? purpleTint : purpleTint.opacity(palette.isDark ? 0.18 : 0.11),
                    hoverBackground: isMultiCollectActiveForThisDoc ? purpleTint.opacity(0.86) : purpleTint.opacity(palette.isDark ? 0.28 : 0.19),
                    borderColor: purpleTint.opacity(isMultiCollectActiveForThisDoc ? 0.95 : 0.50),
                    cornerRadius: 8
                ))

                if isMultiCollectActiveForThisDoc && canAddMore {
                    Button {
                        appState.startAreaScreenshot()
                    } label: {
                        Image(systemName: "crop")
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(TactilePillButtonStyle(
                        background: palette.accent,
                        hoverBackground: palette.accent.opacity(0.85),
                        cornerRadius: 8
                    ))
                    .help("\(uiStore.t(.multiCollectCaptureOne)) (\(appState.hotKeyLabel(for: .captureArea)))")
                }
            }

            // Quick Add Images / Append Clipboard Row
            HStack(spacing: 6) {
                Button {
                    appendImagesFromFilePicker()
                } label: {
                    Label(uiStore.t(.collageAddFiles), systemImage: "photo.badge.plus")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(canAddMore ? palette.primaryText : palette.tertiaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 29)
                }
                .buttonStyle(TactilePillButtonStyle(
                    background: palette.controlFill,
                    hoverBackground: canAddMore ? palette.controlHoverFill : palette.controlFill,
                    borderColor: palette.controlBorder,
                    hoverBorderColor: canAddMore ? purpleTint.opacity(0.6) : palette.controlBorder,
                    cornerRadius: 8
                ))
                .disabled(!canAddMore)

                Button {
                    appendImageFromClipboard()
                } label: {
                    Label(uiStore.t(.collageAppendClipboard), systemImage: "doc.on.clipboard")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(canAddMore ? purpleTint : palette.tertiaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 29)
                }
                .buttonStyle(TactilePillButtonStyle(
                    background: purpleTint.opacity(palette.isDark ? 0.18 : 0.12),
                    hoverBackground: canAddMore ? purpleTint.opacity(palette.isDark ? 0.28 : 0.20) : purpleTint.opacity(0.10),
                    borderColor: purpleTint.opacity(0.45),
                    cornerRadius: 8
                ))
                .disabled(!canAddMore)
            }

            if document.isMultiImage {
                // Reorderable Image Strip (Swap Left/Right + Remove)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(Array(document.collageImages.enumerated()), id: \.element.id) { idx, item in
                            VStack(spacing: 4) {
                                ZStack(alignment: .topLeading) {
                                    Image(decorative: item.image, scale: 1.0, orientation: .up)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 58, height: 42)
                                        .clipped()
                                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                                .strokeBorder(idx == 0 ? purpleTint : palette.controlBorder, lineWidth: idx == 0 ? 1.5 : 0.8)
                                        )

                                    Text("\(idx + 1)")
                                        .font(.system(size: 8.5, weight: .heavy, design: .monospaced))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 4.5)
                                        .padding(.vertical, 1)
                                        .background(idx == 0 ? purpleTint : Color.black.opacity(0.72), in: Capsule())
                                        .padding(3)
                                }

                                HStack(spacing: 3) {
                                    Button {
                                        swapCollageImages(idx, idx - 1)
                                    } label: {
                                        Image(systemName: "chevron.left")
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundStyle(idx > 0 ? palette.secondaryText : palette.tertiaryText.opacity(0.35))
                                            .frame(width: 17, height: 16)
                                    }
                                    .buttonStyle(TactilePillButtonStyle(
                                        background: palette.controlFill,
                                        hoverBackground: palette.controlHoverFill,
                                        cornerRadius: 4
                                    ))
                                    .disabled(idx == 0)

                                    Button {
                                        swapCollageImages(idx, idx + 1)
                                    } label: {
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundStyle(idx < document.collageImages.count - 1 ? palette.secondaryText : palette.tertiaryText.opacity(0.35))
                                            .frame(width: 17, height: 16)
                                    }
                                    .buttonStyle(TactilePillButtonStyle(
                                        background: palette.controlFill,
                                        hoverBackground: palette.controlHoverFill,
                                        cornerRadius: 4
                                    ))
                                    .disabled(idx >= document.collageImages.count - 1)

                                    Button {
                                        removeCollageImage(at: idx)
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundStyle(.red)
                                            .frame(width: 17, height: 16)
                                    }
                                    .buttonStyle(TactilePillButtonStyle(
                                        background: .red.opacity(0.14),
                                        hoverBackground: .red.opacity(0.24),
                                        cornerRadius: 4
                                    ))
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }

                // 4 Layout Mode Tiles (Horizontal / Vertical / Bento Grid / Bento Hero)
                HStack(spacing: 5) {
                    ForEach(MultiImageLayoutMode.allCases) { mode in
                        let isSelected = (document.collageLayout == mode)
                        Button {
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
                                document.collageLayout = mode
                            }
                        } label: {
                            VStack(spacing: 4) {
                                collageLayoutGlyph(mode, color: isSelected ? purpleTint : palette.secondaryText)
                                Text(mode.displayName)
                                    .font(.system(size: 10, weight: isSelected ? .bold : .medium))
                                    .foregroundStyle(isSelected ? palette.primaryText : palette.secondaryText)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                        }
                        .buttonStyle(TactilePillButtonStyle(
                            background: isSelected ? purpleTint.opacity(palette.isDark ? 0.24 : 0.14) : palette.controlFill,
                            hoverBackground: isSelected ? purpleTint.opacity(palette.isDark ? 0.34 : 0.22) : palette.controlHoverFill,
                            borderColor: isSelected ? purpleTint.opacity(0.75) : palette.controlBorder,
                            cornerRadius: 8
                        ))
                    }
                }

                // Fit Mode Switch (Contain vs Fill)
                HStack(spacing: 4) {
                    ForEach(MultiImageFitMode.allCases) { fit in
                        let isSelected = (document.collageFitMode == fit)
                        Button {
                            withAnimation(.easeOut(duration: 0.14)) {
                                document.collageFitMode = fit
                            }
                        } label: {
                            Text(fit.displayName)
                                .font(.system(size: 10.5, weight: isSelected ? .bold : .medium))
                                .foregroundStyle(isSelected ? palette.accent : palette.secondaryText)
                                .frame(maxWidth: .infinity)
                                .frame(height: 25)
                        }
                        .buttonStyle(TactilePillButtonStyle(
                            background: isSelected ? palette.accentSoftFill : .clear,
                            hoverBackground: isSelected ? palette.accentHoverFill : palette.controlHoverFill,
                            borderColor: isSelected ? palette.accentBorder : .clear,
                            cornerRadius: 6
                        ))
                    }
                }
                .padding(3)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(palette.trackFill)
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.controlBorder, lineWidth: 0.7))
                )

                // 120Hz Live Gap Spacing Slider
                inspectorSlider(
                    title: uiStore.t(.collageSpacingLabel),
                    value: $document.collageSpacing,
                    defaultValue: 24,
                    range: 0...80,
                    unit: "pt"
                )
            } else {
                Text(uiStore.t(.collageDropHint))
                    .font(.system(size: 9.5))
                    .foregroundStyle(palette.tertiaryText)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(palette.cardBackground)
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(palette.cardBorder, lineWidth: 0.8))
                .shadow(color: .black.opacity(palette.isDark ? 0 : 0.04), radius: 4, y: 1)
        )
    }

    @ViewBuilder
    private func collageLayoutGlyph(_ mode: MultiImageLayoutMode, color: Color) -> some View {
        switch mode {
        case .horizontal:
            HStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 1.5).fill(color).frame(width: 8, height: 11)
                RoundedRectangle(cornerRadius: 1.5).fill(color.opacity(0.65)).frame(width: 8, height: 11)
            }
        case .vertical:
            VStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 1.5).fill(color).frame(width: 15, height: 5)
                RoundedRectangle(cornerRadius: 1.5).fill(color.opacity(0.65)).frame(width: 15, height: 5)
            }
        case .grid2x2:
            VStack(spacing: 2) {
                HStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 1.5).fill(color).frame(width: 7, height: 5)
                    RoundedRectangle(cornerRadius: 1.5).fill(color.opacity(0.75)).frame(width: 7, height: 5)
                }
                HStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 1.5).fill(color.opacity(0.75)).frame(width: 7, height: 5)
                    RoundedRectangle(cornerRadius: 1.5).fill(color.opacity(0.55)).frame(width: 7, height: 5)
                }
            }
        case .bentoHero:
            HStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 1.5).fill(color).frame(width: 9, height: 12)
                VStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 1.5).fill(color.opacity(0.70)).frame(width: 6, height: 5)
                    RoundedRectangle(cornerRadius: 1.5).fill(color.opacity(0.50)).frame(width: 6, height: 5)
                }
            }
        }
    }

    private func appendImages(_ newImages: [CGImage]) {
        guard !newImages.isEmpty else { return }
        var added = 0
        withAnimation(.spring(response: 0.24, dampingFraction: 0.85)) {
            for img in newImages {
                if document.appendCollageImage(img, maxCount: 6) {
                    added += 1
                } else {
                    break
                }
            }
        }
        guard added > 0 else {
            NSSound.beep()
            flashToast(uiStore.t(.multiCollectLimitReached))
            return
        }
        NSSound(named: NSSound.Name("Pop"))?.play()
        flashToast(uiStore.format(.toastAppendedImagesFormat, added, document.collageImages.count))
    }

    private func appendImagesFromFilePicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.image]
        if panel.runModal() == .OK {
            let decoded = panel.urls.compactMap { ExportHelpers.decodeNormalizedCGImage(from: $0) }
            appendImages(decoded)
        }
    }

    private func appendImageFromClipboard() {
        let images = ExportHelpers.readImagesFromPasteboard(limit: 6)
        guard !images.isEmpty else {
            NSSound.beep()
            flashToast(uiStore.t(.clipboardEmptyAlert))
            return
        }
        appendImages(images)
    }

    private func swapCollageImages(_ a: Int, _ b: Int) {
        guard a >= 0, b >= 0, a < document.collageImages.count, b < document.collageImages.count else { return }
        withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
            document.collageImages.swapAt(a, b)
            if let first = document.collageImages.first {
                document.rawImage = first.image
            }
        }
    }

    private func removeCollageImage(at index: Int) {
        guard document.collageImages.count > 1, index >= 0, index < document.collageImages.count else { return }
        withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
            document.collageImages.remove(at: index)
            if let first = document.collageImages.first {
                document.rawImage = first.image
                if !document.isMultiImage {
                    pixelPatchedImage = first.image
                }
            }
        }
    }

    private func handleDroppedImageFiles(_ providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !fileProviders.isEmpty else { return false }

        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []

        for provider in fileProviders {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil), ExportHelpers.isImageFileURL(url) {
                    lock.lock(); urls.append(url); lock.unlock()
                } else if let url = item as? URL, ExportHelpers.isImageFileURL(url) {
                    lock.lock(); urls.append(url); lock.unlock()
                }
            }
        }

        group.notify(queue: .global(qos: .userInitiated)) {
            let decoded = urls.compactMap { ExportHelpers.decodeNormalizedCGImage(from: $0) }
            DispatchQueue.main.async {
                self.appendImages(decoded)
            }
        }
        return true
    }

    // MARK: - Single-Image Slicer Card & Actions

    private var totalSliceCount: Int {
        (sliceRowSplits.count + 1) * (sliceColSplits.count + 1)
    }

    private var imageSlicerCard: some View {
        let amberTint = Color(red: 0.96, green: 0.62, blue: 0.14)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "scissors")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(amberTint)
                Text(uiStore.t(.sliceCardTitle))
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(palette.primaryText)
                if enableSlicer {
                    Text("\(totalSliceCount)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(amberTint)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(amberTint.opacity(0.18), in: Capsule())
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { enableSlicer },
                    set: { newVal in
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
                            enableSlicer = newVal
                        }
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
            }

            if enableSlicer {
                // 5 Quick Presets (1x2, 2x1, 3x1, 2x2, 3x3)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 5), GridItem(.flexible(), spacing: 5), GridItem(.flexible(), spacing: 5)], spacing: 5) {
                    ForEach(ImageSlicePreset.allCases) { preset in
                        let isSelected = (sliceRows == preset.rows && sliceCols == preset.cols)
                        Button {
                            applySliceGrid(rows: preset.rows, cols: preset.cols)
                        } label: {
                            VStack(spacing: 2) {
                                Text(preset.gridTag)
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(isSelected ? amberTint : palette.tertiaryText)
                                Text(preset.displayName)
                                    .font(.system(size: 9.5, weight: isSelected ? .semibold : .medium))
                                    .foregroundStyle(isSelected ? palette.primaryText : palette.secondaryText)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                        }
                        .buttonStyle(TactilePillButtonStyle(
                            background: isSelected ? amberTint.opacity(palette.isDark ? 0.22 : 0.14) : palette.controlFill,
                            hoverBackground: isSelected ? amberTint.opacity(palette.isDark ? 0.32 : 0.22) : palette.controlHoverFill,
                            borderColor: isSelected ? amberTint.opacity(0.72) : palette.controlBorder,
                            cornerRadius: 7
                        ))
                    }
                }

                // Custom Row x Col Steppers + Reset Equal Splits
                HStack(spacing: 6) {
                    sliceStepperControl(label: uiStore.t(.sliceRowsLabel), value: sliceRows) { next in
                        applySliceGrid(rows: next, cols: sliceCols)
                    }
                    sliceStepperControl(label: uiStore.t(.sliceColsLabel), value: sliceCols) { next in
                        applySliceGrid(rows: sliceRows, cols: next)
                    }
                    Button {
                        applySliceGrid(rows: sliceRows, cols: sliceCols)
                    } label: {
                        Text(uiStore.t(.sliceResetEqual))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(palette.secondaryText)
                            .padding(.horizontal, 8)
                            .frame(height: 26)
                    }
                    .buttonStyle(TactilePillButtonStyle(
                        background: palette.controlFill,
                        hoverBackground: palette.controlHoverFill,
                        borderColor: palette.controlBorder,
                        cornerRadius: 7
                    ))
                }

                // Scope Switch: Image Only vs With Beautified Frame
                HStack(spacing: 4) {
                    sliceScopeButton(title: uiStore.t(.sliceScopeRaw), includeBeautify: false)
                    sliceScopeButton(title: uiStore.t(.sliceScopeBeautified), includeBeautify: true)
                }
                .padding(3)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(palette.trackFill)
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.controlBorder, lineWidth: 0.7))
                )

                Text(uiStore.t(.sliceDragLineHint))
                    .font(.system(size: 9.5))
                    .foregroundStyle(palette.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)

                // Primary Export All Slices CTA
                Button {
                    exportSlicedPNGs()
                } label: {
                    Label(uiStore.format(.sliceExportBtnFormat, totalSliceCount), systemImage: "scissors")
                        .font(.system(size: 11.5, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                }
                .buttonStyle(TactilePrimaryButtonStyle(cornerRadius: 8))
                .disabled(totalSliceCount < 2)

                // Convert slices straight into floating Multi-Image Bento cards (when 2...6 tiles)
                if totalSliceCount >= 2 && totalSliceCount <= 6 {
                    Button {
                        convertSlicesToMultiImage()
                    } label: {
                        Label(uiStore.t(.sliceToCollageBtn), systemImage: "rectangle.3.group.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.primaryText)
                            .frame(maxWidth: .infinity)
                            .frame(height: 29)
                    }
                    .buttonStyle(TactilePillButtonStyle(
                        background: palette.controlFill,
                        hoverBackground: palette.controlHoverFill,
                        borderColor: palette.controlBorder,
                        hoverBorderColor: palette.accentBorder,
                        cornerRadius: 8
                    ))
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(palette.cardBackground)
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(palette.cardBorder, lineWidth: 0.8))
                .shadow(color: .black.opacity(palette.isDark ? 0 : 0.04), radius: 4, y: 1)
        )
    }

    private func sliceStepperControl(label: String, value: Int, onChange: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(palette.secondaryText)
            Button {
                onChange(max(1, value - 1))
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(value > 1 ? palette.primaryText : palette.tertiaryText)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(TactilePillButtonStyle(background: palette.controlFill, hoverBackground: palette.controlHoverFill, cornerRadius: 5))
            .disabled(value <= 1)

            Text("\(value)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(palette.primaryText)
                .frame(minWidth: 14)

            Button {
                onChange(min(5, value + 1))
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(value < 5 ? palette.primaryText : palette.tertiaryText)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(TactilePillButtonStyle(background: palette.controlFill, hoverBackground: palette.controlHoverFill, cornerRadius: 5))
            .disabled(value >= 5)
        }
        .padding(.horizontal, 6)
        .frame(height: 26)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(palette.trackFill)
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(palette.controlBorder, lineWidth: 0.7))
        )
    }

    private func sliceScopeButton(title: String, includeBeautify: Bool) -> some View {
        let isSelected = (sliceIncludeBeautify == includeBeautify)
        return Button {
            withAnimation(.easeOut(duration: 0.14)) {
                sliceIncludeBeautify = includeBeautify
            }
        } label: {
            Text(title)
                .font(.system(size: 10.5, weight: isSelected ? .bold : .medium))
                .foregroundStyle(isSelected ? palette.accent : palette.secondaryText)
                .frame(maxWidth: .infinity)
                .frame(height: 24)
        }
        .buttonStyle(TactilePillButtonStyle(
            background: isSelected ? palette.accentSoftFill : .clear,
            hoverBackground: isSelected ? palette.accentHoverFill : palette.controlHoverFill,
            borderColor: isSelected ? palette.accentBorder : .clear,
            cornerRadius: 6
        ))
    }

    private func applySliceGrid(rows: Int, cols: Int) {
        let r = max(1, min(5, rows))
        let c = max(1, min(5, cols))
        withAnimation(.easeOut(duration: 0.16)) {
            sliceRows = r
            sliceCols = c
            sliceRowSplits = ImageSlicerEngine.equalSplits(segments: r)
            sliceColSplits = ImageSlicerEngine.equalSplits(segments: c)
        }
    }

    private func renderSourceForSlicing() -> CGImage? {
        if sliceIncludeBeautify && document.enableBeautify {
            return renderFullResolution()
        }
        if document.isMultiImage {
            return ScreenshotRenderer.renderMultiImageCompositeBase(
                images: document.collageImages.map(\.image),
                layoutMode: document.collageLayout,
                spacing: document.collageSpacing,
                fitMode: document.collageFitMode,
                cornerRadius: 0,
                annotations: document.annotations
            )
        }
        return ScreenshotRenderer.renderAnnotatedRawImage(rawImage: document.rawImage, annotations: document.annotations)
    }

    private func exportSlicedPNGs() {
        guard let source = renderSourceForSlicing() else { return }
        let tiles = ImageSlicerEngine.slice(image: source, rowSplits: sliceRowSplits, colSplits: sliceColSplits)
        let urls = ImageSlicerEngine.exportSlices(tiles)
        guard !urls.isEmpty else { return }

        ExportHelpers.copyFileURLsToPasteboard(urls)
        ExportHelpers.revealFilesInFinder(urls)
        if let firstURL = urls.first, let firstTile = tiles.first {
            onSaved(firstURL, firstTile.image)
        }
        NSSound(named: NSSound.Name("Glass"))?.play()
        flashToast(uiStore.format(.sliceExportToastFormat, urls.count))
    }

    private func convertSlicesToMultiImage() {
        guard let source = renderSourceForSlicing() else { return }
        let tiles = ImageSlicerEngine.slice(image: source, rowSplits: sliceRowSplits, colSplits: sliceColSplits)
        guard tiles.count >= 2 else { return }

        let targetLayout: MultiImageLayoutMode = {
            if sliceRows == 1 { return .horizontal }
            if sliceCols == 1 { return .vertical }
            return .grid2x2
        }()

        withAnimation(.spring(response: 0.24, dampingFraction: 0.85)) {
            document.collageImages = tiles.prefix(6).map { CollageImageItem(image: $0.image) }
            if let first = document.collageImages.first {
                document.rawImage = first.image
            }
            document.annotations.removeAll()
            document.privacyFindings.removeAll()
            redoStack.removeAll()
            document.collageLayout = targetLayout
            document.collageFitMode = .fit
            document.enableBeautify = true
            enableSlicer = false
        }
        NSSound(named: NSSound.Name("Pop"))?.play()
    }

    private func runPrivacyScan() {
        guard !isScanningPrivacy else { return }
        isScanningPrivacy = true
        let isMulti = document.isMultiImage
        let images = document.collageImages.map(\.image)
        let layoutMode = document.collageLayout
        let spacing = document.collageSpacing
        let fitMode = document.collageFitMode
        let singleRaw = document.rawImage
        let categories = enabledPrivacyCategories
        let style = privacyStyle

        Task {
            let scanImage: CGImage
            if isMulti,
               let comp = ScreenshotRenderer.renderMultiImageCompositeBase(
                   images: images,
                   layoutMode: layoutMode,
                   spacing: spacing,
                   fitMode: fitMode
               ) {
                scanImage = comp
            } else {
                scanImage = singleRaw
            }
            let detected = await PrivacyRedactionEngine.detectSensitiveRegions(in: scanImage, enabledCategories: categories)
            await MainActor.run {
                self.isScanningPrivacy = false
                let oldAutoIDs = Set(self.document.privacyFindings.map(\.annotationID))
                self.document.annotations.removeAll { oldAutoIDs.contains($0.id) }
                self.document.privacyFindings = detected

                if detected.isEmpty {
                    self.flashToast(self.uiStore.t(.privacyNoneDetected))
                } else {
                    let newAnns = detected.map { $0.makeAnnotation(style: style) }
                    self.document.annotations.append(contentsOf: newAnns)
                    self.redoStack.removeAll()
                    NSSound(named: NSSound.Name("Pop"))?.play()
                    self.flashToast(self.uiStore.format(.privacyDetectedCountFormat, detected.count))
                }
            }
        }
    }

    private func togglePrivacyFinding(_ finding: PrivacyFinding) {
        if let idx = document.annotations.firstIndex(where: { $0.id == finding.annotationID }) {
            document.annotations.remove(at: idx)
            if selectedAnnotationID == finding.annotationID { selectedAnnotationID = nil }
        } else {
            document.annotations.append(finding.makeAnnotation(style: privacyStyle))
        }
    }

    private func clearAutoPrivacyRedactions() {
        let ids = Set(document.privacyFindings.map(\.annotationID))
        document.annotations.removeAll { ids.contains($0.id) }
        document.privacyFindings.removeAll()
        if let sel = selectedAnnotationID, ids.contains(sel) {
            selectedAnnotationID = nil
        }
    }

    private func updateAutoPrivacyRedactionStyle(_ style: PrivacyRedactionStyle) {
        let ids = Set(document.privacyFindings.map(\.annotationID))
        for idx in document.annotations.indices where ids.contains(document.annotations[idx].id) {
            document.annotations[idx].tool = style.annotationTool.rawValue
        }
    }

    private var textInputSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(uiStore.t(.addTextTitle))
                .font(.headline)
            TextField(uiStore.t(.addTextPlaceholder), text: $pendingTextInput)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)
                .onSubmit { commitTextAnnotation() }
            HStack {
                Spacer()
                Button(uiStore.t(.cancelAction)) { showTextPopover = false }
                Button(uiStore.t(.addAction)) { commitTextAnnotation() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .preferredColorScheme(uiStore.appearanceMode.swiftUIColorScheme)
    }

    private func commitTextAnnotation() {
        showTextPopover = false
        let trimmed = pendingTextInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let pt = pendingTextPoint else { return }
        let scale = max(1.0, document.pixelSize.width / 1200.0)
        let item = AnnotationItem(
            tool: .text,
            start: pt,
            end: pt,
            color: strokeColor,
            lineWidth: strokeWidth,
            text: trimmed,
            fontSize: 32 * scale
        )
        document.annotations.append(item)
        redoStack.removeAll()
    }

    private func applyStrokeColor(_ color: RGBAColor) {
        strokeColor = color
        if let selID = selectedAnnotationID,
           let idx = document.annotations.firstIndex(where: { $0.id == selID }) {
            document.annotations[idx].color = color
        }
    }

    private func applyStrokeWidth(_ width: CGFloat) {
        strokeWidth = width
        if let selID = selectedAnnotationID,
           let idx = document.annotations.firstIndex(where: { $0.id == selID }) {
            document.annotations[idx].lineWidth = width * max(1.0, document.pixelSize.width / 1200.0)
        }
    }

    // MARK: - Background Async Pixel Effect Baking (Mosaic & Blur only)

    private func bakePixelEffectsAsync() {
        let effects = pixelEffectAnnotations
        let isMulti = document.isMultiImage
        let images = document.collageImages.map(\.image)
        let layoutMode = document.collageLayout
        let spacing = document.collageSpacing
        let fitMode = document.collageFitMode
        let raw = document.rawImage

        if effects.isEmpty {
            pixelPatchedImage = raw
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let baked: CGImage
            if isMulti {
                baked = ScreenshotRenderer.renderMultiImageCompositeBase(
                    images: images,
                    layoutMode: layoutMode,
                    spacing: spacing,
                    fitMode: fitMode,
                    cornerRadius: 0,
                    annotations: effects
                ) ?? raw
            } else {
                baked = ScreenshotRenderer.renderAnnotatedRawImage(rawImage: raw, annotations: effects) ?? raw
            }
            DispatchQueue.main.async {
                self.pixelPatchedImage = baked
            }
        }
    }

    // MARK: - Coordinate Mapping & Hit Testing

    private func annotationHitRect(_ item: AnnotationItem) -> CGRect {
        let base = item.normalizedRect
        if item.toolKind == .step {
            let r = max(24, item.lineWidth * 3.6)
            return CGRect(x: item.startX - r, y: item.startY - r, width: r * 2, height: r * 2)
        }
        if item.toolKind == .text {
            let w = max(80, CGFloat(item.text.count) * item.fontSize * 0.65)
            let h = item.fontSize * 1.4
            return CGRect(x: item.startX - 10, y: item.startY - 8, width: w + 20, height: h + 16)
        }
        return base.insetBy(dx: -18, dy: -18)
    }

    private func hitTestAnnotation(at rawPt: CGPoint) -> AnnotationItem? {
        for item in document.annotations.reversed() {
            if annotationHitRect(item).contains(rawPt) {
                return item
            }
        }
        return nil
    }

    private func currentLayout() -> (canvasSize: CGSize, contentRect: CGRect, chromeHeight: CGFloat) {
        if document.enableBeautify {
            var effectiveStyle = document.style
            if document.isMultiImage {
                effectiveStyle.windowChrome = .none
            }
            return CoordinateConverter.computeCanvasLayout(
                sourceSize: document.pixelSize,
                style: effectiveStyle,
                maxLongEdge: nil,
                evenDimensions: false
            )
        } else {
            return (document.pixelSize, CGRect(origin: .zero, size: document.pixelSize), 0)
        }
    }

    private func mapStagePointToRawPixel(_ pt: CGPoint, contentViewRect: CGRect) -> CGPoint {
        let relX = (pt.x - contentViewRect.minX) / max(1, contentViewRect.width)
        let relY = (pt.y - contentViewRect.minY) / max(1, contentViewRect.height)
        return CGPoint(
            x: min(max(relX, 0), 1) * document.pixelSize.width,
            y: min(max(relY, 0), 1) * document.pixelSize.height
        )
    }

    private func renderFullResolution() -> CGImage? {
        if document.isMultiImage {
            return ScreenshotRenderer.renderMultiImageScreenshot(
                images: document.collageImages.map(\.image),
                layoutMode: document.collageLayout,
                spacing: document.collageSpacing,
                fitMode: document.collageFitMode,
                annotations: document.annotations,
                style: document.style,
                enableBeautify: document.enableBeautify,
                maxLongEdge: nil
            )
        }
        return ScreenshotRenderer.renderScreenshot(
            rawImage: document.rawImage,
            annotations: document.annotations,
            style: document.style,
            enableBeautify: document.enableBeautify,
            maxLongEdge: nil
        )
    }

    private func copyPNG() {
        guard let img = renderFullResolution() else { return }
        ExportHelpers.copyImageToPasteboard(img)
        if let url = document.savedURL {
            ExportHelpers.savePNG(img, to: url)
        }
        NSSound(named: NSSound.Name("Pop"))?.play()
        flashToast(uiStore.t(.toastCopiedPNG))
    }

    private func savePNG() {
        guard let img = renderFullResolution() else { return }
        let url = ExportHelpers.screenshotsDirectory
            .appendingPathComponent(ExportHelpers.timestampedFilename(prefix: "XShot-Tweet", ext: "png"))
        if ExportHelpers.savePNG(img, to: url) {
            document.savedURL = url
            onSaved(url, img)
            NSSound(named: NSSound.Name("Glass"))?.play()
            flashToast(uiStore.t(.toastSavedPNG))
        }
    }

    private func pasteFromClipboardInEditor() {
        let images = ExportHelpers.readImagesFromPasteboard(limit: 6)
        guard let cg = images.first else {
            NSSound.beep()
            flashToast(uiStore.t(.clipboardEmptyAlert))
            return
        }
        if isMultiCollectActiveForThisDoc {
            if document.collageImages.count >= 6 {
                NSSound.beep()
                flashToast(uiStore.t(.multiCollectLimitReached))
                return
            }
            appendImages(images)
            return
        }
        document.collageImages = [CollageImageItem(image: cg)]
        document.rawImage = cg
        document.annotations.removeAll()
        document.privacyFindings.removeAll()
        clearOCRState()
        redoStack.removeAll()
        selectedAnnotationID = nil
        stepCounter = 1
        pixelPatchedImage = cg
        document.enableBeautify = true
        viewMode = CanvasViewportCalculator.recommendedInitialMode(for: currentLayout().canvasSize)
        if let rendered = renderFullResolution(),
           let savedURL = ExportHelpers.saveScreenshotQuickly(rendered) {
            document.savedURL = savedURL
            onSaved(savedURL, rendered)
        }
        NSSound(named: NSSound.Name("Pop"))?.play()
        flashToast(uiStore.format(.toastLoadedClipboardFormat, cg.width, cg.height))
        if autoPrivacyOnPaste {
            runPrivacyScan()
        }
    }

    private func flashToast(_ text: String) {
        withAnimation(.spring(response: 0.24, dampingFraction: 0.85)) {
            toastText = text
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            if toastText == text {
                withAnimation(.easeOut(duration: 0.2)) {
                    toastText = nil
                }
            }
        }
    }

    // MARK: - Small UI Helpers

    private func groupedUtilityButton(_ symbol: String, help: String, tint: Color? = nil, disabled: Bool, action: @escaping () -> Void) -> some View {
        let fg = tint ?? palette.primaryText
        return Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(disabled ? palette.tertiaryText : fg)
                .frame(width: 32, height: 36)
        }
        .buttonStyle(TactilePillButtonStyle(
            background: .clear,
            hoverBackground: disabled ? .clear : palette.controlHoverFill,
            borderColor: .clear,
            cornerRadius: 8
        ))
        .disabled(disabled)
        .help(help)
    }

    private func inspectorCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.secondaryText)
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(palette.cardBackground)
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(palette.cardBorder, lineWidth: 0.8))
                .shadow(color: .black.opacity(palette.isDark ? 0 : 0.04), radius: 4, y: 1)
        )
    }

    private func quickPresetButton(_ title: String, dotColors: [Color], isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Circle()
                    .fill(LinearGradient(colors: dotColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 9, height: 9)
                    .overlay(Circle().strokeBorder(palette.controlBorder, lineWidth: 0.6))
                Text(title)
                    .font(.system(size: 11, weight: isActive ? .bold : .semibold))
                    .foregroundStyle(isActive ? palette.accent : palette.primaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 31)
        }
        .buttonStyle(TactilePillButtonStyle(
            background: isActive ? palette.accentSoftFill : palette.controlFill,
            hoverBackground: isActive ? palette.accentHoverFill : palette.controlHoverFill,
            borderColor: isActive ? palette.accentBorder : palette.controlBorder,
            cornerRadius: 8
        ))
    }

    private func aspectRatioTile(_ ratio: AspectRatioPreset, fullWidth: Bool = false) -> some View {
        let isSelected = (document.style.aspectRatio == ratio)
        return Button {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
                document.style.aspectRatio = ratio
            }
        } label: {
            HStack(spacing: 6) {
                AspectRatioMiniIcon(ratio: ratio, color: isSelected ? palette.accent : palette.tertiaryText)
                Text(ratio.rawValue)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(isSelected ? palette.accent : palette.tertiaryText)
                Text(ratioShortLabel(ratio))
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? palette.primaryText : palette.secondaryText)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if fullWidth && isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(palette.accent)
                }
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .frame(height: 32)
        }
        .buttonStyle(TactilePillButtonStyle(
            background: isSelected ? palette.accentSoftFill : palette.controlFill,
            hoverBackground: isSelected ? palette.accentHoverFill : palette.controlHoverFill,
            borderColor: isSelected ? palette.accentBorder : palette.controlBorder,
            cornerRadius: 8
        ))
    }

    @ViewBuilder
    private func windowChromeMiniGlyph(_ style: WindowChromeStyle) -> some View {
        switch style {
        case .none:
            RoundedRectangle(cornerRadius: 2)
                .strokeBorder(palette.tertiaryText, lineWidth: 1.1)
                .frame(width: 11, height: 8)
        case .macOSDark:
            HStack(spacing: 2) {
                Circle().fill(Color(red: 1.0, green: 0.37, blue: 0.34)).frame(width: 4, height: 4)
                Circle().fill(Color(red: 1.0, green: 0.74, blue: 0.18)).frame(width: 4, height: 4)
            }
            .padding(.horizontal, 3)
            .padding(.vertical, 2.5)
            .background(Color(red: 0.14, green: 0.14, blue: 0.17), in: RoundedRectangle(cornerRadius: 3))
        case .macOSLight:
            HStack(spacing: 2) {
                Circle().fill(Color(red: 1.0, green: 0.37, blue: 0.34)).frame(width: 4, height: 4)
                Circle().fill(Color(red: 1.0, green: 0.74, blue: 0.18)).frame(width: 4, height: 4)
            }
            .padding(.horizontal, 3)
            .padding(.vertical, 2.5)
            .background(Color(red: 0.90, green: 0.91, blue: 0.94), in: RoundedRectangle(cornerRadius: 3))
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.black.opacity(0.14), lineWidth: 0.5))
        }
    }

    private func ratioShortLabel(_ ratio: AspectRatioPreset) -> String {
        switch ratio {
        case .auto: return uiStore.t(.ratioShortAuto)
        case .wide16x9: return uiStore.t(.ratioShort16x9)
        case .card4x3: return uiStore.t(.ratioShort4x3)
        case .square1x1: return uiStore.t(.ratioShort1x1)
        case .vertical9x16: return uiStore.t(.ratioShort9x16)
        }
    }

    private func inspectorSlider(title: String, value: Binding<CGFloat>, defaultValue: CGFloat, range: ClosedRange<CGFloat>, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.secondaryText)
                Spacer()
                Text("\(Int(value.wrappedValue)) \(unit)")
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(palette.accent)
                    .frame(minWidth: 46)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(palette.controlFill, in: RoundedRectangle(cornerRadius: 5))
                    .contentShape(RoundedRectangle(cornerRadius: 5))
                    .onTapGesture(count: 2) {
                        withAnimation(.easeOut(duration: 0.14)) {
                            value.wrappedValue = defaultValue
                        }
                    }
            }
            Slider(value: value, in: range)
                .tint(palette.accent)
        }
    }
}

// MARK: - Tactile Color Swatch Dot

private struct ColorSwatchDotButton: View {
    let color: Color
    let isSelected: Bool
    let palette: StudioPalette
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            ZStack {
                if isSelected {
                    Circle()
                        .strokeBorder(palette.accent, lineWidth: 2.0)
                        .frame(width: 24, height: 24)
                }
                Circle()
                    .fill(color)
                    .frame(width: 18, height: 18)
                    .overlay(
                        Circle()
                            .strokeBorder(palette.isDark ? Color.white.opacity(0.28) : Color.black.opacity(0.20), lineWidth: 0.8)
                    )
                    .scaleEffect(isHovered ? 1.14 : 1.0)
            }
            .frame(width: 26, height: 26)
            .contentShape(Circle())
            .animation(.easeOut(duration: 0.11), value: isHovered)
            .animation(.easeOut(duration: 0.12), value: isSelected)
        }
        .buttonStyle(TactileScaleButtonStyle(pressedScale: 0.88))
        .onHover { isHovered = $0 }
    }
}

// MARK: - 120Hz GPU Live Vector Annotation Canvas

private struct LiveAnnotationsCanvas: View {
    let annotations: [AnnotationItem]
    let activeDraft: AnnotationItem?
    let draggingPixelEffectID: UUID?
    let selectedID: UUID?
    let rawImageSize: CGSize

    var body: some View {
        Canvas { ctx, size in
            let sx = size.width / max(1, rawImageSize.width)
            let sy = size.height / max(1, rawImageSize.height)
            let sAvg = (sx + sy) / 2.0

            func mapPt(_ p: CGPoint) -> CGPoint {
                CGPoint(x: p.x * sx, y: p.y * sy)
            }

            func mapRect(_ r: CGRect) -> CGRect {
                CGRect(x: r.minX * sx, y: r.minY * sy, width: r.width * sx, height: r.height * sy)
            }

            var items = annotations
            if let draft = activeDraft { items.append(draft) }

            for item in items {
                let lw = max(1.5, item.lineWidth * sAvg)
                let color = item.color.swiftUIColor

                switch item.toolKind {
                case .select:
                    continue

                case .mosaic, .blur:
                    // Committed mosaic/blur are baked in pixelPatchedImage; show live frosted preview while drawing OR moving!
                    if item.id == activeDraft?.id || item.id == draggingPixelEffectID {
                        let r = mapRect(item.normalizedRect)
                        let path = Path(roundedRect: r, cornerRadius: 5)
                        ctx.fill(path, with: .color(Color.white.opacity(0.28)))
                        ctx.stroke(path, with: .color(Color.cyan), style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                    }

                case .highlighter:
                    let r = mapRect(item.normalizedRect)
                    ctx.fill(Path(roundedRect: r, cornerRadius: 4), with: .color(color.opacity(0.36)))

                case .rectangle:
                    let r = mapRect(item.normalizedRect)
                    let radius = min(8, min(r.width, r.height) * 0.2)
                    ctx.stroke(Path(roundedRect: r, cornerRadius: radius), with: .color(color), lineWidth: lw)

                case .ellipse:
                    let r = mapRect(item.normalizedRect)
                    ctx.stroke(Path(ellipseIn: r), with: .color(color), lineWidth: lw)

                case .arrow:
                    let p1 = mapPt(item.startPoint)
                    let p2 = mapPt(item.endPoint)
                    drawModernArrow(in: &ctx, from: p1, to: p2, color: color, lineWidth: lw)

                case .step:
                    let c = mapPt(item.startPoint)
                    let r = max(12, item.lineWidth * 3.2 * sAvg)
                    let circle = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
                    ctx.fill(circle, with: .color(color))
                    ctx.stroke(circle, with: .color(.white.opacity(0.95)), lineWidth: max(1.5, r * 0.12))
                    let text = ctx.resolve(Text("\(item.stepNumber)").font(.system(size: r * 1.15, weight: .bold)).foregroundColor(.white))
                    ctx.draw(text, at: c, anchor: .center)

                case .text:
                    let trimmed = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { continue }
                    let origin = mapPt(item.startPoint)
                    let fontSize = max(11, item.fontSize * sAvg)
                    let resolved = ctx.resolve(Text(trimmed).font(.system(size: fontSize, weight: .bold)).foregroundColor(color))
                    let measured = resolved.measure(in: size)
                    let padX = fontSize * 0.35
                    let padY = fontSize * 0.18
                    let pillRect = CGRect(
                        x: origin.x - padX,
                        y: origin.y - padY,
                        width: measured.width + padX * 2,
                        height: measured.height + padY * 2
                    )
                    ctx.fill(Path(roundedRect: pillRect, cornerRadius: 7), with: .color(Color(red: 0.08, green: 0.09, blue: 0.12).opacity(0.84)))
                    ctx.draw(resolved, at: origin, anchor: .topLeading)
                }

                // Crisp selection bounding box in Select mode
                if item.id == selectedID {
                    let selRect: CGRect
                    if item.toolKind == .step {
                        let c = mapPt(item.startPoint)
                        let r = max(16, item.lineWidth * 3.8 * sAvg)
                        selRect = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
                    } else if item.toolKind == .text {
                        let origin = mapPt(item.startPoint)
                        let fontSize = max(11, item.fontSize * sAvg)
                        let resolved = ctx.resolve(Text(item.text).font(.system(size: fontSize, weight: .bold)))
                        let measured = resolved.measure(in: size)
                        selRect = CGRect(x: origin.x - 10, y: origin.y - 8, width: measured.width + 20, height: measured.height + 16)
                    } else {
                        selRect = mapRect(item.normalizedRect).insetBy(dx: -8, dy: -8)
                    }
                    ctx.stroke(
                        Path(roundedRect: selRect, cornerRadius: 5),
                        with: .color(.cyan),
                        style: StrokeStyle(lineWidth: 1.5, dash: [5, 3])
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func drawModernArrow(in ctx: inout GraphicsContext, from start: CGPoint, to end: CGPoint, color: Color, lineWidth: CGFloat) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length > 4 else { return }

        let angle = atan2(dy, dx)
        let headLength = min(length * 0.45, max(14, lineWidth * 4.2))
        let headHalfWidth = headLength * 0.46
        let tailHalfWidth = max(1.2, lineWidth * 0.28)
        let neckHalfWidth = max(2.2, lineWidth * 0.65)
        let neckLength = max(0, length - headLength * 0.78)

        var path = Path()
        path.move(to: CGPoint(x: 0, y: -tailHalfWidth))
        path.addLine(to: CGPoint(x: neckLength, y: -neckHalfWidth))
        path.addLine(to: CGPoint(x: length - headLength, y: -headHalfWidth))
        path.addLine(to: CGPoint(x: length, y: 0))
        path.addLine(to: CGPoint(x: length - headLength, y: headHalfWidth))
        path.addLine(to: CGPoint(x: neckLength, y: neckHalfWidth))
        path.addLine(to: CGPoint(x: 0, y: tailHalfWidth))
        path.closeSubpath()

        var transform = CGAffineTransform(translationX: start.x, y: start.y)
        transform = transform.rotated(by: angle)
        ctx.fill(path.applying(transform), with: .color(color))
    }
}

// MARK: - 120Hz Interactive Draggable Cut-Line Overlay for Single-Image Slicer

private struct LiveSliceGridOverlay: View {
    let targetRect: CGRect
    let pixelSize: CGSize
    @Binding var rowSplits: [CGFloat]
    @Binding var colSplits: [CGFloat]

    var body: some View {
        let xFracs: [CGFloat] = [0] + colSplits + [1]
        let yFracs: [CGFloat] = [0] + rowSplits + [1]
        let xPx = ImageSlicerEngine.pixelBoundaries(totalPixels: max(2, Int(pixelSize.width.rounded())), splits: colSplits)
        let yPx = ImageSlicerEngine.pixelBoundaries(totalPixels: max(2, Int(pixelSize.height.rounded())), splits: rowSplits)
        let amber = Color(red: 1.0, green: 0.68, blue: 0.16)

        ZStack {
            // Non-interactive outer frame & numbered tile badges
            Canvas { ctx, _ in
                // Crisp outer boundary around slice region
                ctx.stroke(
                    Path(targetRect),
                    with: .color(amber.opacity(0.75)),
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                )

                // Horizontal cut lines (dual stroke: dark halo + glowing amber dash)
                for frac in rowSplits {
                    let y = targetRect.minY + frac * targetRect.height
                    var p = Path()
                    p.move(to: CGPoint(x: targetRect.minX, y: y))
                    p.addLine(to: CGPoint(x: targetRect.maxX, y: y))
                    ctx.stroke(p, with: .color(.black.opacity(0.55)), lineWidth: 3.2)
                    ctx.stroke(p, with: .color(amber), style: StrokeStyle(lineWidth: 1.8, dash: [7, 4]))
                }

                // Vertical cut lines
                for frac in colSplits {
                    let x = targetRect.minX + frac * targetRect.width
                    var p = Path()
                    p.move(to: CGPoint(x: x, y: targetRect.minY))
                    p.addLine(to: CGPoint(x: x, y: targetRect.maxY))
                    ctx.stroke(p, with: .color(.black.opacity(0.55)), lineWidth: 3.2)
                    ctx.stroke(p, with: .color(amber), style: StrokeStyle(lineWidth: 1.8, dash: [7, 4]))
                }

                // Numbered tile index + pixel size pills
                var idx = 1
                for r in 0..<(yFracs.count - 1) {
                    for c in 0..<(xFracs.count - 1) {
                        let cellX = targetRect.minX + xFracs[c] * targetRect.width
                        let cellY = targetRect.minY + yFracs[r] * targetRect.height
                        let cellW = (xFracs[c + 1] - xFracs[c]) * targetRect.width
                        let cellH = (yFracs[r + 1] - yFracs[r]) * targetRect.height
                        let pw = (c + 1 < xPx.count) ? (xPx[c + 1] - xPx[c]) : 0
                        let ph = (r + 1 < yPx.count) ? (yPx[r + 1] - yPx[r]) : 0

                        let label = (cellW >= 96 && cellH >= 42) ? "#\(idx) · \(pw)×\(ph)" : "#\(idx)"
                        let resolved = ctx.resolve(
                            Text(label)
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                        )
                        let measured = resolved.measure(in: CGSize(width: 200, height: 30))
                        let pillRect = CGRect(
                            x: cellX + 8,
                            y: cellY + 8,
                            width: measured.width + 12,
                            height: measured.height + 6
                        )
                        ctx.fill(Path(roundedRect: pillRect, cornerRadius: 6), with: .color(Color.black.opacity(0.76)))
                        ctx.stroke(Path(roundedRect: pillRect, cornerRadius: 6), with: .color(amber.opacity(0.85)), lineWidth: 0.9)
                        ctx.draw(resolved, at: CGPoint(x: pillRect.midX, y: pillRect.midY), anchor: .center)
                        idx += 1
                    }
                }
            }
            .allowsHitTesting(false)

            // Interactive 120Hz Horizontal Cut-Line Drag Handles
            ForEach(0..<rowSplits.count, id: \.self) { idx in
                let y = targetRect.minY + rowSplits[idx] * targetRect.height
                ZStack {
                    Color.clear
                    Capsule()
                        .fill(Color.black.opacity(0.80))
                        .overlay(Capsule().strokeBorder(amber, lineWidth: 1.2))
                        .overlay(
                            Image(systemName: "arrow.up.and.down")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(amber)
                        )
                        .frame(width: 28, height: 15)
                }
                .frame(width: max(40, targetRect.width), height: 18)
                .contentShape(Rectangle())
                .position(x: targetRect.midX, y: y)
                .onHover { hovering in
                    if hovering { NSCursor.resizeUpDown.set() } else { NSCursor.arrow.set() }
                }
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .named("editorStage"))
                        .onChanged { val in
                            guard idx < rowSplits.count else { return }
                            let rawFrac = (val.location.y - targetRect.minY) / max(1, targetRect.height)
                            let minBound: CGFloat = (idx > 0 ? rowSplits[idx - 1] : 0) + 0.06
                            let maxBound: CGFloat = (idx + 1 < rowSplits.count ? rowSplits[idx + 1] : 1) - 0.06
                            if minBound < maxBound {
                                rowSplits[idx] = min(max(rawFrac, minBound), maxBound)
                            }
                        }
                )
            }

            // Interactive 120Hz Vertical Cut-Line Drag Handles
            ForEach(0..<colSplits.count, id: \.self) { idx in
                let x = targetRect.minX + colSplits[idx] * targetRect.width
                ZStack {
                    Color.clear
                    Capsule()
                        .fill(Color.black.opacity(0.80))
                        .overlay(Capsule().strokeBorder(amber, lineWidth: 1.2))
                        .overlay(
                            Image(systemName: "arrow.left.and.right")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(amber)
                        )
                        .frame(width: 15, height: 28)
                }
                .frame(width: 18, height: max(40, targetRect.height))
                .contentShape(Rectangle())
                .position(x: x, y: targetRect.midY)
                .onHover { hovering in
                    if hovering { NSCursor.resizeLeftRight.set() } else { NSCursor.arrow.set() }
                }
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .named("editorStage"))
                        .onChanged { val in
                            guard idx < colSplits.count else { return }
                            let rawFrac = (val.location.x - targetRect.minX) / max(1, targetRect.width)
                            let minBound: CGFloat = (idx > 0 ? colSplits[idx - 1] : 0) + 0.06
                            let maxBound: CGFloat = (idx + 1 < colSplits.count ? colSplits[idx + 1] : 1) - 0.06
                            if minBound < maxBound {
                                colSplits[idx] = min(max(rawFrac, minBound), maxBound)
                            }
                        }
                )
            }
        }
    }
}

// MARK: - 120Hz Interactive Canvas OCR Click-to-Copy Text Overlay

private struct LiveOCRTextOverlay: View {
    let lines: [RecognizedTextLine]
    let targetRect: CGRect
    let pixelSize: CGSize
    let onCopyLine: (RecognizedTextLine) -> Void

    var body: some View {
        let sx = targetRect.width / max(1, pixelSize.width)
        let sy = targetRect.height / max(1, pixelSize.height)

        ZStack(alignment: .topLeading) {
            ForEach(lines) { line in
                let box = CGRect(
                    x: targetRect.minX + line.pixelRect.minX * sx,
                    y: targetRect.minY + line.pixelRect.minY * sy,
                    width: max(14, line.pixelRect.width * sx),
                    height: max(12, line.pixelRect.height * sy)
                )
                LiveOCRLineBox(line: line, box: box, onCopy: { onCopyLine(line) })
            }
        }
    }
}

private struct LiveOCRLineBox: View {
    let line: RecognizedTextLine
    let box: CGRect
    let onCopy: () -> Void

    @State private var isHovered = false

    var body: some View {
        let sky = Color(red: 0.06, green: 0.65, blue: 0.91)
        Button(action: onCopy) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .fill(sky.opacity(isHovered ? 0.28 : 0.11))
                    .overlay(
                        RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                            .strokeBorder(sky.opacity(isHovered ? 0.95 : 0.50), lineWidth: isHovered ? 1.4 : 0.85)
                    )

                if isHovered && box.width >= 26 && box.height >= 14 {
                    Image(systemName: "doc.on.doc.fill")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(3)
                        .background(sky, in: RoundedRectangle(cornerRadius: 3.5, style: .continuous))
                        .offset(x: 4, y: -4)
                }
            }
            .frame(width: box.width, height: box.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .position(x: box.midX, y: box.midY)
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }
        }
        .help(line.text)
    }
}
