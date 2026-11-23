import AppKit
import SwiftUI

public struct XShotProPaywallView: View {
    @ObservedObject var store: StoreKitManager
    @ObservedObject private var uiStore = ThemeLocaleStore.shared
    @Environment(\.colorScheme) private var colorScheme
    let onOpenBugFeedback: () -> Void
    let onDismiss: () -> Void

    @State private var selectedProductID: String = XShotProductID.proMonthly

    public init(
        store: StoreKitManager,
        onOpenBugFeedback: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.store = store
        self.onOpenBugFeedback = onOpenBugFeedback
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
            // Hero Header
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.05, green: 0.65, blue: 0.91), Color(red: 0.49, green: 0.23, blue: 0.93)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                    Image(systemName: "sparkles")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(uiStore.t(.iapHeroTitle))
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(palette.primaryText)
                            .lineLimit(1)
                    }
                    Text(uiStore.t(.iapHeroSubtitle))
                        .font(.system(size: 11.5))
                        .foregroundStyle(palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // 6-Month Loyalty-to-Lifetime Progress Banner
            loyaltyProgressCard

            // Core Pro Benefits (highlighting priority bug fixes & timely updates)
            VStack(alignment: .leading, spacing: 7) {
                benefitRow(icon: "ladybug.fill", tint: .orange, text: uiStore.t(.iapFeatureUpdatesAndFixes))
                benefitRow(icon: "arrow.up.and.down.text.horizontal", tint: palette.accent, text: uiStore.t(.iapFeatureCapturePro))
                benefitRow(icon: "video.badge.checkmark", tint: Color(red: 0.64, green: 0.44, blue: 0.98), text: uiStore.t(.iapFeatureVideoStudio))
                benefitRow(icon: "lock.shield.fill", tint: .green, text: uiStore.t(.iapFeaturePrivacyOCR))
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

            if store.entitlement.isLifetime {
                // Already Lifetime Unlocked State
                HStack(spacing: 10) {
                    Button {
                        onDismiss()
                        onOpenBugFeedback()
                    } label: {
                        Label(uiStore.t(.feedbackBtn), systemImage: "ladybug.fill")
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundStyle(palette.accentTextOnAccent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(palette.accent, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .buttonStyle(TactileScaleButtonStyle(pressedScale: 0.98))

                    if store.entitlement.isActiveMonthlySubscriber {
                        Button(uiStore.t(.iapManageSubBtn)) {
                            store.openManageSubscriptions()
                        }
                    }

                    Button(uiStore.t(.okBtn)) {
                        onDismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            } else {
                // Two Selectable Pricing Cards: $6/mo (Free Trial + 6-Mo Auto-Lifetime) vs $36 Lifetime
                HStack(spacing: 10) {
                    planCard(
                        productID: XShotProductID.proMonthly,
                        title: uiStore.t(.iapMonthlyTitle),
                        price: store.monthlyPriceDisplay,
                        periodSuffix: uiStore.t(.iapMonthlyPeriodSuffix),
                        badge: store.freeTrialDisplayText,
                        badgeTint: .green,
                        subtitle: uiStore.t(.iapMonthlySubHint)
                    )
                    planCard(
                        productID: XShotProductID.proLifetime,
                        title: uiStore.t(.iapLifetimeTitle),
                        price: store.lifetimePriceDisplay,
                        periodSuffix: uiStore.t(.iapLifetimeOneTime),
                        badge: uiStore.t(.iapLifetimeBestBadge),
                        badgeTint: Color(red: 0.58, green: 0.36, blue: 0.98),
                        subtitle: uiStore.t(.iapLoyaltyBannerTitle)
                    )
                }

                // Primary Purchase Button
                Button {
                    Task {
                        let ok = await store.purchase(productID: selectedProductID)
                        if ok {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                                onDismiss()
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        if store.isPurchasing {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(primaryCTALabel)
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundStyle(palette.accentTextOnAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(palette.accent, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(TactileScaleButtonStyle(pressedScale: 0.98))
                .disabled(store.isPurchasing || store.isRestoring)
            }

            if let msg = store.statusMessage, !msg.isEmpty {
                Text(msg)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.green)
            }
            if let err = store.errorMessage, !err.isEmpty {
                Text(err)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Mandatory Apple App Review Subscription Footer (Restore, Manage, EULA, Privacy, Renewal Disclosure)
            VStack(spacing: 6) {
                HStack(spacing: 14) {
                    Button {
                        Task { await store.restorePurchases() }
                    } label: {
                        Text(uiStore.t(.iapRestoreBtn))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.accent)
                    }
                    .buttonStyle(.plain)
                    .disabled(store.isRestoring)

                    Button {
                        store.openManageSubscriptions()
                    } label: {
                        Text(uiStore.t(.iapManageSubBtn))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(palette.secondaryText)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button {
                        NSWorkspace.shared.open(StoreKitManager.appleStandardEULAURL)
                    } label: {
                        Text(uiStore.t(.iapTermsLink))
                            .font(.system(size: 10.5))
                            .foregroundStyle(palette.tertiaryText)
                            .underline()
                    }
                    .buttonStyle(.plain)

                    Button {
                        NSWorkspace.shared.open(StoreKitManager.privacyPolicyURL)
                    } label: {
                        Text(uiStore.t(.iapPrivacyLink))
                            .font(.system(size: 10.5))
                            .foregroundStyle(palette.tertiaryText)
                            .underline()
                    }
                    .buttonStyle(.plain)
                }

                Text(uiStore.t(.iapLegalRenewalNote))
                    .font(.system(size: 9.5))
                    .foregroundStyle(palette.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .frame(width: 540)
        .background(palette.windowBackground)
        .environment(\.colorScheme, resolvedScheme)
        .preferredColorScheme(uiStore.appearanceMode.swiftUIColorScheme)
        .task {
            await store.loadProducts()
            await store.refreshEntitlements()
        }
    }

    private var primaryCTALabel: String {
        if selectedProductID == XShotProductID.proLifetime {
            return uiStore.format(.iapBuyLifetimeBtnFormat, store.lifetimePriceDisplay)
        }
        if store.isEligibleForFreeTrial {
            return uiStore.format(.iapStartTrialBtnFormat, store.monthlyPriceDisplay)
        }
        return uiStore.format(.iapSubscribeBtnFormat, store.monthlyPriceDisplay)
    }

    @ViewBuilder
    private var loyaltyProgressCard: some View {
        let ent = store.entitlement
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: ent.isLifetime ? "crown.fill" : "sparkles.rectangle.stack.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(ent.isLifetime ? .green : palette.accent)
                Text(ent.reachedLoyaltyUpgrade ? uiStore.t(.iapLoyaltyUnlockedBanner) : uiStore.t(.iapLoyaltyBannerTitle))
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(ent.isLifetime ? .green : palette.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if ent.reachedLoyaltyUpgrade && ent.isActiveMonthlySubscriber {
                Text(uiStore.t(.iapCancelRenewalTip))
                    .font(.system(size: 10.5))
                    .foregroundStyle(palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // 6-Month visual milestone bar
            HStack(spacing: 5) {
                ForEach(1...ent.loyaltyTargetMonths, id: \.self) { monthIdx in
                    let reached = ent.isLifetime || monthIdx <= ent.paidMonthlyCycles
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(reached ? (ent.isLifetime ? Color.green : palette.accent) : palette.controlFill)
                        .frame(height: 8)
                }
            }

            HStack {
                Text(uiStore.format(.iapLoyaltyProgressFormat, min(ent.paidMonthlyCycles, ent.loyaltyTargetMonths), ent.loyaltyTargetMonths))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.secondaryText)
                Spacer()
                Text(store.currentPlanShortLabel)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(ent.isProUnlocked ? .green : palette.accent)
            }
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(ent.isLifetime ? Color.green.opacity(palette.isDark ? 0.14 : 0.09) : palette.accentSoftFill.opacity(0.65))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(ent.isLifetime ? Color.green.opacity(0.45) : palette.accentBorder.opacity(0.55), lineWidth: 1)
                )
        )
    }

    private func planCard(
        productID: String,
        title: String,
        price: String,
        periodSuffix: String,
        badge: String?,
        badgeTint: Color,
        subtitle: String
    ) -> some View {
        let isSelected = (selectedProductID == productID)
        return Button {
            selectedProductID = productID
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(title)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(palette.primaryText)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if let badge {
                        Text(badge)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(badgeTint, in: Capsule())
                    }
                }

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(price)
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .foregroundStyle(isSelected ? palette.accent : palette.primaryText)
                    Text(periodSuffix)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.secondaryText)
                }

                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? palette.accentSoftFill.opacity(0.55) : palette.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(isSelected ? palette.accent : palette.cardBorder, lineWidth: isSelected ? 1.8 : 0.9)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(TactileScaleButtonStyle(pressedScale: 0.98))
    }

    private func benefitRow(icon: String, tint: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 18)
            Text(text)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(palette.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
