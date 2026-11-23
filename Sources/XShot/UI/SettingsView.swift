import AppKit
import SwiftUI

public struct SettingsView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var permissions: PermissionManager
    @ObservedObject var authManager: XTagsAuthManager
    @ObservedObject var updater: AppUpdaterManager
    @ObservedObject var store: StoreKitManager
    @ObservedObject private var uiStore = ThemeLocaleStore.shared
    @Environment(\.colorScheme) private var colorScheme

    @State private var recordingHotKeyAction: GlobalHotKeyAction?
    @State private var hotKeyMonitor: Any?
    @State private var hotKeyNotice: String?

    public init(appState: AppState, permissions: PermissionManager) {
        self.appState = appState
        self.permissions = permissions
        self.authManager = appState.authManager
        self.updater = appState.updater
        self.store = appState.store
    }

    public var body: some View {
        Form {
            Section(uiStore.t(.appearanceSection)) {
                Picker(uiStore.t(.appearanceMode), selection: $uiStore.appearanceMode) {
                    ForEach(AppAppearanceMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Picker(uiStore.t(.appLanguage), selection: $uiStore.language) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.nativeDisplayName).tag(lang)
                    }
                }
            }

            if AppDistribution.supportsSelfUpdate {
            Section(uiStore.t(.xtagsAccountSection)) {
                if let user = authManager.currentUser {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color(red: 0.05, green: 0.65, blue: 0.91), Color(red: 0.49, green: 0.23, blue: 0.93)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 32, height: 32)
                            Text(user.initials)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(user.displayName)
                                    .font(.system(size: 12.5, weight: .semibold))
                                Text(uiStore.t(.xtagsAutoUpdateBadge))
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.green)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1.5)
                                    .background(Color.green.opacity(0.14), in: Capsule())
                            }
                            Text(user.primarySubtitle)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(uiStore.t(.xtagsSignOutBtn)) {
                            Task { await authManager.signOut() }
                        }
                    }
                } else {
                    HStack(spacing: 10) {
                        Image(systemName: "person.badge.key.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(uiStore.t(.xtagsSignInBtn))
                                .font(.system(size: 12.5, weight: .semibold))
                            Text(uiStore.t(.xtagsSignedOutHint))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(uiStore.t(.xtagsSignInBtn)) {
                            appState.openXTagsLoginWindow()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                Toggle(uiStore.t(.updAutoToggleLabel), isOn: $updater.autoUpdateEnabled)
                    .disabled(!authManager.isSignedIn)

                if !authManager.isSignedIn {
                    Text(uiStore.t(.updAutoRequiresSignInHint))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(uiStore.format(.updCurrentVersionFormat, updater.currentVersion.description))
                            .font(.system(size: 12, weight: .semibold))
                        Text(settingsUpdateStatusText)
                            .font(.system(size: 11))
                            .foregroundStyle(settingsUpdateStatusColor)
                    }
                    Spacer()

                    if case .readyToInstall(let staged) = updater.status {
                        Button(uiStore.t(.updRestartApplyBtn)) {
                            updater.applyStagedUpdateAndRelaunch(staged)
                        }
                        .buttonStyle(.borderedProminent)
                    } else if case .available(let release) = updater.status {
                        if authManager.isSignedIn && release.hasDirectZipBinary {
                            Button(uiStore.t(.updUpdateNowBtn)) {
                                updater.startSeamlessUpdateNow()
                            }
                            .buttonStyle(.borderedProminent)
                        } else {
                            Button(uiStore.t(.updOpenReleasesBtn)) {
                                NSWorkspace.shared.open(release.releasePageURL)
                            }
                        }
                    } else {
                        Button(uiStore.t(.updCheckNowBtn)) {
                            Task { await updater.checkForUpdates(userInitiated: true) }
                        }
                        .disabled(isUpdaterBusy)
                    }
                }

                if case .downloading(_, let progress) = updater.status {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                }

                Text(uiStore.t(.updSeamlessNote))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            } else {
                Section(uiStore.t(.iapSectionTitle)) {
                    let ent = store.entitlement
                    HStack(spacing: 10) {
                        Image(systemName: ent.isLifetime ? "crown.fill" : (ent.isProUnlocked ? "checkmark.seal.fill" : "sparkles"))
                            .font(.system(size: 18))
                            .foregroundStyle(ent.isProUnlocked ? .green : .accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(store.currentPlanShortLabel)
                                .font(.system(size: 12.5, weight: .semibold))
                            Text(ent.reachedLoyaltyUpgrade
                                 ? uiStore.t(.iapLoyaltyUnlockedBanner)
                                 : uiStore.format(.iapLoyaltyProgressFormat, min(ent.paidMonthlyCycles, ent.loyaltyTargetMonths), ent.loyaltyTargetMonths))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if !ent.isLifetime {
                            Button(uiStore.t(.iapUpgradeBtn)) {
                                appState.openProPaywallWindow()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }

                    ProgressView(value: ent.isLifetime ? 1.0 : ent.loyaltyProgress)
                        .tint(ent.isLifetime ? .green : .accentColor)

                    if ent.reachedLoyaltyUpgrade && ent.isActiveMonthlySubscriber {
                        Text(uiStore.t(.iapCancelRenewalTip))
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 8) {
                        Button(uiStore.t(.feedbackBtn)) {
                            appState.openBugFeedbackWindow()
                        }
                        Button(uiStore.t(.iapRestoreBtn)) {
                            Task { await store.restorePurchases() }
                        }
                        .disabled(store.isRestoring)
                        Spacer()
                        Button(uiStore.t(.iapManageSubBtn)) {
                            store.openManageSubscriptions()
                        }
                    }

                    HStack {
                        Text(uiStore.format(.updCurrentVersionFormat, updater.currentVersion.description))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("Mac App Store")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section(uiStore.t(.settingsPermissionsSection)) {
                permissionRow(
                    title: uiStore.t(.permScreenTitle),
                    subtitle: uiStore.t(.permScreenSub),
                    granted: permissions.hasScreenRecording,
                    actionTitle: uiStore.t(.permAuthorizeBtn),
                    action: {
                        permissions.requestScreenRecording()
                        permissions.openScreenRecordingSettings()
                    }
                )
                permissionRow(
                    title: uiStore.t(.permMicTitle),
                    subtitle: uiStore.t(.permMicSub),
                    granted: permissions.hasMicrophone,
                    actionTitle: uiStore.t(.permAuthorizeBtn),
                    action: {
                        permissions.requestMicrophone()
                        permissions.openMicrophoneSettings()
                    }
                )
                permissionRow(
                    title: uiStore.t(.permCameraTitle),
                    subtitle: uiStore.t(.permCameraSub),
                    granted: permissions.hasCamera,
                    actionTitle: uiStore.t(.permAuthorizeBtn),
                    action: {
                        permissions.requestCamera()
                        permissions.openCameraSettings()
                    }
                )
                if AppDistribution.supportsAccessibilityFeatures {
                    permissionRow(
                        title: uiStore.t(.permAxTitle),
                        subtitle: uiStore.t(.permAxSub),
                        granted: permissions.hasAccessibility,
                        actionTitle: uiStore.t(.permAuthorizeBtn),
                        action: {
                            permissions.requestAccessibilityAndInputMonitoring()
                            permissions.openAccessibilitySettings()
                        }
                    )
                }

                HStack {
                    Spacer()
                    Button(uiStore.t(.refreshPermissions)) {
                        permissions.refresh()
                    }
                }
            }

            Section(uiStore.t(.settingsDefaultsSection)) {
                Picker(uiStore.t(.defaultFPSLabel), selection: $appState.targetFPS) {
                    Text(uiStore.t(.fps60Label)).tag(60)
                    Text(uiStore.t(.fps120Label)).tag(120)
                }

                Toggle(uiStore.t(.defaultSysAudio), isOn: $appState.captureSystemAudio)
                Toggle(uiStore.t(.defaultMic), isOn: $appState.captureMicrophone)
                Toggle(uiStore.t(.defaultWebcamPiP), isOn: $appState.captureWebcamPiP)
                if AppDistribution.supportsAccessibilityFeatures {
                    Toggle(uiStore.t(.defaultKeystrokes), isOn: $appState.enableKeystrokesByDefault)
                    if appState.enableKeystrokesByDefault {
                        Picker(uiStore.t(.defaultKeystrokeStyle), selection: $appState.defaultKeystrokeStyle.visualStyle) {
                            ForEach(KeystrokeVisualStyle.allCases) { style in
                                Text(style.displayName).tag(style)
                            }
                        }
                        Picker(uiStore.t(.defaultKeystrokePos), selection: $appState.defaultKeystrokeStyle.position) {
                            ForEach(KeystrokePosition.presetCases) { pos in
                                Text(pos.displayName).tag(pos)
                            }
                            if appState.defaultKeystrokeStyle.position == .custom {
                                Text("\(uiStore.t(.customPositionLabel)) (\(Int((appState.defaultKeystrokeStyle.customX * 100).rounded()))%, \(Int((appState.defaultKeystrokeStyle.customY * 100).rounded()))%)")
                                    .tag(KeystrokePosition.custom)
                            }
                        }
                        Picker(uiStore.t(.defaultKeystrokeFilter), selection: $appState.defaultKeystrokeStyle.filterMode) {
                            ForEach(KeystrokeFilterMode.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                    }
                    Toggle(uiStore.t(.defaultTypingZoom), isOn: $appState.enableTypingFocusZoom)
                }
                Toggle(uiStore.t(.defaultHideCursor), isOn: $appState.hideNativeCursorForSmooth)
                Toggle(uiStore.t(.defaultAutoCopy), isOn: $appState.autoCopyScreenshot)
                Toggle(uiStore.t(.defaultAutoBeautify), isOn: $appState.autoBeautifyOnCapture)
                Toggle(uiStore.t(.defaultAutoPrivacy), isOn: $appState.autoPrivacyRedactOnCapture)
                Picker(uiStore.t(.defaultPrivacyStyle), selection: $appState.defaultPrivacyRedactionStyle) {
                    ForEach(PrivacyRedactionStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.segmented)

                Toggle(uiStore.t(.defaultWatermarkToggle), isOn: $appState.defaultWatermark.enabled)
                if appState.defaultWatermark.enabled {
                    TextField(uiStore.t(.watermarkTextPlaceholder), text: $appState.defaultWatermark.text)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Section {
                ForEach(GlobalHotKeyAction.allCases) { action in
                    let isRecording = (recordingHotKeyAction == action)
                    let isCustom = appState.isHotKeyCustomized(action)
                    HStack(spacing: 8) {
                        Text(action.title)
                        Spacer()

                        if isCustom && !isRecording {
                            Button {
                                appState.resetHotKey(for: action)
                                hotKeyNotice = nil
                            } label: {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help(uiStore.t(.hkResetSingleTooltip))
                        }

                        Button {
                            if isRecording {
                                stopHotKeyCapture()
                            } else {
                                startHotKeyCapture(for: action)
                            }
                        } label: {
                            Text(isRecording ? uiStore.t(.hkPressKeysHint) : appState.hotKeyLabel(for: action))
                                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                                .foregroundStyle(isRecording ? Color.accentColor : Color.primary)
                                .padding(.horizontal, 10)
                                .frame(minWidth: 74, minHeight: 24)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(isRecording ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.07))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                .strokeBorder(
                                                    isRecording ? Color.accentColor : Color.primary.opacity(0.14),
                                                    lineWidth: isRecording ? 1.3 : 0.8
                                                )
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                        .help(uiStore.t(.hkClickToRecordTooltip))
                    }
                }

                if let notice = hotKeyNotice {
                    Text(notice)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.orange)
                }

                if appState.hasCustomHotKeys {
                    HStack {
                        Spacer()
                        Button(uiStore.t(.hkResetAllBtn)) {
                            stopHotKeyCapture()
                            appState.resetAllHotKeys()
                            hotKeyNotice = nil
                        }
                    }
                }
            } header: {
                HStack {
                    Text(uiStore.t(.settingsHotkeysSection))
                    Spacer()
                    Text(uiStore.t(.hkClickToRecordTooltip))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
            }

            Section(uiStore.t(.settingsPathsSection)) {
                HStack {
                    Text(uiStore.t(.screenshotsDirLabel))
                    Spacer()
                    Text("~/Pictures/XShot")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Button(uiStore.t(.openDirBtn)) {
                        NSWorkspace.shared.open(ExportHelpers.screenshotsDirectory)
                    }
                }
                HStack {
                    Text(uiStore.t(.recordingsDirLabel))
                    Spacer()
                    Text("~/Movies/XShot")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Button(uiStore.t(.openDirBtn)) {
                        NSWorkspace.shared.open(ExportHelpers.recordingsDirectory)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 540, minHeight: 600)
        .environment(\.colorScheme, uiStore.appearanceMode.resolvedColorScheme(environment: colorScheme))
        .preferredColorScheme(uiStore.appearanceMode.swiftUIColorScheme)
        .onAppear {
            permissions.refresh()
        }
        .onDisappear {
            stopHotKeyCapture()
        }
    }

    private func startHotKeyCapture(for action: GlobalHotKeyAction) {
        stopHotKeyCapture()
        recordingHotKeyAction = action
        hotKeyNotice = nil
        appState.setHotKeysSuspended(true)

        hotKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Escape cancels recording cleanly
                stopHotKeyCapture()
                return nil
            }
            guard let binding = HotKeyBinding.from(keyCode: event.keyCode, modifierFlags: event.modifierFlags) else {
                hotKeyNotice = uiStore.t(.hkNeedModifierHint)
                NSSound.beep()
                return nil
            }
            let result = appState.updateHotKey(binding, for: action)
            switch result {
            case .updated:
                hotKeyNotice = nil
                NSSound(named: NSSound.Name("Pop"))?.play()
                stopHotKeyCapture()
            case .conflict(let existing):
                hotKeyNotice = uiStore.format(.hkConflictFormat, binding.displayLabel, existing.title)
                NSSound.beep()
            }
            return nil
        }
    }

    private func stopHotKeyCapture() {
        if let mon = hotKeyMonitor {
            NSEvent.removeMonitor(mon)
            hotKeyMonitor = nil
        }
        recordingHotKeyAction = nil
        appState.setHotKeysSuspended(false)
    }

    private var isUpdaterBusy: Bool {
        switch updater.status {
        case .checking, .downloading, .verifying, .installing:
            return true
        default:
            return false
        }
    }

    private var settingsUpdateStatusText: String {
        switch updater.status {
        case .idle:
            return authManager.isSignedIn ? uiStore.t(.xtagsAutoUpdateBadge) : uiStore.t(.updAutoRequiresSignInHint)
        case .checking:
            return uiStore.t(.updChecking)
        case .upToDate:
            return uiStore.t(.updUpToDate)
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

    private var settingsUpdateStatusColor: Color {
        switch updater.status {
        case .upToDate, .readyToInstall:
            return .green
        case .available:
            return .accentColor
        case .failed:
            return .orange
        default:
            return .secondary
        }
    }

    private func permissionRow(
        title: String,
        subtitle: String,
        granted: Bool,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(granted ? .green : .orange)
                .font(.system(size: 16))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if granted {
                Text(uiStore.t(.permGranted))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.green)
            } else {
                Button(actionTitle, action: action)
            }
        }
    }
}
