import AppKit
import SwiftUI

public struct MenuBarView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var permissions: PermissionManager
    @ObservedObject var authManager: XTagsAuthManager
    @ObservedObject var updater: AppUpdaterManager
    @ObservedObject private var uiStore = ThemeLocaleStore.shared
    @Environment(\.colorScheme) private var colorScheme
    let dismissPopover: () -> Void

    public init(appState: AppState, permissions: PermissionManager, dismissPopover: @escaping () -> Void) {
        self.appState = appState
        self.permissions = permissions
        self.authManager = appState.authManager
        self.updater = appState.updater
        self.dismissPopover = dismissPopover
    }

    private var resolvedScheme: ColorScheme {
        uiStore.appearanceMode.resolvedColorScheme(environment: colorScheme)
    }

    private var palette: StudioPalette {
        StudioPalette.resolved(mode: uiStore.appearanceMode, environment: colorScheme)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.05, green: 0.65, blue: 0.91), Color(red: 0.49, green: 0.23, blue: 0.93)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 28, height: 28)
                    Image(systemName: "camera.aperture")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text("XShot")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(palette.primaryText)
                        Text("by XTags")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(palette.accent)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(palette.accentSoftFill, in: Capsule())
                    }
                    Text(uiStore.t(.appSubtitle))
                        .font(.system(size: 10.5))
                        .foregroundStyle(palette.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                // Quick 1-click Multi-Language Switcher Menu (10 languages + System Auto!)
                Menu {
                    Button {
                        uiStore.language = .system
                    } label: {
                        Text(uiStore.language == .system ? "✓ \(uiStore.t(.langSystem))" : uiStore.t(.langSystem))
                    }
                    Divider()
                    ForEach(AppLanguage.concreteLanguages) { lang in
                        Button {
                            uiStore.language = lang
                        } label: {
                            Text(uiStore.language == lang ? "✓ \(lang.nativeDisplayName)" : lang.nativeDisplayName)
                        }
                    }
                } label: {
                    Image(systemName: "globe")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.secondaryText)
                        .frame(width: 26, height: 26)
                        .background(
                            Circle()
                                .fill(palette.controlFill)
                                .overlay(Circle().strokeBorder(palette.controlBorder, lineWidth: 0.7))
                        )
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("\(uiStore.t(.appLanguage)): \(uiStore.language.nativeDisplayName)")

                // Quick 1-click Light / Dark / System theme cycler!
                Button {
                    let all = AppAppearanceMode.allCases
                    if let idx = all.firstIndex(of: uiStore.appearanceMode) {
                        uiStore.appearanceMode = all[(idx + 1) % all.count]
                    }
                } label: {
                    Image(systemName: themeIcon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(themeIconColor)
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(TactilePillButtonStyle(
                    background: palette.controlFill,
                    hoverBackground: palette.controlHoverFill,
                    borderColor: palette.controlBorder,
                    cornerRadius: 13
                ))
                .help("\(uiStore.t(.appearanceMode)): \(uiStore.appearanceMode.displayName)")

                if !permissions.hasScreenRecording {
                    Button {
                        permissions.requestScreenRecording()
                        permissions.openScreenRecordingSettings()
                    } label: {
                        Label(uiStore.t(.grantPermission), systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 8)
                            .frame(height: 24)
                    }
                    .buttonStyle(TactilePillButtonStyle(
                        background: .orange.opacity(0.18),
                        hoverBackground: .orange.opacity(0.28),
                        borderColor: .orange.opacity(0.45),
                        cornerRadius: 12
                    ))
                } else {
                    Button {
                        appState.targetFPS = (appState.targetFPS == 60) ? 120 : 60
                    } label: {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(palette.accent)
                                .frame(width: 5, height: 5)
                            Text("\(appState.targetFPS) FPS")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                        }
                        .foregroundStyle(palette.accent)
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                    }
                    .buttonStyle(TactilePillButtonStyle(
                        background: palette.accentSoftFill,
                        hoverBackground: palette.accentHoverFill,
                        borderColor: palette.accentBorder,
                        cornerRadius: 12
                    ))
                }
            }

            // Active Recording Banner
            if appState.isRecording {
                Button {
                    dismissPopover()
                    appState.stopRecording()
                } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(.white)
                            .frame(width: 8, height: 8)
                        Text(uiStore.format(.recordingBannerFormat, formatSeconds(appState.recordingElapsed)))
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                        Spacer()
                        KeyCapBadge("⌘⇧8", palette: palette, onSolidBanner: true)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 0.92, green: 0.22, blue: 0.30), Color(red: 0.78, green: 0.14, blue: 0.24)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(TactileScaleButtonStyle(pressedScale: 0.97))
            }

            // Active Multi-Image Auto-Collect Banner
            if appState.multiImageCollectMode {
                let purple = Color(red: 0.56, green: 0.32, blue: 0.96)
                HStack(spacing: 6) {
                    Circle()
                        .fill(.white)
                        .frame(width: 7, height: 7)
                    Text(
                        appState.collectedMultiImageCount > 0
                            ? uiStore.format(.multiCollectBannerCountFormat, appState.collectedMultiImageCount)
                            : uiStore.t(.multiCollectBannerEmpty)
                    )
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)

                    Spacer(minLength: 2)

                    if appState.collectedMultiImageCount > 0 {
                        Button {
                            dismissPopover()
                            appState.openActiveMultiImageEditor()
                        } label: {
                            Text(uiStore.t(.multiCollectOpenEditor))
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(purple)
                                .padding(.horizontal, 7)
                                .frame(height: 21)
                        }
                        .buttonStyle(TactilePillButtonStyle(
                            background: .white,
                            hoverBackground: .white.opacity(0.90),
                            cornerRadius: 6
                        ))
                    }

                    Button {
                        dismissPopover()
                        appState.startMultiImageArrangement()
                    } label: {
                        Text(uiStore.t(.multiCollectPickFiles))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .frame(height: 21)
                    }
                    .buttonStyle(TactilePillButtonStyle(
                        background: .white.opacity(0.20),
                        hoverBackground: .white.opacity(0.32),
                        cornerRadius: 6
                    ))

                    Button {
                        withAnimation(.easeOut(duration: 0.16)) {
                            appState.setMultiImageCollectMode(false)
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 21, height: 21)
                    }
                    .buttonStyle(TactilePillButtonStyle(
                        background: .white.opacity(0.18),
                        hoverBackground: .white.opacity(0.30),
                        cornerRadius: 6
                    ))
                    .help(uiStore.t(.multiCollectStopBtn))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    LinearGradient(
                        colors: [Color(red: 0.49, green: 0.23, blue: 0.93), Color(red: 0.35, green: 0.32, blue: 0.96)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
            }

            // Bento Section 1: Screenshot
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(uiStore.t(.sectionScreenshot))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.secondaryText)
                    Spacer()
                    Text(uiStore.t(.sectionScreenshotMeta))
                        .font(.system(size: 10))
                        .foregroundStyle(palette.tertiaryText)
                }

                HStack(spacing: 8) {
                    BentoActionTile(title: uiStore.t(.areaScreenshot), shortcut: appState.hotKeyLabel(for: .captureArea), fallbackHint: uiStore.t(.clickToStart), icon: "crop", tint: palette.accent, palette: palette) {
                        dismissPopover()
                        appState.startAreaScreenshot(fromMenuBar: true)
                    }
                    BentoActionTile(title: uiStore.t(.windowScreenshot), shortcut: appState.hotKeyLabel(for: .captureWindow), fallbackHint: uiStore.t(.clickToStart), icon: "macwindow", tint: Color(red: 0.26, green: 0.60, blue: 1.0), palette: palette) {
                        dismissPopover()
                        appState.startWindowScreenshot(fromMenuBar: true)
                    }
                    BentoActionTile(title: uiStore.t(.fullscreenScreenshot), shortcut: nil, fallbackHint: uiStore.t(.clickToStart), icon: "display", tint: Color(red: 0.56, green: 0.48, blue: 1.0), palette: palette) {
                        dismissPopover()
                        appState.captureFullscreenScreenshot()
                    }
                }

                HStack(spacing: 7) {
                    ClipboardBeautifyRow(
                        title: uiStore.t(.clipboardBeautifyTitle),
                        subtitle: appState.clipboardImageSize.map {
                            uiStore.format(.clipboardReadyFormat, Int($0.width), Int($0.height))
                        } ?? uiStore.t(.clipboardBeautifyHint),
                        shortcut: appState.hotKeyLabel(for: .beautifyClipboard),
                        hasImage: appState.clipboardImageSize != nil,
                        palette: palette
                    ) {
                        dismissPopover()
                        appState.beautifyImageFromClipboard()
                    }

                    MultiImageCollectToggleRow(
                        title: appState.multiImageCollectMode ? uiStore.t(.multiCollectActiveTitle) : uiStore.t(.multiCollectEnableBtn),
                        subtitle: appState.multiImageCollectMode
                            ? uiStore.format(.multiCollectCountFormat, appState.collectedMultiImageCount)
                            : uiStore.t(.multiCollectHintOff),
                        isOn: appState.multiImageCollectMode,
                        palette: palette
                    ) {
                        withAnimation(.easeOut(duration: 0.16)) {
                            appState.toggleMultiImageCollectMode()
                        }
                    }
                }

                HStack(spacing: 7) {
                    CompactFeatureRow(
                        title: uiStore.t(.scrollMenuTitle),
                        shortcut: appState.hotKeyLabel(for: .captureScroll),
                        tooltip: uiStore.t(.scrollMenuHint),
                        icon: "arrow.up.and.down.text.horizontal",
                        tint: Color(red: 0.14, green: 0.78, blue: 0.62),
                        palette: palette
                    ) {
                        dismissPopover()
                        appState.startScrollingScreenshot(fromMenuBar: true)
                    }

                    CompactFeatureRow(
                        title: uiStore.t(.ocrMenuTitle),
                        shortcut: appState.hotKeyLabel(for: .extractTextArea),
                        tooltip: uiStore.t(.ocrMenuHint),
                        icon: "text.viewfinder",
                        tint: Color(red: 0.06, green: 0.65, blue: 0.91),
                        palette: palette
                    ) {
                        dismissPopover()
                        appState.startAreaTextExtraction(fromMenuBar: true)
                    }
                }
            }

            // Bento Section 2: Screen Recording
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(uiStore.t(.sectionRecording))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.secondaryText)
                    Spacer()
                    Text(uiStore.t(.sectionRecordingMeta))
                        .font(.system(size: 10))
                        .foregroundStyle(palette.tertiaryText)
                }

                HStack(spacing: 8) {
                    BentoActionTile(title: uiStore.t(.areaRecording), shortcut: appState.hotKeyLabel(for: .recordArea), fallbackHint: uiStore.t(.clickToStart), icon: "record.circle", tint: Color(red: 1.0, green: 0.34, blue: 0.38), palette: palette, disabled: appState.isRecording) {
                        dismissPopover()
                        appState.startAreaRecording()
                    }
                    BentoActionTile(title: uiStore.t(.windowRecording), shortcut: nil, fallbackHint: uiStore.t(.clickToStart), icon: "rectangle.inset.filled.badge.record", tint: Color(red: 1.0, green: 0.38, blue: 0.62), palette: palette, disabled: appState.isRecording) {
                        dismissPopover()
                        appState.startWindowRecording()
                    }
                    BentoActionTile(title: uiStore.t(.fullscreenRecording), shortcut: nil, fallbackHint: uiStore.t(.clickToStart), icon: "video.fill", tint: Color(red: 1.0, green: 0.62, blue: 0.22), palette: palette, disabled: appState.isRecording) {
                        dismissPopover()
                        appState.startFullscreenRecording()
                    }
                }

                LocalVideoStudioRow(
                    title: uiStore.t(.openLocalVideoBtn),
                    subtitle: uiStore.t(.openLocalVideoHint),
                    palette: palette
                ) {
                    dismissPopover()
                    appState.openLocalVideoInStudio()
                }
            }

            // Quick Options Card
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    RefinedTogglePill(title: uiStore.t(.toggleSystemAudio), icon: "speaker.wave.2.fill", palette: palette, isOn: $appState.captureSystemAudio)
                    RefinedTogglePill(title: uiStore.t(.toggleMic), icon: "mic.fill", palette: palette, isOn: $appState.captureMicrophone)
                }
                HStack(spacing: 6) {
                    RefinedTogglePill(title: uiStore.t(.toggleKeystrokes), icon: "keyboard", palette: palette, isOn: $appState.enableKeystrokesByDefault)
                    RefinedTogglePill(title: uiStore.t(.toggleTypingFocus), icon: "text.cursor", palette: palette, isOn: $appState.enableTypingFocusZoom)
                }
                HStack(spacing: 6) {
                    RefinedTogglePill(title: uiStore.t(.toggleSmoothCursor), icon: "cursorarrow.motionlines", palette: palette, isOn: $appState.hideNativeCursorForSmooth)
                    RefinedTogglePill(title: uiStore.t(.toggleAutoBeautify), icon: "sparkles", palette: palette, isOn: $appState.autoBeautifyOnCapture)
                }
                HStack(spacing: 6) {
                    RefinedTogglePill(title: uiStore.t(.toggleAutoPrivacy), icon: "lock.shield.fill", palette: palette, isOn: $appState.autoPrivacyRedactOnCapture)
                    RefinedTogglePill(title: uiStore.t(.toggleWebcamPiP), icon: "person.crop.rectangle.fill", palette: palette, isOn: $appState.captureWebcamPiP)
                }

                if (appState.enableKeystrokesByDefault || appState.enableTypingFocusZoom) && !permissions.hasAccessibility {
                    Button {
                        permissions.requestAccessibilityAndInputMonitoring()
                        permissions.openAccessibilitySettings()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "hand.raised.fill")
                                .font(.system(size: 10, weight: .bold))
                            Text(uiStore.t(.accessibilityHintBanner))
                                .font(.system(size: 10, weight: .medium))
                                .lineLimit(1)
                            Spacer(minLength: 2)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(TactilePillButtonStyle(
                        background: .orange.opacity(0.16),
                        hoverBackground: .orange.opacity(0.26),
                        borderColor: .orange.opacity(0.38),
                        cornerRadius: 8
                    ))
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(palette.cardBackground)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(palette.cardBorder, lineWidth: 0.9))
            )

            // Recent Captures Strip
            if !appState.recentItems.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(uiStore.t(.recentWorks))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.secondaryText)
                        Spacer()
                        Text(uiStore.t(.dragToXHint))
                            .font(.system(size: 10))
                            .foregroundStyle(palette.tertiaryText)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(appState.recentItems.prefix(6)) { item in
                                RecentCaptureThumb(
                                    item: item,
                                    palette: palette,
                                    copyTooltip: uiStore.t(.copyFile),
                                    finderTooltip: uiStore.t(.revealInFinder)
                                )
                            }
                        }
                    }
                    .frame(height: 56)
                }
            }

            // XTags Account & Seamless Auto-Update Bar
            xtagsAccountAndUpdateCard

            Divider().overlay(palette.divider)

            // Footer
            HStack(spacing: 4) {
                FooterPillButton(title: uiStore.t(.settingsAndPermissions), icon: "gearshape", palette: palette) {
                    dismissPopover()
                    appState.openSettingsWindow()
                }
                FooterPillButton(title: uiStore.t(.outputFolder), icon: "folder", palette: palette) {
                    NSWorkspace.shared.open(ExportHelpers.recordingsDirectory)
                }
                Spacer(minLength: 2)
                Button {
                    Task { await updater.checkForUpdates(userInitiated: true) }
                } label: {
                    Text("v\(updater.currentVersion.description)")
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(palette.tertiaryText)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .background(palette.controlFill, in: RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .help(uiStore.t(.updCheckNowBtn))

                FooterPillButton(title: uiStore.t(.quitApp), icon: "power", palette: palette, subtle: true) {
                    NSApp.terminate(nil)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(width: 340, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .background(palette.popoverBackground.ignoresSafeArea())
        .environment(\.colorScheme, resolvedScheme)
        .preferredColorScheme(uiStore.appearanceMode.swiftUIColorScheme)
        .onAppear {
            permissions.refresh()
            appState.refreshClipboardStatus()
        }
    }

    @ViewBuilder
    private var xtagsAccountAndUpdateCard: some View {
        HStack(spacing: 8) {
            if let user = authManager.currentUser {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.05, green: 0.65, blue: 0.91), Color(red: 0.49, green: 0.23, blue: 0.93)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 24, height: 24)
                    Text(user.initials)
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(user.displayName)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.primaryText)
                            .lineLimit(1)
                        Text(uiStore.t(.xtagsAutoUpdateBadge))
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 4.5)
                            .padding(.vertical, 1)
                            .background(Color.green.opacity(palette.isDark ? 0.20 : 0.12), in: Capsule())
                    }
                    Text(menuUpdateStatusText)
                        .font(.system(size: 9.5))
                        .foregroundStyle(palette.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                menuUpdateActionButton
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(palette.accentSoftFill)
                        .frame(width: 24, height: 24)
                    Image(systemName: "person.badge.key.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.accent)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(uiStore.t(.xtagsSignInBtn))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.primaryText)
                        .lineLimit(1)
                    Text(uiStore.t(.xtagsSignedOutHint))
                        .font(.system(size: 9))
                        .foregroundStyle(palette.tertiaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Button {
                    dismissPopover()
                    appState.openXTagsLoginWindow()
                } label: {
                    Text(uiStore.t(.xtagsSignInBtn))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(palette.accentTextOnAccent)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4.5)
                        .background(palette.accent, in: Capsule())
                }
                .buttonStyle(TactileScaleButtonStyle(pressedScale: 0.94))
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(palette.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(palette.cardBorder, lineWidth: 0.85)
                )
        )
    }

    private var menuUpdateStatusText: String {
        switch updater.status {
        case .idle:
            return uiStore.format(.updCurrentVersionFormat, updater.currentVersion.description)
        case .checking:
            return uiStore.t(.updChecking)
        case .upToDate:
            return "\(uiStore.t(.updUpToDate)) · v\(updater.currentVersion.description)"
        case .available(let release):
            return uiStore.format(.updAvailableFormat, release.version.description)
        case .downloading(let release, let progress):
            return uiStore.format(.updDownloadingFormat, release.version.description, Int((progress * 100).rounded()))
        case .verifying:
            return uiStore.t(.updVerifying)
        case .readyToInstall(let staged):
            return uiStore.format(.updReadyFormat, staged.release.version.description)
        case .installing:
            return uiStore.t(.updInstalling)
        case .failed(let msg):
            return msg
        }
    }

    @ViewBuilder
    private var menuUpdateActionButton: some View {
        switch updater.status {
        case .readyToInstall(let staged):
            Button {
                dismissPopover()
                updater.applyStagedUpdateAndRelaunch(staged)
            } label: {
                Text(uiStore.t(.updRestartApplyBtn))
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green, in: Capsule())
            }
            .buttonStyle(TactileScaleButtonStyle(pressedScale: 0.94))

        case .available:
            Button {
                updater.startSeamlessUpdateNow()
            } label: {
                Text(uiStore.t(.updUpdateNowBtn))
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(palette.accentTextOnAccent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(palette.accent, in: Capsule())
            }
            .buttonStyle(TactileScaleButtonStyle(pressedScale: 0.94))

        case .checking, .downloading, .verifying, .installing:
            ProgressView()
                .controlSize(.small)

        default:
            Button {
                Task { await updater.checkForUpdates(userInitiated: true) }
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(palette.secondaryText)
                    .frame(width: 24, height: 24)
                    .background(palette.controlFill, in: Circle())
            }
            .buttonStyle(TactileScaleButtonStyle(pressedScale: 0.92))
            .help(uiStore.t(.updCheckNowBtn))
        }
    }

    private var themeIcon: String {
        switch uiStore.appearanceMode {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.stars.fill"
        }
    }

    private var themeIconColor: Color {
        switch uiStore.appearanceMode {
        case .system: return palette.secondaryText
        case .light: return Color(red: 0.92, green: 0.58, blue: 0.05)
        case .dark: return palette.accent
        }
    }

    private func formatSeconds(_ s: Double) -> String {
        let total = Int(s)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

private struct ClipboardBeautifyRow: View {
    let title: String
    let subtitle: String
    let shortcut: String
    let hasImage: Bool
    let palette: StudioPalette
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        let tint: Color = hasImage ? Color(red: 0.12, green: 0.78, blue: 0.54) : palette.accent
        Button(action: action) {
            HStack(spacing: 7) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(tint.opacity(hovered ? (palette.isDark ? 0.30 : 0.22) : (palette.isDark ? 0.20 : 0.14)))
                        .frame(width: 26, height: 26)
                    Image(systemName: "doc.on.clipboard.fill")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(tint)
                }

                VStack(alignment: .leading, spacing: 1.5) {
                    HStack(spacing: 4) {
                        Text(title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.primaryText)
                            .lineLimit(1)
                        if hasImage {
                            Circle()
                                .fill(Color(red: 0.14, green: 0.84, blue: 0.56))
                                .frame(width: 5, height: 5)
                        }
                    }
                    Text(hasImage ? subtitle : "⌘⇧9")
                        .font(.system(size: 9, weight: .medium, design: hasImage ? .default : .monospaced))
                        .foregroundStyle(hasImage ? tint : palette.tertiaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(hovered ? tint.opacity(palette.isDark ? 0.17 : 0.10) : palette.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(
                                hovered ? tint.opacity(0.60) : (hasImage ? tint.opacity(0.38) : palette.cardBorder),
                                lineWidth: hovered ? 1.1 : 0.9
                            )
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(TactileScaleButtonStyle(pressedScale: 0.97))
        .onHover { hovered = $0 }
        .help("\(title) (\(shortcut))")
    }
}

private struct MultiImageCollectToggleRow: View {
    let title: String
    let subtitle: String
    let isOn: Bool
    let palette: StudioPalette
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        let tint = Color(red: 0.64, green: 0.44, blue: 0.98)
        Button(action: action) {
            HStack(spacing: 7) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isOn ? tint : tint.opacity(hovered ? (palette.isDark ? 0.30 : 0.22) : (palette.isDark ? 0.20 : 0.14)))
                        .frame(width: 26, height: 26)
                    Image(systemName: isOn ? "rectangle.stack.fill" : "rectangle.stack.badge.plus")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(isOn ? .white : tint)
                }

                VStack(alignment: .leading, spacing: 1.5) {
                    HStack(spacing: 4) {
                        Text(title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(isOn ? tint : palette.primaryText)
                            .lineLimit(1)
                        if isOn {
                            Circle()
                                .fill(tint)
                                .frame(width: 5, height: 5)
                        }
                    }
                    Text(subtitle)
                        .font(.system(size: 9, weight: isOn ? .semibold : .regular))
                        .foregroundStyle(isOn ? tint.opacity(0.92) : palette.tertiaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(
                        isOn
                            ? tint.opacity(palette.isDark ? 0.22 : 0.14)
                            : (hovered ? tint.opacity(palette.isDark ? 0.17 : 0.10) : palette.cardBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(
                                isOn ? tint.opacity(0.75) : (hovered ? tint.opacity(0.60) : palette.cardBorder),
                                lineWidth: (isOn || hovered) ? 1.15 : 0.9
                            )
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(TactileScaleButtonStyle(pressedScale: 0.97))
        .onHover { hovered = $0 }
        .help(subtitle)
    }
}

private struct CompactFeatureRow: View {
    let title: String
    let shortcut: String
    let tooltip: String
    let icon: String
    let tint: Color
    let palette: StudioPalette
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(tint.opacity(hovered ? (palette.isDark ? 0.30 : 0.22) : (palette.isDark ? 0.20 : 0.14)))
                        .frame(width: 26, height: 26)
                    Image(systemName: icon)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(tint)
                }

                VStack(alignment: .leading, spacing: 1.5) {
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.primaryText)
                        .lineLimit(1)
                    KeyCapBadge(shortcut, palette: palette, onSolidBanner: false)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6.5)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(hovered ? tint.opacity(palette.isDark ? 0.17 : 0.10) : palette.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(hovered ? tint.opacity(0.60) : palette.cardBorder, lineWidth: hovered ? 1.1 : 0.9)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(TactileScaleButtonStyle(pressedScale: 0.97))
        .onHover { hovered = $0 }
        .help("\(tooltip) (\(shortcut))")
    }
}

private struct LocalVideoStudioRow: View {
    let title: String
    let subtitle: String
    let palette: StudioPalette
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        let tint = Color(red: 0.98, green: 0.48, blue: 0.28)
        Button(action: action) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(tint.opacity(hovered ? (palette.isDark ? 0.30 : 0.22) : (palette.isDark ? 0.20 : 0.14)))
                        .frame(width: 26, height: 26)
                    Image(systemName: "film.stack.fill")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(tint)
                }

                VStack(alignment: .leading, spacing: 1.5) {
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.primaryText)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 9))
                        .foregroundStyle(palette.tertiaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(hovered ? tint : palette.tertiaryText)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6.5)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(hovered ? tint.opacity(palette.isDark ? 0.17 : 0.10) : palette.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(hovered ? tint.opacity(0.60) : palette.cardBorder, lineWidth: hovered ? 1.1 : 0.9)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(TactileScaleButtonStyle(pressedScale: 0.97))
        .onHover { hovered = $0 }
        .help(subtitle)
    }
}

private struct BentoActionTile: View {
    let title: String
    let shortcut: String?
    let fallbackHint: String
    let icon: String
    let tint: Color
    let palette: StudioPalette
    var disabled: Bool = false
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                ZStack {
                    Circle()
                        .fill(disabled ? palette.controlFill : tint.opacity(hovered ? (palette.isDark ? 0.32 : 0.24) : (palette.isDark ? 0.22 : 0.14)))
                        .frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(disabled ? palette.tertiaryText : tint)
                }

                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(disabled ? palette.tertiaryText : palette.primaryText)
                    .lineLimit(1)

                if let shortcut {
                    KeyCapBadge(shortcut, palette: palette, onSolidBanner: false)
                } else {
                    Text(fallbackHint)
                        .font(.system(size: 9.5))
                        .foregroundStyle(palette.tertiaryText)
                        .lineLimit(1)
                        .frame(height: 16)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(hovered && !disabled ? tint.opacity(palette.isDark ? 0.20 : 0.10) : palette.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(hovered && !disabled ? tint.opacity(0.65) : palette.cardBorder, lineWidth: hovered && !disabled ? 1.1 : 0.9)
                    )
            )
            .scaleEffect(hovered && !disabled ? 1.015 : 1.0)
            .animation(.easeOut(duration: 0.12), value: hovered)
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(TactileScaleButtonStyle(pressedScale: 0.95))
        .disabled(disabled)
        .onHover { hovered = $0 }
    }
}

private struct KeyCapBadge: View {
    let text: String
    let palette: StudioPalette
    let onSolidBanner: Bool

    init(_ text: String, palette: StudioPalette, onSolidBanner: Bool) {
        self.text = text
        self.palette = palette
        self.onSolidBanner = onSolidBanner
    }

    var body: some View {
        Text(text)
            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
            .foregroundStyle(onSolidBanner ? Color.white : palette.secondaryText)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(onSolidBanner ? Color.white.opacity(0.20) : palette.controlFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(onSolidBanner ? Color.clear : palette.controlBorder, lineWidth: 0.6)
                    )
            )
            .frame(height: 16)
    }
}

private struct RefinedTogglePill: View {
    let title: String
    let icon: String
    let palette: StudioPalette
    @Binding var isOn: Bool
    @State private var hovered = false

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.12)) {
                isOn.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(isOn ? palette.accent : palette.tertiaryText)
                Text(title)
                    .font(.system(size: 11, weight: isOn ? .semibold : .medium))
                    .foregroundStyle(isOn ? palette.primaryText : palette.secondaryText)
                    .lineLimit(1)
                Spacer(minLength: 2)
                Circle()
                    .fill(isOn ? palette.accent : palette.tertiaryText.opacity(0.45))
                    .frame(width: 6, height: 6)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isOn ? (hovered ? palette.accentHoverFill : palette.accentSoftFill) : (hovered ? palette.controlHoverFill : palette.controlFill))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(isOn ? palette.accentBorder : palette.controlBorder, lineWidth: 0.85)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(TactileScaleButtonStyle(pressedScale: 0.96))
        .onHover { hovered = $0 }
    }
}

private struct RecentCaptureThumb: View {
    let item: CaptureHistoryItem
    let palette: StudioPalette
    let copyTooltip: String
    let finderTooltip: String
    @State private var hovered = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let thumb = item.thumbnail {
                Image(nsImage: thumb)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 86, height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(palette.controlFill)
                    .frame(width: 86, height: 54)
                    .overlay(Image(systemName: item.kind == .video ? "film" : "photo").foregroundStyle(palette.secondaryText))
            }

            if hovered {
                HStack(spacing: 6) {
                    Button {
                        ExportHelpers.copyFileURLToPasteboard(item.fileURL)
                    } label: {
                        Image(systemName: "doc.on.doc.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(.black.opacity(0.78), in: Circle())
                    }
                    .buttonStyle(TactileScaleButtonStyle(pressedScale: 0.90))
                    .help(copyTooltip)

                    Button {
                        ExportHelpers.revealInFinder(item.fileURL)
                    } label: {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(.black.opacity(0.78), in: Circle())
                    }
                    .buttonStyle(TactileScaleButtonStyle(pressedScale: 0.90))
                    .help(finderTooltip)
                }
                .frame(width: 86, height: 54)
                .background(.black.opacity(0.38), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                Image(systemName: item.kind == .video ? "video.fill" : "photo.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(.black.opacity(0.68), in: RoundedRectangle(cornerRadius: 4))
                    .padding(4)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(hovered ? palette.accentBorder : palette.cardBorder, lineWidth: 0.9))
        .onHover { hovered = $0 }
        .onDrag {
            NSItemProvider(contentsOf: item.fileURL) ?? NSItemProvider(object: item.fileURL as NSURL)
        }
        .help(item.title)
    }
}

private struct FooterPillButton: View {
    let title: String
    let icon: String
    let palette: StudioPalette
    var subtle: Bool = false
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(title)
                    .font(.system(size: 10.5, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(subtle ? palette.secondaryText : palette.primaryText)
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(hovered ? palette.controlHoverFill : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(TactileScaleButtonStyle(pressedScale: 0.95))
        .onHover { hovered = $0 }
    }
}
