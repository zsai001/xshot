import AppKit
import Combine
import CoreGraphics
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
public final class AppState: ObservableObject {
    public let permissions = PermissionManager()
    public let authManager: XTagsAuthManager
    public let updater: AppUpdaterManager
    public let store = StoreKitManager()
    private let hotKeyManager = HotKeyManager()
    private let selectionOverlay = SelectionOverlayController()
    private let recorder = ScreenRecorderEngine()
    private let recordingHUD = RecordingHUDController()
    private let recordingBorder = RecordingBorderOverlayController()
    private let quickOverlay = QuickOverlayController()
    private let ocrWindowController = OCRResultWindowController()
    private let scrollingCapture = ScrollingCaptureController()
    private let webcamRecorder = WebcamRecorderEngine()
    private let webcamBubble = WebcamPreviewBubbleController()
    private var pinnedControllers: [PinnedImageController] = []

    // Editor window references
    private var screenshotEditorWindow: NSWindow?
    private weak var currentEditorDocument: ScreenshotDocument?
    private var editorCloseObserver: NSObjectProtocol?
    private var videoStudioWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var loginWindow: NSWindow?
    private var paywallWindow: NSWindow?
    private var feedbackWindow: NSWindow?

    // Multi-image auto-collect mode state
    private var multiDocCancellable: AnyCancellable?
    private var languageCancellable: AnyCancellable?
    private var pasteboardWatchTimer: Timer?
    private var lastObservedPasteboardChangeCount: Int = 0
    private var isIngestingPasteboardImage: Bool = false

    // Preferences
    @Published public var targetFPS: Int = 60
    @Published public var captureSystemAudio: Bool = true
    @Published public var captureMicrophone: Bool = false
    @Published public var captureWebcamPiP: Bool = false
    @Published public var defaultWebcamPiP: WebcamPiPConfig = .default
    @Published public var defaultWatermark: WatermarkConfig = AppState.loadDefaultWatermark() {
        didSet { Self.saveDefaultWatermark(defaultWatermark) }
    }
    @Published public private(set) var hotKeyVersion: Int = 0
    @Published public var hideNativeCursorForSmooth: Bool = true
    @Published public var enableKeystrokesByDefault: Bool = AppDistribution.supportsAccessibilityFeatures
    @Published public var defaultKeystrokeStyle: KeystrokeStyleConfig = .default
    @Published public var enableTypingFocusZoom: Bool = AppDistribution.supportsAccessibilityFeatures
    @Published public var autoCopyScreenshot: Bool = true
    @Published public var autoBeautifyOnCapture: Bool = true
    @Published public var autoPrivacyRedactOnCapture: Bool = true
    @Published public var defaultPrivacyRedactionStyle: PrivacyRedactionStyle = .mosaic

    // Runtime state
    @Published public var isRecording: Bool = false
    @Published public var recordingElapsed: Double = 0
    @Published public var statusMessage: String?
    @Published public var recentItems: [CaptureHistoryItem] = []
    @Published public var clipboardImageSize: CGSize?
    @Published public private(set) var multiImageCollectMode: Bool = false
    @Published public private(set) var activeMultiImageDocument: ScreenshotDocument?
    @Published public private(set) var collectedMultiImageCount: Int = 0
    @Published public private(set) var multiImageNotificationID: UUID?
    @Published public private(set) var multiImageNotificationText: String?

    public func refreshClipboardStatus() {
        clipboardImageSize = ExportHelpers.pasteboardImageDimensions()
    }

    public init() {
        let auth = XTagsAuthManager()
        self.authManager = auth
        var safeToRelaunchProvider: (@MainActor () -> Bool)?
        self.updater = AppUpdaterManager(
            isSignedInProvider: { auth.isSignedIn },
            canAutoApplyImmediatelyProvider: { safeToRelaunchProvider?() ?? false }
        )
        safeToRelaunchProvider = { [weak self] in
            self?.isSafeForAutomaticRelaunch ?? false
        }
        auth.onAuthStateChanged = { [weak self] signedIn in
            self?.updater.handleAuthStateChanged(signedIn: signedIn)
        }

        recorder.onStatsUpdate = { [weak self] elapsed, frames in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.recordingElapsed = elapsed
                self.recordingHUD.update(elapsedSeconds: elapsed, frameCount: frames)
            }
        }
        recorder.onStreamError = { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isRecording = false
                self.recordingHUD.dismiss()
                self.recordingBorder.dismiss()
                self.webcamBubble.dismiss()
                _ = await self.webcamRecorder.stopRecording()
                self.showError(L10n.format(.errRecordingInterruptedFormat, error.localizedDescription))
            }
        }

        // Live-update native macOS window titles whenever the user switches app language!
        languageCancellable = ThemeLocaleStore.shared.$language
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.screenshotEditorWindow?.title = L10n.t(.windowTitleScreenshot)
                self.videoStudioWindow?.title = L10n.t(.windowTitleStudio)
                self.settingsWindow?.title = L10n.t(.windowTitleSettings)
                self.loginWindow?.title = L10n.t(.xtagsLoginWindowTitle)
                self.paywallWindow?.title = L10n.t(.iapWindowTitle)
                self.feedbackWindow?.title = L10n.t(.feedbackWindowTitle)
                self.ocrWindowController.refreshTitle()
            }

        hotKeyManager.registerDefaults { [weak self] action in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch action {
                case .captureArea:
                    self.startAreaScreenshot()
                case .captureWindow:
                    self.startWindowScreenshot()
                case .captureScroll:
                    self.startScrollingScreenshot()
                case .recordArea:
                    if !self.isRecording {
                        self.startAreaRecording()
                    }
                case .stopRecording:
                    if self.isRecording {
                        self.stopRecording()
                    }
                case .beautifyClipboard:
                    self.beautifyImageFromClipboard()
                case .extractTextArea:
                    self.startAreaTextExtraction()
                }
            }
        }
    }

    // MARK: - Customizable Global HotKeys & Default Watermark

    public func hotKeyBinding(for action: GlobalHotKeyAction) -> HotKeyBinding {
        _ = hotKeyVersion
        return hotKeyManager.binding(for: action)
    }

    public func hotKeyLabel(for action: GlobalHotKeyAction) -> String {
        _ = hotKeyVersion
        return hotKeyManager.label(for: action)
    }

    public func isHotKeyCustomized(_ action: GlobalHotKeyAction) -> Bool {
        _ = hotKeyVersion
        return hotKeyManager.isCustomized(action)
    }

    public var hasCustomHotKeys: Bool {
        _ = hotKeyVersion
        return hotKeyManager.hasAnyCustomization
    }

    @discardableResult
    public func updateHotKey(_ binding: HotKeyBinding, for action: GlobalHotKeyAction) -> HotKeyUpdateResult {
        let res = hotKeyManager.updateBinding(binding, for: action)
        if case .updated = res {
            hotKeyVersion &+= 1
        }
        return res
    }

    public func resetHotKey(for action: GlobalHotKeyAction) {
        hotKeyManager.resetBinding(for: action)
        hotKeyVersion &+= 1
    }

    public func resetAllHotKeys() {
        hotKeyManager.resetAllToDefaults()
        hotKeyVersion &+= 1
    }

    public func setHotKeysSuspended(_ suspended: Bool) {
        hotKeyManager.setSuspended(suspended)
    }

    public func makeDefaultScreenshotStyle() -> BeautifyStyle {
        var style = BeautifyStyle.defaultScreenshot
        style.watermark = defaultWatermark
        return style
    }

    public func makeDefaultVideoStyle() -> BeautifyStyle {
        var style = BeautifyStyle.defaultVideo
        style.watermark = defaultWatermark
        return style
    }

    private static let watermarkStorageKey = "xshot.defaultWatermark.v1"

    private static func loadDefaultWatermark() -> WatermarkConfig {
        guard let data = UserDefaults.standard.data(forKey: watermarkStorageKey),
              let decoded = try? JSONDecoder().decode(WatermarkConfig.self, from: data) else {
            return .default
        }
        return decoded
    }

    private static func saveDefaultWatermark(_ config: WatermarkConfig) {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: watermarkStorageKey)
        }
    }

    // MARK: - Screenshot Triggers

    public func startAreaScreenshot(fromMenuBar: Bool = false) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            // When clicked inside MenuBarView, wait 160ms for popover dismissal animation;
            // when triggered via global hotkey (⌘⇧2), freeze screen IMMEDIATELY (0ms) to trap open menus/popups!
            if fromMenuBar {
                try? await Task.sleep(nanoseconds: 160_000_000)
            }

            let frozenDisplays: [CGDirectDisplayID: CGImage]
            do {
                frozenDisplays = try await ScreenshotEngine.captureAllDisplaysFrozen()
                self.permissions.markScreenRecordingVerified()
            } catch {
                self.handleCaptureError(error)
                return
            }

            self.selectionOverlay.beginSelection(
                mode: .area,
                intent: .screenshot,
                frozenDisplays: frozenDisplays,
                onComplete: { [weak self] target in
                    Task { @MainActor [weak self] in
                        await self?.performScreenshot(target: target, frozenDisplays: frozenDisplays)
                    }
                },
                onCancel: {}
            )
        }
    }

    public func startWindowScreenshot(fromMenuBar: Bool = false) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if fromMenuBar {
                try? await Task.sleep(nanoseconds: 160_000_000)
            }

            // Snapshot BOTH the visible window Z-list and frozen full-Retina displays at t=0ms
            // so even transient menus, popovers, and dropdowns stay frozen & selectable!
            let windowSnapshot = SelectionOverlayController.enumerateVisibleWindows()
            let frozenDisplays: [CGDirectDisplayID: CGImage]
            do {
                frozenDisplays = try await ScreenshotEngine.captureAllDisplaysFrozen()
                self.permissions.markScreenRecordingVerified()
            } catch {
                self.handleCaptureError(error)
                return
            }

            self.selectionOverlay.beginSelection(
                mode: .window,
                intent: .screenshot,
                frozenDisplays: frozenDisplays,
                preEnumeratedWindows: windowSnapshot,
                onComplete: { [weak self] target in
                    Task { @MainActor [weak self] in
                        await self?.performScreenshot(
                            target: target,
                            frozenDisplays: frozenDisplays,
                            windowCandidates: windowSnapshot
                        )
                    }
                },
                onCancel: {}
            )
        }
    }

    /// Instant screen-region OCR: freezes screen at t=0ms, lets user drag-select any text area,
    /// extracts text via 100% on-device Apple Vision, auto-copies it to clipboard, and opens the OCR result window!
    public func startAreaTextExtraction(fromMenuBar: Bool = false) {
        guard requireProOrPrompt() else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            if fromMenuBar {
                try? await Task.sleep(nanoseconds: 160_000_000)
            }

            let frozenDisplays: [CGDirectDisplayID: CGImage]
            do {
                frozenDisplays = try await ScreenshotEngine.captureAllDisplaysFrozen()
                self.permissions.markScreenRecordingVerified()
            } catch {
                self.handleCaptureError(error)
                return
            }

            self.selectionOverlay.beginSelection(
                mode: .area,
                intent: .screenshot,
                frozenDisplays: frozenDisplays,
                onComplete: { [weak self] target in
                    Task { @MainActor [weak self] in
                        await self?.performAreaTextExtraction(target: target, frozenDisplays: frozenDisplays)
                    }
                },
                onCancel: {}
            )
        }
    }

    private func performAreaTextExtraction(
        target: SelectedCaptureTarget,
        frozenDisplays: [CGDirectDisplayID: CGImage]
    ) async {
        do {
            let rawCG: CGImage
            if case .area(let displayID, _, _, let displayLocalRect, _) = target,
               let frozen = frozenDisplays[displayID],
               let screen = NSScreen.screens.first(where: {
                   ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == displayID
               }) ?? NSScreen.main,
               let cropped = ScreenshotEngine.cropFrozenDisplayImage(
                   frozen,
                   displayLocalRect: displayLocalRect,
                   displayPointsSize: screen.frame.size
               ) {
                rawCG = cropped
            } else {
                rawCG = try await ScreenshotEngine.capture(target: target)
            }
            permissions.markScreenRecordingVerified()

            let ocrResult = await TextExtractionEngine.extractText(from: rawCG)
            let autoCopied = !ocrResult.isEmpty
            if autoCopied {
                ExportHelpers.copyTextToPasteboard(ocrResult.fullText)
                lastObservedPasteboardChangeCount = NSPasteboard.general.changeCount
                NSSound(named: NSSound.Name("Pop"))?.play()
            } else {
                NSSound.beep()
            }

            ocrWindowController.show(
                sourceImage: rawCG,
                result: ocrResult,
                autoCopied: autoCopied,
                onOpenBeautifyEditor: { [weak self] in
                    guard let self else { return }
                    let doc = ScreenshotDocument(
                        rawImage: rawCG,
                        style: self.makeDefaultScreenshotStyle(),
                        enableBeautify: self.autoBeautifyOnCapture
                    )
                    self.openScreenshotEditor(document: doc)
                }
            )
        } catch {
            handleCaptureError(error)
        }
    }

    /// Extracts text from an existing ScreenshotDocument (single image or multi-image collage) and opens the OCR result window.
    public func extractTextFromDocument(_ document: ScreenshotDocument) {
        let sourceImage: CGImage
        if document.isMultiImage,
           let comp = ScreenshotRenderer.renderMultiImageCompositeBase(
               images: document.collageImages.map(\.image),
               layoutMode: document.collageLayout,
               spacing: document.collageSpacing,
               fitMode: document.collageFitMode
           ) {
            sourceImage = comp
        } else {
            sourceImage = document.rawImage
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let ocrResult = await TextExtractionEngine.extractText(from: sourceImage)
            let autoCopied = !ocrResult.isEmpty
            if autoCopied {
                ExportHelpers.copyTextToPasteboard(ocrResult.fullText)
                self.lastObservedPasteboardChangeCount = NSPasteboard.general.changeCount
                NSSound(named: NSSound.Name("Pop"))?.play()
            } else {
                NSSound.beep()
            }
            self.ocrWindowController.show(
                sourceImage: sourceImage,
                result: ocrResult,
                autoCopied: autoCopied,
                onOpenBeautifyEditor: { [weak self] in
                    self?.openScreenshotEditor(document: document)
                }
            )
        }
    }

    /// Presents an already-computed OCR result in the dedicated floating OCR window without re-running Vision.
    public func presentOCRResultWindow(sourceImage: CGImage, result: TextExtractionResult, document: ScreenshotDocument) {
        ocrWindowController.show(
            sourceImage: sourceImage,
            result: result,
            autoCopied: false,
            onOpenBeautifyEditor: { [weak self] in
                self?.openScreenshotEditor(document: document)
            }
        )
    }

    /// Launches interactive Scrolling Long-Screenshot capture: user selects any scrollable area,
    /// smoothly scrolls (manually or via optional auto-scroll), and XShot stitches full-Retina frames in real time!
    public func startScrollingScreenshot(fromMenuBar: Bool = false) {
        guard requireProOrPrompt() else { return }
        guard !scrollingCapture.isActive else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            if fromMenuBar {
                try? await Task.sleep(nanoseconds: 160_000_000)
            }
            self.selectionOverlay.beginSelection(
                mode: .area,
                intent: .screenshot,
                onComplete: { [weak self] target in
                    Task { @MainActor [weak self] in
                        await self?.beginScrollingSession(target: target)
                    }
                },
                onCancel: {}
            )
        }
    }

    private func beginScrollingSession(target: SelectedCaptureTarget) async {
        do {
            try? await Task.sleep(nanoseconds: 90_000_000)
            let initialFrame = try await ScreenshotEngine.capture(target: target)
            permissions.markScreenRecordingVerified()
            scrollingCapture.begin(
                target: target,
                initialFrame: initialFrame,
                onComplete: { [weak self] stitchedImage in
                    Task { @MainActor [weak self] in
                        await self?.finalizeCapturedScreenshot(rawCG: stitchedImage)
                    }
                },
                onCancel: {}
            )
        } catch {
            handleCaptureError(error)
        }
    }

    public func captureFullscreenScreenshot() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? CGMainDisplayID()
        let quartzFrame = CoordinateConverter.appKitToQuartz(screen.frame)
        let target = SelectedCaptureTarget.display(
            displayID: displayID,
            quartzFrame: quartzFrame,
            scaleFactor: screen.backingScaleFactor
        )
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            await self?.performScreenshot(target: target)
        }
    }

    /// Enables or disables Multi-Image Auto-Collect Mode.
    /// While ON, every subsequent screenshot (⌘⇧2 / ⌘⇧6 / fullscreen), clipboard beautify (⌘⇧9),
    /// and newly copied external image/system clip automatically appends into the active multi-image board.
    public func setMultiImageCollectMode(_ enabled: Bool, attaching document: ScreenshotDocument? = nil) {
        if enabled && !requireProOrPrompt() { return }
        if enabled {
            multiImageCollectMode = true
            lastObservedPasteboardChangeCount = NSPasteboard.general.changeCount
            if let doc = document {
                setActiveMultiImageDocument(doc)
            } else if activeMultiImageDocument == nil,
                      screenshotEditorWindow?.isVisible == true,
                      let openDoc = currentEditorDocument {
                setActiveMultiImageDocument(openDoc)
            }
            startPasteboardWatcher()
        } else {
            multiImageCollectMode = false
            stopPasteboardWatcher()
            setActiveMultiImageDocument(nil)
        }
    }

    public func toggleMultiImageCollectMode(attaching document: ScreenshotDocument? = nil) {
        setMultiImageCollectMode(!multiImageCollectMode, attaching: document)
    }

    public func openActiveMultiImageEditor() {
        guard let doc = activeMultiImageDocument else { return }
        if let win = screenshotEditorWindow, win.isVisible, currentEditorDocument === doc {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        openScreenshotEditor(document: doc)
    }

    private func setActiveMultiImageDocument(_ doc: ScreenshotDocument?) {
        multiDocCancellable?.cancel()
        multiDocCancellable = nil
        activeMultiImageDocument = doc
        collectedMultiImageCount = doc?.collageImages.count ?? 0
        guard let doc else { return }
        multiDocCancellable = doc.$collageImages
            .receive(on: DispatchQueue.main)
            .sink { [weak self] items in
                self?.collectedMultiImageCount = items.count
            }
    }

    private func startPasteboardWatcher() {
        pasteboardWatchTimer?.invalidate()
        let timer = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pollPasteboardForMultiImageCollect()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pasteboardWatchTimer = timer
    }

    private func stopPasteboardWatcher() {
        pasteboardWatchTimer?.invalidate()
        pasteboardWatchTimer = nil
    }

    private func pollPasteboardForMultiImageCollect() {
        guard multiImageCollectMode, !isIngestingPasteboardImage else { return }
        let pb = NSPasteboard.general
        let current = pb.changeCount
        guard current != lastObservedPasteboardChangeCount else { return }
        lastObservedPasteboardChangeCount = current
        // Never ingest images copied by XShot itself (zero feedback loop!)
        if current == ExportHelpers.lastInternalPasteboardChangeCount { return }

        let images = ExportHelpers.readImagesFromPasteboard(pb, limit: 6)
        guard !images.isEmpty else { return }

        isIngestingPasteboardImage = true
        Task { @MainActor [weak self] in
            defer { self?.isIngestingPasteboardImage = false }
            await self?.ingestImagesIntoMultiImageCollection(images)
        }
    }

    private func renderDocumentPreview(_ doc: ScreenshotDocument) -> CGImage {
        if doc.isMultiImage {
            return ScreenshotRenderer.renderMultiImageScreenshot(
                images: doc.collageImages.map(\.image),
                layoutMode: doc.collageLayout,
                spacing: doc.collageSpacing,
                fitMode: doc.collageFitMode,
                annotations: doc.annotations,
                style: doc.style,
                enableBeautify: doc.enableBeautify
            ) ?? doc.rawImage
        }
        return ScreenshotRenderer.renderScreenshot(
            rawImage: doc.rawImage,
            annotations: doc.annotations,
            style: doc.style,
            enableBeautify: doc.enableBeautify
        ) ?? doc.rawImage
    }

    /// Appends one or more newly captured/copied images directly into the active multi-image board.
    @discardableResult
    public func ingestImagesIntoMultiImageCollection(_ rawImages: [CGImage], showOverlay: Bool = true) async -> ScreenshotDocument? {
        guard !rawImages.isEmpty else { return activeMultiImageDocument }

        var addedCount = 0
        var targetDoc = activeMultiImageDocument

        for rawCG in rawImages {
            var findings: [PrivacyFinding] = []
            var annotations: [AnnotationItem] = []
            if autoPrivacyRedactOnCapture {
                findings = await PrivacyRedactionEngine.detectSensitiveRegions(in: rawCG)
                annotations = findings.map { $0.makeAnnotation(style: defaultPrivacyRedactionStyle) }
            }

            if let existing = targetDoc {
                guard existing.collageImages.count < 6 else { break }
                let tileImage: CGImage
                if !annotations.isEmpty,
                   let baked = ScreenshotRenderer.renderAnnotatedRawImage(rawImage: rawCG, annotations: annotations) {
                    tileImage = baked
                } else {
                    tileImage = rawCG
                }
                if existing.appendCollageImage(tileImage, maxCount: 6) {
                    addedCount += 1
                }
            } else {
                let doc = ScreenshotDocument(
                    rawImage: rawCG,
                    style: .defaultScreenshot,
                    annotations: annotations,
                    enableBeautify: autoBeautifyOnCapture,
                    privacyFindings: findings
                )
                setActiveMultiImageDocument(doc)
                targetDoc = doc
                addedCount += 1
            }
        }

        guard let doc = targetDoc else { return nil }
        collectedMultiImageCount = doc.collageImages.count

        if addedCount == 0 {
            NSSound.beep()
            multiImageNotificationText = L10n.t(.multiCollectLimitReached)
            multiImageNotificationID = UUID()
            if showOverlay {
                let rendered = renderDocumentPreview(doc)
                showQuickScreenshotOverlay(document: doc, renderedImage: rendered)
            }
            return doc
        }

        let rendered = renderDocumentPreview(doc)
        if autoCopyScreenshot {
            ExportHelpers.copyImageToPasteboard(rendered)
            lastObservedPasteboardChangeCount = NSPasteboard.general.changeCount
        }
        if let savedURL = ExportHelpers.saveScreenshotQuickly(rendered) {
            doc.savedURL = savedURL
            addHistoryItem(
                kind: .screenshot,
                url: savedURL,
                thumbnail: NSImage(cgImage: rendered, size: NSSize(width: 240, height: 150)),
                title: savedURL.lastPathComponent
            )
        }

        NSSound(named: NSSound.Name("Pop"))?.play()
        multiImageNotificationText = L10n.format(.toastAppendedImagesFormat, addedCount, doc.collageImages.count)
        multiImageNotificationID = UUID()

        if showOverlay {
            showQuickScreenshotOverlay(document: doc, renderedImage: rendered)
        }
        return doc
    }

    /// Reads an image from the macOS clipboard (copied image or Finder image file) and opens
    /// it straight inside Screenshot Beautify Studio with beautification enabled!
    public func beautifyImageFromClipboard() {
        let images = ExportHelpers.readImagesFromPasteboard(limit: 6)
        guard let rawCG = images.first else {
            showError(L10n.t(.clipboardEmptyAlert))
            return
        }

        if multiImageCollectMode {
            Task { @MainActor [weak self] in
                await self?.ingestImagesIntoMultiImageCollection(images)
            }
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            var findings: [PrivacyFinding] = []
            var annotations: [AnnotationItem] = []
            if self.autoPrivacyRedactOnCapture {
                findings = await PrivacyRedactionEngine.detectSensitiveRegions(in: rawCG)
                annotations = findings.map { $0.makeAnnotation(style: self.defaultPrivacyRedactionStyle) }
            }

            let doc = ScreenshotDocument(
                rawImage: rawCG,
                extraImages: Array(images.dropFirst()),
                collageLayout: images.count >= 4 ? .grid2x2 : (images.count == 3 ? .bentoHero : .horizontal),
                style: .defaultScreenshot,
                annotations: images.count == 1 ? annotations : [],
                enableBeautify: true,
                privacyFindings: images.count == 1 ? findings : []
            )

            let rendered = self.renderDocumentPreview(doc)
            if let savedURL = ExportHelpers.saveScreenshotQuickly(rendered) {
                doc.savedURL = savedURL
                self.addHistoryItem(
                    kind: .screenshot,
                    url: savedURL,
                    thumbnail: NSImage(cgImage: rendered, size: NSSize(width: 240, height: 150)),
                    title: savedURL.lastPathComponent
                )
            }

            NSSound(named: NSSound.Name("Pop"))?.play()
            self.openScreenshotEditor(document: doc)
        }
    }

    /// Opens a multi-file picker so the user can select 2+ images and arrange them in a Bento collage
    /// (or append them directly into the active multi-image collection when Multi-Shot is ON).
    public func startMultiImageArrangement() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK else { return }

        let decoded: [CGImage] = panel.urls.prefix(6).compactMap { ExportHelpers.decodeNormalizedCGImage(from: $0) }
        guard let first = decoded.first else { return }

        if multiImageCollectMode {
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let doc = await self.ingestImagesIntoMultiImageCollection(decoded, showOverlay: false) {
                    self.openScreenshotEditor(document: doc)
                }
            }
            return
        }

        let extras = Array(decoded.dropFirst())
        let defaultLayout: MultiImageLayoutMode = {
            switch decoded.count {
            case 3: return .bentoHero
            case 4...: return .grid2x2
            default: return .horizontal
            }
        }()

        let doc = ScreenshotDocument(
            rawImage: first,
            extraImages: extras,
            collageLayout: defaultLayout,
            collageFitMode: decoded.count >= 3 ? .fill : .fit,
            collageSpacing: 24,
            style: makeDefaultScreenshotStyle(),
            annotations: [],
            enableBeautify: true
        )

        if let rendered = ScreenshotRenderer.renderMultiImageScreenshot(
            images: doc.collageImages.map(\.image),
            layoutMode: doc.collageLayout,
            spacing: doc.collageSpacing,
            fitMode: doc.collageFitMode,
            annotations: [],
            style: doc.style,
            enableBeautify: true
        ), let savedURL = ExportHelpers.saveScreenshotQuickly(rendered) {
            doc.savedURL = savedURL
            addHistoryItem(
                kind: .screenshot,
                url: savedURL,
                thumbnail: NSImage(cgImage: rendered, size: NSSize(width: 240, height: 150)),
                title: savedURL.lastPathComponent
            )
        }

        NSSound(named: NSSound.Name("Pop"))?.play()
        openScreenshotEditor(document: doc)
    }

    private func performScreenshot(
        target: SelectedCaptureTarget,
        frozenDisplays: [CGDirectDisplayID: CGImage] = [:],
        windowCandidates: [OnScreenWindowCandidate] = []
    ) async {
        do {
            let rawCG: CGImage
            switch target {
            case .area(let displayID, _, _, let displayLocalRect, _):
                if let frozen = frozenDisplays[displayID],
                   let screen = NSScreen.screens.first(where: {
                       ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == displayID
                   }) ?? NSScreen.main,
                   let cropped = ScreenshotEngine.cropFrozenDisplayImage(
                       frozen,
                       displayLocalRect: displayLocalRect,
                       displayPointsSize: screen.frame.size
                   ) {
                    rawCG = cropped
                } else {
                    rawCG = try await ScreenshotEngine.capture(target: target)
                }

            case .window(let windowID, _, _, let quartzFrame, _):
                let candidateLayer = windowCandidates.first(where: { $0.windowID == windowID })?.layer ?? 0
                if candidateLayer > 0,
                   let croppedPopup = ScreenshotEngine.cropFrozenWindow(from: frozenDisplays, quartzFrame: quartzFrame) {
                    // Popovers, dropdowns & floating menus look cleanest cropped from the t=0ms frozen screen
                    // (preserves glass vibrancy, avoids dark transparent margins, and never fails if popup closed!)
                    rawCG = croppedPopup
                } else if let liveWindow = try? await ScreenshotEngine.capture(target: target) {
                    rawCG = liveWindow
                } else if let croppedFallback = ScreenshotEngine.cropFrozenWindow(from: frozenDisplays, quartzFrame: quartzFrame) {
                    rawCG = croppedFallback
                } else {
                    rawCG = try await ScreenshotEngine.capture(target: target)
                }

            case .display:
                rawCG = try await ScreenshotEngine.capture(target: target)
            }
            permissions.markScreenRecordingVerified()
            await finalizeCapturedScreenshot(rawCG: rawCG)
        } catch {
            handleCaptureError(error)
        }
    }

    private func finalizeCapturedScreenshot(rawCG: CGImage) async {
        if multiImageCollectMode {
            await ingestImagesIntoMultiImageCollection([rawCG])
            return
        }

        var findings: [PrivacyFinding] = []
        var annotations: [AnnotationItem] = []
        if autoPrivacyRedactOnCapture {
            findings = await PrivacyRedactionEngine.detectSensitiveRegions(in: rawCG)
            annotations = findings.map { $0.makeAnnotation(style: defaultPrivacyRedactionStyle) }
        }

        let doc = ScreenshotDocument(
            rawImage: rawCG,
            style: makeDefaultScreenshotStyle(),
            annotations: annotations,
            enableBeautify: autoBeautifyOnCapture,
            privacyFindings: findings
        )

        // Render initial preview (with auto-redacted privacy boxes + beautify + default watermark!) & auto-save/copy for instant leak-proof X paste!
        let rendered = ScreenshotRenderer.renderScreenshot(
            rawImage: doc.rawImage,
            annotations: doc.annotations,
            style: doc.style,
            enableBeautify: doc.enableBeautify
        ) ?? rawCG

        if autoCopyScreenshot {
            ExportHelpers.copyImageToPasteboard(rendered)
        }
        if let savedURL = ExportHelpers.saveScreenshotQuickly(rendered) {
            doc.savedURL = savedURL
            addHistoryItem(
                kind: .screenshot,
                url: savedURL,
                thumbnail: NSImage(cgImage: rendered, size: NSSize(width: 240, height: 150)),
                title: savedURL.lastPathComponent
            )
        }

        NSSound(named: NSSound.Name("Pop"))?.play()
        showQuickScreenshotOverlay(document: doc, renderedImage: rendered)
    }

    // MARK: - Recording Triggers

    public func startAreaRecording() {
        guard !isRecording else { return }
        selectionOverlay.beginSelection(
            mode: .area,
            intent: .recording,
            onComplete: { [weak self] target in
                Task { @MainActor [weak self] in
                    await self?.beginRecording(target: target)
                }
            },
            onCancel: {}
        )
    }

    public func startWindowRecording() {
        guard !isRecording else { return }
        selectionOverlay.beginSelection(
            mode: .window,
            intent: .recording,
            onComplete: { [weak self] target in
                Task { @MainActor [weak self] in
                    await self?.beginRecording(target: target)
                }
            },
            onCancel: {}
        )
    }

    public func startFullscreenRecording() {
        guard !isRecording else { return }
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? CGMainDisplayID()
        let quartzFrame = CoordinateConverter.appKitToQuartz(screen.frame)
        let target = SelectedCaptureTarget.display(
            displayID: displayID,
            quartzFrame: quartzFrame,
            scaleFactor: screen.backingScaleFactor
        )
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            await self?.beginRecording(target: target)
        }
    }

    private func beginRecording(target: SelectedCaptureTarget) async {
        if captureMicrophone && !permissions.hasMicrophone {
            permissions.requestMicrophone()
        }

        let config = RecordingConfiguration(
            targetFPS: targetFPS,
            captureSystemAudio: captureSystemAudio,
            captureMicrophone: captureMicrophone,
            hideNativeCursor: hideNativeCursorForSmooth,
            enableKeystrokes: enableKeystrokesByDefault,
            keystrokeStyle: defaultKeystrokeStyle,
            enableTypingFocusZoom: enableTypingFocusZoom
        )

        // Present excluded border & HUD before starting ScreenCaptureKit so their window IDs are
        // double-excluded via both `sharingType = .none` and `SCContentFilter.excludingWindows`,
        // while keeping XShot's own Editor / Studio / Settings / Popover windows freely recordable!
        if captureWebcamPiP {
            if let camSession = await webcamRecorder.startRecording() {
                permissions.refresh()
                webcamBubble.show(session: camSession, config: defaultWebcamPiP)
            } else {
                permissions.refresh()
            }
        }

        recordingBorder.show(for: target)
        recordingHUD.show(
            targetFPS: targetFPS,
            onTogglePause: { [weak self] in
                let paused = self?.recorder.togglePause() ?? false
                self?.webcamRecorder.setPaused(paused)
                self?.recordingBorder.setPaused(paused)
                return paused
            },
            onStop: { [weak self] in
                self?.stopRecording()
            }
        )

        do {
            try await recorder.startRecording(target: target, configuration: config)
            permissions.markScreenRecordingVerified()
            isRecording = true
            recordingElapsed = 0
            statusMessage = L10n.format(.statusRecordingFormat, targetFPS)
        } catch {
            recordingHUD.dismiss()
            recordingBorder.dismiss()
            webcamBubble.dismiss()
            _ = await webcamRecorder.stopRecording()
            handleCaptureError(error)
        }
    }

    public func stopRecording() {
        guard isRecording else { return }
        recordingHUD.dismiss()
        recordingBorder.dismiss()
        webcamBubble.dismiss()
        isRecording = false
        statusMessage = L10n.t(.statusGeneratingStudio)

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let camURL = await self.webcamRecorder.stopRecording()
                let session = try await self.recorder.stopRecording()
                session.style.watermark = self.defaultWatermark
                if let camURL {
                    session.webcamVideoURL = camURL
                    var camCfg = self.defaultWebcamPiP
                    camCfg.enabled = true
                    session.webcamPiP = camCfg
                }
                self.statusMessage = nil
                self.openVideoStudio(session: session)
            } catch {
                self.statusMessage = nil
                self.showError(error.localizedDescription)
            }
        }
    }

    // MARK: - Editors & Overlays

    private func showQuickScreenshotOverlay(document: ScreenshotDocument, renderedImage: CGImage) {
        let isCollectingThis = multiImageCollectMode && (activeMultiImageDocument == nil || activeMultiImageDocument === document)
        quickOverlay.showScreenshot(
            image: renderedImage,
            fileURL: document.savedURL,
            copiedToClipboard: autoCopyScreenshot,
            isMultiImageCollectOn: isCollectingThis,
            collectedCount: document.collageImages.count,
            onCopy: { [weak self] in
                let latest = self?.renderDocumentPreview(document) ?? renderedImage
                ExportHelpers.copyImageToPasteboard(latest)
                if let self {
                    self.lastObservedPasteboardChangeCount = NSPasteboard.general.changeCount
                }
            },
            onEdit: { [weak self] in
                self?.openScreenshotEditor(document: document)
            },
            onPin: { [weak self] in
                let latest = self?.renderDocumentPreview(document) ?? renderedImage
                self?.pinImage(latest)
            },
            onReveal: {
                if let url = document.savedURL {
                    ExportHelpers.revealInFinder(url)
                }
            },
            onExtractText: { [weak self] in
                self?.extractTextFromDocument(document)
            },
            onToggleMultiCollect: { [weak self] in
                guard let self else { return }
                let nowOn = !(self.multiImageCollectMode && self.activeMultiImageDocument === document)
                self.setMultiImageCollectMode(nowOn, attaching: nowOn ? document : nil)
                NSSound(named: NSSound.Name("Pop"))?.play()
                let refreshed = self.renderDocumentPreview(document)
                self.showQuickScreenshotOverlay(document: document, renderedImage: refreshed)
            }
        )
    }

    public func showExportedVideoOverlay(url: URL, thumbnail: CGImage?) {
        addHistoryItem(
            kind: .video,
            url: url,
            thumbnail: thumbnail.map { NSImage(cgImage: $0, size: NSSize(width: 240, height: 150)) },
            title: url.lastPathComponent
        )
        quickOverlay.showExportedVideo(
            fileURL: url,
            thumbnail: thumbnail,
            onCopyFile: {
                ExportHelpers.copyFileURLToPasteboard(url)
            },
            onReveal: {
                ExportHelpers.revealInFinder(url)
            }
        )
    }

    public func openScreenshotEditor(document: ScreenshotDocument) {
        if let obs = editorCloseObserver {
            NotificationCenter.default.removeObserver(obs)
            editorCloseObserver = nil
        }
        if let existing = screenshotEditorWindow {
            existing.orderOut(nil)
            existing.contentView = nil
            screenshotEditorWindow = nil
        }

        currentEditorDocument = document
        if multiImageCollectMode {
            setActiveMultiImageDocument(document)
        }

        let editorView = ScreenshotEditorView(
            appState: self,
            document: document,
            defaultPrivacyStyle: defaultPrivacyRedactionStyle,
            autoPrivacyOnPaste: autoPrivacyRedactOnCapture,
            onSaved: { [weak self] url, img in
                self?.addHistoryItem(
                    kind: .screenshot,
                    url: url,
                    thumbnail: NSImage(cgImage: img, size: NSSize(width: 240, height: 150)),
                    title: url.lastPathComponent
                )
            },
            onPin: { [weak self] img in
                self?.pinImage(img)
            }
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1140, height: 750),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.title = L10n.t(.windowTitleScreenshot)
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.appearance = ThemeLocaleStore.shared.appearanceMode.nsAppearance
        window.backgroundColor = StudioPalette.dynamicToolbarNSColor
        window.minSize = NSSize(width: 940, height: 620)
        window.contentView = NSHostingView(rootView: editorView)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.screenshotEditorWindow = window

        let closedDocID = document.id
        editorCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.currentEditorDocument?.id == closedDocID {
                    self.currentEditorDocument = nil
                }
            }
        }
    }

    /// Opens any local `.mp4` / `.mov` video right inside XShot Studio for splitting, speed-ramping, framing & X export.
    public func openLocalVideoInStudio() {
        guard requireProOrPrompt() else { return }
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        guard panel.runModal() == .OK, let url = panel.url else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let session = try await RecordingSession.loadLocalVideo(url: url)
                session.style.watermark = self.defaultWatermark
                self.openVideoStudio(session: session)
            } catch {
                self.showError(error.localizedDescription)
            }
        }
    }

    public func openVideoStudio(session: RecordingSession) {
        if let existing = videoStudioWindow {
            existing.orderOut(nil)
            existing.contentView = nil
            videoStudioWindow = nil
        }

        let studioView = VideoStudioView(
            session: session,
            onExportCompleted: { [weak self] url, thumb in
                self?.showExportedVideoOverlay(url: url, thumbnail: thumb)
            },
            onKeystrokeStyleChanged: { [weak self] newStyle in
                self?.defaultKeystrokeStyle = newStyle
            },
            onSaveDefaultWatermark: { [weak self] wm in
                self?.defaultWatermark = wm
            },
            onFrameCaptured: { [weak self] url, img in
                self?.addHistoryItem(
                    kind: .screenshot,
                    url: url,
                    thumbnail: NSImage(cgImage: img, size: NSSize(width: 240, height: 150)),
                    title: url.lastPathComponent
                )
            }
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 790),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.title = L10n.t(.windowTitleStudio)
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.appearance = ThemeLocaleStore.shared.appearanceMode.nsAppearance
        window.backgroundColor = StudioPalette.dynamicToolbarNSColor
        window.minSize = NSSize(width: 980, height: 660)
        window.contentView = NSHostingView(rootView: studioView)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.videoStudioWindow = window
    }

    public var isSafeForAutomaticRelaunch: Bool {
        if isRecording { return false }
        if screenshotEditorWindow?.isVisible == true { return false }
        if videoStudioWindow?.isVisible == true { return false }
        return true
    }

    /// Starts background session validation, StoreKit 2 listener (MAS), and auto-update polling (Direct).
    public func startBackgroundServices() {
        if AppDistribution.usesStoreKitIAP {
            store.start()
        }
        guard AppDistribution.supportsSelfUpdate else { return }
        Task { @MainActor [weak self] in
            await self?.authManager.refreshSessionIfNeeded()
        }
        updater.startLifecycle()
    }

    @discardableResult
    public func requireProOrPrompt() -> Bool {
        if store.isProUnlocked {
            return true
        }
        openProPaywallWindow()
        return false
    }

    public func openProPaywallWindow() {
        if let existing = paywallWindow {
            if existing.isVisible {
                existing.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                return
            }
            existing.orderOut(nil)
            existing.contentView = nil
            paywallWindow = nil
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 560),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.title = L10n.t(.iapWindowTitle)
        window.appearance = ThemeLocaleStore.shared.appearanceMode.nsAppearance

        let view = XShotProPaywallView(
            store: store,
            onOpenBugFeedback: { [weak self] in
                self?.openBugFeedbackWindow()
            },
            onDismiss: { [weak window] in
                window?.orderOut(nil)
            }
        )
        let host = NSHostingController(rootView: view)
        host.view.layoutSubtreeIfNeeded()
        let fit = host.sizeThatFits(in: CGSize(width: 540, height: 780))
        window.setContentSize(NSSize(width: 540, height: max(460, ceil(fit.height))))
        window.contentViewController = host
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.paywallWindow = window
    }

    public func openBugFeedbackWindow() {
        if let existing = feedbackWindow {
            if existing.isVisible {
                existing.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                return
            }
            existing.orderOut(nil)
            existing.contentView = nil
            feedbackWindow = nil
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 470, height: 390),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.title = L10n.t(.feedbackWindowTitle)
        window.appearance = ThemeLocaleStore.shared.appearanceMode.nsAppearance

        let view = BugFeedbackSheetView(
            store: store,
            appVersion: updater.currentVersion.description,
            onDismiss: { [weak window] in
                window?.orderOut(nil)
            }
        )
        let host = NSHostingController(rootView: view)
        host.view.layoutSubtreeIfNeeded()
        let fit = host.sizeThatFits(in: CGSize(width: 470, height: 600))
        window.setContentSize(NSSize(width: 470, height: max(360, ceil(fit.height))))
        window.contentViewController = host
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.feedbackWindow = window
    }

    public func openXTagsLoginWindow() {
        if let existing = loginWindow {
            if existing.isVisible {
                existing.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                return
            }
            existing.orderOut(nil)
            existing.contentView = nil
            loginWindow = nil
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.title = L10n.t(.xtagsLoginWindowTitle)
        window.appearance = ThemeLocaleStore.shared.appearanceMode.nsAppearance

        let view = XTagsLoginSheetView(authManager: authManager) { [weak window] in
            window?.orderOut(nil)
        }
        let host = NSHostingController(rootView: view)
        host.view.layoutSubtreeIfNeeded()
        let fit = host.sizeThatFits(in: CGSize(width: 460, height: 600))
        window.setContentSize(NSSize(width: 460, height: max(280, ceil(fit.height))))
        window.contentViewController = host
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.loginWindow = window
    }

    public func openSettingsWindow() {
        if let existing = settingsWindow {
            if existing.isVisible {
                existing.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                return
            }
            existing.orderOut(nil)
            existing.contentView = nil
            settingsWindow = nil
        }

        let view = SettingsView(appState: self, permissions: permissions)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 720),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 540, height: 600)
        window.isReleasedWhenClosed = false
        window.title = L10n.t(.windowTitleSettings)
        window.appearance = ThemeLocaleStore.shared.appearanceMode.nsAppearance
        window.contentView = NSHostingView(rootView: view)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.settingsWindow = window
    }

    public func pinImage(_ cgImage: CGImage) {
        let controller = PinnedImageController(image: cgImage) { [weak self] closed in
            self?.pinnedControllers.removeAll { $0 === closed }
        }
        pinnedControllers.append(controller)
        controller.show()
    }

    // MARK: - Helpers

    private func addHistoryItem(kind: CaptureHistoryItem.MediaKind, url: URL, thumbnail: NSImage?, title: String) {
        let item = CaptureHistoryItem(kind: kind, fileURL: url, thumbnail: thumbnail, title: title)
        recentItems.insert(item, at: 0)
        if recentItems.count > 12 {
            recentItems = Array(recentItems.prefix(12))
        }
    }

    private func handleCaptureError(_ error: Error) {
        let nsErr = error as NSError
        let msg = error.localizedDescription.lowercased()
        let isPermissionError =
            nsErr.code == -3801 ||
            msg.contains("declined") ||
            msg.contains("permission") ||
            msg.contains("tcc") ||
            !CGPreflightScreenCaptureAccess()

        if isPermissionError {
            permissions.refresh()
            let alert = NSAlert()
            alert.messageText = L10n.t(.alertScreenPermTitle)
            alert.informativeText = L10n.t(.alertScreenPermBody)
            alert.addButton(withTitle: L10n.t(.openSystemSettings))
            alert.addButton(withTitle: L10n.t(.laterBtn))
            if alert.runModal() == .alertFirstButtonReturn {
                permissions.openScreenRecordingSettings()
            }
        } else {
            showError(error.localizedDescription)
        }
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.t(.alertNoticeTitle)
        alert.informativeText = message
        alert.addButton(withTitle: L10n.t(.okBtn))
        alert.runModal()
    }
}
