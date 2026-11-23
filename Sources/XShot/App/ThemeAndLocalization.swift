import AppKit
import Foundation
import SwiftUI

// MARK: - Appearance / Theme System

public enum AppAppearanceMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .system: return L10n.t(.themeSystem)
        case .light: return L10n.t(.themeLight)
        case .dark: return L10n.t(.themeDark)
        }
    }

    public var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    public var swiftUIColorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    public func resolvedColorScheme(environment: ColorScheme) -> ColorScheme {
        switch self {
        case .system: return environment
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// Adaptive high-craft color palette for Light & Dark Studio editors, popovers, overlays, and HUDs.
public struct StudioPalette: Sendable {
    public let isDark: Bool
    public let windowBackground: Color
    public let popoverBackground: Color
    public let toolbarBackground: Color
    public let inspectorBackground: Color
    public let timelineBackground: Color
    public let stageInner: Color
    public let stageOuter: Color
    public let cardBackground: Color
    public let cardBorder: Color
    public let divider: Color
    public let primaryText: Color
    public let secondaryText: Color
    public let tertiaryText: Color
    public let controlFill: Color
    public let controlHoverFill: Color
    public let controlBorder: Color
    public let trackFill: Color
    public let accent: Color
    public let accentTextOnAccent: Color
    public let accentSoftFill: Color
    public let accentHoverFill: Color
    public let accentBorder: Color
    public let hudSurface: Color
    public let hudBorder: Color
    public let shadowOpacity: Double

    public static func resolved(for scheme: ColorScheme) -> StudioPalette {
        scheme == .dark ? .dark : .light
    }

    public static func resolved(mode: AppAppearanceMode, environment: ColorScheme) -> StudioPalette {
        mode.resolvedColorScheme(environment: environment) == .dark ? .dark : .light
    }

    /// High-contrast elevated Dark Studio palette (crisp surface separation & WCAG-legible text).
    public static let dark = StudioPalette(
        isDark: true,
        windowBackground: Color(red: 0.082, green: 0.094, blue: 0.128),
        popoverBackground: Color(red: 0.105, green: 0.122, blue: 0.168),
        toolbarBackground: Color(red: 0.105, green: 0.120, blue: 0.162),
        inspectorBackground: Color(red: 0.098, green: 0.114, blue: 0.154),
        timelineBackground: Color(red: 0.105, green: 0.120, blue: 0.162),
        stageInner: Color(red: 0.125, green: 0.145, blue: 0.198),
        stageOuter: Color(red: 0.068, green: 0.078, blue: 0.110),
        cardBackground: Color(red: 0.148, green: 0.170, blue: 0.228),
        cardBorder: Color.white.opacity(0.16),
        divider: Color.white.opacity(0.14),
        primaryText: Color(red: 0.96, green: 0.975, blue: 0.995),
        secondaryText: Color(red: 0.78, green: 0.825, blue: 0.895),
        tertiaryText: Color(red: 0.60, green: 0.655, blue: 0.745),
        controlFill: Color.white.opacity(0.12),
        controlHoverFill: Color.white.opacity(0.21),
        controlBorder: Color.white.opacity(0.19),
        trackFill: Color.white.opacity(0.08),
        accent: Color(red: 0.22, green: 0.84, blue: 0.98),
        accentTextOnAccent: Color(red: 0.04, green: 0.08, blue: 0.12),
        accentSoftFill: Color(red: 0.22, green: 0.84, blue: 0.98).opacity(0.22),
        accentHoverFill: Color(red: 0.22, green: 0.84, blue: 0.98).opacity(0.33),
        accentBorder: Color(red: 0.22, green: 0.84, blue: 0.98).opacity(0.75),
        hudSurface: Color(red: 0.125, green: 0.148, blue: 0.205).opacity(0.97),
        hudBorder: Color.white.opacity(0.24),
        shadowOpacity: 0.58
    )

    public static let light = StudioPalette(
        isDark: false,
        windowBackground: Color(red: 0.94, green: 0.95, blue: 0.97),
        popoverBackground: Color(red: 0.965, green: 0.972, blue: 0.985),
        toolbarBackground: Color(red: 0.98, green: 0.985, blue: 0.995),
        inspectorBackground: Color(red: 0.955, green: 0.962, blue: 0.978),
        timelineBackground: Color(red: 0.98, green: 0.985, blue: 0.995),
        stageInner: Color(red: 0.93, green: 0.945, blue: 0.97),
        stageOuter: Color(red: 0.87, green: 0.895, blue: 0.935),
        cardBackground: Color.white,
        cardBorder: Color.black.opacity(0.09),
        divider: Color.black.opacity(0.10),
        primaryText: Color(red: 0.07, green: 0.09, blue: 0.14),
        secondaryText: Color(red: 0.28, green: 0.33, blue: 0.42),
        tertiaryText: Color(red: 0.46, green: 0.51, blue: 0.60),
        controlFill: Color.black.opacity(0.055),
        controlHoverFill: Color.black.opacity(0.11),
        controlBorder: Color.black.opacity(0.11),
        trackFill: Color.black.opacity(0.05),
        accent: Color(red: 0.01, green: 0.52, blue: 0.78),
        accentTextOnAccent: .white,
        accentSoftFill: Color(red: 0.01, green: 0.52, blue: 0.78).opacity(0.13),
        accentHoverFill: Color(red: 0.01, green: 0.52, blue: 0.78).opacity(0.21),
        accentBorder: Color(red: 0.01, green: 0.52, blue: 0.78).opacity(0.55),
        hudSurface: Color(red: 0.985, green: 0.99, blue: 1.0).opacity(0.97),
        hudBorder: Color.black.opacity(0.14),
        shadowOpacity: 0.22
    )

    public var nsWindowBackground: NSColor {
        isDark
            ? NSColor(red: 0.082, green: 0.094, blue: 0.128, alpha: 1)
            : NSColor(red: 0.94, green: 0.95, blue: 0.97, alpha: 1)
    }

    /// Dynamic NSColor matching `toolbarBackground` so macOS window titlebars seamlessly blend
    /// with the studio toolbar in both Light & Dark appearances without manual reload.
    public static var dynamicToolbarNSColor: NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark
                ? NSColor(red: 0.105, green: 0.120, blue: 0.162, alpha: 1)
                : NSColor(red: 0.98, green: 0.985, blue: 0.995, alpha: 1)
        }
    }
}

/// Shared reactive Appearance + Language store so every open window, popover, HUD, and overlay
/// updates LIVE in real time when the user switches Light/Dark/System or Language!
@MainActor
public final class ThemeLocaleStore: ObservableObject {
    public static let shared = ThemeLocaleStore()

    @Published public var appearanceMode: AppAppearanceMode {
        didSet {
            UserDefaults.standard.set(appearanceMode.rawValue, forKey: "xshot.appearanceMode")
            applyAppearanceToApp()
        }
    }

    @Published public var language: AppLanguage {
        didSet {
            L10n.currentLanguage = language
        }
    }

    private init() {
        if let rawTheme = UserDefaults.standard.string(forKey: "xshot.appearanceMode"),
           let mode = AppAppearanceMode(rawValue: rawTheme) {
            self.appearanceMode = mode
        } else {
            self.appearanceMode = .system
        }
        self.language = L10n.currentLanguage
    }

    public func applyAppearanceToApp() {
        let targetAppearance = appearanceMode.nsAppearance
        // CRITICAL: Keep NSApp.appearance = nil so macOS's NSStatusBarWindow (menu bar icon)
        // ALWAYS matches the actual macOS menu bar appearance (never inverted when XShot uses
        // a different Light/Dark theme than macOS!). Apply appearance only to XShot windows.
        NSApp?.appearance = nil
        for win in NSApp?.windows ?? [] {
            let className = String(describing: type(of: win))
            if className.contains("StatusBar") {
                win.appearance = nil
                continue
            }
            win.appearance = targetAppearance
        }
    }

    public func t(_ key: L10nKey) -> String {
        L10n.t(key, language: language)
    }

    public func format(_ key: L10nKey, _ args: CVarArg...) -> String {
        String(format: L10n.t(key, language: language), arguments: args)
    }
}

// MARK: - Multi-Language Localization Engine

public enum AppLanguage: String, CaseIterable, Identifiable, Codable, Sendable {
    case system
    case zhHans = "zh-Hans"
    case zhHant = "zh-Hant"
    case en
    case ja
    case ko
    case es
    case fr
    case de
    case pt
    case ru

    public var id: String { rawValue }

    public var nativeDisplayName: String {
        switch self {
        case .system: return L10n.t(.langSystem)
        case .zhHans: return "简体中文"
        case .zhHant: return "繁體中文"
        case .en: return "English"
        case .ja: return "日本語"
        case .ko: return "한국어"
        case .es: return "Español"
        case .fr: return "Français"
        case .de: return "Deutsch"
        case .pt: return "Português"
        case .ru: return "Русский"
        }
    }

    public var shortCode: String {
        switch self {
        case .system: return resolvedConcreteLanguage().shortCode
        case .zhHans: return "简"
        case .zhHant: return "繁"
        case .en: return "EN"
        case .ja: return "日"
        case .ko: return "한"
        case .es: return "ES"
        case .fr: return "FR"
        case .de: return "DE"
        case .pt: return "PT"
        case .ru: return "RU"
        }
    }

    public static let concreteLanguages: [AppLanguage] = [.zhHans, .zhHant, .en, .ja, .ko, .es, .fr, .de, .pt, .ru]

    public func resolvedConcreteLanguage(preferredLanguages: [String] = Locale.preferredLanguages) -> AppLanguage {
        if self != .system { return self }
        for code in preferredLanguages {
            let lower = code.lowercased()
            if lower.hasPrefix("zh-hant") || lower.hasPrefix("zh-tw") || lower.hasPrefix("zh-hk") || lower.hasPrefix("zh-mo") {
                return .zhHant
            }
            if lower.hasPrefix("zh") { return .zhHans }
            if lower.hasPrefix("ja") { return .ja }
            if lower.hasPrefix("ko") { return .ko }
            if lower.hasPrefix("es") { return .es }
            if lower.hasPrefix("fr") { return .fr }
            if lower.hasPrefix("de") { return .de }
            if lower.hasPrefix("pt") { return .pt }
            if lower.hasPrefix("ru") { return .ru }
            if lower.hasPrefix("en") { return .en }
        }
        return .en
    }
}

public enum L10nKey: String, CaseIterable, Sendable {
    // Theme & Language
    case themeSystem, themeLight, themeDark
    case langSystem
    case appearanceSection, appearanceMode, appLanguage

    // Menu Bar
    case appSubtitle, grantPermission, recordingBannerFormat
    case sectionScreenshot, sectionScreenshotMeta, sectionRecording, sectionRecordingMeta
    case areaScreenshot, windowScreenshot, fullscreenScreenshot
    case clipboardBeautifyTitle, clipboardBeautifyHint, clipboardReadyFormat, clipboardEmptyAlert
    case collageMenuTitle, collageMenuHint
    case areaRecording, windowRecording, fullscreenRecording, clickToStart
    case toggleSystemAudio, toggleMic, toggleKeystrokes, toggleTypingFocus, toggleSmoothCursor, toggleAutoBeautify, toggleAutoPrivacy
    case accessibilityHintBanner
    case recentWorks, dragToXHint, copyFile, revealInFinder
    case settingsAndPermissions, outputFolder, quitApp

    // Recording HUD & Selection Overlay
    case hudDone, hudPauseTooltip, hudResumeTooltip, hudStopTooltip
    case overlayHintRecording, overlayHintScreenshot, overlayHintWindow
    case overlayStartRecording, overlayCancel
    case overlayWindowRecordPrefix, overlayWindowShotPrefix

    // Quick Overlay
    case quickCopiedTitle, quickShotDoneTitle, quickVideoReadyTitle
    case quickDragToX, quickBeautifyEdit, quickRevealFinder, quickCopy, quickCopied, quickPin

    // Screenshot Editor
    case windowTitleScreenshot, windowTitleStudio, windowTitleSettings
    case toolSelect, toolArrow, toolRectangle, toolEllipse, toolHighlighter, toolText, toolStep, toolMosaic, toolBlur
    case undo, redo, deleteSelected, clearAll, pinAction, saveAction, copyForX
    case beautifyShell, quickPresets, presetAurora, presetDarkWindow, presetCleanLight, presetNeon, presetDarkGeek, presetNoFrame
    case backgroundWallpaper, wallpaperTabGradients, wallpaperTabSystem, wallpaperDesktopName, wallpaperPickLocal, wallpaperLoadingSystem
    case canvasAspectX, paddingAndDepth, paddingLabel, cornerRadiusLabel, shadowLabel
    case windowChromeTitle, chromeNone, chromeDark, chromeLight, windowTitlePlaceholder, glassStroke
    case addTextTitle, addTextPlaceholder, addAction, cancelAction
    case toastCopiedPNG, toastSavedPNG, dragMeToX
    case pasteFromClipboard, toastLoadedClipboardFormat, customColorTooltip
    case privacyCardTitle, privacyScanBtn, privacyScanFullBtn, privacyScanning, privacyClearAuto, privacyStyleLabel
    case privacyCatApiKey, privacyCatEmail, privacyCatPhone, privacyCatFinancialID, privacyCatIP
    case privacyDetectedCountFormat, privacyNoneDetected, privacyOnDeviceNote
    case collageCardTitle, collageCountBadgeFormat, collageAddFiles, collageAppendClipboard, collageDropHint
    case collageHorizontal, collageVertical, collageGrid, collageBento
    case collageFitContain, collageFitFill, collageSpacingLabel, toastAppendedImagesFormat
    case sliceCardTitle, slicePreset1x2, slicePreset2x1, slicePreset3x1, slicePreset2x2, slicePreset3x3
    case sliceRowsLabel, sliceColsLabel, sliceResetEqual, sliceScopeRaw, sliceScopeBeautified
    case sliceDragLineHint, sliceExportBtnFormat, sliceToCollageBtn, sliceExportToastFormat
    case multiCollectEnableBtn, multiCollectActiveTitle, multiCollectHintOff, multiCollectCountFormat
    case multiCollectBannerEmpty, multiCollectBannerCountFormat, multiCollectOpenEditor, multiCollectPickFiles, multiCollectStopBtn
    case multiCollectCardToggle, multiCollectCaptureOne, multiCollectLimitReached, multiCollectCanvasBannerFormat
    case quickMultiCollectTooltip, quickMultiCollectStopTooltip, quickMultiCollectTitleFormat, quickMultiArrangeFormat
    case openLocalVideoBtn, openLocalVideoHint
    case splitClipBtn, splitClipTooltip, setTrimInTooltip, setTrimOutTooltip, stepBackTooltip, stepForwardTooltip
    case deleteClipBtn, clipSelectedFormat, clipSpeedLabel
    case fadeCardTitle, fadeInLabel, fadeOutLabel, audioVolumeLabel
    case captureFrameBtn, captureFrameTooltip, captureFrameToast, clipTimelineTip
    case trackVideoLabel, trackZoomLabel, trackAudioLabel, snapToggleTooltip, timelineZoomFit
    case mergeNextClipBtn, duplicateZoomBtn, clearAllZoomsBtn, audioTrackMutedHint, audioTrackNoAudioHint, timelineShortcutsHint

    // Video Studio
    case exportMP4, exportGIF, exportDonePrefix, copyFileBtn, openFinderBtn, closeBtn
    case zoomTargetHint, zoomBadgeFormat, loadingMetalPreview
    case backToTrimStart, resetTrim, addZoomBtn, autoZoomSummaryFormat
    case zoomTimelineEmptyHint, zoomSegmentTyping, zoomSegmentClick, zoomScaleLabel, zoomEaseLabel, followCursorLabel, deleteAction
    case tabAppearance, tabMotionExport
    case cardSmartCamera, toggleAutoZoom, clickZoomCountFormat, typingZoomCountFormat
    case toggleVectorCursor, cursorSizeLabel, toggleClickRipples
    case cardKeystrokeStylePos, toggleShowKeystrokesFormat, previewSample, hideSample
    case keycapStyleLabel, displayPositionLabel, customPositionLabel, dragPositionHint, keycapSizeLabel
    case noKeystrokesCapturedHint
    case cardAudioTrack, toggleKeepAudio
    case cardEncodingPipeline, specZeroCopy, specConstant60, specRec709, specHighBitrate

    // Presets & Models
    case ratioAuto, ratio16x9, ratio4x3, ratio1x1, ratio9x16
    case ratioShortAuto, ratioShort16x9, ratioShort4x3, ratioShort1x1, ratioShort9x16
    case export1080pShort, export2KShort, export4KShort, exportGIFShort
    case ksStyleDark, ksStyleLight, ksStyleMinimal, ksStyleNeon
    case ksPosTopLeft, ksPosTopCenter, ksPosTopRight, ksPosBottomLeft, ksPosBottomCenter, ksPosBottomRight, ksPosCustom
    case ksFilterAll, ksFilterShortcutsOnly
    case hkAreaShot, hkWindowShot, hkRecordArea, hkStopRecord, hkClipboardBeautify

    // Settings
    case settingsPermissionsSection, permScreenTitle, permScreenSub, permMicTitle, permMicSub, permAxTitle, permAxSub
    case permGranted, permAuthorizeBtn, refreshPermissions
    case settingsDefaultsSection, defaultFPSLabel, fps60Label, fps120Label
    case defaultSysAudio, defaultMic, defaultKeystrokes, defaultKeystrokeStyle, defaultKeystrokePos, defaultKeystrokeFilter
    case defaultTypingZoom, defaultHideCursor, defaultAutoCopy, defaultAutoBeautify, defaultAutoPrivacy, defaultPrivacyStyle
    case settingsHotkeysSection, settingsPathsSection, screenshotsDirLabel, recordingsDirLabel, openDirBtn

    // Alerts, Errors & System Menus
    case alertScreenPermTitle, alertScreenPermBody, openSystemSettings, laterBtn, alertNoticeTitle, okBtn
    case quitXShotMenu, errRecordingInterruptedFormat, statusRecordingFormat, statusGeneratingStudio
    case errAlreadyRecording, errNotRecording, errDisplayNotFound, errWindowNotFound, errWindowNotFoundClosed
    case errWriterSetupFailedFormat, errNoFramesCaptured, errCaptureFailedFormat
    case errNoVideoTrack, errReadVideoFailedFormat, errWriteVideoFailedFormat, errRenderFrameFailed, errExportCancelled
    case errGIFInitFailed, errGIFWriteFailed
    case timelineZoomInTooltip, timelineZoomOutTooltip
    case hkExtractText, ocrMenuTitle, ocrMenuHint, ocrWindowTitle, ocrCardTitle, ocrExtractBtn, ocrScanning
    case ocrAutoCopiedBannerFormat, ocrStatsFormat, ocrNoTextFound, ocrModeKeepLines, ocrModeJoinParagraphs
    case ocrViewEditor, ocrViewLines, ocrCopyAllBtn, ocrCopiedToast, ocrCopiedLineToast
    case ocrCanvasOverlayToggle, ocrOpenEditorBtn, quickOCRTooltip
    // Customizable Hotkeys, Watermark Signature, Scrolling Capture & Webcam PiP
    case hkScrollShot, hkClickToRecordTooltip, hkPressKeysHint, hkNeedModifierHint, hkConflictFormat, hkResetSingleTooltip, hkResetAllBtn
    case watermarkCardTitle, watermarkTextPlaceholder, watermarkStyleGlass, watermarkStyleMinimal, watermarkStyleBadge, watermarkPosTiled
    case watermarkOpacityLabel, watermarkScaleLabel, watermarkBrandGlyph, watermarkSaveDefaultBtn, watermarkSavedDefaultToast, defaultWatermarkToggle
    case scrollMenuTitle, scrollMenuHint, scrollHudTitle, scrollHudHint, scrollFramesBadgeFormat
    case scrollAutoStartBtn, scrollAutoStopBtn, scrollManualAppendTooltip, scrollFinishBtn, scrollLimitReached
    case toggleWebcamPiP, defaultWebcamPiP, permCameraTitle, permCameraSub, webcamCardTitle
    case webcamShapeCircle, webcamShapeRounded, webcamShapeVertical, webcamSizeLabel, webcamMirrorLabel, webcamBorderLabel
    case webcamNoTrackHint, webcamAttachLocalBtn
    case viewModeFit, viewModeFitWidth, viewModeActual
    case viewModeFitTooltip, viewModeFitWidthTooltip, viewModeActualTooltip, viewZoomOutTooltip, viewZoomInTooltip
    // XTags Account Login & Seamless Auto-Updater
    case authErrInvalidToken, authErrUnauthorized, authErrServer
    case updErrInvalidRelease, updErrNoBinary, updErrChecksum, updErrSignature
    case xtagsAccountSection, xtagsSignInBtn, xtagsSignOutBtn, xtagsSignedOutHint, xtagsAutoUpdateBadge
    case xtagsLoginWindowTitle, xtagsLoginSubtitle, xtagsLoginStepBrowser, xtagsLoginOpenBrowserBtn, xtagsLoginWaitingHint
    case xtagsLoginTokenPlaceholder, xtagsLoginVerifyBtn, xtagsLoginVerifying, xtagsLoginSuccessFormat
    case updSectionTitle, updCurrentVersionFormat, updAutoToggleLabel, updAutoRequiresSignInHint
    case updCheckNowBtn, updChecking, updUpToDate, updAvailableFormat, updDownloadingFormat
    case updVerifying, updReadyFormat, updInstalling, updUpdateNowBtn, updRestartApplyBtn, updOpenReleasesBtn, updSeamlessNote
}

public enum L10n {
    private static let lock = NSLock()
    private static var currentOverride: AppLanguage = {
        if let raw = UserDefaults.standard.string(forKey: "xshot.language"),
           let lang = AppLanguage(rawValue: raw) {
            return lang
        }
        return .system
    }()

    public static var currentLanguage: AppLanguage {
        get {
            lock.lock()
            defer { lock.unlock() }
            return currentOverride
        }
        set {
            lock.lock()
            currentOverride = newValue
            lock.unlock()
            UserDefaults.standard.set(newValue.rawValue, forKey: "xshot.language")
        }
    }

    public static func t(_ key: L10nKey, language: AppLanguage? = nil) -> String {
        let lang = (language ?? currentLanguage).resolvedConcreteLanguage()
        return table[lang]?[key] ?? table[.en]?[key] ?? key.rawValue
    }

    public static func format(_ key: L10nKey, _ args: CVarArg...) -> String {
        String(format: t(key), arguments: args)
    }

    /// Full dictionaries for all 10 supported languages (validated by unit tests for 100% key & format coverage).
    public static let table: [AppLanguage: [L10nKey: String]] = [
        .zhHans: zhHansStrings,
        .zhHant: zhHantStrings,
        .en: enStrings,
        .ja: jaStrings,
        .ko: koStrings,
        .es: ExtraLanguagesCatalog.esStrings,
        .fr: ExtraLanguagesCatalog.frStrings,
        .de: ExtraLanguagesCatalog.deStrings,
        .pt: ExtraLanguagesCatalog.ptStrings,
        .ru: ExtraLanguagesCatalog.ruStrings
    ]

    // MARK: - 简体中文
    private static let zhHansStrings: [L10nKey: String] = [
        .themeSystem: "跟随系统", .themeLight: "浅色", .themeDark: "深色",
        .langSystem: "跟随系统",
        .appearanceSection: "外观与语言", .appearanceMode: "界面外观", .appLanguage: "显示语言",

        .appSubtitle: "Retina 截图 & 60fps 发推录屏", .grantPermission: "去授权", .recordingBannerFormat: "录制中 %@ · 点击停止并精修",
        .sectionScreenshot: "高清截图", .sectionScreenshotMeta: "Retina 2x · 自动复制", .sectionRecording: "丝滑录屏", .sectionRecordingMeta: "自动缩放 · X 专用 MP4",
        .areaScreenshot: "区域截图", .windowScreenshot: "窗口截图", .fullscreenScreenshot: "全屏截图",
        .clipboardBeautifyTitle: "从剪贴板美化图片", .clipboardBeautifyHint: "读取已复制图片直接美化", .clipboardReadyFormat: "已检测到图片 · %d×%d", .clipboardEmptyAlert: "剪贴板中没有可用图片，请先复制图片、截图或在访达中复制图片文件后再试。",
        .collageMenuTitle: "多图排列", .collageMenuHint: "多张截图自由拼图美化",
        .areaRecording: "区域录屏", .windowRecording: "窗口录屏", .fullscreenRecording: "全屏录屏", .clickToStart: "点击启动",
        .toggleSystemAudio: "系统音频", .toggleMic: "麦克风", .toggleKeystrokes: "按键提示", .toggleTypingFocus: "输入焦点放大", .toggleSmoothCursor: "丝滑矢量光标", .toggleAutoBeautify: "截图自动美化", .toggleAutoPrivacy: "隐私自动打码",
        .accessibilityHintBanner: "开启「辅助功能」以启用全局按键提示与精准输入焦点放大",
        .recentWorks: "最近作品", .dragToXHint: "可拖拽直发推文", .copyFile: "复制文件", .revealInFinder: "在访达中查看",
        .settingsAndPermissions: "设置与权限", .outputFolder: "输出目录", .quitApp: "退出",

        .hudDone: "完成", .hudPauseTooltip: "暂停录制", .hudResumeTooltip: "继续录制", .hudStopTooltip: "停止录制并进入 Video Studio (⌘⇧8)",
        .overlayHintRecording: "拖动框选录屏区域（选完可拖动微调 / 锁 16:9） · Esc 取消",
        .overlayHintScreenshot: "拖动框选 Retina 高清截图区域 · 松开即刻出图 · Esc 取消",
        .overlayHintWindow: "移动鼠标高亮目标窗口并点击 · Esc 取消",
        .overlayStartRecording: "⏺ 开始录制 (Enter)", .overlayCancel: "取消",
        .overlayWindowRecordPrefix: "点击录制窗口 · ", .overlayWindowShotPrefix: "点击截图窗口 · ",

        .quickCopiedTitle: "已复制到剪贴板 · 可直接 ⌘V", .quickShotDoneTitle: "Retina 截图完成", .quickVideoReadyTitle: "%@ 已就绪 · 拖入 X 发推",
        .quickDragToX: "拖拽发推", .quickBeautifyEdit: "美化 / 标注", .quickRevealFinder: "访达定位", .quickCopy: "复制", .quickCopied: "已复制", .quickPin: "置顶贴图",

        .windowTitleScreenshot: "XShot · 截图美化与标注", .windowTitleStudio: "XShot Studio · 推文高清视频精修", .windowTitleSettings: "XShot 设置与权限",
        .toolSelect: "选择", .toolArrow: "箭头", .toolRectangle: "矩形", .toolEllipse: "椭圆", .toolHighlighter: "高亮", .toolText: "文字", .toolStep: "序号", .toolMosaic: "马赛克", .toolBlur: "模糊",
        .undo: "撤销 (⌘Z)", .redo: "重做 (⌘⇧Z)", .deleteSelected: "删除选中标注", .clearAll: "清空全部标注", .pinAction: "贴图", .saveAction: "保存", .copyForX: "复制发推",
        .beautifyShell: "推文美化外壳", .quickPresets: "一键预设", .presetAurora: "推文极光", .presetDarkWindow: "暗黑窗口", .presetCleanLight: "纯净白卡", .presetNeon: "推文霓虹", .presetDarkGeek: "暗黑极客", .presetNoFrame: "极简无壳",
        .backgroundWallpaper: "背景壁纸", .wallpaperTabGradients: "精选渐变", .wallpaperTabSystem: "系统壁纸", .wallpaperDesktopName: "当前桌面", .wallpaperPickLocal: "自选图片…", .wallpaperLoadingSystem: "正在加载 macOS 壁纸…",
        .canvasAspectX: "画布比例（X 信息流）", .paddingAndDepth: "边距与立体感", .paddingLabel: "外边距", .cornerRadiusLabel: "圆角半径", .shadowLabel: "立体阴影",
        .windowChromeTitle: "macOS 窗口标题栏", .chromeNone: "无标题栏", .chromeDark: "深色顶栏", .chromeLight: "浅色顶栏", .windowTitlePlaceholder: "可选：窗口标题（如 XShot Demo）", .glassStroke: "玻璃高光内描边",
        .addTextTitle: "添加文字标注", .addTextPlaceholder: "输入要显示的标注文字…", .addAction: "添加", .cancelAction: "取消",
        .toastCopiedPNG: "已复制 Retina PNG · ⌘V 发推", .toastSavedPNG: "已保存到 ~/Pictures/XShot", .dragMeToX: "拖我直发 X",
        .pasteFromClipboard: "从剪贴板读取图片 (⌘⇧9)", .toastLoadedClipboardFormat: "已读取剪贴板图片 · %d×%d", .customColorTooltip: "自定义颜色（打开系统调色盘）",
        .privacyCardTitle: "隐私检测与自动打码", .privacyScanBtn: "隐私打码", .privacyScanFullBtn: "扫描并自动打码", .privacyScanning: "正在本地识别隐私…", .privacyClearAuto: "清除", .privacyStyleLabel: "打码样式",
        .privacyCatApiKey: "密钥/Token", .privacyCatEmail: "邮箱", .privacyCatPhone: "手机号", .privacyCatFinancialID: "卡号/证件", .privacyCatIP: "IP 地址",
        .privacyDetectedCountFormat: "已自动打码 %d 处隐私", .privacyNoneDetected: "未检测到敏感隐私信息", .privacyOnDeviceNote: "100% 本地 Vision OCR 识别 · 绝不上传云端",
        .collageCardTitle: "多图排列", .collageCountBadgeFormat: "%d 张", .collageAddFiles: "添加图片", .collageAppendClipboard: "剪贴板追加", .collageDropHint: "支持直接拖入多张图片到左侧画布",
        .collageHorizontal: "横排", .collageVertical: "竖排", .collageGrid: "宫格", .collageBento: "焦点",
        .collageFitContain: "完整显示", .collageFitFill: "铺满对齐", .collageSpacingLabel: "图间距", .toastAppendedImagesFormat: "已加入 %d 张图片 · 共 %d 张",
        .sliceCardTitle: "单图切割", .slicePreset1x2: "左右2切", .slicePreset2x1: "上下2切", .slicePreset3x1: "长图3切", .slicePreset2x2: "四宫格", .slicePreset3x3: "九宫格",
        .sliceRowsLabel: "行", .sliceColsLabel: "列", .sliceResetEqual: "均分", .sliceScopeRaw: "仅切图片", .sliceScopeBeautified: "含美化背景",
        .sliceDragLineHint: "拖动画面中的虚线可自由微调切割位置", .sliceExportBtnFormat: "切割并导出 %d 张 PNG", .sliceToCollageBtn: "转为多图排列", .sliceExportToastFormat: "已切分导出 %d 张 PNG · 已复制文件",
        .multiCollectEnableBtn: "开启多图", .multiCollectActiveTitle: "多图已开启", .multiCollectHintOff: "后续截图自动放入", .multiCollectCountFormat: "已收 %d/6 张",
        .multiCollectBannerEmpty: "多图已开启 · 后续截图或复制图片自动加入", .multiCollectBannerCountFormat: "多图收集 · 已收 %d/6 张（截图自动加入）", .multiCollectOpenEditor: "编排", .multiCollectPickFiles: "选图", .multiCollectStopBtn: "结束",
        .multiCollectCardToggle: "开启多图 · 后续截图自动放进来", .multiCollectCaptureOne: "截一张", .multiCollectLimitReached: "多图画板已满（最多 6 张）", .multiCollectCanvasBannerFormat: "多图已开启 (%d/6) · 后续截图或复制图片自动放入",
        .quickMultiCollectTooltip: "开启多图：后续截图自动合并进来", .quickMultiCollectStopTooltip: "结束多图自动收集", .quickMultiCollectTitleFormat: "多图已收 %d/6 张 · 继续截图自动加入", .quickMultiArrangeFormat: "编排 (%d)",
        .openLocalVideoBtn: "剪辑本地视频", .openLocalVideoHint: "导入 MP4 / MOV 剪辑、变速与美化",
        .splitClipBtn: "分割", .splitClipTooltip: "在当前播放头分割片段 (S)", .setTrimInTooltip: "将播放头设为起点 (I)", .setTrimOutTooltip: "将播放头设为终点 (O)", .stepBackTooltip: "后退 0.1 秒 (←)", .stepForwardTooltip: "前进 0.1 秒 (→)",
        .deleteClipBtn: "删除片段", .clipSelectedFormat: "片段 #%d", .clipSpeedLabel: "倍速",
        .fadeCardTitle: "淡入淡出", .fadeInLabel: "片头淡入", .fadeOutLabel: "片尾淡出", .audioVolumeLabel: "音量增益",
        .captureFrameBtn: "截帧", .captureFrameTooltip: "截取当前美化画面作为封面并复制", .captureFrameToast: "已截取当前高清封面并复制到剪贴板", .clipTimelineTip: "点片段可调倍速/删除 · S 分割 · 拖拽缩放块边缘调时长",
        .trackVideoLabel: "视频", .trackZoomLabel: "缩放", .trackAudioLabel: "音频", .snapToggleTooltip: "磁吸对齐（自动吸附播放头与切点）", .timelineZoomFit: "适应",
        .mergeNextClipBtn: "合并", .duplicateZoomBtn: "复制", .clearAllZoomsBtn: "清空缩放", .audioTrackMutedHint: "音轨已静音（点击左侧恢复）", .audioTrackNoAudioHint: "当前视频未包含音轨", .timelineShortcutsHint: "Space 播放 · S 分割 · I/O 裁首尾 · ←/→ 微调 · ⌘Z 撤销 · 双击缩放轨新增缩放",

        .exportMP4: "导出发推 MP4", .exportGIF: "导出 GIF", .exportDonePrefix: "导出完成 · ", .copyFileBtn: "复制文件", .openFinderBtn: "访达打开", .closeBtn: "关闭",
        .zoomTargetHint: "点击画面可直接指定缩放焦点", .zoomBadgeFormat: "缩放 %.2fx", .loadingMetalPreview: "正在初始化 Metal GPU 预览…",
        .backToTrimStart: "回到裁剪起点", .resetTrim: "重置裁剪", .addZoomBtn: "添加缩放", .autoZoomSummaryFormat: "自动缩放 (%d点击 · %d输入)",
        .zoomTimelineEmptyHint: "双击此轨道添加缩放片段 · 录屏点击/打字会自动生成", .zoomSegmentTyping: "输入焦点缩放", .zoomSegmentClick: "点击缩放片段", .zoomScaleLabel: "倍率", .zoomEaseLabel: "缓动", .followCursorLabel: "跟随光标", .deleteAction: "删除",
        .tabAppearance: "画面外观", .tabMotionExport: "镜头与导出",
        .cardSmartCamera: "智能镜头与焦点放大", .toggleAutoZoom: "启用平滑自动缩放", .clickZoomCountFormat: "点击放大 (%d)", .typingZoomCountFormat: "输入焦点放大 (%d)",
        .toggleVectorCursor: "丝滑定制矢量光标", .cursorSizeLabel: "光标大小", .toggleClickRipples: "点击波纹高亮",
        .cardKeystrokeStylePos: "按键提示 · 样式与位置", .toggleShowKeystrokesFormat: "显示按键提示 (%d条)", .previewSample: "预览", .hideSample: "隐藏示例",
        .keycapStyleLabel: "键帽样式", .displayPositionLabel: "显示位置", .customPositionLabel: "自定义", .dragPositionHint: "支持在左侧预览画面中直接鼠标拖拽定位", .keycapSizeLabel: "键帽大小",
        .noKeystrokesCapturedHint: "本次录制未捕获到键盘事件。请在「系统设置 → 隐私与安全性 → 辅助功能」勾选 XShot 后再录屏即可自动记录按键。",
        .cardAudioTrack: "音频轨", .toggleKeepAudio: "保留录制音频（系统音 + 麦）",
        .cardEncodingPipeline: "极速零拷贝编码管线", .specZeroCopy: "Metal GPU + IOSurface 零拷贝合成", .specConstant60: "恒定 60fps · VideoToolbox 硬件 H.264", .specRec709: "Rec.709 sRGB 防 X 上传偏色", .specHighBitrate: "18~42 Mbps 高码率抗二次压缩",

        .ratioAuto: "自适应", .ratio16x9: "16:9 推文横屏", .ratio4x3: "4:3 推文卡片", .ratio1x1: "1:1 正方形", .ratio9x16: "9:16 竖屏",
        .ratioShortAuto: "原比例", .ratioShort16x9: "横屏", .ratioShort4x3: "卡片", .ratioShort1x1: "方形", .ratioShort9x16: "竖屏",
        .export1080pShort: "1080p 60fps (X 推荐)", .export2KShort: "2K 60fps (超清)", .export4KShort: "4K 60fps (极致)", .exportGIFShort: "GIF 动图",
        .ksStyleDark: "深色键帽", .ksStyleLight: "浅色键帽", .ksStyleMinimal: "极简胶囊", .ksStyleNeon: "霓虹边框",
        .ksPosTopLeft: "左上", .ksPosTopCenter: "顶中", .ksPosTopRight: "右上", .ksPosBottomLeft: "左下", .ksPosBottomCenter: "底中", .ksPosBottomRight: "右下", .ksPosCustom: "自定义拖拽",
        .ksFilterAll: "快捷键 + 打字", .ksFilterShortcutsOnly: "仅快捷键",
        .hkAreaShot: "区域截图", .hkWindowShot: "窗口截图", .hkRecordArea: "区域录屏", .hkStopRecord: "停止录屏", .hkClipboardBeautify: "从剪贴板美化图片",

        .settingsPermissionsSection: "系统权限状态", .permScreenTitle: "屏幕录制（必须）", .permScreenSub: "用于 ScreenCaptureKit 原生 Retina 截图与 60fps 录屏",
        .permMicTitle: "麦克风（可选）", .permMicSub: "录制讲解配音时启用",
        .permAxTitle: "辅助功能（按键提示 + 输入焦点放大）", .permAxSub: "用于捕获全局按键提示及追踪文本光标位置自动放大",
        .permGranted: "已授权", .permAuthorizeBtn: "去授权", .refreshPermissions: "刷新权限状态",
        .settingsDefaultsSection: "录制与截图默认项", .defaultFPSLabel: "默认录屏帧率", .fps60Label: "60 fps（推荐 · 流畅省体积）", .fps120Label: "120 fps（ProMotion 超丝滑）",
        .defaultSysAudio: "默认录制系统音频（免黑洞驱动）", .defaultMic: "默认录制麦克风", .defaultKeystrokes: "默认启用按键提示（实体键帽 + 打字气泡）",
        .defaultKeystrokeStyle: "默认按键样式", .defaultKeystrokePos: "默认按键位置", .defaultKeystrokeFilter: "按键显示范围",
        .defaultTypingZoom: "默认启用输入焦点自动放大", .defaultHideCursor: "录制时隐藏系统光标（使用 Studio 丝滑矢量光标）",
        .defaultAutoCopy: "截图完成后自动复制到剪贴板", .defaultAutoBeautify: "截图自动套用发推美化背景", .defaultAutoPrivacy: "截图/剪贴板载入时自动检测并打码隐私（密钥/邮箱/手机/IP）", .defaultPrivacyStyle: "默认打码样式",
        .settingsHotkeysSection: "全局快捷键", .settingsPathsSection: "默认输出路径", .screenshotsDirLabel: "截图目录", .recordingsDirLabel: "视频目录", .openDirBtn: "打开",

        .alertScreenPermTitle: "需要“屏幕与系统录音”权限",
        .alertScreenPermBody: "请在「系统设置 → 隐私与安全性 → 屏幕与系统录音」中确认已勾选 XShot（如曾授权旧版本，请先点减号「-」移除再重新添加）。授权后重启一次 XShot 即永久生效。",
        .openSystemSettings: "打开系统设置", .laterBtn: "稍后", .alertNoticeTitle: "XShot 提示", .okBtn: "好",
        .quitXShotMenu: "退出 XShot", .errRecordingInterruptedFormat: "录屏意外中断：%@", .statusRecordingFormat: "正在以 %dfps 高清录制…", .statusGeneratingStudio: "正在生成 Studio 时间轴与自动缩放…",
        .errAlreadyRecording: "当前已经在录制中。", .errNotRecording: "当前没有进行中的录制。", .errDisplayNotFound: "未找到目标显示器。", .errWindowNotFound: "未找到目标窗口。", .errWindowNotFoundClosed: "未找到目标窗口，窗口可能已关闭或最小化。",
        .errWriterSetupFailedFormat: "初始化录屏编码器失败：%@", .errNoFramesCaptured: "未捕获到有效视频帧，请检查系统屏幕录制权限。", .errCaptureFailedFormat: "截图失败：%@",
        .errNoVideoTrack: "录制文件中未找到视频轨道。", .errReadVideoFailedFormat: "无法读取原始录制视频：%@", .errWriteVideoFailedFormat: "无法创建导出视频：%@", .errRenderFrameFailed: "视频帧合成失败。", .errExportCancelled: "导出已取消。",
        .errGIFInitFailed: "无法初始化 GIF 输出文件。", .errGIFWriteFailed: "GIF 写入失败。",
        .timelineZoomInTooltip: "放大时间轴 (⌘+)", .timelineZoomOutTooltip: "缩小时间轴 (⌘-)",
        .hkExtractText: "截图提取文字 (OCR)", .ocrMenuTitle: "截图提取文字", .ocrMenuHint: "框选屏幕秒提文字并自动复制", .ocrWindowTitle: "XShot · 文字提取 (OCR)", .ocrCardTitle: "提取文字 (OCR)", .ocrExtractBtn: "提取图中文字", .ocrScanning: "本地识别文字中…",
        .ocrAutoCopiedBannerFormat: "已自动复制 · %d 行 · %d 字", .ocrStatsFormat: "%d 行 · %d 字", .ocrNoTextFound: "未在图片中识别到文字", .ocrModeKeepLines: "保留换行", .ocrModeJoinParagraphs: "合并段落",
        .ocrViewEditor: "文本编辑", .ocrViewLines: "逐行复制", .ocrCopyAllBtn: "复制全部文字", .ocrCopiedToast: "已复制文字到剪贴板", .ocrCopiedLineToast: "已复制该行文字",
        .ocrCanvasOverlayToggle: "画布文字框（点击单行即复制）", .ocrOpenEditorBtn: "进入美化编辑", .quickOCRTooltip: "提取图中文字 (OCR)",
        .hkScrollShot: "滚屏长截图", .hkClickToRecordTooltip: "点击录制自定义快捷键", .hkPressKeysHint: "请按快捷键… (Esc取消)", .hkNeedModifierHint: "请至少包含 ⌘ / ⌥ / ⌃ 修饰键或使用 F1–F12", .hkConflictFormat: "快捷键 %@ 已被「%@」占用", .hkResetSingleTooltip: "恢复此快捷键默认设置", .hkResetAllBtn: "恢复全部默认快捷键",
        .watermarkCardTitle: "自定义水印签名", .watermarkTextPlaceholder: "输入签名或 X 账号（如 @yourname）", .watermarkStyleGlass: "毛玻璃", .watermarkStyleMinimal: "极简字", .watermarkStyleBadge: "高光徽章", .watermarkPosTiled: "全屏平铺",
        .watermarkOpacityLabel: "透明度", .watermarkScaleLabel: "字号缩放", .watermarkBrandGlyph: "星标 ✦", .watermarkSaveDefaultBtn: "设为默认签名", .watermarkSavedDefaultToast: "已保存为默认水印签名", .defaultWatermarkToggle: "默认启用水印签名",
        .scrollMenuTitle: "滚屏长截图", .scrollMenuHint: "框选区域后滚动页面，自动无缝拼接长图", .scrollHudTitle: "滚屏长截图拼接中", .scrollHudHint: "在框选区域内向下滚动，系统会自动无缝拼接（回车完成 / Esc 取消）", .scrollFramesBadgeFormat: "%d 帧",
        .scrollAutoStartBtn: "自动滚动", .scrollAutoStopBtn: "暂停滚动", .scrollManualAppendTooltip: "手动拼入当前画面", .scrollFinishBtn: "完成长图", .scrollLimitReached: "已达最大拼接高度上限，请点击完成",
        .toggleWebcamPiP: "摄像头画中画", .defaultWebcamPiP: "录屏时开启摄像头画中画 (PiP)", .permCameraTitle: "摄像头权限", .permCameraSub: "录屏时同步录制摄像头画中画，支持 Studio 自由调整形状与位置", .webcamCardTitle: "摄像头画中画 (PiP)",
        .webcamShapeCircle: "圆形", .webcamShapeRounded: "圆角矩形", .webcamShapeVertical: "竖屏卡片", .webcamSizeLabel: "画面尺寸", .webcamMirrorLabel: "水平镜像", .webcamBorderLabel: "纯白边框",
        .webcamNoTrackHint: "当前视频未附带摄像头轨道；录屏前开启「摄像头画中画」，或导入本地人物视频叠加。", .webcamAttachLocalBtn: "叠加本地摄像头视频…",
        .viewModeFit: "全图", .viewModeFitWidth: "适宽", .viewModeActual: "1:1",
        .viewModeFitTooltip: "适应窗口完整预览 (⌘0)", .viewModeFitWidthTooltip: "适应窗口宽度，长图清晰滚动阅读 (⌘2)", .viewModeActualTooltip: "100% 原始清晰度预览 (⌘1)", .viewZoomOutTooltip: "缩小视图 (⌘-)", .viewZoomInTooltip: "放大视图 (⌘+)",
        .authErrInvalidToken: "令牌格式无效，请确认复制了完整的 xtags_ 授权码。", .authErrUnauthorized: "XTags 授权已过期或无效，请重新登录。", .authErrServer: "XTags 服务返回了异常响应，请稍后重试。",
        .updErrInvalidRelease: "无法读取 GitHub 最新版本信息。", .updErrNoBinary: "当前发布页未找到适用于此 Mac 的免安装二进制包。", .updErrChecksum: "安装包 SHA-256 校验失败，已自动中止更新。", .updErrSignature: "更新包完整性或签名验证失败，已取消安装。",
        .xtagsAccountSection: "XTags 账号与无缝更新", .xtagsSignInBtn: "登录 XTags", .xtagsSignOutBtn: "退出登录", .xtagsSignedOutHint: "登录后自动解锁后台无缝原地更新（无需 DMG 拖拽）", .xtagsAutoUpdateBadge: "无缝自动更新",
        .xtagsLoginWindowTitle: "登录 XTags 账号", .xtagsLoginSubtitle: "登录 XTags 后即可开启 XShot 无缝自动更新，新版本将在后台校验并原地替换重启，无需打开 DMG 拖拽。",
        .xtagsLoginStepBrowser: "已在浏览器打开 xtags.top 授权页，支持 X / Google / GitHub 一键登录。", .xtagsLoginOpenBrowserBtn: "打开浏览器登录", .xtagsLoginWaitingHint: "正在监听回调或剪贴板授权码（网页点「复制」即可自动完成登录）…",
        .xtagsLoginTokenPlaceholder: "或在此粘贴 xtags_ext_... 授权令牌", .xtagsLoginVerifyBtn: "验证并登录", .xtagsLoginVerifying: "正在验证 XTags 账号…", .xtagsLoginSuccessFormat: "已登录 %@",
        .updSectionTitle: "软件更新", .updCurrentVersionFormat: "当前版本 v%@", .updAutoToggleLabel: "开启无缝自动更新（原地替换并自动重启，无 DMG）", .updAutoRequiresSignInHint: "需登录 XTags 账号后开启自动无缝更新",
        .updCheckNowBtn: "检查更新", .updChecking: "正在检查新版本…", .updUpToDate: "已是最新版本", .updAvailableFormat: "发现新版本 v%@", .updDownloadingFormat: "正在下载 v%@ · %d%%",
        .updVerifying: "正在校验 SHA-256 与应用签名…", .updReadyFormat: "v%@ 已就绪 · 点击无缝重启", .updInstalling: "正在原地替换并自动重启…", .updUpdateNowBtn: "立即无缝更新", .updRestartApplyBtn: "重启并应用更新", .updOpenReleasesBtn: "前往 GitHub 下载", .updSeamlessNote: "采用原地原子替换机制，自动保留录屏权限，无需挂载 DMG 拖拽安装。"
    ]

    // MARK: - 繁體中文
    private static let zhHantStrings: [L10nKey: String] = [
        .themeSystem: "跟隨系統", .themeLight: "淺色", .themeDark: "深色",
        .langSystem: "跟隨系統",
        .appearanceSection: "外觀與語言", .appearanceMode: "介面外觀", .appLanguage: "顯示語言",

        .appSubtitle: "Retina 截圖 & 60fps 推文錄影", .grantPermission: "前往授權", .recordingBannerFormat: "錄製中 %@ · 點擊停止並編輯",
        .sectionScreenshot: "高畫質截圖", .sectionScreenshotMeta: "Retina 2x · 自動複製", .sectionRecording: "流暢錄影", .sectionRecordingMeta: "自動縮放 · X 專用 MP4",
        .areaScreenshot: "區域截圖", .windowScreenshot: "視窗截圖", .fullscreenScreenshot: "全螢幕截圖",
        .clipboardBeautifyTitle: "從剪貼簿美化圖片", .clipboardBeautifyHint: "讀取已複製圖片直接美化", .clipboardReadyFormat: "已偵測到圖片 · %d×%d", .clipboardEmptyAlert: "剪貼簿中沒有可用圖片，請先複製圖片、截圖或在 Finder 中複製圖片檔案後再試。",
        .collageMenuTitle: "多圖排列", .collageMenuHint: "多張截圖自由拼圖美化",
        .areaRecording: "區域錄影", .windowRecording: "視窗錄影", .fullscreenRecording: "全螢幕錄影", .clickToStart: "點擊開始",
        .toggleSystemAudio: "系統音訊", .toggleMic: "麥克風", .toggleKeystrokes: "按鍵提示", .toggleTypingFocus: "輸入焦點放大", .toggleSmoothCursor: "絲滑向量游標", .toggleAutoBeautify: "截圖自動美化", .toggleAutoPrivacy: "隱私自動打碼",
        .accessibilityHintBanner: "開啟「輔助使用」以啟用全域按鍵提示與精準輸入焦點放大",
        .recentWorks: "最近作品", .dragToXHint: "可拖曳直發推文", .copyFile: "複製檔案", .revealInFinder: "在 Finder 中顯示",
        .settingsAndPermissions: "設定與權限", .outputFolder: "輸出資料夾", .quitApp: "結束",

        .hudDone: "完成", .hudPauseTooltip: "暫停錄製", .hudResumeTooltip: "繼續錄製", .hudStopTooltip: "停止錄製並進入 Video Studio (⌘⇧8)",
        .overlayHintRecording: "拖曳框選錄影區域（選完可微調 / 鎖定 16:9） · Esc 取消",
        .overlayHintScreenshot: "拖曳框選 Retina 截圖區域 · 放開即完成 · Esc 取消",
        .overlayHintWindow: "移動滑鼠高亮目標視窗並點擊 · Esc 取消",
        .overlayStartRecording: "⏺ 開始錄製 (Enter)", .overlayCancel: "取消",
        .overlayWindowRecordPrefix: "點擊錄製視窗 · ", .overlayWindowShotPrefix: "點擊擷取視窗 · ",

        .quickCopiedTitle: "已複製到剪貼簿 · 可直接 ⌘V", .quickShotDoneTitle: "Retina 截圖完成", .quickVideoReadyTitle: "%@ 已就緒 · 拖入 X 發推",
        .quickDragToX: "拖曳發推", .quickBeautifyEdit: "美化 / 標註", .quickRevealFinder: "Finder 定位", .quickCopy: "複製", .quickCopied: "已複製", .quickPin: "置頂貼圖",

        .windowTitleScreenshot: "XShot · 截圖美化與標註", .windowTitleStudio: "XShot Studio · 推文高畫質影片精修", .windowTitleSettings: "XShot 設定與權限",
        .toolSelect: "選取", .toolArrow: "箭頭", .toolRectangle: "矩形", .toolEllipse: "橢圓", .toolHighlighter: "螢光筆", .toolText: "文字", .toolStep: "編號", .toolMosaic: "馬賽克", .toolBlur: "模糊",
        .undo: "還原 (⌘Z)", .redo: "重做 (⌘⇧Z)", .deleteSelected: "刪除選取標註", .clearAll: "清除全部標註", .pinAction: "貼圖", .saveAction: "儲存", .copyForX: "複製發推",
        .beautifyShell: "推文美化外框", .quickPresets: "一鍵預設", .presetAurora: "推文極光", .presetDarkWindow: "暗黑視窗", .presetCleanLight: "純淨白卡", .presetNeon: "推文霓虹", .presetDarkGeek: "暗黑極客", .presetNoFrame: "極簡無框",
        .backgroundWallpaper: "背景桌布", .wallpaperTabGradients: "精選漸層", .wallpaperTabSystem: "系統桌布", .wallpaperDesktopName: "目前桌面", .wallpaperPickLocal: "自選圖片…", .wallpaperLoadingSystem: "正在載入 macOS 桌布…",
        .canvasAspectX: "畫布比例（X 動態牆）", .paddingAndDepth: "邊距與立體感", .paddingLabel: "外邊距", .cornerRadiusLabel: "圓角半徑", .shadowLabel: "立體陰影",
        .windowChromeTitle: "macOS 視窗標題列", .chromeNone: "無標題列", .chromeDark: "深色頂列", .chromeLight: "淺色頂列", .windowTitlePlaceholder: "選填：視窗標題（如 XShot Demo）", .glassStroke: "玻璃高光內描邊",
        .addTextTitle: "新增文字標註", .addTextPlaceholder: "輸入要顯示的標註文字…", .addAction: "新增", .cancelAction: "取消",
        .toastCopiedPNG: "已複製 Retina PNG · ⌘V 發推", .toastSavedPNG: "已儲存至 ~/Pictures/XShot", .dragMeToX: "拖我直發 X",
        .pasteFromClipboard: "從剪貼簿讀取圖片 (⌘⇧9)", .toastLoadedClipboardFormat: "已讀取剪貼簿圖片 · %d×%d", .customColorTooltip: "自訂顏色（開啟系統調色盤）",
        .privacyCardTitle: "隱私偵測與自動打碼", .privacyScanBtn: "隱私打碼", .privacyScanFullBtn: "掃描並自動打碼", .privacyScanning: "正在本機辨識隱私…", .privacyClearAuto: "清除", .privacyStyleLabel: "打碼樣式",
        .privacyCatApiKey: "金鑰/Token", .privacyCatEmail: "信箱", .privacyCatPhone: "手機號", .privacyCatFinancialID: "卡號/證件", .privacyCatIP: "IP 位址",
        .privacyDetectedCountFormat: "已自動打碼 %d 處隱私", .privacyNoneDetected: "未偵測到敏感隱私資訊", .privacyOnDeviceNote: "100% 本機 Vision OCR 辨識 · 絕不上傳雲端",
        .collageCardTitle: "多圖排列", .collageCountBadgeFormat: "%d 張", .collageAddFiles: "新增圖片", .collageAppendClipboard: "剪貼簿追加", .collageDropHint: "支援直接拖曳多張圖片到左側畫布",
        .collageHorizontal: "橫排", .collageVertical: "直排", .collageGrid: "宮格", .collageBento: "焦點",
        .collageFitContain: "完整顯示", .collageFitFill: "填滿對齊", .collageSpacingLabel: "圖間距", .toastAppendedImagesFormat: "已加入 %d 張圖片 · 共 %d 張",
        .sliceCardTitle: "單圖切割", .slicePreset1x2: "左右2切", .slicePreset2x1: "上下2切", .slicePreset3x1: "長圖3切", .slicePreset2x2: "四宮格", .slicePreset3x3: "九宮格",
        .sliceRowsLabel: "行", .sliceColsLabel: "列", .sliceResetEqual: "均分", .sliceScopeRaw: "僅切圖片", .sliceScopeBeautified: "含美化背景",
        .sliceDragLineHint: "拖曳畫面中的虛線可自由微調切割位置", .sliceExportBtnFormat: "切割並匯出 %d 張 PNG", .sliceToCollageBtn: "轉為多圖排列", .sliceExportToastFormat: "已切分匯出 %d 張 PNG · 已複製檔案",
        .multiCollectEnableBtn: "開啟多圖", .multiCollectActiveTitle: "多圖已開啟", .multiCollectHintOff: "後續截圖自動放入", .multiCollectCountFormat: "已收 %d/6 張",
        .multiCollectBannerEmpty: "多圖已開啟 · 後續截圖或複製圖片自動加入", .multiCollectBannerCountFormat: "多圖收集 · 已收 %d/6 張（截圖自動加入）", .multiCollectOpenEditor: "編排", .multiCollectPickFiles: "選圖", .multiCollectStopBtn: "結束",
        .multiCollectCardToggle: "開啟多圖 · 後續截圖自動放進來", .multiCollectCaptureOne: "截一張", .multiCollectLimitReached: "多圖畫板已滿（最多 6 張）", .multiCollectCanvasBannerFormat: "多圖已開啟 (%d/6) · 後續截圖或複製圖片自動放入",
        .quickMultiCollectTooltip: "開啟多圖：後續截圖自動合併進來", .quickMultiCollectStopTooltip: "結束多圖自動收集", .quickMultiCollectTitleFormat: "多圖已收 %d/6 張 · 繼續截圖自動加入", .quickMultiArrangeFormat: "編排 (%d)",
        .openLocalVideoBtn: "剪輯本機影片", .openLocalVideoHint: "匯入 MP4 / MOV 剪輯、變速與美化",
        .splitClipBtn: "分割", .splitClipTooltip: "在目前播放頭分割片段 (S)", .setTrimInTooltip: "將播放頭設為起點 (I)", .setTrimOutTooltip: "將播放頭設為終點 (O)", .stepBackTooltip: "後退 0.1 秒 (←)", .stepForwardTooltip: "前進 0.1 秒 (→)",
        .deleteClipBtn: "刪除片段", .clipSelectedFormat: "片段 #%d", .clipSpeedLabel: "倍速",
        .fadeCardTitle: "淡入淡出", .fadeInLabel: "片頭淡入", .fadeOutLabel: "片尾淡出", .audioVolumeLabel: "音量增益",
        .captureFrameBtn: "截幀", .captureFrameTooltip: "截取目前美化畫面作為封面並複製", .captureFrameToast: "已截取目前高畫質封面並複製到剪貼簿", .clipTimelineTip: "點片段可調倍速/刪除 · S 分割 · 拖曳縮放塊邊緣調時長",
        .trackVideoLabel: "影片", .trackZoomLabel: "縮放", .trackAudioLabel: "音訊", .snapToggleTooltip: "磁吸對齊（自動吸附播放頭與切點）", .timelineZoomFit: "自適應",
        .mergeNextClipBtn: "合併", .duplicateZoomBtn: "複製", .clearAllZoomsBtn: "清空縮放", .audioTrackMutedHint: "音軌已靜音（點擊左側恢復）", .audioTrackNoAudioHint: "目前影片未包含音軌", .timelineShortcutsHint: "Space 播放 · S 分割 · I/O 裁首尾 · ←/→ 微調 · ⌘Z 撤銷 · 雙擊縮放軌新增縮放",

        .exportMP4: "匯出推文 MP4", .exportGIF: "匯出 GIF", .exportDonePrefix: "匯出完成 · ", .copyFileBtn: "複製檔案", .openFinderBtn: "開啟 Finder", .closeBtn: "關閉",
        .zoomTargetHint: "點擊畫面可直接指定縮放焦點", .zoomBadgeFormat: "縮放 %.2fx", .loadingMetalPreview: "正在初始化 Metal GPU 預覽…",
        .backToTrimStart: "回到剪輯起點", .resetTrim: "重設剪輯", .addZoomBtn: "新增縮放", .autoZoomSummaryFormat: "自動縮放 (%d點擊 · %d輸入)",
        .zoomTimelineEmptyHint: "雙擊此軌道新增縮放片段 · 錄影點擊/打字會自動產生", .zoomSegmentTyping: "輸入焦點縮放", .zoomSegmentClick: "點擊縮放片段", .zoomScaleLabel: "倍率", .zoomEaseLabel: "緩動", .followCursorLabel: "跟隨游標", .deleteAction: "刪除",
        .tabAppearance: "畫面外觀", .tabMotionExport: "鏡頭與匯出",
        .cardSmartCamera: "智慧鏡頭與焦點放大", .toggleAutoZoom: "啟用平滑自動縮放", .clickZoomCountFormat: "點擊放大 (%d)", .typingZoomCountFormat: "輸入焦點放大 (%d)",
        .toggleVectorCursor: "絲滑客製向量游標", .cursorSizeLabel: "游標大小", .toggleClickRipples: "點擊波紋高亮",
        .cardKeystrokeStylePos: "按鍵提示 · 樣式與位置", .toggleShowKeystrokesFormat: "顯示按鍵提示 (%d筆)", .previewSample: "預覽", .hideSample: "隱藏範例",
        .keycapStyleLabel: "鍵帽樣式", .displayPositionLabel: "顯示位置", .customPositionLabel: "自訂", .dragPositionHint: "支援在左側預覽畫面直接滑鼠拖曳定位", .keycapSizeLabel: "鍵帽大小",
        .noKeystrokesCapturedHint: "本次錄影未擷取到鍵盤事件。請在「系統設定 → 隱私權與安全性 → 輔助使用」勾選 XShot 後再錄影。",
        .cardAudioTrack: "音訊軌", .toggleKeepAudio: "保留錄製音訊（系統音 + 麥）",
        .cardEncodingPipeline: "極速零拷貝編碼管線", .specZeroCopy: "Metal GPU + IOSurface 零拷貝合成", .specConstant60: "恆定 60fps · VideoToolbox 硬體 H.264", .specRec709: "Rec.709 sRGB 防 X 上傳偏色", .specHighBitrate: "18~42 Mbps 高位元率抗二次壓縮",

        .ratioAuto: "自適應", .ratio16x9: "16:9 推文橫屏", .ratio4x3: "4:3 推文卡片", .ratio1x1: "1:1 正方形", .ratio9x16: "9:16 直屏",
        .ratioShortAuto: "原比例", .ratioShort16x9: "橫屏", .ratioShort4x3: "卡片", .ratioShort1x1: "方形", .ratioShort9x16: "直屏",
        .export1080pShort: "1080p 60fps (X 推薦)", .export2KShort: "2K 60fps (超清)", .export4KShort: "4K 60fps (極致)", .exportGIFShort: "GIF 動圖",
        .ksStyleDark: "深色鍵帽", .ksStyleLight: "淺色鍵帽", .ksStyleMinimal: "極簡膠囊", .ksStyleNeon: "霓虹邊框",
        .ksPosTopLeft: "左上", .ksPosTopCenter: "頂中", .ksPosTopRight: "右上", .ksPosBottomLeft: "左下", .ksPosBottomCenter: "底中", .ksPosBottomRight: "右下", .ksPosCustom: "自訂拖曳",
        .ksFilterAll: "快速鍵 + 打字", .ksFilterShortcutsOnly: "僅快速鍵",
        .hkAreaShot: "區域截圖", .hkWindowShot: "視窗截圖", .hkRecordArea: "區域錄影", .hkStopRecord: "停止錄影", .hkClipboardBeautify: "從剪貼簿美化圖片",

        .settingsPermissionsSection: "系統權限狀態", .permScreenTitle: "螢幕錄製（必要）", .permScreenSub: "用於 ScreenCaptureKit 原生 Retina 截圖與 60fps 錄影",
        .permMicTitle: "麥克風（選用）", .permMicSub: "錄製解說配音時啟用",
        .permAxTitle: "輔助使用（按鍵提示 + 輸入焦點放大）", .permAxSub: "用於擷取全域按鍵提示並追蹤文字游標自動放大",
        .permGranted: "已授權", .permAuthorizeBtn: "前往授權", .refreshPermissions: "重新整理權限狀態",
        .settingsDefaultsSection: "錄影與截圖預設值", .defaultFPSLabel: "預設錄影幀率", .fps60Label: "60 fps（推薦 · 流暢省空間）", .fps120Label: "120 fps（ProMotion 超絲滑）",
        .defaultSysAudio: "預設錄製系統音訊（免驅動）", .defaultMic: "預設錄製麥克風", .defaultKeystrokes: "預設啟用按鍵提示（實體鍵帽 + 打字氣泡）",
        .defaultKeystrokeStyle: "預設按鍵樣式", .defaultKeystrokePos: "預設按鍵位置", .defaultKeystrokeFilter: "按鍵顯示範圍",
        .defaultTypingZoom: "預設啟用輸入焦點自動放大", .defaultHideCursor: "錄影時隱藏系統游標（改用 Studio 絲滑游標）",
        .defaultAutoCopy: "截圖完成後自動複製到剪貼簿", .defaultAutoBeautify: "截圖自動套用推文美化背景", .defaultAutoPrivacy: "截圖/剪貼簿載入時自動偵測並打碼隱私（金鑰/信箱/手機/IP）", .defaultPrivacyStyle: "預設打碼樣式",
        .settingsHotkeysSection: "全域快速鍵", .settingsPathsSection: "預設輸出路徑", .screenshotsDirLabel: "截圖目錄", .recordingsDirLabel: "影片目錄", .openDirBtn: "開啟",

        .alertScreenPermTitle: "需要「螢幕與系統音訊錄製」權限",
        .alertScreenPermBody: "請在「系統設定 → 隱私權與安全性 → 螢幕與系統音訊錄製」中確認已勾選 XShot。授權後重新開啟一次 XShot 即可永久生效。",
        .openSystemSettings: "開啟系統設定", .laterBtn: "稍後", .alertNoticeTitle: "XShot 提示", .okBtn: "好",
        .quitXShotMenu: "結束 XShot", .errRecordingInterruptedFormat: "錄影意外中斷：%@", .statusRecordingFormat: "正在以 %dfps 高畫質錄製…", .statusGeneratingStudio: "正在產生 Studio 時間軸與自動縮放…",
        .errAlreadyRecording: "目前已經在錄製中。", .errNotRecording: "目前沒有進行中的錄製。", .errDisplayNotFound: "找不到目標顯示器。", .errWindowNotFound: "找不到目標視窗。", .errWindowNotFoundClosed: "找不到目標視窗，視窗可能已關閉或最小化。",
        .errWriterSetupFailedFormat: "初始化錄影編碼器失敗：%@", .errNoFramesCaptured: "未擷取到有效影片影格，請檢查系統螢幕錄製權限。", .errCaptureFailedFormat: "截圖失敗：%@",
        .errNoVideoTrack: "錄製檔案中找不到視訊軌道。", .errReadVideoFailedFormat: "無法讀取原始錄製影片：%@", .errWriteVideoFailedFormat: "無法建立匯出影片：%@", .errRenderFrameFailed: "影片影格合成失敗。", .errExportCancelled: "匯出已取消。",
        .errGIFInitFailed: "無法初始化 GIF 輸出檔案。", .errGIFWriteFailed: "GIF 寫入失敗。",
        .timelineZoomInTooltip: "放大時間軸 (⌘+)", .timelineZoomOutTooltip: "縮小時間軸 (⌘-)",
        .hkExtractText: "截圖擷取文字 (OCR)", .ocrMenuTitle: "截圖擷取文字", .ocrMenuHint: "框選螢幕秒提文字並自動複製", .ocrWindowTitle: "XShot · 文字擷取 (OCR)", .ocrCardTitle: "擷取文字 (OCR)", .ocrExtractBtn: "擷取圖中文字", .ocrScanning: "本機辨識文字中…",
        .ocrAutoCopiedBannerFormat: "已自動複製 · %d 行 · %d 字", .ocrStatsFormat: "%d 行 · %d 字", .ocrNoTextFound: "未在圖片中辨識到文字", .ocrModeKeepLines: "保留換行", .ocrModeJoinParagraphs: "合併段落",
        .ocrViewEditor: "文字編輯", .ocrViewLines: "逐行複製", .ocrCopyAllBtn: "複製全部文字", .ocrCopiedToast: "已複製文字到剪貼簿", .ocrCopiedLineToast: "已複製該行文字",
        .ocrCanvasOverlayToggle: "畫布文字框（點擊單行即複製）", .ocrOpenEditorBtn: "進入美化編輯", .quickOCRTooltip: "擷取圖中文字 (OCR)",
        .hkScrollShot: "捲動長截圖", .hkClickToRecordTooltip: "點擊錄製自訂快速鍵", .hkPressKeysHint: "請按快速鍵… (Esc取消)", .hkNeedModifierHint: "請至少包含 ⌘ / ⌥ / ⌃ 修飾鍵或使用 F1–F12", .hkConflictFormat: "快速鍵 %@ 已被「%@」佔用", .hkResetSingleTooltip: "恢復此快速鍵預設值", .hkResetAllBtn: "恢復全部預設快速鍵",
        .watermarkCardTitle: "自訂浮水印簽名", .watermarkTextPlaceholder: "輸入簽名或 X 帳號（如 @yourname）", .watermarkStyleGlass: "毛玻璃", .watermarkStyleMinimal: "極簡字", .watermarkStyleBadge: "高光徽章", .watermarkPosTiled: "全螢幕平鋪",
        .watermarkOpacityLabel: "透明度", .watermarkScaleLabel: "字級縮放", .watermarkBrandGlyph: "星標 ✦", .watermarkSaveDefaultBtn: "設為預設簽名", .watermarkSavedDefaultToast: "已儲存為預設浮水印簽名", .defaultWatermarkToggle: "預設啟用浮水印簽名",
        .scrollMenuTitle: "捲動長截圖", .scrollMenuHint: "框選區域後捲動頁面，自動無縫拼接長圖", .scrollHudTitle: "捲動長截圖拼接中", .scrollHudHint: "在框選區域內向下捲動，系統將自動無縫拼接（Enter 完成 / Esc 取消）", .scrollFramesBadgeFormat: "%d 幀",
        .scrollAutoStartBtn: "自動捲動", .scrollAutoStopBtn: "暫停捲動", .scrollManualAppendTooltip: "手動拼入目前畫面", .scrollFinishBtn: "完成長圖", .scrollLimitReached: "已達最大拼接高度上限，請點擊完成",
        .toggleWebcamPiP: "鏡頭子母畫面", .defaultWebcamPiP: "錄影時開啟鏡頭子母畫面 (PiP)", .permCameraTitle: "相機權限", .permCameraSub: "錄影時同步錄製鏡頭畫面，可在 Studio 自由調整形狀與位置", .webcamCardTitle: "鏡頭子母畫面 (PiP)",
        .webcamShapeCircle: "圓形", .webcamShapeRounded: "圓角矩形", .webcamShapeVertical: "直式卡片", .webcamSizeLabel: "畫面尺寸", .webcamMirrorLabel: "水平鏡像", .webcamBorderLabel: "純白邊框",
        .webcamNoTrackHint: "目前影片未包含鏡頭軌道；錄影前開啟「鏡頭子母畫面」，或匯入本機人像影片疊加。", .webcamAttachLocalBtn: "疊加本機鏡頭影片…",
        .viewModeFit: "全圖", .viewModeFitWidth: "適寬", .viewModeActual: "1:1",
        .viewModeFitTooltip: "適應視窗完整預覽 (⌘0)", .viewModeFitWidthTooltip: "適應視窗寬度，長圖清晰捲動閱讀 (⌘2)", .viewModeActualTooltip: "100% 原始清晰度預覽 (⌘1)", .viewZoomOutTooltip: "縮小檢視 (⌘-)", .viewZoomInTooltip: "放大檢視 (⌘+)",
        .authErrInvalidToken: "權杖格式無效，請確認已複製完整的 xtags_ 授權碼。", .authErrUnauthorized: "XTags 授權已過期或無效，請重新登入。", .authErrServer: "XTags 服務回傳異常，請稍後再試。",
        .updErrInvalidRelease: "無法讀取 GitHub 最新版本資訊。", .updErrNoBinary: "目前發佈頁未找到適用於此 Mac 的免安裝二進位包。", .updErrChecksum: "安裝包 SHA-256 校驗失敗，已自動中止更新。", .updErrSignature: "更新包完整性或簽章驗證失敗，已取消安裝。",
        .xtagsAccountSection: "XTags 帳號與無縫更新", .xtagsSignInBtn: "登入 XTags", .xtagsSignOutBtn: "登出", .xtagsSignedOutHint: "登入後自動解鎖背景無縫原地更新（免 DMG 拖曳）", .xtagsAutoUpdateBadge: "無縫自動更新",
        .xtagsLoginWindowTitle: "登入 XTags 帳號", .xtagsLoginSubtitle: "登入 XTags 後即可開啟 XShot 無縫自動更新，新版本會在背景校驗並原地替換重啟，無需開啟 DMG 拖曳。",
        .xtagsLoginStepBrowser: "已在瀏覽器開啟 xtags.top 授權頁，支援 X / Google / GitHub 一鍵登入。", .xtagsLoginOpenBrowserBtn: "開啟瀏覽器登入", .xtagsLoginWaitingHint: "正在監聽回呼或剪貼簿授權碼（網頁點「複製」即可自動完成登入）…",
        .xtagsLoginTokenPlaceholder: "或在此貼上 xtags_ext_... 授權權杖", .xtagsLoginVerifyBtn: "驗證並登入", .xtagsLoginVerifying: "正在驗證 XTags 帳號…", .xtagsLoginSuccessFormat: "已登入 %@",
        .updSectionTitle: "軟體更新", .updCurrentVersionFormat: "目前版本 v%@", .updAutoToggleLabel: "開啟無縫自動更新（原地替換並自動重啟，免 DMG）", .updAutoRequiresSignInHint: "需登入 XTags 帳號後開啟自動無縫更新",
        .updCheckNowBtn: "檢查更新", .updChecking: "正在檢查新版本…", .updUpToDate: "已是最新版本", .updAvailableFormat: "發現新版本 v%@", .updDownloadingFormat: "正在下載 v%@ · %d%%",
        .updVerifying: "正在校驗 SHA-256 與應用程式簽章…", .updReadyFormat: "v%@ 已就緒 · 點擊無縫重啟", .updInstalling: "正在原地替換並自動重啟…", .updUpdateNowBtn: "立即無縫更新", .updRestartApplyBtn: "重啟並套用更新", .updOpenReleasesBtn: "前往 GitHub 下載", .updSeamlessNote: "採用原地原子替換機制，無需掛載 DMG 拖曳安裝。"
    ]

    // MARK: - English
    private static let enStrings: [L10nKey: String] = [
        .themeSystem: "System", .themeLight: "Light", .themeDark: "Dark",
        .langSystem: "System",
        .appearanceSection: "Appearance & Language", .appearanceMode: "Appearance", .appLanguage: "Language",

        .appSubtitle: "Retina Capture & 60fps X Recorder", .grantPermission: "Authorize", .recordingBannerFormat: "Recording %@ · Click to Stop",
        .sectionScreenshot: "Retina Screenshot", .sectionScreenshotMeta: "2x PNG · Auto Copy", .sectionRecording: "Smooth Recording", .sectionRecordingMeta: "Auto-Zoom · X MP4",
        .areaScreenshot: "Area", .windowScreenshot: "Window", .fullscreenScreenshot: "Screen",
        .clipboardBeautifyTitle: "Beautify Clipboard", .clipboardBeautifyHint: "Open copied image to beautify", .clipboardReadyFormat: "Image ready · %d×%d", .clipboardEmptyAlert: "No image found on the clipboard. Copy an image, screenshot, or image file in Finder first.",
        .collageMenuTitle: "Multi-Image Layout", .collageMenuHint: "Combine & arrange multiple images",
        .areaRecording: "Area", .windowRecording: "Window", .fullscreenRecording: "Screen", .clickToStart: "Click to run",
        .toggleSystemAudio: "System Audio", .toggleMic: "Microphone", .toggleKeystrokes: "Keystrokes", .toggleTypingFocus: "Typing Zoom", .toggleSmoothCursor: "Smooth Cursor", .toggleAutoBeautify: "Auto Beautify", .toggleAutoPrivacy: "Auto Redact",
        .accessibilityHintBanner: "Enable Accessibility for global keystrokes & typing focus zoom",
        .recentWorks: "Recent Captures", .dragToXHint: "Drag directly to X", .copyFile: "Copy File", .revealInFinder: "Reveal in Finder",
        .settingsAndPermissions: "Settings", .outputFolder: "Folder", .quitApp: "Quit",

        .hudDone: "Stop", .hudPauseTooltip: "Pause Recording", .hudResumeTooltip: "Resume Recording", .hudStopTooltip: "Stop & Open Video Studio (⌘⇧8)",
        .overlayHintRecording: "Drag to select recording region (resize handles / 16:9 snap) · Esc to cancel",
        .overlayHintScreenshot: "Drag to capture Retina screenshot · Release to snap · Esc to cancel",
        .overlayHintWindow: "Hover a window and click to capture · Esc to cancel",
        .overlayStartRecording: "⏺ Start (Enter)", .overlayCancel: "Cancel",
        .overlayWindowRecordPrefix: "Record Window · ", .overlayWindowShotPrefix: "Capture Window · ",

        .quickCopiedTitle: "Copied · Press ⌘V to post", .quickShotDoneTitle: "Retina Capture Ready", .quickVideoReadyTitle: "%@ Ready · Drag to X",
        .quickDragToX: "Drag to X", .quickBeautifyEdit: "Beautify / Edit", .quickRevealFinder: "Show in Finder", .quickCopy: "Copy", .quickCopied: "Copied", .quickPin: "Pin on Top",

        .windowTitleScreenshot: "XShot · Screenshot Studio", .windowTitleStudio: "XShot Studio · Video Editor", .windowTitleSettings: "XShot Settings",
        .toolSelect: "Select", .toolArrow: "Arrow", .toolRectangle: "Rect", .toolEllipse: "Oval", .toolHighlighter: "Mark", .toolText: "Text", .toolStep: "Step", .toolMosaic: "Mosaic", .toolBlur: "Blur",
        .undo: "Undo (⌘Z)", .redo: "Redo (⌘⇧Z)", .deleteSelected: "Delete Selected", .clearAll: "Clear All", .pinAction: "Pin", .saveAction: "Save", .copyForX: "Copy PNG",
        .beautifyShell: "Tweet Beautify Frame", .quickPresets: "Quick Presets", .presetAurora: "Aurora", .presetDarkWindow: "Dark Card", .presetCleanLight: "Light Card", .presetNeon: "Neon X", .presetDarkGeek: "Obsidian", .presetNoFrame: "No Frame",
        .backgroundWallpaper: "Wallpaper", .wallpaperTabGradients: "Gradients", .wallpaperTabSystem: "macOS", .wallpaperDesktopName: "Desktop", .wallpaperPickLocal: "Choose Image…", .wallpaperLoadingSystem: "Loading macOS wallpapers…",
        .canvasAspectX: "Aspect Ratio (X Feed)", .paddingAndDepth: "Padding & Depth", .paddingLabel: "Padding", .cornerRadiusLabel: "Corner Radius", .shadowLabel: "Drop Shadow",
        .windowChromeTitle: "macOS Title Bar", .chromeNone: "None", .chromeDark: "Dark", .chromeLight: "Light", .windowTitlePlaceholder: "Optional window title (e.g. XShot Demo)", .glassStroke: "Glass Inner Border",
        .addTextTitle: "Add Text Label", .addTextPlaceholder: "Type annotation text…", .addAction: "Add", .cancelAction: "Cancel",
        .toastCopiedPNG: "Copied Retina PNG · ⌘V into X", .toastSavedPNG: "Saved to ~/Pictures/XShot", .dragMeToX: "Drag to X",
        .pasteFromClipboard: "Paste Image from Clipboard (⌘⇧9)", .toastLoadedClipboardFormat: "Loaded Clipboard Image · %d×%d", .customColorTooltip: "Custom Color (System Color Wheel)",
        .privacyCardTitle: "Privacy Detection & Redact", .privacyScanBtn: "Auto Redact", .privacyScanFullBtn: "Scan & Redact Secrets", .privacyScanning: "Scanning on-device…", .privacyClearAuto: "Clear", .privacyStyleLabel: "Mask Style",
        .privacyCatApiKey: "Keys/Tokens", .privacyCatEmail: "Emails", .privacyCatPhone: "Phones", .privacyCatFinancialID: "Cards/IDs", .privacyCatIP: "IPs",
        .privacyDetectedCountFormat: "Auto-redacted %d sensitive items", .privacyNoneDetected: "No sensitive data detected", .privacyOnDeviceNote: "100% On-Device Apple Vision OCR · Never leaves your Mac",
        .collageCardTitle: "Multi-Image Layout", .collageCountBadgeFormat: "%d imgs", .collageAddFiles: "Add Images", .collageAppendClipboard: "Append Clipboard", .collageDropHint: "Or drop image files directly onto the canvas",
        .collageHorizontal: "Row", .collageVertical: "Stack", .collageGrid: "Grid", .collageBento: "Bento",
        .collageFitContain: "Fit All", .collageFitFill: "Fill Cells", .collageSpacingLabel: "Gap", .toastAppendedImagesFormat: "Added %d image(s) · %d total",
        .sliceCardTitle: "Image Slicer", .slicePreset1x2: "2 Split H", .slicePreset2x1: "2 Split V", .slicePreset3x1: "3 Long", .slicePreset2x2: "2×2 Grid", .slicePreset3x3: "3×3 Grid",
        .sliceRowsLabel: "Rows", .sliceColsLabel: "Cols", .sliceResetEqual: "Even", .sliceScopeRaw: "Image Only", .sliceScopeBeautified: "With Frame",
        .sliceDragLineHint: "Drag dashed lines on the canvas to fine-tune cut positions", .sliceExportBtnFormat: "Slice & Export %d PNGs", .sliceToCollageBtn: "Convert to Multi-Image", .sliceExportToastFormat: "Exported %d PNG slices · Files copied",
        .multiCollectEnableBtn: "Multi-Shot", .multiCollectActiveTitle: "Multi ON", .multiCollectHintOff: "Auto-add captures", .multiCollectCountFormat: "%d/6 added",
        .multiCollectBannerEmpty: "Multi-Shot ON · Captures & copied images auto-add", .multiCollectBannerCountFormat: "Multi-Shot · %d/6 (new captures auto-add)", .multiCollectOpenEditor: "Arrange", .multiCollectPickFiles: "Files", .multiCollectStopBtn: "Done",
        .multiCollectCardToggle: "Auto-add subsequent captures", .multiCollectCaptureOne: "Capture", .multiCollectLimitReached: "Multi-image board is full (max 6)", .multiCollectCanvasBannerFormat: "Multi-Shot ON (%d/6) · Captures & copied images auto-add",
        .quickMultiCollectTooltip: "Enable Multi-Shot: auto-merge subsequent captures", .quickMultiCollectStopTooltip: "Stop Multi-Shot collection", .quickMultiCollectTitleFormat: "Multi-Shot %d/6 · Next capture auto-adds", .quickMultiArrangeFormat: "Arrange (%d)",
        .openLocalVideoBtn: "Edit Local Video", .openLocalVideoHint: "Trim, cut, speed-ramp & frame MP4 / MOV",
        .splitClipBtn: "Split", .splitClipTooltip: "Split clip at playhead (S)", .setTrimInTooltip: "Trim start to playhead (I)", .setTrimOutTooltip: "Trim end to playhead (O)", .stepBackTooltip: "Step back 0.1s (←)", .stepForwardTooltip: "Step forward 0.1s (→)",
        .deleteClipBtn: "Delete Clip", .clipSelectedFormat: "Clip #%d", .clipSpeedLabel: "Speed",
        .fadeCardTitle: "Fade In / Out", .fadeInLabel: "Fade In", .fadeOutLabel: "Fade Out", .audioVolumeLabel: "Volume",
        .captureFrameBtn: "Frame", .captureFrameTooltip: "Capture current beautified frame to clipboard & Pictures", .captureFrameToast: "Captured current frame & copied PNG", .clipTimelineTip: "Click a clip for speed/cut · Press S to split · Drag zoom edges to resize",
        .trackVideoLabel: "Video", .trackZoomLabel: "Zoom", .trackAudioLabel: "Audio", .snapToggleTooltip: "Magnetic Snapping (playhead & cut edges)", .timelineZoomFit: "Fit",
        .mergeNextClipBtn: "Merge", .duplicateZoomBtn: "Copy", .clearAllZoomsBtn: "Clear Zooms", .audioTrackMutedHint: "Audio muted (click speaker to unmute)", .audioTrackNoAudioHint: "No audio track in source video", .timelineShortcutsHint: "Space Play · S Split · I/O Trim · ←/→ Step · ⌘Z Undo · Double-click Zoom track to add",

        .exportMP4: "Export X MP4", .exportGIF: "Export GIF", .exportDonePrefix: "Exported · ", .copyFileBtn: "Copy File", .openFinderBtn: "Finder", .closeBtn: "Close",
        .zoomTargetHint: "Click video preview to set zoom focus", .zoomBadgeFormat: "Zoom %.2fx", .loadingMetalPreview: "Initializing Metal GPU preview…",
        .backToTrimStart: "Jump to Trim Start", .resetTrim: "Reset Trim", .addZoomBtn: "Add Zoom", .autoZoomSummaryFormat: "Auto Zoom (%d clicks · %d typing)",
        .zoomTimelineEmptyHint: "Double-click lane to add zoom · Auto-generated from clicks & typing", .zoomSegmentTyping: "Typing Focus Zoom", .zoomSegmentClick: "Click Zoom", .zoomScaleLabel: "Scale", .zoomEaseLabel: "Ease", .followCursorLabel: "Follow Focus", .deleteAction: "Delete",
        .tabAppearance: "Appearance", .tabMotionExport: "Motion & HUD",
        .cardSmartCamera: "Smart Camera & Focus Zoom", .toggleAutoZoom: "Smooth Auto-Zoom", .clickZoomCountFormat: "Click Zoom (%d)", .typingZoomCountFormat: "Typing Focus (%d)",
        .toggleVectorCursor: "Smooth Vector Cursor", .cursorSizeLabel: "Cursor Size", .toggleClickRipples: "Click Ripples",
        .cardKeystrokeStylePos: "Keystrokes · Style & Position", .toggleShowKeystrokesFormat: "Show Keystrokes (%d)", .previewSample: "Preview", .hideSample: "Hide",
        .keycapStyleLabel: "Keycap Style", .displayPositionLabel: "Position", .customPositionLabel: "Custom", .dragPositionHint: "Drag the keycap directly on the video preview to position freely", .keycapSizeLabel: "Keycap Size",
        .noKeystrokesCapturedHint: "No keystrokes recorded in this clip. Grant Accessibility to XShot in System Settings to capture global keycaps & caret focus.",
        .cardAudioTrack: "Audio Track", .toggleKeepAudio: "Include Audio (System + Mic)",
        .cardEncodingPipeline: "Zero-Copy Metal Pipeline", .specZeroCopy: "Metal GPU + IOSurface Zero-Copy", .specConstant60: "Constant 60fps · VideoToolbox H.264", .specRec709: "Rec.709 sRGB for Accurate X Colors", .specHighBitrate: "18–42 Mbps High Bitrate Crisp Text",

        .ratioAuto: "Auto", .ratio16x9: "16:9 Landscape", .ratio4x3: "4:3 Card", .ratio1x1: "1:1 Square", .ratio9x16: "9:16 Vertical",
        .ratioShortAuto: "Auto", .ratioShort16x9: "Wide", .ratioShort4x3: "Card", .ratioShort1x1: "Square", .ratioShort9x16: "Tall",
        .export1080pShort: "1080p 60fps (X Best)", .export2KShort: "2K 60fps (Ultra)", .export4KShort: "4K 60fps (Max)", .exportGIFShort: "Smooth GIF",
        .ksStyleDark: "Dark Keys", .ksStyleLight: "Light Keys", .ksStyleMinimal: "Glass Pill", .ksStyleNeon: "Neon Glow",
        .ksPosTopLeft: "Top L", .ksPosTopCenter: "Top C", .ksPosTopRight: "Top R", .ksPosBottomLeft: "Bot L", .ksPosBottomCenter: "Bot C", .ksPosBottomRight: "Bot R", .ksPosCustom: "Custom Drag",
        .ksFilterAll: "Shortcuts + Typing", .ksFilterShortcutsOnly: "Shortcuts Only",
        .hkAreaShot: "Area Screenshot", .hkWindowShot: "Window Screenshot", .hkRecordArea: "Area Recording", .hkStopRecord: "Stop Recording", .hkClipboardBeautify: "Beautify Clipboard Image",

        .settingsPermissionsSection: "macOS Permissions", .permScreenTitle: "Screen Recording (Required)", .permScreenSub: "Required by ScreenCaptureKit for Retina capture & 60fps video",
        .permMicTitle: "Microphone (Optional)", .permMicSub: "Enable when recording voiceover narration",
        .permAxTitle: "Accessibility (Keystrokes + Typing Zoom)", .permAxSub: "Captures global keycaps and tracks text caret for typing focus zoom",
        .permGranted: "Granted", .permAuthorizeBtn: "Authorize", .refreshPermissions: "Refresh Status",
        .settingsDefaultsSection: "Capture Defaults", .defaultFPSLabel: "Default Recording FPS", .fps60Label: "60 fps (Recommended)", .fps120Label: "120 fps (ProMotion Ultra Smooth)",
        .defaultSysAudio: "Capture System Audio by default", .defaultMic: "Capture Microphone by default", .defaultKeystrokes: "Show Keystrokes HUD by default",
        .defaultKeystrokeStyle: "Default Keycap Style", .defaultKeystrokePos: "Default Keycap Position", .defaultKeystrokeFilter: "Keystroke Filter",
        .defaultTypingZoom: "Enable Typing Focus Auto-Zoom by default", .defaultHideCursor: "Hide system cursor (use smooth Studio cursor)",
        .defaultAutoCopy: "Auto-copy screenshots to clipboard", .defaultAutoBeautify: "Auto-beautify screenshots on capture", .defaultAutoPrivacy: "Auto-detect & redact sensitive data (keys, emails, phones, IPs)", .defaultPrivacyStyle: "Default Redaction Style",
        .settingsHotkeysSection: "Global Shortcuts", .settingsPathsSection: "Output Folders", .screenshotsDirLabel: "Screenshots", .recordingsDirLabel: "Recordings", .openDirBtn: "Open",

        .alertScreenPermTitle: "Screen Recording Permission Required",
        .alertScreenPermBody: "Please enable XShot in System Settings → Privacy & Security → Screen & System Audio Recording, then relaunch XShot once.",
        .openSystemSettings: "Open Settings", .laterBtn: "Later", .alertNoticeTitle: "XShot", .okBtn: "OK",
        .quitXShotMenu: "Quit XShot", .errRecordingInterruptedFormat: "Recording interrupted: %@", .statusRecordingFormat: "Recording at %dfps…", .statusGeneratingStudio: "Preparing Studio timeline & Auto-Zoom…",
        .errAlreadyRecording: "A recording is already in progress.", .errNotRecording: "No active recording to stop.", .errDisplayNotFound: "Target display not found.", .errWindowNotFound: "Target window not found.", .errWindowNotFoundClosed: "Target window not found (it may be closed or minimized).",
        .errWriterSetupFailedFormat: "Failed to initialize video encoder: %@", .errNoFramesCaptured: "No video frames were captured. Please check Screen Recording permission.", .errCaptureFailedFormat: "Screenshot failed: %@",
        .errNoVideoTrack: "No video track found in recording.", .errReadVideoFailedFormat: "Could not read source video: %@", .errWriteVideoFailedFormat: "Could not create export video: %@", .errRenderFrameFailed: "Failed to composite video frame.", .errExportCancelled: "Export cancelled.",
        .errGIFInitFailed: "Could not initialize GIF output file.", .errGIFWriteFailed: "Failed to finalize GIF output.",
        .timelineZoomInTooltip: "Zoom In Timeline (⌘+)", .timelineZoomOutTooltip: "Zoom Out Timeline (⌘-)",
        .hkExtractText: "Extract Text (OCR)", .ocrMenuTitle: "Extract Text (OCR)", .ocrMenuHint: "Capture region & copy text instantly", .ocrWindowTitle: "XShot · Text Extraction (OCR)", .ocrCardTitle: "Extract Text (OCR)", .ocrExtractBtn: "Extract Text", .ocrScanning: "Recognizing text…",
        .ocrAutoCopiedBannerFormat: "Auto-copied · %d lines · %d chars", .ocrStatsFormat: "%d lines · %d chars", .ocrNoTextFound: "No text detected in image", .ocrModeKeepLines: "Keep Lines", .ocrModeJoinParagraphs: "Join Paragraphs",
        .ocrViewEditor: "Text Editor", .ocrViewLines: "By Line", .ocrCopyAllBtn: "Copy All Text", .ocrCopiedToast: "Copied text to clipboard", .ocrCopiedLineToast: "Copied line to clipboard",
        .ocrCanvasOverlayToggle: "Canvas text boxes (click line to copy)", .ocrOpenEditorBtn: "Beautify Image", .quickOCRTooltip: "Extract text from screenshot (OCR)",
        .hkScrollShot: "Scrolling Capture", .hkClickToRecordTooltip: "Click to record custom shortcut", .hkPressKeysHint: "Press keys… (Esc)", .hkNeedModifierHint: "Include ⌘ / ⌥ / ⌃ modifier or use F1–F12", .hkConflictFormat: "%@ is already used by \"%@\"", .hkResetSingleTooltip: "Reset to default", .hkResetAllBtn: "Reset All Shortcuts",
        .watermarkCardTitle: "Custom Watermark", .watermarkTextPlaceholder: "Signature or @handle (e.g. @XShot)", .watermarkStyleGlass: "Glass", .watermarkStyleMinimal: "Minimal", .watermarkStyleBadge: "Badge", .watermarkPosTiled: "Tiled",
        .watermarkOpacityLabel: "Opacity", .watermarkScaleLabel: "Size", .watermarkBrandGlyph: "Spark ✦", .watermarkSaveDefaultBtn: "Save Default", .watermarkSavedDefaultToast: "Saved as default watermark", .defaultWatermarkToggle: "Enable Watermark by Default",
        .scrollMenuTitle: "Scrolling Shot", .scrollMenuHint: "Select region & scroll smoothly to stitch a long screenshot", .scrollHudTitle: "Scrolling Capture", .scrollHudHint: "Scroll down inside the cyan frame to auto-stitch (Return to finish / Esc to cancel)", .scrollFramesBadgeFormat: "%d frames",
        .scrollAutoStartBtn: "Auto Scroll", .scrollAutoStopBtn: "Pause", .scrollManualAppendTooltip: "Manually append current view", .scrollFinishBtn: "Finish", .scrollLimitReached: "Max stitch height reached — click Finish",
        .toggleWebcamPiP: "Webcam PiP", .defaultWebcamPiP: "Record Webcam Picture-in-Picture", .permCameraTitle: "Camera", .permCameraSub: "Records a synced webcam track you can reshape & move non-destructively in Studio", .webcamCardTitle: "Webcam PiP",
        .webcamShapeCircle: "Circle", .webcamShapeRounded: "Rounded", .webcamShapeVertical: "Portrait", .webcamSizeLabel: "Bubble Size", .webcamMirrorLabel: "Mirror", .webcamBorderLabel: "Border",
        .webcamNoTrackHint: "No webcam track in this clip. Enable Webcam PiP before recording, or attach a local camera video.", .webcamAttachLocalBtn: "Attach Camera Video…",
        .viewModeFit: "Fit", .viewModeFitWidth: "Width", .viewModeActual: "1:1",
        .viewModeFitTooltip: "Fit entire image in window (⌘0)", .viewModeFitWidthTooltip: "Fit width for crisp long-screenshot reading (⌘2)", .viewModeActualTooltip: "100% Retina actual size (⌘1)", .viewZoomOutTooltip: "Zoom out (⌘-)", .viewZoomInTooltip: "Zoom in (⌘+)",
        .authErrInvalidToken: "Invalid token format. Please copy the full xtags_ access token.", .authErrUnauthorized: "Your XTags session expired or is invalid. Please sign in again.", .authErrServer: "Unexpected response from XTags server. Please try again.",
        .updErrInvalidRelease: "Unable to read the latest GitHub release metadata.", .updErrNoBinary: "No direct macOS binary archive was found in this release.", .updErrChecksum: "SHA-256 checksum verification failed. Update aborted.", .updErrSignature: "App bundle integrity or signature verification failed.",
        .xtagsAccountSection: "XTags Account & Auto-Update", .xtagsSignInBtn: "Sign in with XTags", .xtagsSignOutBtn: "Sign Out", .xtagsSignedOutHint: "Sign in to unlock seamless background auto-updates (no DMG)", .xtagsAutoUpdateBadge: "Auto-Update On",
        .xtagsLoginWindowTitle: "Sign in to XTags", .xtagsLoginSubtitle: "Sign in with your XTags account to unlock seamless in-place auto-updates — new builds verify, replace XShot in-place, and relaunch with zero DMG dragging.",
        .xtagsLoginStepBrowser: "Opened xtags.top in your browser. Sign in with X, Google, or GitHub.", .xtagsLoginOpenBrowserBtn: "Open Browser to Sign In", .xtagsLoginWaitingHint: "Listening for callback or copied token (clicking Copy on xtags.top completes sign-in automatically)…",
        .xtagsLoginTokenPlaceholder: "Or paste xtags_ext_... token manually", .xtagsLoginVerifyBtn: "Verify & Sign In", .xtagsLoginVerifying: "Verifying XTags account…", .xtagsLoginSuccessFormat: "Signed in as %@",
        .updSectionTitle: "Software Updates", .updCurrentVersionFormat: "Current version v%@", .updAutoToggleLabel: "Seamless auto-updates (in-place swap & relaunch, zero DMG)", .updAutoRequiresSignInHint: "Sign in with XTags to enable seamless auto-updates",
        .updCheckNowBtn: "Check for Updates", .updChecking: "Checking for updates…", .updUpToDate: "You're up to date", .updAvailableFormat: "v%@ available", .updDownloadingFormat: "Downloading v%@ · %d%%",
        .updVerifying: "Verifying SHA-256 & signature…", .updReadyFormat: "v%@ ready · Click to relaunch", .updInstalling: "Replacing app in-place & relaunching…", .updUpdateNowBtn: "Update Seamlessly", .updRestartApplyBtn: "Restart & Apply", .updOpenReleasesBtn: "Download on GitHub", .updSeamlessNote: "Updates replace XShot.app atomically in-place and relaunch automatically — no DMG window or manual dragging."
    ]

    // MARK: - 日本語
    private static let jaStrings: [L10nKey: String] = [
        .themeSystem: "システムに従う", .themeLight: "ライト", .themeDark: "ダーク",
        .langSystem: "システムに従う",
        .appearanceSection: "外観と言語", .appearanceMode: "外観モード", .appLanguage: "表示言語",

        .appSubtitle: "Retina スクショ & 60fps X 投稿録画", .grantPermission: "許可する", .recordingBannerFormat: "録画中 %@ · クリックして停止",
        .sectionScreenshot: "高画質スクショ", .sectionScreenshotMeta: "Retina 2x · 自動コピー", .sectionRecording: "滑らか録画", .sectionRecordingMeta: "自動ズーム · X 最適化 MP4",
        .areaScreenshot: "範囲", .windowScreenshot: "ウィンドウ", .fullscreenScreenshot: "全画面",
        .clipboardBeautifyTitle: "クリップボード画像を装飾", .clipboardBeautifyHint: "コピー済み画像をすぐ装飾", .clipboardReadyFormat: "画像あり · %d×%d", .clipboardEmptyAlert: "クリップボードに画像が見つかりません。先に画像や画像ファイルをコピーしてください。",
        .collageMenuTitle: "複数画像レイアウト", .collageMenuHint: "複数スクショを並べて装飾",
        .areaRecording: "範囲録画", .windowRecording: "ウィンドウ", .fullscreenRecording: "全画面", .clickToStart: "クリック開始",
        .toggleSystemAudio: "システム音声", .toggleMic: "マイク", .toggleKeystrokes: "キー表示", .toggleTypingFocus: "入力ズーム", .toggleSmoothCursor: "滑らかカーソル", .toggleAutoBeautify: "自動装飾", .toggleAutoPrivacy: "自動モザイク",
        .accessibilityHintBanner: "「アクセシビリティ」を許可するとキー表示と入力ズームが有効になります",
        .recentWorks: "最近のキャプチャ", .dragToXHint: "X に直接ドラッグ可能", .copyFile: "ファイルをコピー", .revealInFinder: "Finder で表示",
        .settingsAndPermissions: "設定と権限", .outputFolder: "保存先", .quitApp: "終了",

        .hudDone: "完了", .hudPauseTooltip: "一時停止", .hudResumeTooltip: "再開", .hudStopTooltip: "録画を停止して Studio を開く (⌘⇧8)",
        .overlayHintRecording: "ドラッグして録画範囲を選択（角で調整 / 16:9 固定） · Esc でキャンセル",
        .overlayHintScreenshot: "ドラッグして Retina スクショを撮影 · 離すと即撮影 · Esc でキャンセル",
        .overlayHintWindow: "対象ウィンドウにカーソルを合わせてクリック · Esc でキャンセル",
        .overlayStartRecording: "⏺ 録画開始 (Enter)", .overlayCancel: "キャンセル",
        .overlayWindowRecordPrefix: "ウィンドウを録画 · ", .overlayWindowShotPrefix: "ウィンドウを撮影 · ",

        .quickCopiedTitle: "コピー済み · ⌘V で即投稿", .quickShotDoneTitle: "Retina 撮影完了", .quickVideoReadyTitle: "%@ 書き出し完了 · X へドラッグ",
        .quickDragToX: "X へドラッグ", .quickBeautifyEdit: "装飾 / 注釈", .quickRevealFinder: "Finder で表示", .quickCopy: "コピー", .quickCopied: "完了", .quickPin: "最前面に固定",

        .windowTitleScreenshot: "XShot · スクショ装飾スタジオ", .windowTitleStudio: "XShot Studio · X 動画編集", .windowTitleSettings: "XShot 設定と権限",
        .toolSelect: "選択", .toolArrow: "矢印", .toolRectangle: "四角", .toolEllipse: "楕円", .toolHighlighter: "蛍光", .toolText: "文字", .toolStep: "番号", .toolMosaic: "モザイク", .toolBlur: "ぼかし",
        .undo: "元に戻す (⌘Z)", .redo: "やり直す (⌘⇧Z)", .deleteSelected: "選択を削除", .clearAll: "すべて消去", .pinAction: "固定", .saveAction: "保存", .copyForX: "PNG コピー",
        .beautifyShell: "投稿用フレーム装飾", .quickPresets: "ワンクリックプリセット", .presetAurora: "オーロラ", .presetDarkWindow: "ダーク枠", .presetCleanLight: "ホワイト枠", .presetNeon: "ネオン X", .presetDarkGeek: "オブシディアン", .presetNoFrame: "フレームなし",
        .backgroundWallpaper: "背景壁紙", .wallpaperTabGradients: "グラデーション", .wallpaperTabSystem: "システム壁紙", .wallpaperDesktopName: "現在のデスクトップ", .wallpaperPickLocal: "画像を選択…", .wallpaperLoadingSystem: "macOS 壁紙を読み込み中…",
        .canvasAspectX: "比率（X タイムライン）", .paddingAndDepth: "余白と立体感", .paddingLabel: "余白", .cornerRadiusLabel: "角丸", .shadowLabel: "シャドウ",
        .windowChromeTitle: "macOS タイトルバー", .chromeNone: "なし", .chromeDark: "ダーク", .chromeLight: "ライト", .windowTitlePlaceholder: "任意：ウィンドウタイトル", .glassStroke: "ガラス内枠線",
        .addTextTitle: "テキスト注釈を追加", .addTextPlaceholder: "表示するテキストを入力…", .addAction: "追加", .cancelAction: "キャンセル",
        .toastCopiedPNG: "Retina PNG をコピーしました", .toastSavedPNG: "~/Pictures/XShot に保存しました", .dragMeToX: "X にドラッグ",
        .pasteFromClipboard: "クリップボードから貼り付け (⌘⇧9)", .toastLoadedClipboardFormat: "クリップボード画像を読み込み · %d×%d", .customColorTooltip: "カスタムカラー（システムカラーパネル）",
        .privacyCardTitle: "プライバシー検出・自動隠し", .privacyScanBtn: "自動隠し", .privacyScanFullBtn: "機密情報をスキャンして隠す", .privacyScanning: "ローカル解析中…", .privacyClearAuto: "解除", .privacyStyleLabel: "隠しスタイル",
        .privacyCatApiKey: "APIキー", .privacyCatEmail: "メール", .privacyCatPhone: "電話番号", .privacyCatFinancialID: "カード/ID", .privacyCatIP: "IPアドレス",
        .privacyDetectedCountFormat: "%d件のプライバシー情報を自動で隠しました", .privacyNoneDetected: "機密情報は検出されませんでした", .privacyOnDeviceNote: "100% ローカル Vision OCR 処理 · 外部送信なし",
        .collageCardTitle: "複数画像レイアウト", .collageCountBadgeFormat: "%d枚", .collageAddFiles: "画像を追加", .collageAppendClipboard: "貼付で追加", .collageDropHint: "左のキャンバスへ画像を直接ドラッグ可能",
        .collageHorizontal: "横並び", .collageVertical: "縦並び", .collageGrid: "グリッド", .collageBento: "ベントー",
        .collageFitContain: "全体表示", .collageFitFill: "枠いっぱい", .collageSpacingLabel: "間隔", .toastAppendedImagesFormat: "%d枚追加しました · 合計%d枚",
        .sliceCardTitle: "画像分割・カット", .slicePreset1x2: "左右2分割", .slicePreset2x1: "上下2分割", .slicePreset3x1: "縦長3分割", .slicePreset2x2: "4分割", .slicePreset3x3: "9分割",
        .sliceRowsLabel: "行", .sliceColsLabel: "列", .sliceResetEqual: "均等", .sliceScopeRaw: "画像のみ", .sliceScopeBeautified: "装飾込み",
        .sliceDragLineHint: "プレビュー上の破線をドラッグして分割位置を微調整できます", .sliceExportBtnFormat: "%d枚の PNG に分割書き出し", .sliceToCollageBtn: "複数画像レイアウトへ", .sliceExportToastFormat: "%d枚の PNG を書き出し・コピーしました",
        .multiCollectEnableBtn: "連続マルチ", .multiCollectActiveTitle: "マルチ収集中", .multiCollectHintOff: "以降の撮影を自動追加", .multiCollectCountFormat: "%d/6 枚収集",
        .multiCollectBannerEmpty: "連続マルチON · 撮影やコピー画像を自動追加", .multiCollectBannerCountFormat: "連続マルチ · %d/6 枚（撮影で自動追加）", .multiCollectOpenEditor: "編集", .multiCollectPickFiles: "選択", .multiCollectStopBtn: "終了",
        .multiCollectCardToggle: "連続マルチ · 以降のスクショを自動追加", .multiCollectCaptureOne: "1枚撮る", .multiCollectLimitReached: "マルチ画像は最大 6 枚までです", .multiCollectCanvasBannerFormat: "連続マルチON (%d/6) · 撮影やコピー画像を自動追加",
        .quickMultiCollectTooltip: "連続マルチをON：以降のスクショを自動結合", .quickMultiCollectStopTooltip: "連続マルチ収集を終了", .quickMultiCollectTitleFormat: "マルチ収集 %d/6 枚 · 次の撮影も自動追加", .quickMultiArrangeFormat: "編集 (%d)",
        .openLocalVideoBtn: "ローカル動画を編集", .openLocalVideoHint: "MP4 / MOV のカット・倍速・装飾",
        .splitClipBtn: "分割", .splitClipTooltip: "再生位置でクリップを分割 (S)", .setTrimInTooltip: "再生位置を開始点に設定 (I)", .setTrimOutTooltip: "再生位置を終了点に設定 (O)", .stepBackTooltip: "0.1秒戻る (←)", .stepForwardTooltip: "0.1秒進む (→)",
        .deleteClipBtn: "クリップ削除", .clipSelectedFormat: "クリップ #%d", .clipSpeedLabel: "速度",
        .fadeCardTitle: "フェードイン・アウト", .fadeInLabel: "フェードイン", .fadeOutLabel: "フェードアウト", .audioVolumeLabel: "音量",
        .captureFrameBtn: "静止画", .captureFrameTooltip: "現在の装飾フレームをカバー画像として保存・コピー", .captureFrameToast: "現在のフレームを保存・コピーしました", .clipTimelineTip: "クリップ選択で倍速/削除 · S で分割 · ズーム端ドラッグで長さ調整",
        .trackVideoLabel: "映像", .trackZoomLabel: "ズーム", .trackAudioLabel: "音声", .snapToggleTooltip: "マグネット吸着（再生ヘッド・カット点）", .timelineZoomFit: "全体",
        .mergeNextClipBtn: "結合", .duplicateZoomBtn: "複製", .clearAllZoomsBtn: "全削除", .audioTrackMutedHint: "ミュート中（左のアイコンで解除）", .audioTrackNoAudioHint: "音声トラックなし", .timelineShortcutsHint: "Space 再生 · S 分割 · I/O トリム · ←/→ 微調整 · ⌘Z 元に戻す · ズーム欄ダブルクリックで追加",

        .exportMP4: "X 用 MP4 書き出し", .exportGIF: "GIF 書き出し", .exportDonePrefix: "書き出し完了 · ", .copyFileBtn: "コピー", .openFinderBtn: "Finder", .closeBtn: "閉じる",
        .zoomTargetHint: "プレビューをクリックしてズーム焦点を指定", .zoomBadgeFormat: "ズーム %.2fx", .loadingMetalPreview: "Metal GPU プレビュー準備中…",
        .backToTrimStart: "開始位置へ戻る", .resetTrim: "トリム解除", .addZoomBtn: "ズーム追加", .autoZoomSummaryFormat: "自動ズーム (%dクリック · %d入力)",
        .zoomTimelineEmptyHint: "ダブルクリックでズーム追加 · クリック/入力から自動生成", .zoomSegmentTyping: "入力フォーカスズーム", .zoomSegmentClick: "クリックズーム", .zoomScaleLabel: "倍率", .zoomEaseLabel: "イージング", .followCursorLabel: "追従", .deleteAction: "削除",
        .tabAppearance: "外観・背景", .tabMotionExport: "動き・キー表示",
        .cardSmartCamera: "スマートズーム", .toggleAutoZoom: "自動スムーズズーム", .clickZoomCountFormat: "クリック (%d)", .typingZoomCountFormat: "入力フォーカス (%d)",
        .toggleVectorCursor: "滑らかベクターカーソル", .cursorSizeLabel: "カーソルサイズ", .toggleClickRipples: "クリック波紋",
        .cardKeystrokeStylePos: "キー表示 · スタイルと位置", .toggleShowKeystrokesFormat: "キー入力を表示 (%d件)", .previewSample: "プレビュー", .hideSample: "隠す",
        .keycapStyleLabel: "キーキャップスタイル", .displayPositionLabel: "表示位置", .customPositionLabel: "カスタム", .dragPositionHint: "左のプレビュー上で直接ドラッグして自由に配置できます", .keycapSizeLabel: "サイズ",
        .noKeystrokesCapturedHint: "キー入力が記録されていません。システム設定の「アクセシビリティ」で XShot を許可してください。",
        .cardAudioTrack: "オーディオ", .toggleKeepAudio: "音声を含める（システム音 + マイク）",
        .cardEncodingPipeline: "高速ゼロコピーパイプライン", .specZeroCopy: "Metal GPU + IOSurface ゼロコピー合成", .specConstant60: "固定 60fps · VideoToolbox H.264", .specRec709: "Rec.709 sRGB 色ズレ防止", .specHighBitrate: "18〜42 Mbps 高ビットレート文字鮮明",

        .ratioAuto: "自動", .ratio16x9: "16:9 横長", .ratio4x3: "4:3 カード", .ratio1x1: "1:1 正方形", .ratio9x16: "9:16 縦長",
        .ratioShortAuto: "自動", .ratioShort16x9: "横長", .ratioShort4x3: "カード", .ratioShort1x1: "正方形", .ratioShort9x16: "縦長",
        .export1080pShort: "1080p 60fps (X 推奨)", .export2KShort: "2K 60fps (超高画質)", .export4KShort: "4K 60fps (最高)", .exportGIFShort: "滑らか GIF",
        .ksStyleDark: "ダークキー", .ksStyleLight: "ライトキー", .ksStyleMinimal: "ガラスピル", .ksStyleNeon: "ネオン枠",
        .ksPosTopLeft: "左上", .ksPosTopCenter: "上中央", .ksPosTopRight: "右上", .ksPosBottomLeft: "左下", .ksPosBottomCenter: "下中央", .ksPosBottomRight: "右下", .ksPosCustom: "自由配置",
        .ksFilterAll: "ショートカット + 入力", .ksFilterShortcutsOnly: "ショートカットのみ",
        .hkAreaShot: "範囲スクショ", .hkWindowShot: "ウィンドウスクショ", .hkRecordArea: "範囲録画", .hkStopRecord: "録画停止", .hkClipboardBeautify: "クリップボード画像を装飾",

        .settingsPermissionsSection: "システム権限", .permScreenTitle: "画面収録（必須）", .permScreenSub: "Retina スクショと 60fps 録画に必要です",
        .permMicTitle: "マイク（任意）", .permMicSub: "ナレーション音声を録音する場合に許可",
        .permAxTitle: "アクセシビリティ（キー表示 + 入力ズーム）", .permAxSub: "グローバルキー表示とテキストカーソル追従ズームに使用",
        .permGranted: "許可済み", .permAuthorizeBtn: "許可する", .refreshPermissions: "権限を再確認",
        .settingsDefaultsSection: "録画・撮影の既定設定", .defaultFPSLabel: "既定フレームレート", .fps60Label: "60 fps（推奨）", .fps120Label: "120 fps（ProMotion 超滑らか）",
        .defaultSysAudio: "システム音声を既定で録音", .defaultMic: "マイクを既定で録音", .defaultKeystrokes: "キー表示を既定で有効にする",
        .defaultKeystrokeStyle: "既定のキー表示スタイル", .defaultKeystrokePos: "既定のキー表示位置", .defaultKeystrokeFilter: "キー表示フィルター",
        .defaultTypingZoom: "入力フォーカス自動ズームを既定で有効", .defaultHideCursor: "録画中は標準カーソルを隠す（Studio カーソル使用）",
        .defaultAutoCopy: "撮影後にクリップボードへ自動コピー", .defaultAutoBeautify: "撮影時に自動装飾を適用", .defaultAutoPrivacy: "撮影/貼付時に機密情報（キー・メール・電話・IP）を自動で隠す", .defaultPrivacyStyle: "既定の隠しスタイル",
        .settingsHotkeysSection: "グローバルショートカット", .settingsPathsSection: "保存先フォルダ", .screenshotsDirLabel: "スクショ保存先", .recordingsDirLabel: "動画保存先", .openDirBtn: "開く",

        .alertScreenPermTitle: "「画面収録」権限が必要です",
        .alertScreenPermBody: "システム設定 → プライバシーとセキュリティ → 画面収録とシステムオーディオ録音 で XShot をオンにし、アプリを再起動してください。",
        .openSystemSettings: "システム設定を開く", .laterBtn: "あとで", .alertNoticeTitle: "XShot", .okBtn: "OK",
        .quitXShotMenu: "XShot を終了", .errRecordingInterruptedFormat: "録画が予期せず中断されました：%@", .statusRecordingFormat: "%dfps で高画質録画中…", .statusGeneratingStudio: "Studio タイムラインと自動ズームを生成中…",
        .errAlreadyRecording: "現在すでに録画中です。", .errNotRecording: "停止できる録画がありません。", .errDisplayNotFound: "対象のディスプレイが見つかりません。", .errWindowNotFound: "対象のウィンドウが見つかりません。", .errWindowNotFoundClosed: "対象のウィンドウが見つかりません（閉じられたか最小化されています）。",
        .errWriterSetupFailedFormat: "録画エンコーダーの初期化に失敗：%@", .errNoFramesCaptured: "有効な映像フレームを取得できませんでした。画面収録権限を確認してください。", .errCaptureFailedFormat: "スクリーンショットに失敗：%@",
        .errNoVideoTrack: "録画ファイルに映像トラックが見つかりません。", .errReadVideoFailedFormat: "元動画を読み込めません：%@", .errWriteVideoFailedFormat: "書き出し動画を作成できません：%@", .errRenderFrameFailed: "映像フレームの合成に失敗しました。", .errExportCancelled: "書き出しをキャンセルしました。",
        .errGIFInitFailed: "GIF 出力ファイルを初期化できません。", .errGIFWriteFailed: "GIF の書き出しに失敗しました。",
        .timelineZoomInTooltip: "タイムラインを拡大 (⌘+)", .timelineZoomOutTooltip: "タイムラインを縮小 (⌘-)",
        .hkExtractText: "テキスト抽出 (OCR)", .ocrMenuTitle: "画面から文字抽出", .ocrMenuHint: "範囲選択で文字を自動コピー", .ocrWindowTitle: "XShot · テキスト抽出 (OCR)", .ocrCardTitle: "テキスト抽出 (OCR)", .ocrExtractBtn: "画像から文字を抽出", .ocrScanning: "オンデバイス認識中…",
        .ocrAutoCopiedBannerFormat: "自動コピー済み · %d行 · %d文字", .ocrStatsFormat: "%d行 · %d文字", .ocrNoTextFound: "画像からテキストが見つかりませんでした", .ocrModeKeepLines: "改行を維持", .ocrModeJoinParagraphs: "段落を結合",
        .ocrViewEditor: "テキスト編集", .ocrViewLines: "行ごとにコピー", .ocrCopyAllBtn: "すべてコピー", .ocrCopiedToast: "テキストをコピーしました", .ocrCopiedLineToast: "この行をコピーしました",
        .ocrCanvasOverlayToggle: "キャンバス文字枠（クリックで1行コピー）", .ocrOpenEditorBtn: "画像を装飾", .quickOCRTooltip: "画像からテキスト抽出 (OCR)",
        .hkScrollShot: "スクロール長尺キャプチャ", .hkClickToRecordTooltip: "クリックしてショートカットを登録", .hkPressKeysHint: "キーを入力… (Esc)", .hkNeedModifierHint: "⌘ / ⌥ / ⌃ キーまたは F1–F12 を含めてください", .hkConflictFormat: "%@ は「%@」で使用中です", .hkResetSingleTooltip: "デフォルトに戻す", .hkResetAllBtn: "すべて初期設定に戻す",
        .watermarkCardTitle: "カスタム透かし署名", .watermarkTextPlaceholder: "署名または @ハンドル（例: @XShot）", .watermarkStyleGlass: "グラス", .watermarkStyleMinimal: "ミニマル", .watermarkStyleBadge: "バッジ", .watermarkPosTiled: "タイル敷き",
        .watermarkOpacityLabel: "不透明度", .watermarkScaleLabel: "サイズ", .watermarkBrandGlyph: "マーク ✦", .watermarkSaveDefaultBtn: "デフォルト保存", .watermarkSavedDefaultToast: "デフォルト透かしを保存しました", .defaultWatermarkToggle: "デフォルトで透かしを有効化",
        .scrollMenuTitle: "スクロール撮影", .scrollMenuHint: "範囲を選択してスクロールすると自動で長尺結合", .scrollHudTitle: "スクロール長尺結合中", .scrollHudHint: "枠内を下へスクロールすると自動結合（Returnで完了 / Escでキャンセル）", .scrollFramesBadgeFormat: "%d 枚",
        .scrollAutoStartBtn: "自動スクロール", .scrollAutoStopBtn: "一時停止", .scrollManualAppendTooltip: "現在の画面を手動追加", .scrollFinishBtn: "完了", .scrollLimitReached: "最大結合高さに達しました。「完了」を押してください",
        .toggleWebcamPiP: "カメラ PiP", .defaultWebcamPiP: "録画時にカメラ ピクチャ・イン・ピクチャを有効化", .permCameraTitle: "カメラ", .permCameraSub: "画面録画と同時にカメラ映像を記録し、Studioで形や位置を自在に調整します", .webcamCardTitle: "カメラ PiP",
        .webcamShapeCircle: "円形", .webcamShapeRounded: "角丸", .webcamShapeVertical: "縦型", .webcamSizeLabel: "サイズ", .webcamMirrorLabel: "左右反転", .webcamBorderLabel: "枠線",
        .webcamNoTrackHint: "カメラ映像が含まれていません。録画前にカメラPiPをオンにするか、ローカル動画を読み込みます。", .webcamAttachLocalBtn: "カメラ動画を読み込む…",
        .viewModeFit: "全体", .viewModeFitWidth: "幅に合わせる", .viewModeActual: "1:1",
        .viewModeFitTooltip: "ウィンドウ全体に表示 (⌘0)", .viewModeFitWidthTooltip: "幅に合わせて縦長画像をくっきりスクロール閲覧 (⌘2)", .viewModeActualTooltip: "100% 原寸表示 (⌘1)", .viewZoomOutTooltip: "縮小 (⌘-)", .viewZoomInTooltip: "拡大 (⌘+)",
        .authErrInvalidToken: "トークン形式が無効です。xtags_ で始まる完全なトークンをコピーしてください。", .authErrUnauthorized: "XTags の認証期限が切れているか無効です。再度ログインしてください。", .authErrServer: "XTags サーバーから予期しない応答がありました。",
        .updErrInvalidRelease: "GitHub の最新リリース情報を取得できませんでした。", .updErrNoBinary: "このリリースに macOS 用バイナリが見つかりません。", .updErrChecksum: "SHA-256 チェックサムの検証に失敗したため更新を中止しました。", .updErrSignature: "アプリ署名の検証に失敗したためインストールを中止しました。",
        .xtagsAccountSection: "XTags アカウントと自動更新", .xtagsSignInBtn: "XTags でログイン", .xtagsSignOutBtn: "ログアウト", .xtagsSignedOutHint: "ログインすると DMG 不要のシームレス自動更新が有効になります", .xtagsAutoUpdateBadge: "自動更新オン",
        .xtagsLoginWindowTitle: "XTags アカウントにログイン", .xtagsLoginSubtitle: "XTags でログインすると、DMG を開かずバックグラウンドで直接置換・再起動するシームレス自動更新が利用できます。",
        .xtagsLoginStepBrowser: "ブラウザで xtags.top を開きました。X / Google / GitHub でログインしてください。", .xtagsLoginOpenBrowserBtn: "ブラウザでログイン", .xtagsLoginWaitingHint: "コールバックまたはクリップボードのトークンを待機中（Web 側でコピーすると自動認証）…",
        .xtagsLoginTokenPlaceholder: "または xtags_ext_... トークンを手動貼り付け", .xtagsLoginVerifyBtn: "認証してログイン", .xtagsLoginVerifying: "XTags アカウントを認証中…", .xtagsLoginSuccessFormat: "%@ としてログイン中",
        .updSectionTitle: "ソフトウェアアップデート", .updCurrentVersionFormat: "現在のバージョン v%@", .updAutoToggleLabel: "シームレス自動更新（DMG 不要・直接置換して再起動）", .updAutoRequiresSignInHint: "自動更新を有効にするには XTags でログインしてください",
        .updCheckNowBtn: "アップデートを確認", .updChecking: "更新を確認中…", .updUpToDate: "最新バージョンです", .updAvailableFormat: "v%@ が利用可能", .updDownloadingFormat: "v%@ をダウンロード中 · %d%%",
        .updVerifying: "SHA-256 と署名を検証中…", .updReadyFormat: "v%@ 準備完了 · クリックで再起動", .updInstalling: "アプリを置換して再起動中…", .updUpdateNowBtn: "今すぐ更新", .updRestartApplyBtn: "再起動して適用", .updOpenReleasesBtn: "GitHub からダウンロード", .updSeamlessNote: "DMG を開いたりドラッグする必要なく、安全にアプリ本体を直接更新して再起動します。"
    ]

    // MARK: - 한국어
    private static let koStrings: [L10nKey: String] = [
        .themeSystem: "시스템 설정", .themeLight: "라이트", .themeDark: "다크",
        .langSystem: "시스템 언어",
        .appearanceSection: "화면 모드 및 언어", .appearanceMode: "화면 모드", .appLanguage: "표시 언어",

        .appSubtitle: "Retina 캡처 & 60fps X 녹화", .grantPermission: "권한 허용", .recordingBannerFormat: "녹화 중 %@ · 클릭하여 중지",
        .sectionScreenshot: "고화질 스크린샷", .sectionScreenshotMeta: "Retina 2x · 자동 복사", .sectionRecording: "부드러운 화면 녹화", .sectionRecordingMeta: "자동 줌 · X 전용 MP4",
        .areaScreenshot: "영역 캡처", .windowScreenshot: "창 캡처", .fullscreenScreenshot: "전체 화면",
        .clipboardBeautifyTitle: "클립보드 이미지 꾸미기", .clipboardBeautifyHint: "복사한 이미지를 바로 꾸미기", .clipboardReadyFormat: "이미지 감지됨 · %d×%d", .clipboardEmptyAlert: "클립보드에 이미지가 없습니다. 먼저 이미지나 Finder에서 이미지 파일을 복사해 주세요.",
        .collageMenuTitle: "다중 이미지 배치", .collageMenuHint: "여러 스크린샷을 한 장으로 정렬",
        .areaRecording: "영역 녹화", .windowRecording: "창 녹화", .fullscreenRecording: "전체 녹화", .clickToStart: "클릭하여 시작",
        .toggleSystemAudio: "시스템 오디오", .toggleMic: "마이크", .toggleKeystrokes: "키 입력 표시", .toggleTypingFocus: "입력 포커스 줌", .toggleSmoothCursor: "부드러운 커서", .toggleAutoBeautify: "캡처 자동 꾸미기", .toggleAutoPrivacy: "개인정보 자동 가림",
        .accessibilityHintBanner: "전역 키 입력 표시와 입력 포커스 줌을 위해 「손쉬운 사용」을 허용하세요",
        .recentWorks: "최근 작업", .dragToXHint: "X로 바로 드래그", .copyFile: "파일 복사", .revealInFinder: "Finder에서 보기",
        .settingsAndPermissions: "설정 및 권한", .outputFolder: "출력 폴더", .quitApp: "종료",

        .hudDone: "완료", .hudPauseTooltip: "일시 정지", .hudResumeTooltip: "녹화 재개", .hudStopTooltip: "녹화 중지 후 Studio 열기 (⌘⇧8)",
        .overlayHintRecording: "드래그하여 녹화 영역 선택 (모서리 조절 / 16:9 스냅) · Esc 취소",
        .overlayHintScreenshot: "드래그하여 Retina 캡처 · 놓으면 즉시 촬영 · Esc 취소",
        .overlayHintWindow: "대상 창에 마우스를 올리고 클릭 · Esc 취소",
        .overlayStartRecording: "⏺ 녹화 시작 (Enter)", .overlayCancel: "취소",
        .overlayWindowRecordPrefix: "창 녹화 · ", .overlayWindowShotPrefix: "창 캡처 · ",

        .quickCopiedTitle: "복사됨 · ⌘V로 바로 붙여넣기", .quickShotDoneTitle: "Retina 캡처 완료", .quickVideoReadyTitle: "%@ 완료 · X로 드래그",
        .quickDragToX: "X로 드래그", .quickBeautifyEdit: "꾸미기 / 주석", .quickRevealFinder: "Finder 보기", .quickCopy: "복사", .quickCopied: "복사됨", .quickPin: "화면 고정",

        .windowTitleScreenshot: "XShot · 스크린샷 스튜디오", .windowTitleStudio: "XShot Studio · X 영상 편집", .windowTitleSettings: "XShot 설정 및 권한",
        .toolSelect: "선택", .toolArrow: "화살표", .toolRectangle: "사각형", .toolEllipse: "원형", .toolHighlighter: "형광펜", .toolText: "텍스트", .toolStep: "번호", .toolMosaic: "모자이크", .toolBlur: "블러",
        .undo: "실행 취소 (⌘Z)", .redo: "다시 실행 (⌘⇧Z)", .deleteSelected: "선택 삭제", .clearAll: "모두 지우기", .pinAction: "고정", .saveAction: "저장", .copyForX: "PNG 복사",
        .beautifyShell: "트윗 꾸미기 프레임", .quickPresets: "빠른 프리셋", .presetAurora: "오로라", .presetDarkWindow: "다크 창", .presetCleanLight: "라이트 카드", .presetNeon: "네온 X", .presetDarkGeek: "옵시디언", .presetNoFrame: "프레임 없음",
        .backgroundWallpaper: "배경 화면", .wallpaperTabGradients: "그라데이션", .wallpaperTabSystem: "시스템 배경", .wallpaperDesktopName: "현재 데스크톱", .wallpaperPickLocal: "이미지 선택…", .wallpaperLoadingSystem: "macOS 배경 불러오는 중…",
        .canvasAspectX: "화면 비율 (X 피드)", .paddingAndDepth: "여백 및 입체감", .paddingLabel: "여백", .cornerRadiusLabel: "모서리 둥글기", .shadowLabel: "그림자",
        .windowChromeTitle: "macOS 타이틀 바", .chromeNone: "없음", .chromeDark: "다크", .chromeLight: "라이트", .windowTitlePlaceholder: "선택: 창 제목 입력", .glassStroke: "글래스 내부 테두리",
        .addTextTitle: "텍스트 주석 추가", .addTextPlaceholder: "표시할 텍스트를 입력하세요…", .addAction: "추가", .cancelAction: "취소",
        .toastCopiedPNG: "Retina PNG 복사됨 · ⌘V로 게시", .toastSavedPNG: "~/Pictures/XShot에 저장됨", .dragMeToX: "X로 드래그",
        .pasteFromClipboard: "클립보드에서 이미지 불러오기 (⌘⇧9)", .toastLoadedClipboardFormat: "클립보드 이미지 불러옴 · %d×%d", .customColorTooltip: "사용자 지정 색상 (시스템 색상 패널)",
        .privacyCardTitle: "개인정보 감지 및 자동 모자이크", .privacyScanBtn: "자동 모자이크", .privacyScanFullBtn: "민감 정보 스캔 및 자동 가림", .privacyScanning: "온디바이스 분석 중…", .privacyClearAuto: "해제", .privacyStyleLabel: "가림 스타일",
        .privacyCatApiKey: "키/토큰", .privacyCatEmail: "이메일", .privacyCatPhone: "전화번호", .privacyCatFinancialID: "카드/신분증", .privacyCatIP: "IP 주소",
        .privacyDetectedCountFormat: "민감한 정보 %d건을 자동으로 가렸습니다", .privacyNoneDetected: "감지된 민감 정보가 없습니다", .privacyOnDeviceNote: "100% 온디바이스 Vision OCR · 외부 전송 없음",
        .collageCardTitle: "다중 이미지 배치", .collageCountBadgeFormat: "%d장", .collageAddFiles: "이미지 추가", .collageAppendClipboard: "클립보드 추가", .collageDropHint: "왼쪽 캔버스에 이미지를 바로 드래그할 수 있습니다",
        .collageHorizontal: "가로", .collageVertical: "세로", .collageGrid: "그리드", .collageBento: "벤토",
        .collageFitContain: "전체 보기", .collageFitFill: "꽉 채우기", .collageSpacingLabel: "간격", .toastAppendedImagesFormat: "%d장 추가됨 · 총 %d장",
        .sliceCardTitle: "이미지 분할", .slicePreset1x2: "좌우 2분할", .slicePreset2x1: "상하 2분할", .slicePreset3x1: "긴 이미지 3분할", .slicePreset2x2: "4분할", .slicePreset3x3: "9분할",
        .sliceRowsLabel: "행", .sliceColsLabel: "열", .sliceResetEqual: "균등", .sliceScopeRaw: "원본만", .sliceScopeBeautified: "배경 포함",
        .sliceDragLineHint: "캔버스의 점선을 드래그해 분할 위치를 미세 조정하세요", .sliceExportBtnFormat: "%d장 PNG로 분할 내보내기", .sliceToCollageBtn: "다중 이미지 배치로 변환", .sliceExportToastFormat: "%d장 PNG 분할 완료 · 파일 복사됨",
        .multiCollectEnableBtn: "다중 수집", .multiCollectActiveTitle: "수집 켜짐", .multiCollectHintOff: "이후 캡처 자동 추가", .multiCollectCountFormat: "%d/6장 수집",
        .multiCollectBannerEmpty: "다중 수집 켜짐 · 캡처/복사 이미지 자동 추가", .multiCollectBannerCountFormat: "다중 수집 · %d/6장 (캡처 시 자동 추가)", .multiCollectOpenEditor: "배치", .multiCollectPickFiles: "파일", .multiCollectStopBtn: "종료",
        .multiCollectCardToggle: "다중 수집 · 이후 캡처 자동 추가", .multiCollectCaptureOne: "한 장 캡처", .multiCollectLimitReached: "다중 이미지 보드가 가득 찼습니다 (최대 6장)", .multiCollectCanvasBannerFormat: "다중 수집 켜짐 (%d/6) · 이후 캡처/복사 이미지 자동 추가",
        .quickMultiCollectTooltip: "다중 수집 켜기: 이후 캡처를 자동으로 합치기", .quickMultiCollectStopTooltip: "다중 자동 수집 중지", .quickMultiCollectTitleFormat: "다중 수집 %d/6장 · 다음 캡처 자동 추가", .quickMultiArrangeFormat: "배치 (%d)",
        .openLocalVideoBtn: "로컬 영상 편집", .openLocalVideoHint: "MP4 / MOV 컷 편집·배속·꾸미기",
        .splitClipBtn: "분할", .splitClipTooltip: "현재 재생 헤드에서 클립 분할 (S)", .setTrimInTooltip: "현재 위치를 시작점으로 자르기 (I)", .setTrimOutTooltip: "현재 위치를 종료점으로 자르기 (O)", .stepBackTooltip: "0.1초 뒤로 (←)", .stepForwardTooltip: "0.1초 앞으로 (→)",
        .deleteClipBtn: "클립 삭제", .clipSelectedFormat: "클립 #%d", .clipSpeedLabel: "속도",
        .fadeCardTitle: "페이드 인 / 아웃", .fadeInLabel: "페이드 인", .fadeOutLabel: "페이드 아웃", .audioVolumeLabel: "음량",
        .captureFrameBtn: "프레임", .captureFrameTooltip: "현재 꾸며진 프레임을 커버 이미지로 저장 및 복사", .captureFrameToast: "현재 프레임을 저장 및 복사했습니다", .clipTimelineTip: "클립 클릭으로 배속/삭제 · S 분할 · 줌 가장자리 드래그로 길이 조절",
        .trackVideoLabel: "비디오", .trackZoomLabel: "줌", .trackAudioLabel: "오디오", .snapToggleTooltip: "자석 스냅 (재생 헤드 및 컷 경계)", .timelineZoomFit: "맞춤",
        .mergeNextClipBtn: "병합", .duplicateZoomBtn: "복제", .clearAllZoomsBtn: "줌 비우기", .audioTrackMutedHint: "음소거됨 (왼쪽 아이콘으로 해제)", .audioTrackNoAudioHint: "오디오 트랙 없음", .timelineShortcutsHint: "Space 재생 · S 분할 · I/O 자르기 · ←/→ 이동 · ⌘Z 실행 취소 · 줌 트랙 더블클릭으로 추가",

        .exportMP4: "X용 MP4 내보내기", .exportGIF: "GIF 내보내기", .exportDonePrefix: "내보내기 완료 · ", .copyFileBtn: "파일 복사", .openFinderBtn: "Finder", .closeBtn: "닫기",
        .zoomTargetHint: "미리보기 화면을 클릭해 줌 초점을 지정하세요", .zoomBadgeFormat: "확대 %.2fx", .loadingMetalPreview: "Metal GPU 미리보기 준비 중…",
        .backToTrimStart: "트림 시작으로 이동", .resetTrim: "트림 초기화", .addZoomBtn: "줌 추가", .autoZoomSummaryFormat: "자동 줌 (%d클릭 · %d입력)",
        .zoomTimelineEmptyHint: "더블클릭하여 줌 추가 · 클릭/타이핑 시 자동 생성", .zoomSegmentTyping: "입력 포커스 줌", .zoomSegmentClick: "클릭 줌", .zoomScaleLabel: "배율", .zoomEaseLabel: "부드러움", .followCursorLabel: "커서 추적", .deleteAction: "삭제",
        .tabAppearance: "화면 외관", .tabMotionExport: "모션 및 키 표시",
        .cardSmartCamera: "스마트 줌 및 포커스", .toggleAutoZoom: "부드러운 자동 줌", .clickZoomCountFormat: "클릭 줌 (%d)", .typingZoomCountFormat: "입력 포커스 (%d)",
        .toggleVectorCursor: "부드러운 벡터 커서", .cursorSizeLabel: "커서 크기", .toggleClickRipples: "클릭 파동 효과",
        .cardKeystrokeStylePos: "키 입력 · 스타일 및 위치", .toggleShowKeystrokesFormat: "키 입력 표시 (%d건)", .previewSample: "미리보기", .hideSample: "숨기기",
        .keycapStyleLabel: "키캡 스타일", .displayPositionLabel: "표시 위치", .customPositionLabel: "사용자 지정", .dragPositionHint: "왼쪽 미리보기 화면에서 마우스로 직접 드래그해 배치하세요", .keycapSizeLabel: "키캡 크기",
        .noKeystrokesCapturedHint: "기록된 키 입력이 없습니다. 시스템 설정 → 개인정보 보호 → 손쉬운 사용에서 XShot를 허용하세요.",
        .cardAudioTrack: "오디오 트랙", .toggleKeepAudio: "오디오 포함 (시스템음 + 마이크)",
        .cardEncodingPipeline: "초고속 제로카피 파이프라인", .specZeroCopy: "Metal GPU + IOSurface 제로카피 합성", .specConstant60: "고정 60fps · VideoToolbox H.264", .specRec709: "Rec.709 sRGB 색 왜곡 방지", .specHighBitrate: "18~42 Mbps 고비트레이트 선명한 텍스트",

        .ratioAuto: "자동", .ratio16x9: "16:9 가로", .ratio4x3: "4:3 카드", .ratio1x1: "1:1 정사각형", .ratio9x16: "9:16 세로",
        .ratioShortAuto: "자동", .ratioShort16x9: "가로", .ratioShort4x3: "카드", .ratioShort1x1: "정사각", .ratioShort9x16: "세로",
        .export1080pShort: "1080p 60fps (X 추천)", .export2KShort: "2K 60fps (초고화질)", .export4KShort: "4K 60fps (최고)", .exportGIFShort: "부드러운 GIF",
        .ksStyleDark: "다크 키캡", .ksStyleLight: "라이트 키캡", .ksStyleMinimal: "글래스 필", .ksStyleNeon: "네온 테두리",
        .ksPosTopLeft: "좌상", .ksPosTopCenter: "상단", .ksPosTopRight: "우상", .ksPosBottomLeft: "좌하", .ksPosBottomCenter: "하단", .ksPosBottomRight: "우하", .ksPosCustom: "직접 드래그",
        .ksFilterAll: "단축키 + 타이핑", .ksFilterShortcutsOnly: "단축키만",
        .hkAreaShot: "영역 스크린샷", .hkWindowShot: "창 스크린샷", .hkRecordArea: "영역 녹화", .hkStopRecord: "녹화 중지", .hkClipboardBeautify: "클립보드 이미지 꾸미기",

        .settingsPermissionsSection: "시스템 권한", .permScreenTitle: "화면 기록 (필수)", .permScreenSub: "Retina 캡처 및 60fps 녹화에 필요합니다",
        .permMicTitle: "마이크 (선택)", .permMicSub: "음성 나레이션 녹음 시 사용",
        .permAxTitle: "손쉬운 사용 (키 입력 + 입력 포커스 줌)", .permAxSub: "전역 키캡 표시 및 텍스트 커서 추적 자동 줌에 사용",
        .permGranted: "허용됨", .permAuthorizeBtn: "허용하기", .refreshPermissions: "권한 새로고침",
        .settingsDefaultsSection: "녹화 및 캡처 기본값", .defaultFPSLabel: "기본 녹화 프레임", .fps60Label: "60 fps (추천)", .fps120Label: "120 fps (ProMotion 초부드러움)",
        .defaultSysAudio: "기본으로 시스템 오디오 녹음", .defaultMic: "기본으로 마이크 녹음", .defaultKeystrokes: "기본으로 키 입력 표시 사용",
        .defaultKeystrokeStyle: "기본 키캡 스타일", .defaultKeystrokePos: "기본 키캡 위치", .defaultKeystrokeFilter: "키 입력 필터",
        .defaultTypingZoom: "기본으로 입력 포커스 자동 줌 사용", .defaultHideCursor: "녹화 시 시스템 커서 숨기기 (Studio 커서 사용)",
        .defaultAutoCopy: "캡처 후 클립보드 자동 복사", .defaultAutoBeautify: "캡처 시 자동 꾸미기 적용", .defaultAutoPrivacy: "캡처/붙여넣기 시 민감 정보(키·이메일·전화·IP) 자동 가림", .defaultPrivacyStyle: "기본 가림 스타일",
        .settingsHotkeysSection: "전역 단축키", .settingsPathsSection: "출력 폴더", .screenshotsDirLabel: "스크린샷 폴더", .recordingsDirLabel: "동영상 폴더", .openDirBtn: "열기",

        .alertScreenPermTitle: "「화면 기록」 권한이 필요합니다",
        .alertScreenPermBody: "시스템 설정 → 개인정보 보호 및 보안 → 화면 및 시스템 오디오 기록에서 XShot를 활성화한 뒤 앱을 다시 실행해 주세요.",
        .openSystemSettings: "시스템 설정 열기", .laterBtn: "나중에", .alertNoticeTitle: "XShot 알림", .okBtn: "확인",
        .quitXShotMenu: "XShot 종료", .errRecordingInterruptedFormat: "녹화가 예기치 않게 중단되었습니다: %@", .statusRecordingFormat: "%dfps 고화질 녹화 중…", .statusGeneratingStudio: "Studio 타임라인 및 자동 줌 생성 중…",
        .errAlreadyRecording: "이미 녹화가 진행 중입니다.", .errNotRecording: "중지할 녹화가 없습니다.", .errDisplayNotFound: "대상 디스플레이를 찾을 수 없습니다.", .errWindowNotFound: "대상 창을 찾을 수 없습니다.", .errWindowNotFoundClosed: "대상 창을 찾을 수 없습니다 (닫혔거나 최소화됨).",
        .errWriterSetupFailedFormat: "녹화 인코더 초기화 실패: %@", .errNoFramesCaptured: "유효한 비디오 프레임을 캡처하지 못했습니다. 화면 기록 권한을 확인해 주세요.", .errCaptureFailedFormat: "스크린샷 실패: %@",
        .errNoVideoTrack: "녹화 파일에서 비디오 트랙을 찾을 수 없습니다.", .errReadVideoFailedFormat: "원본 동영상을 읽을 수 없습니다: %@", .errWriteVideoFailedFormat: "내보내기 동영상을 생성할 수 없습니다: %@", .errRenderFrameFailed: "비디오 프레임 합성에 실패했습니다.", .errExportCancelled: "내보내기가 취소되었습니다.",
        .errGIFInitFailed: "GIF 출력 파일을 초기화할 수 없습니다.", .errGIFWriteFailed: "GIF 쓰기에 실패했습니다.",
        .timelineZoomInTooltip: "타임라인 확대 (⌘+)", .timelineZoomOutTooltip: "타임라인 축소 (⌘-)",
        .hkExtractText: "텍스트 추출 (OCR)", .ocrMenuTitle: "화면 텍스트 추출", .ocrMenuHint: "영역 캡처로 텍스트 자동 복사", .ocrWindowTitle: "XShot · 텍스트 추출 (OCR)", .ocrCardTitle: "텍스트 추출 (OCR)", .ocrExtractBtn: "이미지에서 텍스트 추출", .ocrScanning: "온디바이스 인식 중…",
        .ocrAutoCopiedBannerFormat: "자동 복사됨 · %d줄 · %d자", .ocrStatsFormat: "%d줄 · %d자", .ocrNoTextFound: "이미지에서 텍스트를 찾지 못했습니다", .ocrModeKeepLines: "줄바꿈 유지", .ocrModeJoinParagraphs: "문단 합치기",
        .ocrViewEditor: "텍스트 편집", .ocrViewLines: "줄별 복사", .ocrCopyAllBtn: "전체 복사", .ocrCopiedToast: "텍스트가 클립보드에 복사되었습니다", .ocrCopiedLineToast: "선택한 줄을 복사했습니다",
        .ocrCanvasOverlayToggle: "캔버스 텍스트 박스 (클릭하여 한 줄 복사)", .ocrOpenEditorBtn: "이미지 꾸미기", .quickOCRTooltip: "스크린샷 텍스트 추출 (OCR)",
        .hkScrollShot: "스크롤 긴 캡처", .hkClickToRecordTooltip: "클릭하여 단축키 지정", .hkPressKeysHint: "키 입력… (Esc)", .hkNeedModifierHint: "⌘ / ⌥ / ⌃ 보조 키 또는 F1–F12를 포함하세요", .hkConflictFormat: "%@ 단축키가 「%@」에서 사용 중입니다", .hkResetSingleTooltip: "기본값 복원", .hkResetAllBtn: "모든 단축키 초기화",
        .watermarkCardTitle: "사용자 워터마크", .watermarkTextPlaceholder: "서명 또는 @계정 (예: @XShot)", .watermarkStyleGlass: "글래스", .watermarkStyleMinimal: "미니멀", .watermarkStyleBadge: "배지", .watermarkPosTiled: "바둑판",
        .watermarkOpacityLabel: "투명도", .watermarkScaleLabel: "크기", .watermarkBrandGlyph: "심볼 ✦", .watermarkSaveDefaultBtn: "기본값 저장", .watermarkSavedDefaultToast: "기본 워터마크로 저장됨", .defaultWatermarkToggle: "기본으로 워터마크 표시",
        .scrollMenuTitle: "스크롤 캡처", .scrollMenuHint: "영역 선택 후 스크롤하면 긴 이미지로 자동 이어붙임", .scrollHudTitle: "스크롤 긴 캡처 중", .scrollHudHint: "영역 안에서 아래로 스크롤하면 자동 결합 (Enter 완료 / Esc 취소)", .scrollFramesBadgeFormat: "%d 프레임",
        .scrollAutoStartBtn: "자동 스크롤", .scrollAutoStopBtn: "일시 정지", .scrollManualAppendTooltip: "현재 화면 수동 추가", .scrollFinishBtn: "완료", .scrollLimitReached: "최대 결합 높이에 도달했습니다. 완료를 누르세요",
        .toggleWebcamPiP: "웹캠 PiP", .defaultWebcamPiP: "녹화 시 웹캠 PIP(화면 속 화면) 함께 녹화", .permCameraTitle: "카메라", .permCameraSub: "화면 녹화와 함께 웹캠을 별도 트랙으로 기록하여 Studio에서 자유롭게 편집합니다", .webcamCardTitle: "웹캠 PiP",
        .webcamShapeCircle: "원형", .webcamShapeRounded: "둥근 사각형", .webcamShapeVertical: "세로 카드", .webcamSizeLabel: "크기", .webcamMirrorLabel: "좌우 반전", .webcamBorderLabel: "테두리",
        .webcamNoTrackHint: "웹캠 트랙이 없습니다. 녹화 전 웹캠 PiP를 켜거나 로컬 카메라 영상을 불러오세요.", .webcamAttachLocalBtn: "카메라 영상 불러오기…",
        .viewModeFit: "전체", .viewModeFitWidth: "너비맞춤", .viewModeActual: "1:1",
        .viewModeFitTooltip: "창에 전체 맞춤 (⌘0)", .viewModeFitWidthTooltip: "너비에 맞춰 긴 이미지 선명하게 스크롤 (⌘2)", .viewModeActualTooltip: "100% 원본 크기 (⌘1)", .viewZoomOutTooltip: "축소 (⌘-)", .viewZoomInTooltip: "확대 (⌘+)",
        .authErrInvalidToken: "토큰 형식이 올바르지 않습니다. 전체 xtags_ 토큰을 복사해 주세요.", .authErrUnauthorized: "XTags 인증이 만료되었거나 유효하지 않습니다. 다시 로그인해 주세요.", .authErrServer: "XTags 서버 응답을 처리할 수 없습니다.",
        .updErrInvalidRelease: "GitHub 최신 릴리스 정보를 불러오지 못했습니다.", .updErrNoBinary: "이 릴리스에서 macOS 바이너리 압축 파일을 찾지 못했습니다.", .updErrChecksum: "SHA-256 무결성 검증에 실패해 업데이트를 중단했습니다.", .updErrSignature: "앱 번들 서명 검증에 실패했습니다.",
        .xtagsAccountSection: "XTags 계정 및 자동 업데이트", .xtagsSignInBtn: "XTags 로그인", .xtagsSignOutBtn: "로그아웃", .xtagsSignedOutHint: "로그인하면 DMG 없이 바로 교체되는 자동 업데이트가 활성화됩니다", .xtagsAutoUpdateBadge: "자동 업데이트 켜짐",
        .xtagsLoginWindowTitle: "XTags 계정 로그인", .xtagsLoginSubtitle: "XTags 계정에 로그인하면 DMG 열기나 드래그 없이 백그라운드에서 바로 교체·재실행되는 무중단 자동 업데이트를 사용할 수 있습니다.",
        .xtagsLoginStepBrowser: "브라우저에서 xtags.top을 열었습니다. X / Google / GitHub으로 로그인하세요.", .xtagsLoginOpenBrowserBtn: "브라우저에서 로그인", .xtagsLoginWaitingHint: "콜백 또는 복사된 토큰 감지 대기 중 (웹에서 복사 클릭 시 자동 완료)…",
        .xtagsLoginTokenPlaceholder: "또는 xtags_ext_... 토큰을 직접 붙여넣기", .xtagsLoginVerifyBtn: "확인 후 로그인", .xtagsLoginVerifying: "XTags 계정 확인 중…", .xtagsLoginSuccessFormat: "%@ 로그인됨",
        .updSectionTitle: "소프트웨어 업데이트", .updCurrentVersionFormat: "현재 버전 v%@", .updAutoToggleLabel: "무중단 자동 업데이트 (DMG 없이 바로 교체 및 재실행)", .updAutoRequiresSignInHint: "자동 업데이트를 켜려면 XTags에 로그인하세요",
        .updCheckNowBtn: "업데이트 확인", .updChecking: "업데이트 확인 중…", .updUpToDate: "최신 버전입니다", .updAvailableFormat: "v%@ 업데이트 가능", .updDownloadingFormat: "v%@ 다운로드 중 · %d%%",
        .updVerifying: "SHA-256 및 서명 검증 중…", .updReadyFormat: "v%@ 준비 완료 · 클릭해 재실행", .updInstalling: "앱 교체 및 재실행 중…", .updUpdateNowBtn: "지금 바로 업데이트", .updRestartApplyBtn: "재실행하여 적용", .updOpenReleasesBtn: "GitHub에서 다운로드", .updSeamlessNote: "DMG 마운트나 드래그 없이 설치된 XShot.app을 안전하게 교체하고 즉시 재실행합니다."
    ]
}
