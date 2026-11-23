import Foundation
import XCTest
@testable import XShot

final class StoreKitEntitlementTests: XCTestCase {

    func testFreeTierStartsLockedWithZeroPaidMonths() {
        let snap = ProEntitlementEvaluator.evaluate(allTransactions: [], currentEntitlements: [])
        XCTAssertFalse(snap.isProUnlocked)
        XCTAssertFalse(snap.isLifetime)
        XCTAssertEqual(snap.paidMonthlyCycles, 0)
        XCTAssertEqual(snap.remainingMonthsForLifetime, 6)
        XCTAssertEqual(snap.reason, .freeTier)
    }

    func testFreeTrialUnlocksProWithoutCountingTowardSixPaidMonths() {
        let now = Date()
        let trialTx = StoreTransactionRecord(
            transactionID: 100,
            productID: XShotProductID.proMonthly,
            purchaseDate: now.addingTimeInterval(-3600),
            expirationDate: now.addingTimeInterval(6 * 86400),
            isFreeIntroductoryOffer: true
        )
        let snap = ProEntitlementEvaluator.evaluate(
            allTransactions: [trialTx],
            currentEntitlements: [trialTx],
            now: now
        )
        XCTAssertTrue(snap.isProUnlocked)
        XCTAssertTrue(snap.isInFreeTrial)
        XCTAssertFalse(snap.isLifetime)
        XCTAssertEqual(snap.paidMonthlyCycles, 0)
        XCTAssertEqual(snap.remainingMonthsForLifetime, 6)
    }

    func testFivePaidMonthsStayMonthlyAndTrackProgressAccurately() {
        let now = Date()
        var txs: [StoreTransactionRecord] = [
            // Free trial (should not count as paid)
            StoreTransactionRecord(
                transactionID: 1,
                productID: XShotProductID.proMonthly,
                purchaseDate: now.addingTimeInterval(-160 * 86400),
                expirationDate: now.addingTimeInterval(-153 * 86400),
                isFreeIntroductoryOffer: true
            )
        ]
        for i in 1...5 {
            txs.append(StoreTransactionRecord(
                transactionID: UInt64(10 + i),
                productID: XShotProductID.proMonthly,
                purchaseDate: now.addingTimeInterval(Double(-30 * (6 - i)) * 86400),
                expirationDate: now.addingTimeInterval(Double(30 * (i - 4)) * 86400),
                isFreeIntroductoryOffer: false
            ))
        }
        let active = txs.last!
        let snap = ProEntitlementEvaluator.evaluate(
            allTransactions: txs,
            currentEntitlements: [active],
            now: now
        )
        XCTAssertTrue(snap.isProUnlocked)
        XCTAssertFalse(snap.isLifetime)
        XCTAssertEqual(snap.paidMonthlyCycles, 5)
        XCTAssertEqual(snap.remainingMonthsForLifetime, 1)
        XCTAssertEqual(snap.loyaltyProgress, 5.0 / 6.0, accuracy: 0.0001)
    }

    func testSixPaidMonthsAutomaticallyUpgradeToPermanentLifetimeEvenAfterCancellation() {
        let now = Date()
        var txs: [StoreTransactionRecord] = []
        for i in 1...6 {
            txs.append(StoreTransactionRecord(
                transactionID: UInt64(200 + i),
                productID: XShotProductID.proMonthly,
                purchaseDate: now.addingTimeInterval(Double(-30 * (7 - i)) * 86400),
                expirationDate: now.addingTimeInterval(Double(-30 * (6 - i)) * 86400),
                isFreeIntroductoryOffer: false
            ))
        }

        // Even with NO active current subscription (user canceled renewal after month 6!),
        // Lifetime Pro MUST remain permanently unlocked!
        let snap = ProEntitlementEvaluator.evaluate(
            allTransactions: txs,
            currentEntitlements: [],
            now: now
        )
        XCTAssertTrue(snap.isProUnlocked)
        XCTAssertTrue(snap.isLifetime)
        XCTAssertTrue(snap.reachedLoyaltyUpgrade)
        XCTAssertFalse(snap.isActiveMonthlySubscriber)
        XCTAssertEqual(snap.paidMonthlyCycles, 6)
        XCTAssertEqual(snap.remainingMonthsForLifetime, 0)
        XCTAssertEqual(snap.reason, .lifetimeAutoUpgradedAfterSixMonths(paidMonths: 6))
    }

    func testRefundedSixthMonthDoesNotGrantPrematureLifetimeUpgrade() {
        let now = Date()
        var txs: [StoreTransactionRecord] = []
        for i in 1...6 {
            txs.append(StoreTransactionRecord(
                transactionID: UInt64(300 + i),
                productID: XShotProductID.proMonthly,
                purchaseDate: now.addingTimeInterval(Double(-30 * (7 - i)) * 86400),
                expirationDate: now.addingTimeInterval(Double(-30 * (6 - i)) * 86400),
                revocationDate: (i == 6) ? now.addingTimeInterval(-86400) : nil,
                isFreeIntroductoryOffer: false
            ))
        }

        let snap = ProEntitlementEvaluator.evaluate(
            allTransactions: txs,
            currentEntitlements: [],
            now: now
        )
        XCTAssertFalse(snap.isLifetime)
        XCTAssertEqual(snap.paidMonthlyCycles, 5)
        XCTAssertEqual(snap.remainingMonthsForLifetime, 1)
    }

    func testDirectLifetimePurchaseUnlocksPermanently() {
        let now = Date()
        let lifeTx = StoreTransactionRecord(
            transactionID: 999,
            productID: XShotProductID.proLifetime,
            purchaseDate: now,
            expirationDate: nil,
            isFreeIntroductoryOffer: false
        )
        let snap = ProEntitlementEvaluator.evaluate(
            allTransactions: [lifeTx],
            currentEntitlements: [lifeTx],
            now: now
        )
        XCTAssertTrue(snap.isProUnlocked)
        XCTAssertTrue(snap.isLifetime)
        XCTAssertFalse(snap.reachedLoyaltyUpgrade)
        XCTAssertEqual(snap.reason, .lifetimePurchased)
    }

    func testBugFeedbackBuildersProduceValidGitHubAndMailtoURLs() {
        let ghURL = BugFeedbackBuilder.buildGitHubIssueURL(
            category: .bug,
            title: "Scroll stitch misalignment",
            details: "Happens on Safari tall pages",
            includeDiagnostics: true,
            planLabel: "Lifetime Pro",
            appVersion: "1.0.0"
        )
        XCTAssertNotNil(ghURL)
        XCTAssertEqual(ghURL?.host, "github.com")
        XCTAssertTrue(ghURL?.absoluteString.contains("Scroll%20stitch") == true)
        XCTAssertTrue(ghURL?.absoluteString.contains("Lifetime%20Pro") == true)

        let mailURL = BugFeedbackBuilder.buildMailtoURL(
            category: .feature,
            title: "Custom export bitrate",
            details: "Would love 50 Mbps preset",
            includeDiagnostics: false,
            planLabel: "Pro Monthly",
            appVersion: "1.0.0"
        )
        XCTAssertNotNil(mailURL)
        XCTAssertEqual(mailURL?.scheme, "mailto")
        XCTAssertTrue(mailURL?.absoluteString.contains("zsai001@xdev.sh") == true)
    }
}
