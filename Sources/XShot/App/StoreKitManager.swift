import AppKit
import Foundation
import StoreKit

// MARK: - Product Identifiers & Pricing Constants

public enum XShotProductID {
    /// Auto-Renewable Monthly Subscription ($6/mo with Free Trial introductory offer).
    /// Accumulating 6 paid monthly billing cycles automatically upgrades the user to Lifetime Pro permanently!
    public static let proMonthly = "top.xtags.xshot.pro.monthly"

    /// One-Time Non-Consumable Lifetime Update License ($36 once).
    public static let proLifetime = "top.xtags.xshot.pro.lifetime"

    public static let all: Set<String> = [proMonthly, proLifetime]
    public static let loyaltyMonthsRequiredForLifetime: Int = 6
}

// MARK: - Pure, Testable Entitlement & 6-Month Loyalty Calculation Engine

public struct StoreTransactionRecord: Equatable, Hashable, Sendable {
    public let transactionID: UInt64
    public let productID: String
    public let purchaseDate: Date
    public let expirationDate: Date?
    public let revocationDate: Date?
    public let isFreeIntroductoryOffer: Bool

    public init(
        transactionID: UInt64,
        productID: String,
        purchaseDate: Date,
        expirationDate: Date? = nil,
        revocationDate: Date? = nil,
        isFreeIntroductoryOffer: Bool = false
    ) {
        self.transactionID = transactionID
        self.productID = productID
        self.purchaseDate = purchaseDate
        self.expirationDate = expirationDate
        self.revocationDate = revocationDate
        self.isFreeIntroductoryOffer = isFreeIntroductoryOffer
    }
}

public enum ProUnlockReason: Equatable, Sendable {
    case openSourceBuild
    case freeTier
    case activeFreeTrial(expiresAt: Date?)
    case activeMonthlySubscription(paidMonths: Int, expiresAt: Date?)
    case lifetimePurchased
    case lifetimeAutoUpgradedAfterSixMonths(paidMonths: Int)
}

public struct ProEntitlementSnapshot: Equatable, Sendable {
    public let isProUnlocked: Bool
    public let isLifetime: Bool
    public let isActiveMonthlySubscriber: Bool
    public let isInFreeTrial: Bool
    public let paidMonthlyCycles: Int
    public let loyaltyTargetMonths: Int
    public let reason: ProUnlockReason

    public var remainingMonthsForLifetime: Int {
        max(0, loyaltyTargetMonths - paidMonthlyCycles)
    }

    public var loyaltyProgress: Double {
        guard loyaltyTargetMonths > 0 else { return 1.0 }
        return min(1.0, Double(paidMonthlyCycles) / Double(loyaltyTargetMonths))
    }

    public var reachedLoyaltyUpgrade: Bool {
        if case .lifetimeAutoUpgradedAfterSixMonths = reason { return true }
        return false
    }

    public var hasPrioritySupportAccess: Bool {
        isProUnlocked
    }
}

public enum ProEntitlementEvaluator {
    /// Evaluates verified StoreKit 2 transaction history purely and deterministically:
    /// 1. Direct Lifetime (`proLifetime`) non-revoked purchase -> permanent Lifetime Pro.
    /// 2. Unique paid monthly subscription transactions (`proMonthly`, non-revoked, excluding $0 free trial) >= 6 ->
    ///    automatically upgrades permanently to Lifetime Pro (even after user cancels future renewals!).
    /// 3. Active non-expired monthly subscription (either in Free Trial or paid cycle) -> Pro unlocked.
    public static func evaluate(
        allTransactions: [StoreTransactionRecord],
        currentEntitlements: [StoreTransactionRecord],
        now: Date = Date(),
        loyaltyTargetMonths: Int = XShotProductID.loyaltyMonthsRequiredForLifetime
    ) -> ProEntitlementSnapshot {
        // Deduplicate by transactionID while honoring revocation
        var byID: [UInt64: StoreTransactionRecord] = [:]
        for tx in allTransactions + currentEntitlements {
            if let existing = byID[tx.transactionID] {
                if tx.revocationDate != nil && existing.revocationDate == nil {
                    byID[tx.transactionID] = tx
                }
            } else {
                byID[tx.transactionID] = tx
            }
        }
        let validTxs = byID.values.filter { $0.revocationDate == nil }

        // Count unique PAID monthly billing cycles (exclude $0 free trial introductory periods & revoked orders)
        let paidMonthlyCount = validTxs.filter { tx in
            tx.productID == XShotProductID.proMonthly && !tx.isFreeIntroductoryOffer
        }.count

        // Check active current monthly subscription (whether active renewal or free trial)
        let activeMonthly = currentEntitlements
            .filter { tx in
                tx.productID == XShotProductID.proMonthly &&
                tx.revocationDate == nil &&
                (tx.expirationDate == nil || tx.expirationDate! > now)
            }
            .sorted { ($0.expirationDate ?? .distantFuture) > ($1.expirationDate ?? .distantFuture) }
            .first

        // 1. Direct Lifetime Non-Consumable Purchase
        let hasDirectLifetime = validTxs.contains { $0.productID == XShotProductID.proLifetime }
        if hasDirectLifetime {
            return ProEntitlementSnapshot(
                isProUnlocked: true,
                isLifetime: true,
                isActiveMonthlySubscriber: activeMonthly != nil,
                isInFreeTrial: false,
                paidMonthlyCycles: paidMonthlyCount,
                loyaltyTargetMonths: loyaltyTargetMonths,
                reason: .lifetimePurchased
            )
        }

        // 2. Loyalty Auto-Upgrade: 6 Paid Monthly Cycles -> Permanent Lifetime Pro!
        if paidMonthlyCount >= loyaltyTargetMonths {
            return ProEntitlementSnapshot(
                isProUnlocked: true,
                isLifetime: true,
                isActiveMonthlySubscriber: activeMonthly != nil,
                isInFreeTrial: false,
                paidMonthlyCycles: paidMonthlyCount,
                loyaltyTargetMonths: loyaltyTargetMonths,
                reason: .lifetimeAutoUpgradedAfterSixMonths(paidMonths: paidMonthlyCount)
            )
        }

        // 3. Active Monthly Subscription or Active Free Trial
        if let active = activeMonthly {
            if active.isFreeIntroductoryOffer {
                return ProEntitlementSnapshot(
                    isProUnlocked: true,
                    isLifetime: false,
                    isActiveMonthlySubscriber: true,
                    isInFreeTrial: true,
                    paidMonthlyCycles: paidMonthlyCount,
                    loyaltyTargetMonths: loyaltyTargetMonths,
                    reason: .activeFreeTrial(expiresAt: active.expirationDate)
                )
            }
            return ProEntitlementSnapshot(
                isProUnlocked: true,
                isLifetime: false,
                isActiveMonthlySubscriber: true,
                isInFreeTrial: false,
                paidMonthlyCycles: paidMonthlyCount,
                loyaltyTargetMonths: loyaltyTargetMonths,
                reason: .activeMonthlySubscription(paidMonths: paidMonthlyCount, expiresAt: active.expirationDate)
            )
        }

        // 4. Free Tier (retains paid month progress toward 6-month lifetime upgrade if they resubscribe later!)
        return ProEntitlementSnapshot(
            isProUnlocked: false,
            isLifetime: false,
            isActiveMonthlySubscriber: false,
            isInFreeTrial: false,
            paidMonthlyCycles: paidMonthlyCount,
            loyaltyTargetMonths: loyaltyTargetMonths,
            reason: .freeTier
        )
    }
}

// MARK: - Priority Bug Feedback URL Builder (100% App Sandbox Safe — Zero Network Entitlement)

public enum BugFeedbackCategory: String, CaseIterable, Identifiable, Sendable {
    case bug
    case feature
    case performance

    public var id: String { rawValue }
}

public enum BugFeedbackBuilder {
    public static let githubIssuesNewBase = "https://github.com/zsai001/xshot/issues/new"
    public static let supportEmail = "zsai001@xdev.sh"

    public static func systemDiagnosticsSummary(planLabel: String, appVersion: String) -> String {
        let osVer = ProcessInfo.processInfo.operatingSystemVersionString
        #if arch(arm64)
        let arch = "Apple Silicon (arm64)"
        #elseif arch(x86_64)
        let arch = "Intel (x86_64)"
        #else
        let arch = "macOS"
        #endif
        let channel = AppDistribution.isMacAppStore ? "Mac App Store" : "Direct Release"
        return """
        - **App Version**: XShot v\(appVersion) (\(channel))
        - **Plan Tier**: \(planLabel)
        - **macOS**: \(osVer)
        - **Architecture**: \(arch)
        """
    }

    public static func buildGitHubIssueURL(
        category: BugFeedbackCategory,
        title: String,
        details: String,
        includeDiagnostics: Bool,
        planLabel: String,
        appVersion: String
    ) -> URL? {
        let prefix: String
        switch category {
        case .bug: prefix = "[Bug]"
        case .feature: prefix = "[Feature]"
        case .performance: prefix = "[Performance]"
        }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let fullTitle = cleanTitle.isEmpty ? "\(prefix) XShot Feedback" : "\(prefix) \(cleanTitle)"

        var body = details.trimmingCharacters(in: .whitespacesAndNewlines)
        if includeDiagnostics {
            let diag = systemDiagnosticsSummary(planLabel: planLabel, appVersion: appVersion)
            body = body.isEmpty ? diag : "\(body)\n\n---\n### Environment\n\(diag)"
        }

        var comps = URLComponents(string: githubIssuesNewBase)
        comps?.queryItems = [
            URLQueryItem(name: "title", value: fullTitle),
            URLQueryItem(name: "body", value: body)
        ]
        return comps?.url
    }

    public static func buildMailtoURL(
        category: BugFeedbackCategory,
        title: String,
        details: String,
        includeDiagnostics: Bool,
        planLabel: String,
        appVersion: String
    ) -> URL? {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let subject = "[XShot Priority \(category.rawValue.capitalized)] \(cleanTitle.isEmpty ? "Feedback" : cleanTitle)"
        var body = details.trimmingCharacters(in: .whitespacesAndNewlines)
        if includeDiagnostics {
            let diag = systemDiagnosticsSummary(planLabel: planLabel, appVersion: appVersion)
            body = body.isEmpty ? diag : "\(body)\n\n---\n\(diag)"
        }
        var comps = URLComponents()
        comps.scheme = "mailto"
        comps.path = supportEmail
        comps.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body)
        ]
        return comps.url
    }
}

// MARK: - Live StoreKit 2 Manager

@MainActor
public final class StoreKitManager: ObservableObject {
    public nonisolated static let appleStandardEULAURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    public nonisolated static let privacyPolicyURL = URL(string: "https://github.com/zsai001/xshot/blob/main/SECURITY.md")!
    public nonisolated static let manageSubscriptionsURL = URL(string: "https://apps.apple.com/account/subscriptions")!

    @Published public private(set) var monthlyProduct: Product?
    @Published public private(set) var lifetimeProduct: Product?
    @Published public private(set) var isEligibleForFreeTrial: Bool = true
    @Published public private(set) var isLoadingProducts: Bool = false
    @Published public private(set) var isPurchasing: Bool = false
    @Published public private(set) var isRestoring: Bool = false
    @Published public private(set) var entitlement: ProEntitlementSnapshot
    @Published public var statusMessage: String?
    @Published public var errorMessage: String?

    private var transactionListenerTask: Task<Void, Never>?

    public var isProUnlocked: Bool {
        if !AppDistribution.usesStoreKitIAP {
            return true
        }
        return entitlement.isProUnlocked
    }

    public var monthlyPriceDisplay: String {
        monthlyProduct?.displayPrice ?? "$6"
    }

    public var lifetimePriceDisplay: String {
        lifetimeProduct?.displayPrice ?? "$36"
    }

    public var freeTrialDisplayText: String? {
        guard isEligibleForFreeTrial else { return nil }
        if let offer = monthlyProduct?.subscription?.introductoryOffer,
           offer.paymentMode == .freeTrial {
            let unit = offer.period.unit
            let val = offer.period.value
            switch unit {
            case .day: return L10n.format(.iapTrialDaysFormat, val)
            case .week: return L10n.format(.iapTrialDaysFormat, val * 7)
            case .month: return L10n.format(.iapTrialMonthsFormat, val)
            case .year: return L10n.format(.iapTrialMonthsFormat, val * 12)
            @unknown default: return L10n.t(.iapFreeTrialBadge)
            }
        }
        return L10n.t(.iapFreeTrialBadge)
    }

    public var currentPlanShortLabel: String {
        if !AppDistribution.usesStoreKitIAP {
            return "Open Source"
        }
        switch entitlement.reason {
        case .lifetimePurchased:
            return L10n.t(.iapPlanLifetimeBadge)
        case .lifetimeAutoUpgradedAfterSixMonths:
            return L10n.t(.iapPlanLifetimeLoyaltyBadge)
        case .activeFreeTrial:
            return L10n.t(.iapPlanTrialBadge)
        case .activeMonthlySubscription(let months, _):
            return L10n.format(.iapPlanMonthlyProgressFormat, months, entitlement.loyaltyTargetMonths)
        case .freeTier:
            return L10n.t(.iapPlanFreeBadge)
        case .openSourceBuild:
            return "Open Source"
        }
    }

    public init() {
        if AppDistribution.usesStoreKitIAP {
            self.entitlement = ProEntitlementSnapshot(
                isProUnlocked: false,
                isLifetime: false,
                isActiveMonthlySubscriber: false,
                isInFreeTrial: false,
                paidMonthlyCycles: 0,
                loyaltyTargetMonths: XShotProductID.loyaltyMonthsRequiredForLifetime,
                reason: .freeTier
            )
        } else {
            self.entitlement = ProEntitlementSnapshot(
                isProUnlocked: true,
                isLifetime: true,
                isActiveMonthlySubscriber: false,
                isInFreeTrial: false,
                paidMonthlyCycles: 0,
                loyaltyTargetMonths: XShotProductID.loyaltyMonthsRequiredForLifetime,
                reason: .openSourceBuild
            )
        }
    }

    deinit {
        transactionListenerTask?.cancel()
    }

    /// Starts StoreKit 2 live transaction listener, fetches products, and verifies entitlements + 6-month loyalty history.
    public func start() {
        guard AppDistribution.usesStoreKitIAP else { return }
        if transactionListenerTask == nil {
            transactionListenerTask = Task.detached(priority: .background) { [weak self] in
                for await result in Transaction.updates {
                    if case .verified(let tx) = result {
                        await tx.finish()
                        await self?.refreshEntitlements()
                    }
                }
            }
        }
        Task { @MainActor [weak self] in
            await self?.loadProducts()
            await self?.refreshEntitlements()
        }
    }

    public func loadProducts() async {
        guard AppDistribution.usesStoreKitIAP else { return }
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            let fetched = try await Product.products(for: XShotProductID.all)
            self.monthlyProduct = fetched.first(where: { $0.id == XShotProductID.proMonthly })
            self.lifetimeProduct = fetched.first(where: { $0.id == XShotProductID.proLifetime })
            if let sub = self.monthlyProduct?.subscription {
                self.isEligibleForFreeTrial = await sub.isEligibleForIntroOffer
            }
        } catch {
            // Keep default fallback pricing labels visible if App Store Sandbox isn't signed in yet
        }
    }

    public func refreshEntitlements() async {
        guard AppDistribution.usesStoreKitIAP else { return }

        var allRecords: [StoreTransactionRecord] = []
        for await result in Transaction.all {
            if case .verified(let tx) = result, XShotProductID.all.contains(tx.productID) {
                allRecords.append(Self.mapTransaction(tx))
            }
        }

        var currentRecords: [StoreTransactionRecord] = []
        for await result in Transaction.currentEntitlements {
            if case .verified(let tx) = result, XShotProductID.all.contains(tx.productID) {
                currentRecords.append(Self.mapTransaction(tx))
            }
        }

        let evaluated = ProEntitlementEvaluator.evaluate(
            allTransactions: allRecords,
            currentEntitlements: currentRecords
        )
        self.entitlement = evaluated

        if let sub = self.monthlyProduct?.subscription {
            self.isEligibleForFreeTrial = await sub.isEligibleForIntroOffer
        }
    }

    @discardableResult
    public func purchase(productID: String) async -> Bool {
        guard AppDistribution.usesStoreKitIAP else { return true }
        errorMessage = nil
        statusMessage = nil

        if monthlyProduct == nil && lifetimeProduct == nil {
            await loadProducts()
        }
        let targetProduct = (productID == XShotProductID.proMonthly) ? monthlyProduct : lifetimeProduct
        guard let product = targetProduct else {
            errorMessage = L10n.t(.iapErrProductsUnavailable)
            return false
        }

        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()
                    await refreshEntitlements()
                    statusMessage = L10n.t(.iapPurchaseSuccessToast)
                    NSSound(named: NSSound.Name("Pop"))?.play()
                    return true
                case .unverified:
                    errorMessage = L10n.t(.iapErrVerificationFailed)
                    return false
                }
            case .userCancelled:
                return false
            case .pending:
                statusMessage = L10n.t(.iapPurchasePending)
                return false
            @unknown default:
                return false
            }
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    public func restorePurchases() async {
        guard AppDistribution.usesStoreKitIAP else { return }
        isRestoring = true
        errorMessage = nil
        statusMessage = nil
        defer { isRestoring = false }

        do {
            try await AppStore.sync()
            await refreshEntitlements()
            if entitlement.isProUnlocked {
                statusMessage = L10n.t(.iapRestoreSuccessToast)
            } else {
                statusMessage = L10n.t(.iapRestoreNothingFound)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func openManageSubscriptions() {
        NSWorkspace.shared.open(Self.manageSubscriptionsURL)
    }

    private static func mapTransaction(_ tx: Transaction) -> StoreTransactionRecord {
        let isFreeIntro: Bool
        if let offer = tx.offer, offer.type == .introductory, (tx.price ?? 0) == 0 {
            isFreeIntro = true
        } else {
            isFreeIntro = false
        }
        return StoreTransactionRecord(
            transactionID: tx.id,
            productID: tx.productID,
            purchaseDate: tx.purchaseDate,
            expirationDate: tx.expirationDate,
            revocationDate: tx.revocationDate,
            isFreeIntroductoryOffer: isFreeIntro
        )
    }
}
