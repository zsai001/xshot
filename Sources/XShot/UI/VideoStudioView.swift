import AppKit
@preconcurrency import AVFoundation
import CoreGraphics
import SwiftUI
import UniformTypeIdentifiers

public struct VideoStudioView: View {
    @ObservedObject var session: RecordingSession
    @ObservedObject private var uiStore = ThemeLocaleStore.shared
    @Environment(\.colorScheme) private var colorScheme
    let onExportCompleted: (URL, CGImage?) -> Void
    let onKeystrokeStyleChanged: ((KeystrokeStyleConfig) -> Void)?
    let onSaveDefaultWatermark: ((WatermarkConfig) -> Void)?
    let onFrameCaptured: ((URL, CGImage) -> Void)?

    private let exporter = VideoCompositorExporter()

    /// Output-timeline playhead time (`0 ... session.outputDuration`).
    @State private var currentTime: Double = 0
    @State private var isPlaying: Bool = false
    @State private var playbackTimer: Timer?
    @State private var audioPlayer: AVPlayer?
    @State private var playbackStartWallTime: CFTimeInterval = 0
    @State private var playbackStartOutputTime: Double = 0

    @State private var previewFrame: CGImage?
    @State private var filmstripFrames: [(sourceTime: Double, image: CGImage)] = []
    @State private var waveformPeaks: [Float] = []
    @State private var timelineZoom: Double = 1.0
    @State private var enableMagneticSnap: Bool = true
    @State private var selectedSegmentID: UUID?
    @State private var selectedClipID: UUID?
    @State private var undoStack: [VideoTimelineSnapshot] = []
    @State private var redoStack: [VideoTimelineSnapshot] = []

    @State private var inspectorTab: Int = 0
    @State private var showSampleKeystrokeInPreview: Bool = false
    @State private var isDraggingKeystroke: Bool = false
    @State private var isHoveringKeystroke: Bool = false
    @State private var keystrokeGrabOffset: CGSize = .zero
    @State private var keystrokePreviewImage: CGImage?
    @State private var keystrokePreviewNormRect: CGRect = .zero
    @State private var snappedCenterX: Bool = false
    @State private var snappedCenterY: Bool = false
    @State private var stageToast: String?

    @State private var smoothedCursorPath: [CursorSample] = []
    @State private var imageGenerator: AVAssetImageGenerator?
    @State private var webcamImageGenerator: AVAssetImageGenerator?
    @State private var cachedRawFrameTime: Double = -999
    @State private var cachedRawFrameCG: CGImage?
    @State private var cachedWebcamFrameTime: Double = -999
    @State private var cachedWebcamFrameCG: CGImage?
    @State private var isRenderingPreview = false
    @State private var pendingPreviewRender = false

    @State private var exportTask: Task<Void, Never>?
    @State private var isExporting: Bool = false
    @State private var exportProgress: Double = 0
    @State private var exportFPS: Double = 0
    @State private var exportETA: Double = 0
    @State private var exportError: String?
    @State private var exportedURL: URL?
    @State private var exportedFileSizeText: String = ""
    @State private var copiedFileToast: Bool = false

    public init(
        session: RecordingSession,
        onExportCompleted: @escaping (URL, CGImage?) -> Void,
        onKeystrokeStyleChanged: ((KeystrokeStyleConfig) -> Void)? = nil,
        onSaveDefaultWatermark: ((WatermarkConfig) -> Void)? = nil,
        onFrameCaptured: ((URL, CGImage) -> Void)? = nil
    ) {
        self.session = session
        self.onExportCompleted = onExportCompleted
        self.onKeystrokeStyleChanged = onKeystrokeStyleChanged
        self.onSaveDefaultWatermark = onSaveDefaultWatermark
        self.onFrameCaptured = onFrameCaptured
    }

    private var resolvedScheme: ColorScheme {
        uiStore.appearanceMode.resolvedColorScheme(environment: colorScheme)
    }

    private var palette: StudioPalette {
        StudioPalette.resolved(mode: uiStore.appearanceMode, environment: colorScheme)
    }

    private var computedOutputSize: CGSize {
        CoordinateConverter.computeCanvasLayout(
            sourceSize: session.videoSize,
            style: session.style,
            maxLongEdge: session.exportPreset.maxLongEdge,
            evenDimensions: true
        ).canvasSize
    }

    private var currentSourceMapping: OutputTimeMapping {
        VideoTimelineMapper.mapOutputTimeToSource(currentTime, clips: session.clipSegments)
            ?? OutputTimeMapping(sourceTime: 0, clipIndex: 0, clipID: session.clipSegments.first?.id ?? UUID(), speed: 1.0)
    }

    private var currentSourceTime: Double {
        currentSourceMapping.sourceTime
    }

    private var currentCameraState: CameraState {
        AutoZoomEngine.evaluateCamera(
            at: currentSourceTime,
            segments: session.zoomSegments,
            smoothedCursorPath: smoothedCursorPath,
            typingFocusEvents: session.telemetry.typingFocusEvents,
            enabled: session.enableAutoZoom
        )
    }

    public var body: some View {
        VStack(spacing: 0) {
            studioHeader
            Divider().overlay(palette.divider)
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    previewStage
                    Divider().overlay(palette.divider)
                    timelineDeck
                }
                Divider().overlay(palette.divider)
                rightInspector
            }
        }
        .background(palette.windowBackground)
        .environment(\.colorScheme, resolvedScheme)
        .preferredColorScheme(uiStore.appearanceMode.swiftUIColorScheme)
        .onAppear { setupPreviewPipeline() }
        .onDisappear {
            stopPlayback()
            exportTask?.cancel()
        }
        .onChange(of: session.style) { _, _ in
            requestPreviewRender()
            refreshKeystrokeOverlayPreview()
        }
        .onChange(of: session.webcamPiP) { _, _ in requestPreviewRender() }
        .onChange(of: session.zoomSegments) { _, _ in requestPreviewRender() }
        .onChange(of: session.clipSegments) { _, _ in
            let maxOut = session.outputDuration
            if currentTime > maxOut { currentTime = max(0, maxOut) }
            if isPlaying { stopPlayback() }
            requestPreviewRender()
        }
        .onChange(of: session.fadeConfig) { _, _ in
            if isPlaying { stopPlayback() }
            requestPreviewRender()
        }
        .onChange(of: session.audioVolume) { _, newVol in
            if let player = audioPlayer, isPlaying {
                player.volume = Float(min(max(newVol, 0), 1.0))
            }
        }
        .onChange(of: session.includeAudio) { _, _ in
            if isPlaying { stopPlayback() }
        }
        .onChange(of: session.enableAutoZoom) { _, _ in requestPreviewRender() }
        .onChange(of: session.enableSmoothCursor) { _, _ in requestPreviewRender() }
        .onChange(of: session.enableClickRipples) { _, _ in requestPreviewRender() }
        .onChange(of: session.enableKeystrokes) { _, _ in
            refreshKeystrokeOverlayPreview()
            requestPreviewRender()
        }
        .onChange(of: session.keystrokeStyle) { _, newStyle in
            onKeystrokeStyleChanged?(newStyle)
            if session.enableKeystrokes && !isPlaying {
                showSampleKeystrokeInPreview = true
            }
            if !isDraggingKeystroke {
                refreshKeystrokeOverlayPreview()
            }
        }
        .onChange(of: showSampleKeystrokeInPreview) { _, _ in
            refreshKeystrokeOverlayPreview()
        }
        .onChange(of: inspectorTab) { _, tab in
            if tab == 1 && session.enableKeystrokes && !isPlaying {
                showSampleKeystrokeInPreview = true
            } else if tab == 0 {
                showSampleKeystrokeInPreview = false
            }
            refreshKeystrokeOverlayPreview()
        }
        .onChange(of: session.cursorScale) { _, _ in requestPreviewRender() }
    }

    // MARK: - Unified macOS Titlebar Header

    private var studioHeader: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles.tv.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(colors: [palette.accent, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                Text("XShot Studio")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.primaryText)
            }

            HStack(spacing: 6) {
                Circle()
                    .fill(palette.accent)
                    .frame(width: 6, height: 6)
                Text("\(Int(computedOutputSize.width))×\(Int(computedOutputSize.height))")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(palette.primaryText)
                Text("·")
                    .foregroundStyle(palette.tertiaryText)
                Text("\(session.exportPreset.isGIF ? 18 : session.exportPreset.fps)fps")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(palette.accent)
                Text("·")
                    .foregroundStyle(palette.tertiaryText)
                Text(String(format: "%.1fs", session.outputDuration))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(session.hasTimelineEdits ? Color.orange : palette.secondaryText)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(palette.controlFill)
                    .overlay(Capsule().strokeBorder(palette.controlBorder, lineWidth: 0.7))
            )

            Spacer()

            if isExporting {
                HStack(spacing: 10) {
                    ProgressView(value: exportProgress)
                        .tint(palette.accent)
                        .frame(width: 110)

                    HStack(spacing: 5) {
                        Text("\(Int(exportProgress * 100))%")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(palette.accent)
                        if exportFPS > 1 {
                            Text("· \(Int(exportFPS)) fps")
                                .font(.system(size: 10, design: .monospaced))
                                .monospacedDigit()
                                .foregroundStyle(palette.secondaryText)
                        }
                        if exportETA >= 0.3 {
                            Text("· \(String(format: "%.1fs", exportETA))")
                                .font(.system(size: 10, design: .monospaced))
                                .monospacedDigit()
                                .foregroundStyle(palette.tertiaryText)
                        }
                    }

                    Button {
                        exportTask?.cancel()
                    } label: {
                        Text(uiStore.t(.cancelAction))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.primaryText)
                            .padding(.horizontal, 10)
                            .frame(height: 24)
                    }
                    .buttonStyle(TactilePillButtonStyle(
                        background: palette.controlFill,
                        hoverBackground: palette.controlHoverFill,
                        borderColor: palette.controlBorder,
                        cornerRadius: 12
                    ))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(palette.controlFill, in: Capsule())
            } else {
                Button {
                    captureCurrentBeautifiedFrame()
                } label: {
                    Label(uiStore.t(.captureFrameBtn), systemImage: "camera.viewfinder")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(palette.primaryText)
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                }
                .buttonStyle(TactilePillButtonStyle(
                    background: palette.controlFill,
                    hoverBackground: palette.controlHoverFill,
                    borderColor: palette.controlBorder,
                    hoverBorderColor: palette.accentBorder,
                    cornerRadius: 8
                ))
                .help(uiStore.t(.captureFrameTooltip))

                Picker("", selection: $session.exportPreset) {
                    ForEach(VideoExportPreset.allCases) { preset in
                        Text(preset.shortTitle).tag(preset)
                    }
                }
                .frame(width: 174)
                .labelsHidden()

                Button {
                    startExport()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: session.exportPreset.isGIF ? "sparkles" : "arrow.up.circle.fill")
                            .font(.system(size: 12, weight: .bold))
                        Text(session.exportPreset.isGIF ? uiStore.t(.exportGIF) : uiStore.t(.exportMP4))
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 30)
                }
                .buttonStyle(TactilePrimaryButtonStyle(cornerRadius: 8))
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
        .frame(height: 46)
        .background(palette.toolbarBackground)
    }

    // MARK: - Live Metal Preview Stage

    private var previewStage: some View {
        GeometryReader { geo in
            let pad: CGFloat = 24
            let avail = CGRect(x: pad, y: pad, width: max(1, geo.size.width - pad * 2), height: max(1, geo.size.height - pad * 2))
            let previewSize = previewFrame.map { CGSize(width: $0.width, height: $0.height) } ?? computedOutputSize
            let fitted = aspectFitRect(content: previewSize, inside: avail)
            let srcSize = cachedRawFrameCG.map { CGSize(width: $0.width, height: $0.height) } ?? session.videoSize
            let previewLayout = CoordinateConverter.computeCanvasLayout(
                sourceSize: srcSize,
                style: session.style,
                maxLongEdge: 1120,
                evenDimensions: true
            )
            let contentViewRect = CGRect(
                x: fitted.minX + (previewLayout.contentRect.minX / max(1, previewLayout.canvasSize.width)) * fitted.width,
                y: fitted.minY + (previewLayout.contentRect.minY / max(1, previewLayout.canvasSize.height)) * fitted.height,
                width: (previewLayout.contentRect.width / max(1, previewLayout.canvasSize.width)) * fitted.width,
                height: (previewLayout.contentRect.height / max(1, previewLayout.canvasSize.height)) * fitted.height
            )
            let activeCamera = currentCameraState
            let cropTopLeft = activeCamera.sourceCropRect(for: srcSize)

            ZStack {
                RadialGradient(
                    colors: [palette.stageInner, palette.stageOuter],
                    center: .center,
                    startRadius: 20,
                    endRadius: max(geo.size.width, geo.size.height) * 0.7
                )

                if let cg = previewFrame {
                    Image(nsImage: NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)))
                        .resizable()
                        .interpolation(.high)
                        .frame(width: fitted.width, height: fitted.height)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .shadow(color: .black.opacity(palette.shadowOpacity), radius: 24, y: 10)
                        .position(x: fitted.midX, y: fitted.midY)
                        .onTapGesture(coordinateSpace: .named("previewStage")) { stagePt in
                            if let selID = selectedSegmentID,
                               let idx = session.zoomSegments.firstIndex(where: { $0.id == selID }) {
                                let mapped = mapStagePointToSourceNormalized(
                                    stagePt,
                                    contentViewRect: contentViewRect,
                                    cropTopLeft: cropTopLeft,
                                    sourceSize: srcSize
                                )
                                pushUndoSnapshot()
                                session.zoomSegments[idx].focusX = mapped.x
                                session.zoomSegments[idx].focusY = mapped.y
                                session.zoomSegments[idx].followCursor = false
                                requestPreviewRender()
                            } else {
                                togglePlayback()
                            }
                        }

                    // Visual Draggable Focus Target Reticle when a Zoom Segment is selected!
                    if !isPlaying,
                       let selID = selectedSegmentID,
                       let idx = session.zoomSegments.firstIndex(where: { $0.id == selID }) {
                        let seg = session.zoomSegments[idx]
                        let relX = (seg.focusX * srcSize.width - cropTopLeft.origin.x) / max(1, cropTopLeft.width)
                        let relY = (seg.focusY * srcSize.height - cropTopLeft.origin.y) / max(1, cropTopLeft.height)
                        let reticlePt = CGPoint(
                            x: contentViewRect.minX + CGFloat(min(max(relX, 0.02), 0.98)) * contentViewRect.width,
                            y: contentViewRect.minY + CGFloat(min(max(relY, 0.02), 0.98)) * contentViewRect.height
                        )

                        ZStack {
                            Circle()
                                .strokeBorder(Color.white.opacity(0.90), lineWidth: 2.2)
                                .frame(width: 28, height: 28)
                                .shadow(color: .purple.opacity(0.85), radius: 6)
                            Circle()
                                .strokeBorder(Color.purple, lineWidth: 2.0)
                                .frame(width: 22, height: 22)
                            Circle()
                                .fill(Color.purple)
                                .frame(width: 6, height: 6)
                        }
                        .frame(width: 36, height: 36)
                        .contentShape(Circle())
                        .position(reticlePt)
                        .onHover { hovering in
                            if hovering { NSCursor.crosshair.set() } else { NSCursor.arrow.set() }
                        }
                        .gesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .named("previewStage"))
                                .onChanged { val in
                                    guard idx < session.zoomSegments.count else { return }
                                    let mapped = mapStagePointToSourceNormalized(
                                        val.location,
                                        contentViewRect: contentViewRect,
                                        cropTopLeft: cropTopLeft,
                                        sourceSize: srcSize
                                    )
                                    session.zoomSegments[idx].focusX = mapped.x
                                    session.zoomSegments[idx].focusY = mapped.y
                                    session.zoomSegments[idx].followCursor = false
                                    requestPreviewRender()
                                }
                        )
                    }

                    // 120Hz Native ProMotion Direct-Drag Keystroke Layer (0ms lag, fixed parent coordinate space!)
                    if shouldShowKeystrokeDragHandle, let ksCG = keystrokePreviewImage, !keystrokePreviewNormRect.isEmpty {
                        let ksRect = CGRect(
                            x: fitted.minX + keystrokePreviewNormRect.minX * fitted.width,
                            y: fitted.minY + keystrokePreviewNormRect.minY * fitted.height,
                            width: keystrokePreviewNormRect.width * fitted.width,
                            height: keystrokePreviewNormRect.height * fitted.height
                        )

                        if isDraggingKeystroke {
                            if snappedCenterX {
                                Rectangle()
                                    .fill(palette.accent.opacity(0.8))
                                    .frame(width: 1.2, height: fitted.height)
                                    .position(x: fitted.midX, y: fitted.midY)
                                    .allowsHitTesting(false)
                            }
                            if snappedCenterY {
                                Rectangle()
                                    .fill(palette.accent.opacity(0.8))
                                    .frame(width: fitted.width, height: 1.2)
                                    .position(x: fitted.midX, y: fitted.midY)
                                    .allowsHitTesting(false)
                            }
                        }

                        ZStack(alignment: .top) {
                            Image(nsImage: NSImage(cgImage: ksCG, size: NSSize(width: ksCG.width, height: ksCG.height)))
                                .resizable()
                                .interpolation(.high)
                                .frame(width: ksRect.width, height: ksRect.height)

                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(
                                    palette.accent.opacity(isDraggingKeystroke ? 0.95 : (isHoveringKeystroke ? 0.78 : 0.30)),
                                    style: StrokeStyle(lineWidth: isDraggingKeystroke ? 1.8 : 1.2, dash: [5, 3])
                                )
                                .frame(width: max(40, ksRect.width - 8), height: max(28, ksRect.height - 8))
                                .frame(width: ksRect.width, height: ksRect.height)

                            if isHoveringKeystroke || isDraggingKeystroke {
                                let pctX = Int((keystrokePreviewNormRect.midX * 100).rounded())
                                let pctY = Int((keystrokePreviewNormRect.midY * 100).rounded())
                                Text(isDraggingKeystroke ? "X \(pctX)% · Y \(pctY)%" : "✥ \(uiStore.t(.customPositionLabel))")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(palette.accentTextOnAccent)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(palette.accent, in: Capsule())
                                    .offset(y: -18)
                                    .allowsHitTesting(false)
                            }
                        }
                        .frame(width: ksRect.width, height: ksRect.height)
                        .contentShape(Rectangle())
                        .position(x: ksRect.midX, y: ksRect.midY)
                        .onHover { hovering in
                            isHoveringKeystroke = hovering
                            if hovering {
                                NSCursor.openHand.set()
                            } else if !isDraggingKeystroke {
                                NSCursor.arrow.set()
                            }
                        }
                        .gesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .named("previewStage"))
                                .onChanged { val in
                                    if !isDraggingKeystroke {
                                        isDraggingKeystroke = true
                                        keystrokeGrabOffset = CGSize(
                                            width: ksRect.midX - val.startLocation.x,
                                            height: ksRect.midY - val.startLocation.y
                                        )
                                        NSCursor.closedHand.set()
                                    }

                                    let desiredCenterX = val.location.x + keystrokeGrabOffset.width
                                    let desiredCenterY = val.location.y + keystrokeGrabOffset.height

                                    var nx = Double((desiredCenterX - fitted.minX) / max(1, fitted.width))
                                    var ny = Double((desiredCenterY - fitted.minY) / max(1, fitted.height))

                                    let halfNormW = Double(keystrokePreviewNormRect.width / 2.0)
                                    let halfNormH = Double(keystrokePreviewNormRect.height / 2.0)
                                    nx = min(max(nx, halfNormW + 0.005), max(halfNormW + 0.005, 1.0 - halfNormW - 0.005))
                                    ny = min(max(ny, halfNormH + 0.005), max(halfNormH + 0.005, 1.0 - halfNormH - 0.005))

                                    if abs(nx - 0.5) < 0.018 {
                                        nx = 0.5
                                        snappedCenterX = true
                                    } else {
                                        snappedCenterX = false
                                    }
                                    if abs(ny - 0.5) < 0.018 {
                                        ny = 0.5
                                        snappedCenterY = true
                                    } else {
                                        snappedCenterY = false
                                    }

                                    keystrokePreviewNormRect = CGRect(
                                        x: CGFloat(nx) - keystrokePreviewNormRect.width / 2.0,
                                        y: CGFloat(ny) - keystrokePreviewNormRect.height / 2.0,
                                        width: keystrokePreviewNormRect.width,
                                        height: keystrokePreviewNormRect.height
                                    )
                                    session.keystrokeStyle.position = .custom
                                    session.keystrokeStyle.customX = nx
                                    session.keystrokeStyle.customY = ny
                                }
                                .onEnded { _ in
                                    isDraggingKeystroke = false
                                    snappedCenterX = false
                                    snappedCenterY = false
                                    NSCursor.arrow.set()
                                    refreshKeystrokeOverlayPreview()
                                }
                        )
                    }
                } else {
                    VStack(spacing: 10) {
                        ProgressView()
                            .scaleEffect(0.85)
                        Text(uiStore.t(.loadingMetalPreview))
                            .font(.system(size: 12))
                            .foregroundStyle(palette.secondaryText)
                    }
                }

                // Stage overlay badges & toast
                VStack {
                    ZStack {
                        HStack {
                            if selectedSegmentID != nil {
                                Label(uiStore.t(.zoomTargetHint), systemImage: "scope")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.purple)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(palette.hudSurface, in: Capsule())
                                    .overlay(Capsule().strokeBorder(.purple.opacity(0.45), lineWidth: 0.8))
                            }
                            Spacer()
                            HStack(spacing: 6) {
                                if abs(currentSourceMapping.speed - 1.0) > 0.01 {
                                    Text(formatSpeed(currentSourceMapping.speed))
                                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                                        .foregroundStyle(.orange)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(palette.hudSurface, in: Capsule())
                                        .overlay(Capsule().strokeBorder(.orange.opacity(0.50), lineWidth: 0.8))
                                }
                                if activeCamera.scale > 1.03 {
                                    Label(uiStore.format(.zoomBadgeFormat, activeCamera.scale), systemImage: "magnifyingglass")
                                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(palette.accent)
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 4)
                                        .background(palette.hudSurface, in: Capsule())
                                        .overlay(Capsule().strokeBorder(palette.accentBorder, lineWidth: 0.8))
                                }
                            }
                        }

                        if let toast = stageToast {
                            Label(toast, systemImage: "checkmark.circle.fill")
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
                        }
                    }
                    .padding(14)
                    .allowsHitTesting(false)

                    Spacer()

                    if let url = exportedURL, !isExporting {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(.green)

                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(uiStore.t(.exportDonePrefix))\(url.lastPathComponent)")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(palette.primaryText)
                                    .lineLimit(1)
                                Text(exportedFileSizeText)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(palette.secondaryText)
                            }

                            Spacer(minLength: 8)

                            Label(uiStore.t(.dragMeToX), systemImage: "hand.draw.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(palette.accentTextOnAccent)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(palette.accent, in: Capsule())
                                .onDrag {
                                    NSItemProvider(contentsOf: url) ?? NSItemProvider(object: url as NSURL)
                                }

                            Button {
                                ExportHelpers.copyFileURLToPasteboard(url)
                                copiedFileToast = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                                    copiedFileToast = false
                                }
                            } label: {
                                Text(copiedFileToast ? uiStore.t(.quickCopied) : uiStore.t(.copyFileBtn))
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(copiedFileToast ? .green : palette.primaryText)
                                    .padding(.horizontal, 10)
                                    .frame(height: 26)
                            }
                            .buttonStyle(TactilePillButtonStyle(
                                background: palette.controlFill,
                                hoverBackground: palette.controlHoverFill,
                                borderColor: palette.controlBorder,
                                cornerRadius: 13
                            ))

                            Button {
                                ExportHelpers.revealInFinder(url)
                            } label: {
                                Image(systemName: "folder")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(palette.primaryText)
                                    .frame(width: 26, height: 26)
                            }
                            .buttonStyle(TactilePillButtonStyle(
                                background: palette.controlFill,
                                hoverBackground: palette.controlHoverFill,
                                borderColor: palette.controlBorder,
                                cornerRadius: 13
                            ))
                            .help(uiStore.t(.openFinderBtn))

                            Button {
                                exportedURL = nil
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(palette.secondaryText)
                                    .frame(width: 24, height: 24)
                            }
                            .buttonStyle(TactilePillButtonStyle(
                                background: .clear,
                                hoverBackground: palette.controlHoverFill,
                                cornerRadius: 12
                            ))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(palette.hudSurface)
                                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.green.opacity(0.45), lineWidth: 1))
                        )
                        .shadow(color: .black.opacity(palette.shadowOpacity * 0.7), radius: 14, y: 6)
                        .padding(.horizontal, 18)
                        .padding(.bottom, 14)
                    }

                    if let err = exportError {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text(err)
                            Spacer()
                            Button(uiStore.t(.closeBtn)) { exportError = nil }
                                .buttonStyle(.plain)
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Color.red.opacity(0.88), in: RoundedRectangle(cornerRadius: 10))
                        .padding(14)
                    }
                }
            }
            .coordinateSpace(name: "previewStage")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Pro Multi-Track NLE Timeline Deck (3-Zone Balanced Toolbar + Sticky Track Headers + Fixed Context Bar)

    private var timelineDeck: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Balanced 3-Zone NLE Transport & Edit Toolbar (Zero Crowding / Zero Wrapping at >= 980pt!)
            ZStack {
                HStack(spacing: 8) {
                    // Left Zone: Grouped Clip Edit Pill (Split / Trim In / Trim Out | Undo / Redo | Reset)
                    HStack(spacing: 2) {
                        Button {
                            splitAtPlayhead()
                        } label: {
                            Label(uiStore.t(.splitClipBtn), systemImage: "scissors")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(palette.primaryText)
                                .padding(.horizontal, 8)
                                .frame(height: 24)
                        }
                        .buttonStyle(TactilePillButtonStyle(
                            background: .clear,
                            hoverBackground: palette.controlHoverFill,
                            cornerRadius: 5
                        ))
                        .keyboardShortcut("s", modifiers: [])
                        .help(uiStore.t(.splitClipTooltip))

                        groupedToolbarIcon("chevron.left.to.line", help: uiStore.t(.setTrimInTooltip)) {
                            trimTimelineToPlayhead(isStart: true)
                        }
                        .keyboardShortcut("i", modifiers: [])

                        groupedToolbarIcon("chevron.right.to.line", help: uiStore.t(.setTrimOutTooltip)) {
                            trimTimelineToPlayhead(isStart: false)
                        }
                        .keyboardShortcut("o", modifiers: [])

                        Divider().frame(height: 14).overlay(palette.divider).padding(.horizontal, 2)

                        groupedToolbarIcon("arrow.uturn.backward", help: uiStore.t(.undo), disabled: undoStack.isEmpty) {
                            performUndo()
                        }
                        .keyboardShortcut("z", modifiers: [.command])

                        groupedToolbarIcon("arrow.uturn.forward", help: uiStore.t(.redo), disabled: redoStack.isEmpty) {
                            performRedo()
                        }
                        .keyboardShortcut("z", modifiers: [.command, .shift])

                        if session.hasTimelineEdits {
                            Divider().frame(height: 14).overlay(palette.divider).padding(.horizontal, 2)
                            groupedToolbarIcon("arrow.counterclockwise", help: uiStore.t(.resetTrim), tint: .orange) {
                                pushUndoSnapshot()
                                session.resetTimeline()
                                selectedClipID = session.clipSegments.first?.id
                                currentTime = min(currentTime, session.outputDuration)
                                requestPreviewRender()
                            }
                        }
                    }
                    .padding(3)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(palette.controlFill)
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.controlBorder, lineWidth: 0.7))
                    )

                    Spacer(minLength: 8)

                    // Right Zone: Magnetic Snapping + Timeline Zoom Slider + Fit Button
                    HStack(spacing: 3) {
                        Button {
                            enableMagneticSnap.toggle()
                        } label: {
                            Image(systemName: "square.and.line.vertical.and.square")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(enableMagneticSnap ? palette.accent : palette.tertiaryText)
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(TactilePillButtonStyle(
                            background: enableMagneticSnap ? palette.accentSoftFill : .clear,
                            hoverBackground: enableMagneticSnap ? palette.accentHoverFill : palette.controlHoverFill,
                            borderColor: enableMagneticSnap ? palette.accentBorder : .clear,
                            cornerRadius: 5
                        ))
                        .help(uiStore.t(.snapToggleTooltip))

                        Divider().frame(height: 14).overlay(palette.divider).padding(.horizontal, 2)

                        groupedToolbarIcon("minus.magnifyingglass", help: uiStore.t(.timelineZoomOutTooltip), disabled: timelineZoom <= 1.01) {
                            withAnimation(.easeOut(duration: 0.14)) {
                                timelineZoom = max(1.0, timelineZoom / 1.4)
                            }
                        }
                        .keyboardShortcut("-", modifiers: [.command])

                        Slider(value: $timelineZoom, in: 1.0...8.0)
                            .tint(palette.accent)
                            .frame(width: 62)

                        groupedToolbarIcon("plus.magnifyingglass", help: uiStore.t(.timelineZoomInTooltip), disabled: timelineZoom >= 7.99) {
                            withAnimation(.easeOut(duration: 0.14)) {
                                timelineZoom = min(8.0, timelineZoom * 1.4)
                            }
                        }
                        .keyboardShortcut("=", modifiers: [.command])

                        Button {
                            withAnimation(.easeOut(duration: 0.14)) {
                                timelineZoom = 1.0
                            }
                        } label: {
                            Text(timelineZoom > 1.05 ? String(format: "%.1fx", timelineZoom) : uiStore.t(.timelineZoomFit))
                                .font(.system(size: 9.5, weight: .semibold, design: timelineZoom > 1.05 ? .monospaced : .default))
                                .foregroundStyle(timelineZoom > 1.05 ? palette.accent : palette.secondaryText)
                                .padding(.horizontal, 6)
                                .frame(height: 22)
                        }
                        .buttonStyle(TactilePillButtonStyle(
                            background: timelineZoom > 1.05 ? palette.accentSoftFill : .clear,
                            hoverBackground: palette.controlHoverFill,
                            cornerRadius: 5
                        ))
                        .keyboardShortcut("0", modifiers: [.command])
                    }
                    .padding(3)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(palette.controlFill)
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.controlBorder, lineWidth: 0.7))
                    )
                }

                // Dead-Center Zone: Playback Transport + Crisp Timecode (True NLE Symmetry!)
                HStack(spacing: 4) {
                    groupedToolbarIcon("backward.end.fill", help: uiStore.t(.backToTrimStart)) {
                        stopPlayback()
                        currentTime = 0
                        requestPreviewRender()
                    }

                    groupedToolbarIcon("backward.frame.fill", help: uiStore.t(.stepBackTooltip)) {
                        stepPlayhead(by: -0.1)
                    }
                    .keyboardShortcut(.leftArrow, modifiers: [])

                    Button {
                        togglePlayback()
                    } label: {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundStyle(palette.accentTextOnAccent)
                            .frame(width: 32, height: 24)
                    }
                    .buttonStyle(TactilePillButtonStyle(
                        background: palette.accent,
                        hoverBackground: palette.accent.opacity(0.88),
                        cornerRadius: 6
                    ))
                    .keyboardShortcut(.space, modifiers: [])

                    groupedToolbarIcon("forward.frame.fill", help: uiStore.t(.stepForwardTooltip)) {
                        stepPlayhead(by: 0.1)
                    }
                    .keyboardShortcut(.rightArrow, modifiers: [])

                    Divider().frame(height: 14).overlay(palette.divider).padding(.horizontal, 2)

                    HStack(spacing: 3) {
                        Text(formatTime(currentTime))
                            .foregroundStyle(palette.primaryText)
                        Text("/")
                            .foregroundStyle(palette.tertiaryText)
                        Text(formatTime(session.outputDuration))
                            .foregroundStyle(palette.secondaryText)
                    }
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .padding(.horizontal, 6)
                }
                .padding(3)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(palette.cardBackground)
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.cardBorder, lineWidth: 0.8))
                )
            }
            .frame(height: 32)

            // Pro 3-Track Canvas (Sticky Track Headers + Zoomable Scrollable Video/Zoom/Audio Tracks)
            ProMultiTrackTimeline(
                sourceDuration: session.duration,
                currentTime: $currentTime,
                clipSegments: $session.clipSegments,
                zoomSegments: $session.zoomSegments,
                selectedClipID: $selectedClipID,
                selectedSegmentID: $selectedSegmentID,
                includeAudio: $session.includeAudio,
                audioVolume: session.audioVolume,
                fadeConfig: session.fadeConfig,
                hasSourceAudio: session.hasSystemAudio || session.hasMicAudio,
                timelineZoom: timelineZoom,
                enableMagneticSnap: enableMagneticSnap,
                filmstripFrames: filmstripFrames,
                waveformPeaks: waveformPeaks,
                clickEvents: session.telemetry.clickEvents,
                typingEvents: session.telemetry.typingFocusEvents,
                palette: palette,
                uiStore: uiStore,
                onWillMutate: { pushUndoSnapshot() },
                onScrub: {
                    if isPlaying { stopPlayback() }
                    requestPreviewRender()
                },
                onAddZoomAtPlayhead: { addZoomAt(sourceTime: currentSourceTime) },
                onAddZoomAtSourceTime: { srcT in addZoomAt(sourceTime: srcT) },
                onRegenerateAutoZooms: { regenerateAutoZooms() },
                onSplitAtPlayhead: { splitAtPlayhead() },
                onDeleteClip: { clipID in deleteSelectedClip(id: clipID) },
                onMergeClipAtIndex: { idx in mergeClipWithNext(at: idx) },
                onDuplicateZoom: { segID in duplicateZoomSegment(id: segID) },
                onDeleteZoom: { segID in deleteZoomSegment(id: segID) }
            )

            // Fixed-Height Context Inspector Strip (Zero Preview Jump when switching selection!)
            Group {
                if let selID = selectedSegmentID,
                   let idx = session.zoomSegments.firstIndex(where: { $0.id == selID }) {
                    selectedZoomBar(idx: idx)
                } else if let clipID = selectedClipID,
                          let cIdx = session.clipSegments.firstIndex(where: { $0.id == clipID }) {
                    selectedClipBar(idx: cIdx)
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "keyboard")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(palette.tertiaryText)
                        Text(uiStore.t(.timelineShortcutsHint))
                            .font(.system(size: 10))
                            .foregroundStyle(palette.tertiaryText)
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        if !session.zoomSegments.isEmpty {
                            Button {
                                pushUndoSnapshot()
                                session.zoomSegments.removeAll()
                                selectedSegmentID = nil
                            } label: {
                                Text(uiStore.t(.clearAllZoomsBtn))
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.red.opacity(0.9))
                                    .padding(.horizontal, 8)
                                    .frame(height: 22)
                            }
                            .buttonStyle(TactilePillButtonStyle(
                                background: .red.opacity(0.10),
                                hoverBackground: .red.opacity(0.20),
                                cornerRadius: 6
                            ))
                        }
                    }
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(palette.controlFill.opacity(0.55))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(palette.controlBorder.opacity(0.65), lineWidth: 0.7))
                    )
                }
            }
            .frame(height: 34)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(palette.timelineBackground)
    }

    private func selectedClipBar(idx: Int) -> some View {
        let clip = session.clipSegments[idx]
        let canDelete = session.clipSegments.count > 1
        let canMerge = VideoTimelineMapper.canMergeWithNext(session.clipSegments, at: idx)

        return HStack(spacing: 9) {
            HStack(spacing: 5) {
                Circle().fill(palette.accent).frame(width: 7, height: 7)
                Text(uiStore.format(.clipSelectedFormat, idx + 1))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(palette.primaryText)
                Text(String(format: "%.1fs", clip.outputDuration))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(palette.secondaryText)
            }

            Divider().frame(height: 14).overlay(palette.divider)

            HStack(spacing: 4) {
                Text(uiStore.t(.clipSpeedLabel))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(palette.secondaryText)

                ForEach(VideoTimelineMapper.speedPresets, id: \.self) { spd in
                    let isSelected = abs(clip.speed - spd) < 0.01
                    Button {
                        pushUndoSnapshot()
                        session.clipSegments[idx].speed = spd
                    } label: {
                        Text(formatSpeed(spd))
                            .font(.system(size: 10, weight: isSelected ? .bold : .semibold, design: .monospaced))
                            .foregroundStyle(isSelected ? palette.accentTextOnAccent : palette.primaryText)
                            .padding(.horizontal, 7)
                            .frame(height: 22)
                    }
                    .buttonStyle(TactilePillButtonStyle(
                        background: isSelected ? palette.accent : palette.controlFill,
                        hoverBackground: isSelected ? palette.accent.opacity(0.88) : palette.controlHoverFill,
                        borderColor: isSelected ? .clear : palette.controlBorder,
                        cornerRadius: 6
                    ))
                }
            }

            Spacer(minLength: 6)

            if canMerge {
                Button {
                    mergeClipWithNext(at: idx)
                } label: {
                    Label(uiStore.t(.mergeNextClipBtn), systemImage: "arrow.triangle.merge")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(palette.primaryText)
                        .padding(.horizontal, 8)
                        .frame(height: 23)
                }
                .buttonStyle(TactilePillButtonStyle(
                    background: palette.controlFill,
                    hoverBackground: palette.controlHoverFill,
                    borderColor: palette.controlBorder,
                    cornerRadius: 6
                ))
            }

            if canDelete {
                Button {
                    deleteSelectedClip(id: clip.id)
                } label: {
                    Label(uiStore.t(.deleteClipBtn), systemImage: "trash")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 9)
                        .frame(height: 23)
                }
                .buttonStyle(TactilePillButtonStyle(
                    background: .red.opacity(0.14),
                    hoverBackground: .red.opacity(0.24),
                    borderColor: .red.opacity(0.30),
                    cornerRadius: 6
                ))
                .keyboardShortcut(.delete, modifiers: [])
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(palette.accentSoftFill.opacity(0.70))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(palette.accentBorder, lineWidth: 0.8))
        )
    }

    private func selectedZoomBar(idx: Int) -> some View {
        let seg = session.zoomSegments[idx]
        return HStack(spacing: 10) {
            HStack(spacing: 5) {
                let isTypingSeg = seg.triggerKind == .typing
                Circle().fill(isTypingSeg ? Color.mint : Color.purple).frame(width: 7, height: 7)
                Text(isTypingSeg ? uiStore.t(.zoomSegmentTyping) : uiStore.t(.zoomSegmentClick))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(palette.primaryText)
                    .lineLimit(1)
            }

            HStack(spacing: 5) {
                Text(uiStore.t(.zoomScaleLabel))
                    .font(.system(size: 10.5))
                    .foregroundStyle(palette.secondaryText)
                Slider(value: $session.zoomSegments[idx].scale, in: 1.25...2.5, step: 0.05)
                    .tint(.purple)
                    .frame(width: 82)
                Text(String(format: "%.2fx", seg.scale))
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(palette.primaryText)
                    .frame(width: 36, alignment: .leading)
            }

            HStack(spacing: 5) {
                Text(uiStore.t(.zoomEaseLabel))
                    .font(.system(size: 10.5))
                    .foregroundStyle(palette.secondaryText)
                Slider(value: $session.zoomSegments[idx].easeDuration, in: 0.15...0.85, step: 0.05)
                    .tint(.purple)
                    .frame(width: 66)
                Text(String(format: "%.2fs", seg.easeDuration))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(palette.primaryText)
                    .frame(width: 36, alignment: .leading)
            }

            Toggle(uiStore.t(.followCursorLabel), isOn: $session.zoomSegments[idx].followCursor)
                .toggleStyle(.checkbox)
                .font(.system(size: 10.5))
                .foregroundStyle(palette.primaryText)

            Spacer(minLength: 4)

            Button {
                duplicateZoomSegment(id: seg.id)
            } label: {
                Label(uiStore.t(.duplicateZoomBtn), systemImage: "doc.on.doc")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(palette.primaryText)
                    .padding(.horizontal, 8)
                    .frame(height: 23)
            }
            .buttonStyle(TactilePillButtonStyle(
                background: palette.controlFill,
                hoverBackground: palette.controlHoverFill,
                borderColor: palette.controlBorder,
                cornerRadius: 6
            ))

            Button {
                deleteZoomSegment(id: seg.id)
            } label: {
                Label(uiStore.t(.deleteAction), systemImage: "trash")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 8)
                    .frame(height: 23)
            }
            .buttonStyle(TactilePillButtonStyle(
                background: .red.opacity(0.14),
                hoverBackground: .red.opacity(0.24),
                borderColor: .red.opacity(0.30),
                cornerRadius: 6
            ))
            .keyboardShortcut(.delete, modifiers: [])
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.purple.opacity(0.11))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.purple.opacity(0.32), lineWidth: 0.8))
        )
    }

    // MARK: - Adaptive Right Inspector

    private var rightInspector: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                inspectorTabButton(title: uiStore.t(.tabAppearance), icon: "paintbrush.fill", tag: 0)
                inspectorTabButton(title: uiStore.t(.tabMotionExport), icon: "wand.and.rays", tag: 1)
            }
            .padding(4)
            .background(palette.controlFill, in: RoundedRectangle(cornerRadius: 9))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider().overlay(palette.divider)

            ScrollView {
                if inspectorTab == 0 {
                    appearanceInspector
                } else {
                    motionAndAudioInspector
                }
            }
        }
        .frame(width: 296)
        .background(palette.inspectorBackground)
    }

    private func inspectorTabButton(title: String, icon: String, tag: Int) -> some View {
        let isSelected = (inspectorTab == tag)
        return Button {
            withAnimation(.easeOut(duration: 0.14)) {
                inspectorTab = tag
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10.5, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? palette.primaryText : palette.secondaryText)
            .frame(maxWidth: .infinity)
            .frame(height: 28)
        }
        .buttonStyle(TactilePillButtonStyle(
            background: isSelected ? palette.cardBackground : .clear,
            hoverBackground: isSelected ? palette.cardBackground : palette.controlHoverFill,
            borderColor: isSelected ? palette.cardBorder : .clear,
            cornerRadius: 7
        ))
    }

    private var appearanceInspector: some View {
        VStack(alignment: .leading, spacing: 12) {
            inspectorCard(title: uiStore.t(.quickPresets)) {
                HStack(spacing: 6) {
                    quickPresetButton(
                        uiStore.t(.presetNeon),
                        dotColors: [Color(red: 0.25, green: 0.58, blue: 0.96), Color(red: 0.56, green: 0.30, blue: 0.96)],
                        isActive: session.style.background.id == BackgroundPreset.curated[0].id && session.style.windowChrome == .none
                    ) {
                        session.style = BeautifyStyle(background: BackgroundPreset.curated[0], padding: 56, cornerRadius: 20, shadowRadius: 42, shadowOpacity: 0.52, aspectRatio: .wide16x9, windowChrome: .none, insetStroke: true, watermark: session.style.watermark)
                    }
                    quickPresetButton(
                        uiStore.t(.presetDarkGeek),
                        dotColors: [Color(red: 0.12, green: 0.14, blue: 0.22), Color(red: 0.26, green: 0.30, blue: 0.42)],
                        isActive: session.style.background.id == BackgroundPreset.curated[6].id && session.style.windowChrome == .macOSDark
                    ) {
                        session.style = BeautifyStyle(background: BackgroundPreset.curated[6], padding: 48, cornerRadius: 16, shadowRadius: 36, shadowOpacity: 0.55, aspectRatio: .wide16x9, windowChrome: .macOSDark, insetStroke: true, watermark: session.style.watermark)
                    }
                    quickPresetButton(
                        uiStore.t(.presetNoFrame),
                        dotColors: [palette.tertiaryText, palette.secondaryText],
                        isActive: session.style.padding == 0 && session.style.cornerRadius == 0
                    ) {
                        session.style = BeautifyStyle(background: BackgroundPreset.curated[9], padding: 0, cornerRadius: 0, shadowRadius: 0, shadowOpacity: 0, aspectRatio: .auto, windowChrome: .none, insetStroke: false, watermark: session.style.watermark)
                    }
                }
            }

            inspectorCard(title: uiStore.t(.backgroundWallpaper)) {
                WallpaperPickerSection(selectedBackground: $session.style.background, palette: palette)
            }

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
                    sliderRow(title: uiStore.t(.paddingLabel), value: $session.style.padding, defaultValue: 56, range: 0...160, unit: "pt")
                    sliderRow(title: uiStore.t(.cornerRadiusLabel), value: $session.style.cornerRadius, defaultValue: 20, range: 0...44, unit: "pt")
                    sliderRow(title: uiStore.t(.shadowLabel), value: $session.style.shadowRadius, defaultValue: 42, range: 0...72, unit: "pt")
                }
            }

            inspectorCard(title: uiStore.t(.windowChromeTitle)) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        ForEach(WindowChromeStyle.allCases) { style in
                            let isSelected = (session.style.windowChrome == style)
                            Button {
                                session.style.windowChrome = style
                            } label: {
                                Text(style.displayName)
                                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                                    .foregroundStyle(isSelected ? palette.accent : palette.secondaryText)
                                    .lineLimit(1)
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

                    if session.style.windowChrome != .none {
                        TextField(uiStore.t(.windowTitlePlaceholder), text: $session.style.windowTitle)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                    }

                    Toggle(uiStore.t(.glassStroke), isOn: $session.style.insetStroke)
                        .font(.system(size: 12))
                        .foregroundStyle(palette.primaryText)
                }
            }

            inspectorCard(title: uiStore.t(.fadeCardTitle)) {
                VStack(spacing: 10) {
                    secondsSliderRow(title: uiStore.t(.fadeInLabel), value: $session.fadeConfig.fadeInDuration, defaultValue: 0, range: 0...1.5)
                    secondsSliderRow(title: uiStore.t(.fadeOutLabel), value: $session.fadeConfig.fadeOutDuration, defaultValue: 0, range: 0...1.5)
                }
            }

            // Webcam Picture-in-Picture Card (supports recorded webcam track OR attaching a local camera video!)
            webcamPiPCard

            // Custom Watermark / Creator Signature Card (baked once into GPU canvas -> zero per-frame export overhead!)
            WatermarkInspectorCard(
                config: $session.style.watermark,
                palette: palette,
                onSaveAsDefault: {
                    onSaveDefaultWatermark?(session.style.watermark)
                    NSSound(named: NSSound.Name("Pop"))?.play()
                    flashStageToast(uiStore.t(.watermarkSavedDefaultToast))
                }
            )
        }
        .padding(12)
    }

    private var webcamPiPCard: some View {
        let teal = Color(red: 0.12, green: 0.78, blue: 0.68)
        let hasCamTrack = (session.webcamVideoURL != nil)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "person.crop.rectangle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(teal)
                Text(uiStore.t(.webcamCardTitle))
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(palette.primaryText)
                    .lineLimit(1)
                Spacer()
                if hasCamTrack {
                    Toggle("", isOn: $session.webcamPiP.enabled)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                }
            }

            if hasCamTrack && session.webcamPiP.enabled {
                // 3 Shapes: Circle / Rounded Rect / Vertical
                HStack(spacing: 4) {
                    ForEach(WebcamPiPShape.allCases) { shape in
                        let isSelected = (session.webcamPiP.shape == shape)
                        Button {
                            withAnimation(.easeOut(duration: 0.14)) {
                                session.webcamPiP.shape = shape
                            }
                        } label: {
                            Text(shape.displayName)
                                .font(.system(size: 10, weight: isSelected ? .bold : .medium))
                                .foregroundStyle(isSelected ? teal : palette.secondaryText)
                                .frame(maxWidth: .infinity)
                                .frame(height: 24)
                                .lineLimit(1)
                        }
                        .buttonStyle(TactilePillButtonStyle(
                            background: isSelected ? teal.opacity(0.18) : .clear,
                            hoverBackground: isSelected ? teal.opacity(0.26) : palette.controlHoverFill,
                            borderColor: isSelected ? teal.opacity(0.60) : .clear,
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

                // 4 Corners
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 5), GridItem(.flexible(), spacing: 5)], spacing: 5) {
                    ForEach(WebcamPiPCorner.allCases) { corner in
                        let isSelected = (session.webcamPiP.corner == corner)
                        Button {
                            withAnimation(.easeOut(duration: 0.14)) {
                                session.webcamPiP.corner = corner
                            }
                        } label: {
                            Text(corner.displayName)
                                .font(.system(size: 10, weight: isSelected ? .bold : .medium))
                                .foregroundStyle(isSelected ? palette.accent : palette.secondaryText)
                                .frame(maxWidth: .infinity)
                                .frame(height: 25)
                        }
                        .buttonStyle(TactilePillButtonStyle(
                            background: isSelected ? palette.accentSoftFill : palette.controlFill,
                            hoverBackground: isSelected ? palette.accentHoverFill : palette.controlHoverFill,
                            borderColor: isSelected ? palette.accentBorder : palette.controlBorder,
                            cornerRadius: 6
                        ))
                    }
                }

                // Size slider
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(uiStore.t(.webcamSizeLabel))
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(palette.secondaryText)
                        Spacer()
                        Text("\(Int((session.webcamPiP.sizeFraction * 100).rounded()))%")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(teal)
                    }
                    Slider(value: $session.webcamPiP.sizeFraction, in: 0.14...0.38)
                        .tint(teal)
                }

                HStack(spacing: 10) {
                    Toggle(uiStore.t(.webcamMirrorLabel), isOn: $session.webcamPiP.mirrored)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 10.5))
                        .foregroundStyle(palette.secondaryText)
                    Toggle(uiStore.t(.webcamBorderLabel), isOn: $session.webcamPiP.showBorder)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 10.5))
                        .foregroundStyle(palette.secondaryText)
                }
            } else if !hasCamTrack {
                Text(uiStore.t(.webcamNoTrackHint))
                    .font(.system(size: 10))
                    .foregroundStyle(palette.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    pickLocalWebcamVideo()
                } label: {
                    Label(uiStore.t(.webcamAttachLocalBtn), systemImage: "video.badge.plus")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(teal)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                }
                .buttonStyle(TactilePillButtonStyle(
                    background: teal.opacity(0.14),
                    hoverBackground: teal.opacity(0.24),
                    borderColor: teal.opacity(0.45),
                    cornerRadius: 7
                ))
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

    private func pickLocalWebcamVideo() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        session.webcamVideoURL = url
        session.webcamPiP.enabled = true
        setupWebcamGenerator(url: url)
        cachedWebcamFrameTime = -999
        cachedWebcamFrameCG = nil
        requestPreviewRender()
    }

    private func setupWebcamGenerator(url: URL) {
        let camAsset = AVURLAsset(url: url)
        let camGen = AVAssetImageGenerator(asset: camAsset)
        camGen.appliesPreferredTrackTransform = true
        camGen.maximumSize = CGSize(width: 720, height: 720)
        camGen.requestedTimeToleranceBefore = CMTime(seconds: 0.05, preferredTimescale: 600)
        camGen.requestedTimeToleranceAfter = CMTime(seconds: 0.05, preferredTimescale: 600)
        self.webcamImageGenerator = camGen
    }

    private var motionAndAudioInspector: some View {
        VStack(alignment: .leading, spacing: 14) {
            inspectorCard(title: uiStore.t(.cardSmartCamera)) {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(uiStore.t(.toggleAutoZoom), isOn: $session.enableAutoZoom)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(palette.primaryText)

                    HStack(spacing: 8) {
                        Toggle(uiStore.format(.clickZoomCountFormat, session.telemetry.clickEvents.count), isOn: $session.includeClickZoom)
                            .toggleStyle(.checkbox)
                            .font(.system(size: 11))
                            .onChange(of: session.includeClickZoom) { _, _ in regenerateAutoZooms() }
                        Toggle(uiStore.format(.typingZoomCountFormat, session.telemetry.typingFocusEvents.count), isOn: $session.includeTypingFocusZoom)
                            .toggleStyle(.checkbox)
                            .font(.system(size: 11))
                            .onChange(of: session.includeTypingFocusZoom) { _, _ in regenerateAutoZooms() }
                    }
                    .foregroundStyle(palette.secondaryText)

                    Divider().overlay(palette.divider)

                    Toggle(uiStore.t(.toggleVectorCursor), isOn: $session.enableSmoothCursor)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(palette.primaryText)

                    if session.enableSmoothCursor {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(uiStore.t(.cursorSizeLabel))
                                    .font(.system(size: 11))
                                    .foregroundStyle(palette.secondaryText)
                                Spacer()
                                Text(String(format: "%.2fx", session.cursorScale))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(palette.accent)
                            }
                            Slider(value: $session.cursorScale, in: 0.8...2.2, step: 0.05)
                                .tint(palette.accent)
                        }
                    }

                    Toggle(uiStore.t(.toggleClickRipples), isOn: $session.enableClickRipples)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(palette.primaryText)
                }
            }

            inspectorCard(title: uiStore.t(.cardKeystrokeStylePos)) {
                VStack(alignment: .leading, spacing: 11) {
                    HStack {
                        Toggle(uiStore.format(.toggleShowKeystrokesFormat, session.telemetry.keystrokeEvents.count), isOn: $session.enableKeystrokes)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(palette.primaryText)
                        Spacer(minLength: 4)
                        if session.enableKeystrokes {
                            Button {
                                showSampleKeystrokeInPreview.toggle()
                            } label: {
                                Label(showSampleKeystrokeInPreview ? uiStore.t(.hideSample) : uiStore.t(.previewSample), systemImage: showSampleKeystrokeInPreview ? "eye.slash" : "eye")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(showSampleKeystrokeInPreview ? palette.accent : palette.secondaryText)
                                    .padding(.horizontal, 8)
                                    .frame(height: 22)
                            }
                            .buttonStyle(TactilePillButtonStyle(
                                background: showSampleKeystrokeInPreview ? palette.accentSoftFill : palette.controlFill,
                                hoverBackground: showSampleKeystrokeInPreview ? palette.accentHoverFill : palette.controlHoverFill,
                                borderColor: showSampleKeystrokeInPreview ? palette.accentBorder : palette.controlBorder,
                                cornerRadius: 11
                            ))
                        }
                    }

                    if session.enableKeystrokes {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(uiStore.t(.keycapStyleLabel))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(palette.secondaryText)

                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                                ForEach(KeystrokeVisualStyle.allCases) { vStyle in
                                    let isSelected = session.keystrokeStyle.visualStyle == vStyle
                                    Button {
                                        session.keystrokeStyle.visualStyle = vStyle
                                    } label: {
                                        VStack(spacing: 5) {
                                            keystrokeMiniPreview(vStyle)
                                            Text(vStyle.displayName)
                                                .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
                                                .foregroundStyle(isSelected ? palette.accent : palette.secondaryText)
                                                .lineLimit(1)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                    }
                                    .buttonStyle(TactilePillButtonStyle(
                                        background: isSelected ? palette.accentSoftFill : palette.controlFill,
                                        hoverBackground: isSelected ? palette.accentHoverFill : palette.controlHoverFill,
                                        borderColor: isSelected ? palette.accentBorder : palette.controlBorder,
                                        cornerRadius: 8
                                    ))
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(uiStore.t(.displayPositionLabel))
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(palette.secondaryText)
                                Spacer()
                                if session.keystrokeStyle.position == .custom {
                                    Text("\(uiStore.t(.customPositionLabel)) (\(Int((session.keystrokeStyle.customX * 100).rounded()))%, \(Int((session.keystrokeStyle.customY * 100).rounded()))%)")
                                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(palette.accent)
                                } else {
                                    Text(session.keystrokeStyle.position.displayName)
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(palette.accent)
                                }
                            }

                            VStack(spacing: 6) {
                                HStack(spacing: 6) {
                                    positionCell(.topLeft)
                                    positionCell(.topCenter)
                                    positionCell(.topRight)
                                }
                                HStack(spacing: 6) {
                                    positionCell(.bottomLeft)
                                    positionCell(.bottomCenter)
                                    positionCell(.bottomRight)
                                }
                            }
                            .padding(7)
                            .background(
                                RoundedRectangle(cornerRadius: 9)
                                    .fill(palette.trackFill)
                                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(palette.controlBorder, lineWidth: 0.8))
                            )

                            HStack(spacing: 5) {
                                Image(systemName: "hand.draw")
                                    .font(.system(size: 10))
                                    .foregroundStyle(palette.accent)
                                Text(uiStore.t(.dragPositionHint))
                                    .font(.system(size: 10))
                                    .foregroundStyle(palette.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(uiStore.t(.keycapSizeLabel))
                                    .font(.system(size: 11))
                                    .foregroundStyle(palette.secondaryText)
                                Spacer()
                                Text(String(format: "%.2fx", session.keystrokeStyle.sizeScale))
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(palette.accent)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(palette.controlFill, in: RoundedRectangle(cornerRadius: 4))
                            }
                            Slider(value: $session.keystrokeStyle.sizeScale, in: 0.75...1.5, step: 0.05)
                                .tint(palette.accent)
                        }

                        Picker("", selection: $session.keystrokeStyle.filterMode) {
                            ForEach(KeystrokeFilterMode.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                    if session.telemetry.keystrokeEvents.isEmpty {
                        Text(uiStore.t(.noKeystrokesCapturedHint))
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            inspectorCard(title: uiStore.t(.cardAudioTrack)) {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(uiStore.t(.toggleKeepAudio), isOn: $session.includeAudio)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(palette.primaryText)
                        .disabled(!session.hasSystemAudio && !session.hasMicAudio)

                    if session.includeAudio && (session.hasSystemAudio || session.hasMicAudio) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(uiStore.t(.audioVolumeLabel))
                                    .font(.system(size: 11))
                                    .foregroundStyle(palette.secondaryText)
                                Spacer()
                                Text("\(Int((session.audioVolume * 100).rounded()))%")
                                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                                    .monospacedDigit()
                                    .foregroundStyle(palette.accent)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(palette.controlFill, in: RoundedRectangle(cornerRadius: 5))
                                    .onTapGesture(count: 2) {
                                        session.audioVolume = 1.0
                                    }
                            }
                            Slider(value: $session.audioVolume, in: 0.0...2.0, step: 0.05)
                                .tint(palette.accent)
                        }
                    }
                }
            }

            inspectorCard(title: uiStore.t(.cardEncodingPipeline)) {
                VStack(alignment: .leading, spacing: 6) {
                    specRow(icon: "bolt.fill", color: .orange, text: uiStore.t(.specZeroCopy))
                    specRow(icon: "video.fill", color: palette.accent, text: uiStore.t(.specConstant60))
                    specRow(icon: "paintpalette.fill", color: .purple, text: uiStore.t(.specRec709))
                    specRow(icon: "waveform.path.ecg", color: .green, text: uiStore.t(.specHighBitrate))
                }
            }
        }
        .padding(12)
    }

    // MARK: - Timeline Editing Operations & Undo/Redo

    private func pushUndoSnapshot() {
        let snap = VideoTimelineSnapshot(clipSegments: session.clipSegments, zoomSegments: session.zoomSegments)
        if undoStack.last != snap {
            undoStack.append(snap)
            if undoStack.count > 40 {
                undoStack.removeFirst()
            }
            redoStack.removeAll()
        }
    }

    private func performUndo() {
        guard let prev = undoStack.popLast() else { return }
        let current = VideoTimelineSnapshot(clipSegments: session.clipSegments, zoomSegments: session.zoomSegments)
        redoStack.append(current)
        session.clipSegments = prev.clipSegments
        session.zoomSegments = prev.zoomSegments
        selectedClipID = session.clipSegments.first(where: { $0.id == selectedClipID })?.id
        selectedSegmentID = session.zoomSegments.first(where: { $0.id == selectedSegmentID })?.id
        currentTime = min(currentTime, session.outputDuration)
        requestPreviewRender()
    }

    private func performRedo() {
        guard let next = redoStack.popLast() else { return }
        let current = VideoTimelineSnapshot(clipSegments: session.clipSegments, zoomSegments: session.zoomSegments)
        undoStack.append(current)
        session.clipSegments = next.clipSegments
        session.zoomSegments = next.zoomSegments
        selectedClipID = session.clipSegments.first(where: { $0.id == selectedClipID })?.id
        selectedSegmentID = session.zoomSegments.first(where: { $0.id == selectedSegmentID })?.id
        currentTime = min(currentTime, session.outputDuration)
        requestPreviewRender()
    }

    private func stepPlayhead(by delta: Double) {
        stopPlayback()
        currentTime = min(max(0, currentTime + delta), session.outputDuration)
        requestPreviewRender()
    }

    private func splitAtPlayhead() {
        stopPlayback()
        guard let res = VideoTimelineMapper.splitClip(session.clipSegments, atOutputTime: currentTime) else {
            NSSound.beep()
            return
        }
        pushUndoSnapshot()
        session.clipSegments = res.clips
        selectedSegmentID = nil
        selectedClipID = res.rightClipID
        NSSound(named: NSSound.Name("Pop"))?.play()
        requestPreviewRender()
    }

    private func deleteSelectedClip(id: UUID) {
        stopPlayback()
        guard let updated = VideoTimelineMapper.deleteClip(session.clipSegments, id: id) else {
            NSSound.beep()
            return
        }
        pushUndoSnapshot()
        session.clipSegments = updated
        selectedClipID = updated.first?.id
        currentTime = min(currentTime, session.outputDuration)
        NSSound(named: NSSound.Name("Pop"))?.play()
        requestPreviewRender()
    }

    private func mergeClipWithNext(at idx: Int) {
        stopPlayback()
        guard let merged = VideoTimelineMapper.mergeAdjacentClips(session.clipSegments, at: idx) else {
            NSSound.beep()
            return
        }
        pushUndoSnapshot()
        session.clipSegments = merged
        selectedClipID = merged[min(idx, merged.count - 1)].id
        currentTime = min(currentTime, session.outputDuration)
        NSSound(named: NSSound.Name("Pop"))?.play()
        requestPreviewRender()
    }

    private func duplicateZoomSegment(id: UUID) {
        guard let seg = session.zoomSegments.first(where: { $0.id == id }) else { return }
        let dur = max(0.5, seg.endTime - seg.startTime)
        let desiredStart = min(max(0, seg.endTime + 0.15), max(0, session.duration - dur))
        guard desiredStart + 0.4 <= session.duration else {
            NSSound.beep()
            return
        }
        pushUndoSnapshot()
        let copy = ZoomSegment(
            startTime: desiredStart,
            endTime: min(session.duration, desiredStart + dur),
            focusX: seg.focusX,
            focusY: seg.focusY,
            scale: seg.scale,
            easeDuration: seg.easeDuration,
            followCursor: seg.followCursor,
            triggerKind: .manual
        )
        session.zoomSegments.append(copy)
        session.zoomSegments.sort { $0.startTime < $1.startTime }
        selectedSegmentID = copy.id
        selectedClipID = nil
        if let outT = VideoTimelineMapper.mapSourceTimeToOutput((copy.startTime + copy.endTime) / 2.0, clips: session.clipSegments) {
            currentTime = outT
        }
        NSSound(named: NSSound.Name("Pop"))?.play()
        requestPreviewRender()
    }

    private func deleteZoomSegment(id: UUID) {
        guard let idx = session.zoomSegments.firstIndex(where: { $0.id == id }) else { return }
        pushUndoSnapshot()
        session.zoomSegments.remove(at: idx)
        if selectedSegmentID == id {
            selectedSegmentID = nil
        }
        NSSound(named: NSSound.Name("Pop"))?.play()
        requestPreviewRender()
    }

    private func trimTimelineToPlayhead(isStart: Bool) {
        stopPlayback()
        guard let updated = VideoTimelineMapper.trimToPlayhead(
            session.clipSegments,
            atOutputTime: currentTime,
            isStart: isStart
        ) else {
            NSSound.beep()
            return
        }
        pushUndoSnapshot()
        session.clipSegments = updated
        if isStart {
            currentTime = 0
        } else {
            currentTime = session.outputDuration
        }
        NSSound(named: NSSound.Name("Pop"))?.play()
        requestPreviewRender()
    }

    private func captureCurrentBeautifiedFrame() {
        let srcT = currentSourceTime
        let raw = cachedRawFrameCG
        let rawURL = session.rawVideoURL
        let camURL = session.webcamPiP.enabled ? session.webcamVideoURL : nil
        let cachedCam = cachedWebcamFrameCG
        let opts = VideoCompositeOptions(session: session)
        let smoothed = smoothedCursorPath
        let exp = exporter
        let maxEdge = session.exportPreset.maxLongEdge

        Task.detached(priority: .userInitiated) {
            let sourceCG: CGImage?
            if let raw {
                sourceCG = raw
            } else {
                let asset = AVURLAsset(url: rawURL)
                let gen = AVAssetImageGenerator(asset: asset)
                gen.appliesPreferredTrackTransform = true
                sourceCG = (try? await gen.image(at: CMTime(seconds: srcT, preferredTimescale: 600)))?.image
            }
            let camCG: CGImage?
            if let camURL {
                if let cachedCam {
                    camCG = cachedCam
                } else {
                    let camAsset = AVURLAsset(url: camURL)
                    let camGen = AVAssetImageGenerator(asset: camAsset)
                    camGen.appliesPreferredTrackTransform = true
                    camCG = (try? await camGen.image(at: CMTime(seconds: srcT, preferredTimescale: 600)))?.image
                }
            } else {
                camCG = nil
            }
            guard let sourceCG,
                  let rendered = exp.renderPreviewFrame(
                      sourceCGImage: sourceCG,
                      time: srcT,
                      options: opts,
                      smoothedCursorPath: smoothed,
                      maxPreviewEdge: maxEdge,
                      fadeOpacity: 1.0,
                      webcamCGImage: camCG
                  ) else { return }

            await MainActor.run {
                ExportHelpers.copyImageToPasteboard(rendered)
                if let savedURL = ExportHelpers.saveScreenshotQuickly(rendered) {
                    self.onFrameCaptured?(savedURL, rendered)
                }
                NSSound(named: NSSound.Name("Pop"))?.play()
                self.flashStageToast(self.uiStore.t(.captureFrameToast))
            }
        }
    }

    private func flashStageToast(_ text: String) {
        withAnimation(.spring(response: 0.24, dampingFraction: 0.85)) {
            stageToast = text
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            if stageToast == text {
                withAnimation(.easeOut(duration: 0.2)) {
                    stageToast = nil
                }
            }
        }
    }

    // MARK: - Playback (Audio-Synced!) & Export Engine Hooks

    private func setupPreviewPipeline() {
        smoothedCursorPath = AutoZoomEngine.smoothCursorSamples(session.telemetry.cursorSamples, fps: 60)
        selectedClipID = session.clipSegments.first?.id
        let asset = AVURLAsset(url: session.rawVideoURL)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.requestedTimeToleranceBefore = CMTime(seconds: 0.02, preferredTimescale: 600)
        gen.requestedTimeToleranceAfter = CMTime(seconds: 0.03, preferredTimescale: 600)
        self.imageGenerator = gen
        if let camURL = session.webcamVideoURL {
            setupWebcamGenerator(url: camURL)
        }
        currentTime = 0
        requestPreviewRender()
        generateFilmstripAsync(for: session.rawVideoURL, duration: session.duration)
        if session.hasSystemAudio || session.hasMicAudio {
            let url = session.rawVideoURL
            Task {
                let peaks = await AudioWaveformExtractor.extractPeaks(from: url, bucketCount: 360)
                await MainActor.run {
                    self.waveformPeaks = peaks
                }
            }
        }
    }

    private func generateFilmstripAsync(for url: URL, duration: Double) {
        let count = 14
        Task.detached(priority: .utility) {
            let asset = AVURLAsset(url: url)
            let gen = AVAssetImageGenerator(asset: asset)
            gen.appliesPreferredTrackTransform = true
            gen.maximumSize = CGSize(width: 180, height: 110)
            gen.requestedTimeToleranceBefore = CMTime(seconds: 0.15, preferredTimescale: 600)
            gen.requestedTimeToleranceAfter = CMTime(seconds: 0.15, preferredTimescale: 600)

            var thumbs: [(Double, CGImage)] = []
            for i in 0..<count {
                let frac = (Double(i) + 0.5) / Double(count)
                let sec = max(0, min(duration - 0.02, frac * duration))
                if let img = (try? await gen.image(at: CMTime(seconds: sec, preferredTimescale: 600)))?.image {
                    thumbs.append((sec, img))
                }
            }
            let finalThumbs = thumbs
            await MainActor.run {
                self.filmstripFrames = finalThumbs
            }
        }
    }

    private func togglePlayback() {
        if isPlaying {
            stopPlayback()
            return
        }

        let totalOut = session.outputDuration
        if currentTime >= totalOut - 0.05 {
            currentTime = 0
        }
        showSampleKeystrokeInPreview = false
        keystrokePreviewImage = nil
        isPlaying = true
        playbackStartWallTime = CACurrentMediaTime()
        playbackStartOutputTime = currentTime

        // Start real-time pitch-preserved audio playback synced to split/speed clips!
        let shouldPlayAudio = session.includeAudio && (session.hasSystemAudio || session.hasMicAudio) && session.audioVolume > 0.001
        if shouldPlayAudio {
            let startOut = currentTime
            let clips = session.clipSegments
            let fade = session.fadeConfig
            let vol = Float(session.audioVolume)
            let url = session.rawVideoURL
            Task { @MainActor in
                let asset = AVURLAsset(url: url)
                if let built = try? await VideoTimelineMapper.buildAudioComposition(from: asset, clips: clips, fade: fade, volume: vol),
                   self.isPlaying {
                    let item = AVPlayerItem(asset: built.composition)
                    item.audioMix = built.audioMix
                    item.audioTimePitchAlgorithm = .timeDomain
                    let player = AVPlayer(playerItem: item)
                    _ = await player.seek(to: CMTime(seconds: startOut, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                    guard self.isPlaying else { return }
                    player.play()
                    self.audioPlayer = player
                }
            }
        }

        playbackTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
            Task { @MainActor in
                guard self.isPlaying else { return }
                let total = self.session.outputDuration
                let next: Double
                if let player = self.audioPlayer, player.rate > 0, player.currentTime().isNumeric {
                    next = player.currentTime().seconds
                } else {
                    next = self.playbackStartOutputTime + (CACurrentMediaTime() - self.playbackStartWallTime)
                }

                if next >= total {
                    self.currentTime = 0
                    self.playbackStartWallTime = CACurrentMediaTime()
                    self.playbackStartOutputTime = 0
                    if let player = self.audioPlayer {
                        _ = await player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
                        if self.isPlaying {
                            player.play()
                        }
                    }
                } else {
                    self.currentTime = max(0, next)
                }
                self.requestPreviewRender()
            }
        }
    }

    private func stopPlayback() {
        isPlaying = false
        playbackTimer?.invalidate()
        playbackTimer = nil
        audioPlayer?.pause()
        audioPlayer = nil
        refreshKeystrokeOverlayPreview()
        requestPreviewRender()
    }

    private func activePreviewKeystrokeEvent() -> KeystrokeEvent? {
        guard session.enableKeystrokes else { return nil }
        if let live = AutoZoomEngine.activeKeystroke(
            at: currentSourceTime,
            keystrokes: session.telemetry.keystrokeEvents,
            filterMode: session.keystrokeStyle.filterMode
        ) {
            return live.event
        }
        if showSampleKeystrokeInPreview {
            return KeystrokeEvent(time: currentSourceTime, text: "⌘⇧P", keycaps: ["⌘", "⇧", "P"], isTypingText: false)
        }
        return nil
    }

    private func refreshKeystrokeOverlayPreview() {
        guard !isPlaying, let event = activePreviewKeystrokeEvent() else {
            keystrokePreviewImage = nil
            keystrokePreviewNormRect = .zero
            return
        }
        let srcSize = cachedRawFrameCG.map { CGSize(width: $0.width, height: $0.height) } ?? session.videoSize
        if let res = exporter.renderKeystrokeOverlayForPreview(
            sourceSize: srcSize,
            event: event,
            style: session.style,
            keystrokeStyle: session.keystrokeStyle,
            maxPreviewEdge: 1120
        ) {
            keystrokePreviewImage = res.image
            if !isDraggingKeystroke {
                keystrokePreviewNormRect = res.normalizedRectTopLeft
            }
        }
    }

    private func requestPreviewRender() {
        guard let gen = imageGenerator else { return }
        if isRenderingPreview {
            pendingPreviewRender = true
            return
        }
        isRenderingPreview = true
        pendingPreviewRender = false

        let outT = currentTime
        let totalOut = session.outputDuration
        let srcT = currentSourceTime
        let fadeAlpha = VideoTimelineMapper.fadeOpacity(atOutputTime: outT, totalDuration: totalOut, fade: session.fadeConfig)
        let playingNow = isPlaying
        var opts = VideoCompositeOptions(session: session, previewSampleKeystroke: nil)
        if !playingNow {
            opts.enableKeystrokes = false
        }
        let smoothed = smoothedCursorPath
        let exp = exporter
        let reusableRaw: CGImage? = (abs(srcT - cachedRawFrameTime) < 0.008) ? cachedRawFrameCG : nil
        let camGen = (opts.webcamPiP.enabled && opts.webcamVideoURL != nil) ? webcamImageGenerator : nil
        let reusableCam: CGImage? = (abs(srcT - cachedWebcamFrameTime) < 0.03) ? cachedWebcamFrameCG : nil

        Task.detached(priority: .userInitiated) {
            let rawFrame: CGImage?
            if let reusableRaw {
                rawFrame = reusableRaw
            } else {
                let cmTime = CMTime(seconds: srcT, preferredTimescale: 600)
                rawFrame = (try? await gen.image(at: cmTime))?.image
            }

            let camFrame: CGImage?
            if let camGen {
                if let reusableCam {
                    camFrame = reusableCam
                } else {
                    let cmTime = CMTime(seconds: srcT, preferredTimescale: 600)
                    camFrame = (try? await camGen.image(at: cmTime))?.image
                }
            } else {
                camFrame = nil
            }

            let rendered: CGImage?
            if let rawFrame {
                rendered = exp.renderPreviewFrame(
                    sourceCGImage: rawFrame,
                    time: srcT,
                    options: opts,
                    smoothedCursorPath: smoothed,
                    maxPreviewEdge: 1120,
                    fadeOpacity: fadeAlpha,
                    webcamCGImage: camFrame
                )
            } else {
                rendered = nil
            }
            await MainActor.run {
                if let rawFrame {
                    self.cachedRawFrameTime = srcT
                    self.cachedRawFrameCG = rawFrame
                }
                if let camFrame {
                    self.cachedWebcamFrameTime = srcT
                    self.cachedWebcamFrameCG = camFrame
                }
                if let rendered {
                    self.previewFrame = rendered
                }
                if !self.isPlaying {
                    self.refreshKeystrokeOverlayPreview()
                }
                self.isRenderingPreview = false
                if self.pendingPreviewRender {
                    self.requestPreviewRender()
                }
            }
        }
    }

    private func addZoomAt(sourceTime: Double) {
        pushUndoSnapshot()
        let cursor = AutoZoomEngine.sampleCursor(at: sourceTime, in: smoothedCursorPath)
        let start = max(0, sourceTime - 0.35)
        let end = min(session.duration, sourceTime + 1.8)
        let seg = ZoomSegment(
            startTime: start,
            endTime: max(start + 0.6, end),
            focusX: cursor?.x ?? 0.5,
            focusY: cursor?.y ?? 0.5,
            scale: 1.8,
            easeDuration: 0.4,
            followCursor: true,
            triggerKind: .manual
        )
        session.zoomSegments.append(seg)
        session.zoomSegments.sort { $0.startTime < $1.startTime }
        session.enableAutoZoom = true
        selectedClipID = nil
        selectedSegmentID = seg.id
        if let outT = VideoTimelineMapper.mapSourceTimeToOutput(sourceTime, clips: session.clipSegments) {
            currentTime = outT
        }
        requestPreviewRender()
    }

    private func regenerateAutoZooms() {
        pushUndoSnapshot()
        let generated = AutoZoomEngine.generateAutoZoomSegments(
            clicks: session.telemetry.clickEvents,
            typingEvents: session.telemetry.typingFocusEvents,
            includeClicks: session.includeClickZoom,
            includeTypingFocus: session.includeTypingFocusZoom,
            duration: session.duration
        )
        session.zoomSegments = generated
        session.enableAutoZoom = !generated.isEmpty
        selectedClipID = nil
        selectedSegmentID = generated.first?.id
        requestPreviewRender()
    }

    private func startExport() {
        stopPlayback()
        exportTask?.cancel()
        isExporting = true
        exportProgress = 0
        exportFPS = 0
        exportETA = 0
        exportError = nil

        let opts = VideoCompositeOptions(session: session)
        let ext = opts.exportPreset.isGIF ? "gif" : "mp4"
        let outURL = ExportHelpers.recordingsDirectory
            .appendingPathComponent(ExportHelpers.timestampedFilename(prefix: "XShot-Tweet", ext: ext))
        let srcURL = session.rawVideoURL
        let thumb = previewFrame

        exportTask = Task {
            do {
                let finalURL = try await exporter.exportVideoWithMetrics(
                    sourceURL: srcURL,
                    outputURL: outURL,
                    options: opts,
                    progressHandler: { update in
                        Task { @MainActor in
                            self.exportProgress = update.progress
                            if update.framesPerSecond > 0 {
                                self.exportFPS = update.framesPerSecond
                            }
                            self.exportETA = update.estimatedRemainingSeconds
                        }
                    }
                )
                let sizeBytes = (try? FileManager.default.attributesOfItem(atPath: finalURL.path)[.size] as? Int64) ?? 0
                let sizeMB = Double(sizeBytes) / (1024.0 * 1024.0)
                let sizeLabel = String(format: "%.2f MB · %@ · %dfps", sizeMB, ext.uppercased(), opts.exportPreset.isGIF ? 18 : opts.exportPreset.fps)

                await MainActor.run {
                    self.isExporting = false
                    self.exportedURL = finalURL
                    self.exportedFileSizeText = sizeLabel
                    self.session.lastExportedURL = finalURL
                    NSSound(named: NSSound.Name("Glass"))?.play()
                    self.onExportCompleted(finalURL, thumb)
                }
            } catch VideoExportError.cancelled {
                await MainActor.run {
                    self.isExporting = false
                }
            } catch {
                await MainActor.run {
                    self.isExporting = false
                    self.exportError = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Coordinate & UI Builders

    private func mapStagePointToSourceNormalized(
        _ pt: CGPoint,
        contentViewRect: CGRect,
        cropTopLeft: CGRect,
        sourceSize: CGSize
    ) -> (x: Double, y: Double) {
        let relX = min(max(Double((pt.x - contentViewRect.minX) / max(1, contentViewRect.width)), 0), 1)
        let relY = min(max(Double((pt.y - contentViewRect.minY) / max(1, contentViewRect.height)), 0), 1)
        let srcX = Double(cropTopLeft.origin.x) + relX * Double(cropTopLeft.width)
        let srcY = Double(cropTopLeft.origin.y) + relY * Double(cropTopLeft.height)
        return (
            x: min(max(srcX / max(1, Double(sourceSize.width)), 0.03), 0.97),
            y: min(max(srcY / max(1, Double(sourceSize.height)), 0.03), 0.97)
        )
    }

    private func groupedToolbarIcon(
        _ symbol: String,
        help: String,
        tint: Color? = nil,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        let fg = tint ?? palette.primaryText
        return Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(disabled ? palette.tertiaryText.opacity(0.6) : fg)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(TactilePillButtonStyle(
            background: .clear,
            hoverBackground: disabled ? .clear : palette.controlHoverFill,
            borderColor: .clear,
            cornerRadius: 5
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
            RoundedRectangle(cornerRadius: 11)
                .fill(palette.cardBackground)
                .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(palette.cardBorder, lineWidth: 0.8))
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
        let isSelected = (session.style.aspectRatio == ratio)
        return Button {
            session.style.aspectRatio = ratio
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

    private var shouldShowKeystrokeDragHandle: Bool {
        guard session.enableKeystrokes, !isPlaying else { return false }
        if showSampleKeystrokeInPreview { return true }
        return AutoZoomEngine.activeKeystroke(
            at: currentSourceTime,
            keystrokes: session.telemetry.keystrokeEvents,
            filterMode: session.keystrokeStyle.filterMode
        ) != nil
    }

    private func positionCell(_ pos: KeystrokePosition) -> some View {
        let isSelected = (session.keystrokeStyle.position == pos)
        return Button {
            session.keystrokeStyle.applyPresetPosition(pos)
        } label: {
            Text(pos.displayName)
                .font(.system(size: 10, weight: isSelected ? .bold : .medium))
                .foregroundStyle(isSelected ? palette.accentTextOnAccent : palette.secondaryText)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
        }
        .buttonStyle(TactilePillButtonStyle(
            background: isSelected ? palette.accent : palette.controlFill,
            hoverBackground: isSelected ? palette.accent.opacity(0.88) : palette.controlHoverFill,
            borderColor: isSelected ? .clear : palette.controlBorder,
            cornerRadius: 6
        ))
    }

    @ViewBuilder
    private func keystrokeMiniPreview(_ style: KeystrokeVisualStyle) -> some View {
        switch style {
        case .macKeycapDark:
            HStack(spacing: 3) {
                Text("⌘").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Color(white: 0.22), in: RoundedRectangle(cornerRadius: 4))
                Text("K").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Color(white: 0.22), in: RoundedRectangle(cornerRadius: 4))
            }
            .padding(.horizontal, 5).padding(.vertical, 3)
            .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 6))

        case .macKeycapLight:
            HStack(spacing: 3) {
                Text("⌘").font(.system(size: 9, weight: .bold)).foregroundStyle(.black)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 4))
                Text("K").font(.system(size: 9, weight: .bold)).foregroundStyle(.black)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 4))
            }
            .padding(.horizontal, 5).padding(.vertical, 3)
            .background(Color(white: 0.85), in: RoundedRectangle(cornerRadius: 6))

        case .minimalGlass:
            Text("⌘ K")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.65))
                        .overlay(Capsule().strokeBorder(.white.opacity(0.28), lineWidth: 0.8))
                )

        case .neonAccent:
            HStack(spacing: 3) {
                Text("⌘").font(.system(size: 9, weight: .bold)).foregroundStyle(.cyan)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Color(red: 0.11, green: 0.14, blue: 0.26), in: RoundedRectangle(cornerRadius: 4))
                Text("K").font(.system(size: 9, weight: .bold)).foregroundStyle(.cyan)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Color(red: 0.11, green: 0.14, blue: 0.26), in: RoundedRectangle(cornerRadius: 4))
            }
            .padding(.horizontal, 5).padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(red: 0.05, green: 0.06, blue: 0.12))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.cyan.opacity(0.8), lineWidth: 1))
            )
        }
    }

    private func specRow(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 14)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(palette.secondaryText)
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

    private func aspectFitRect(content: CGSize, inside container: CGRect) -> CGRect {
        let scale = min(container.width / max(1, content.width), container.height / max(1, content.height))
        let w = content.width * scale
        let h = content.height * scale
        return CGRect(x: container.midX - w / 2, y: container.midY - h / 2, width: w, height: h)
    }

    private func formatTime(_ s: Double) -> String {
        let total = max(0, s)
        let mins = Int(total) / 60
        let secs = Int(total) % 60
        let tenths = Int((total - floor(total)) * 10)
        return String(format: "%02d:%02d.%d", mins, secs, tenths)
    }

    private func formatSpeed(_ spd: Double) -> String {
        abs(spd - Double(Int(spd))) < 0.01 ? "\(Int(spd))x" : String(format: "%.1fx", spd)
    }

    private func sliderRow(title: String, value: Binding<CGFloat>, defaultValue: CGFloat, range: ClosedRange<CGFloat>, unit: String) -> some View {
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
                        value.wrappedValue = defaultValue
                    }
            }
            Slider(value: value, in: range)
                .tint(palette.accent)
        }
    }

    private func secondsSliderRow(title: String, value: Binding<Double>, defaultValue: Double, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.secondaryText)
                Spacer()
                Text(String(format: "%.1fs", value.wrappedValue))
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(value.wrappedValue > 0.01 ? palette.accent : palette.tertiaryText)
                    .frame(minWidth: 42)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(palette.controlFill, in: RoundedRectangle(cornerRadius: 5))
                    .contentShape(RoundedRectangle(cornerRadius: 5))
                    .onTapGesture(count: 2) {
                        value.wrappedValue = defaultValue
                    }
            }
            Slider(value: value, in: range, step: 0.1)
                .tint(palette.accent)
        }
    }
}

