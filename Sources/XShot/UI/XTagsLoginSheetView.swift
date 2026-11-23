import AppKit
import SwiftUI

public struct XTagsLoginSheetView: View {
    @ObservedObject var authManager: XTagsAuthManager
    @ObservedObject private var uiStore = ThemeLocaleStore.shared
    @Environment(\.colorScheme) private var colorScheme
    let onDismiss: () -> Void

    @State private var manualToken: String = ""

    public init(authManager: XTagsAuthManager, onDismiss: @escaping () -> Void) {
        self.authManager = authManager
        self.onDismiss = onDismiss
    }

    private var resolvedScheme: ColorScheme {
        uiStore.appearanceMode.resolvedColorScheme(environment: colorScheme)
    }

    private var palette: StudioPalette {
        StudioPalette.resolved(mode: uiStore.appearanceMode, environment: colorScheme)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.05, green: 0.65, blue: 0.91), Color(red: 0.49, green: 0.23, blue: 0.93)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 40, height: 40)
                    Image(systemName: "person.badge.key.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(uiStore.t(.xtagsLoginWindowTitle))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(palette.primaryText)
                    Text("xtags.top · X / Google / GitHub")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.accent)
                }

                Spacer()
            }

            Text(uiStore.t(.xtagsLoginSubtitle))
                .font(.system(size: 12))
                .foregroundStyle(palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if let user = authManager.currentUser {
                // Signed-In Confirmation State
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.green.opacity(0.20))
                            .frame(width: 38, height: 38)
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.green)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(uiStore.format(.xtagsLoginSuccessFormat, user.displayName))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(palette.primaryText)
                        Text(uiStore.t(.xtagsAutoUpdateBadge))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.green)
                    }
                    Spacer()
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.green.opacity(palette.isDark ? 0.14 : 0.09))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.green.opacity(0.42), lineWidth: 1)
                        )
                )

                HStack {
                    Spacer()
                    Button(uiStore.t(.okBtn)) {
                        onDismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            } else {
                // Browser Sign-In Action Card
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "safari.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(palette.accent)
                        Text(uiStore.t(.xtagsLoginStepBrowser))
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(palette.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button {
                        authManager.beginBrowserSignIn(openBrowser: true)
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "arrow.up.right.square.fill")
                                .font(.system(size: 13, weight: .semibold))
                            Text(uiStore.t(.xtagsLoginOpenBrowserBtn))
                                .font(.system(size: 12.5, weight: .bold))
                        }
                        .foregroundStyle(palette.accentTextOnAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(palette.accent, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .buttonStyle(TactileScaleButtonStyle(pressedScale: 0.98))

                    if authManager.isWaitingForBrowserCallback {
                        HStack(spacing: 7) {
                            ProgressView()
                                .controlSize(.small)
                            Text(uiStore.t(.xtagsLoginWaitingHint))
                                .font(.system(size: 10.5))
                                .foregroundStyle(palette.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(palette.cardBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(palette.cardBorder, lineWidth: 0.9)
                        )
                )

                // Manual / Paste Token Box (Instant Fallback)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        TextField(uiStore.t(.xtagsLoginTokenPlaceholder), text: $manualToken)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11.5, design: .monospaced))
                            .disabled(authManager.isAuthenticating)
                            .onSubmit { submitManualToken() }

                        Button {
                            submitManualToken()
                        } label: {
                            if authManager.isAuthenticating {
                                ProgressView()
                                    .controlSize(.small)
                                    .frame(width: 78)
                            } else {
                                Text(uiStore.t(.xtagsLoginVerifyBtn))
                                    .font(.system(size: 11.5, weight: .semibold))
                            }
                        }
                        .disabled(manualToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || authManager.isAuthenticating)
                    }

                    if let err = authManager.lastErrorMessage, !err.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.orange)
                            Text(err)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                HStack {
                    Spacer()
                    Button(uiStore.t(.cancelAction)) {
                        authManager.stopWaitingForBrowserSignIn()
                        onDismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                }
            }
        }
        .padding(20)
        .frame(width: 460)
        .background(palette.windowBackground)
        .environment(\.colorScheme, resolvedScheme)
        .preferredColorScheme(uiStore.appearanceMode.swiftUIColorScheme)
        .onAppear {
            if !authManager.isSignedIn {
                authManager.beginBrowserSignIn(openBrowser: true)
            }
        }
        .onDisappear {
            authManager.stopWaitingForBrowserSignIn()
        }
        .onChange(of: authManager.session) { _, newSession in
            if newSession != nil {
                NSSound(named: NSSound.Name("Pop"))?.play()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                    onDismiss()
                }
            }
        }
    }

    private func submitManualToken() {
        let trimmed = manualToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Task { @MainActor in
            _ = try? await authManager.signIn(withToken: trimmed)
        }
    }
}
