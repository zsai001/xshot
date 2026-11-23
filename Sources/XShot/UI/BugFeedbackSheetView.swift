import AppKit
import SwiftUI

public struct BugFeedbackSheetView: View {
    @ObservedObject var store: StoreKitManager
    let appVersion: String
    @ObservedObject private var uiStore = ThemeLocaleStore.shared
    @Environment(\.colorScheme) private var colorScheme
    let onDismiss: () -> Void

    @State private var category: BugFeedbackCategory = .bug
    @State private var titleText: String = ""
    @State private var detailsText: String = ""
    @State private var includeDiagnostics: Bool = true

    public init(store: StoreKitManager, appVersion: String, onDismiss: @escaping () -> Void) {
        self.store = store
        self.appVersion = appVersion
        self.onDismiss = onDismiss
    }

    private var resolvedScheme: ColorScheme {
        uiStore.appearanceMode.resolvedColorScheme(environment: colorScheme)
    }

    private var palette: StudioPalette {
        StudioPalette.resolved(mode: uiStore.appearanceMode, environment: colorScheme)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.orange.opacity(0.18))
                        .frame(width: 38, height: 38)
                    Image(systemName: "ladybug.fill")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.orange)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(uiStore.t(.feedbackWindowTitle))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(palette.primaryText)
                    Text(uiStore.t(.feedbackSubtitle))
                        .font(.system(size: 11))
                        .foregroundStyle(palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Picker(uiStore.t(.feedbackCategoryLabel), selection: $category) {
                Text(uiStore.t(.feedbackCatBug)).tag(BugFeedbackCategory.bug)
                Text(uiStore.t(.feedbackCatFeature)).tag(BugFeedbackCategory.feature)
                Text(uiStore.t(.feedbackCatPerf)).tag(BugFeedbackCategory.performance)
            }
            .pickerStyle(.segmented)

            TextField(uiStore.t(.feedbackTitlePlaceholder), text: $titleText)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))

            ZStack(alignment: .topLeading) {
                TextEditor(text: $detailsText)
                    .font(.system(size: 12))
                    .frame(height: 120)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(palette.cardBackground)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(palette.cardBorder, lineWidth: 0.9)
                            )
                    )
                if detailsText.isEmpty {
                    Text(uiStore.t(.feedbackDetailsPlaceholder))
                        .font(.system(size: 12))
                        .foregroundStyle(palette.tertiaryText)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 10)
                        .allowsHitTesting(false)
                }
            }

            Toggle(uiStore.t(.feedbackIncludeDiagnostics), isOn: $includeDiagnostics)
                .font(.system(size: 11))
                .foregroundStyle(palette.secondaryText)

            HStack(spacing: 8) {
                Button(uiStore.t(.cancelAction)) {
                    onDismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button {
                    if let url = BugFeedbackBuilder.buildMailtoURL(
                        category: category,
                        title: titleText,
                        details: detailsText,
                        includeDiagnostics: includeDiagnostics,
                        planLabel: store.currentPlanShortLabel,
                        appVersion: appVersion
                    ) {
                        NSWorkspace.shared.open(url)
                        onDismiss()
                    }
                } label: {
                    Label(uiStore.t(.feedbackSubmitEmailBtn), systemImage: "envelope.fill")
                        .font(.system(size: 11.5, weight: .semibold))
                }

                Button {
                    if let url = BugFeedbackBuilder.buildGitHubIssueURL(
                        category: category,
                        title: titleText,
                        details: detailsText,
                        includeDiagnostics: includeDiagnostics,
                        planLabel: store.currentPlanShortLabel,
                        appVersion: appVersion
                    ) {
                        NSWorkspace.shared.open(url)
                        onDismiss()
                    }
                } label: {
                    Label(uiStore.t(.feedbackSubmitGitHubBtn), systemImage: "arrow.up.right.square.fill")
                        .font(.system(size: 11.5, weight: .bold))
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 470)
        .background(palette.windowBackground)
        .environment(\.colorScheme, resolvedScheme)
        .preferredColorScheme(uiStore.appearanceMode.swiftUIColorScheme)
    }
}
