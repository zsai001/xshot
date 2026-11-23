import Foundation

/// Central distribution channel capabilities so the exact same Swift codebase builds cleanly
/// for both direct open-source GitHub distribution and the sandboxed Mac App Store (MAS).
public enum AppDistribution {
    #if MAC_APP_STORE
    public static let isMacAppStore: Bool = true
    #else
    public static let isMacAppStore: Bool = false
    #endif

    /// Self-updating binaries (GitHub Releases + in-place app swap) are disallowed on Mac App Store (Guideline 2.5.2).
    public static var supportsSelfUpdate: Bool { !isMacAppStore }

    /// External XTags OAuth login is used exclusively to unlock seamless self-updates in direct builds.
    public static var supportsXTagsLogin: Bool { !isMacAppStore }

    /// Global keystroke logging, AXUIElement caret probing, and synthetic CGEvent scrolling require
    /// Accessibility / Input Monitoring outside App Sandbox.
    public static var supportsAccessibilityFeatures: Bool { !isMacAppStore }

    /// StoreKit 2 In-App Purchases (Free Trial, $6/mo auto-upgrading to Lifetime after 6 paid months, or $36 Lifetime)
    /// are active on Mac App Store builds; direct open-source source builds remain 100% unlocked.
    public static var usesStoreKitIAP: Bool { isMacAppStore }
}
