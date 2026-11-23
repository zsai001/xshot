import AppKit
import CryptoKit
import Foundation

// MARK: - Semantic Versioning

public struct AppVersion: Comparable, Equatable, Hashable, CustomStringConvertible, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let build: Int
    public let prerelease: String?

    public init(major: Int, minor: Int, patch: Int, build: Int = 0, prerelease: String? = nil) {
        self.major = max(0, major)
        self.minor = max(0, minor)
        self.patch = max(0, patch)
        self.build = max(0, build)
        self.prerelease = prerelease?.isEmpty == true ? nil : prerelease
    }

    public init?(_ raw: String) {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("v") || cleaned.hasPrefix("V") {
            cleaned.removeFirst()
        }
        guard !cleaned.isEmpty else { return nil }

        // Strip build metadata (+...)
        if let plusIdx = cleaned.firstIndex(of: "+") {
            cleaned = String(cleaned[..<plusIdx])
        }

        let corePart: String
        let prePart: String?
        if let dashIdx = cleaned.firstIndex(of: "-") {
            corePart = String(cleaned[..<dashIdx])
            prePart = String(cleaned[cleaned.index(after: dashIdx)...])
        } else {
            corePart = cleaned
            prePart = nil
        }

        let comps = corePart.split(separator: ".").compactMap { Int($0) }
        guard !comps.isEmpty, comps.count == corePart.split(separator: ".").count else {
            return nil
        }

        self.major = comps[0]
        self.minor = comps.count > 1 ? comps[1] : 0
        self.patch = comps.count > 2 ? comps[2] : 0
        self.build = comps.count > 3 ? comps[3] : 0
        self.prerelease = prePart?.isEmpty == true ? nil : prePart
    }

    public var description: String {
        let base = build > 0 ? "\(major).\(minor).\(patch).\(build)" : "\(major).\(minor).\(patch)"
        if let pre = prerelease {
            return "\(base)-\(pre)"
        }
        return base
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
        if lhs.build != rhs.build { return lhs.build < rhs.build }

        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, nil):
            return false
        case (_?, nil):
            // Prerelease is older than final release (e.g., 1.0.1-beta.1 < 1.0.1)
            return true
        case (nil, _?):
            return false
        case (let a?, let b?):
            return a.localizedStandardCompare(b) == .orderedAscending
        }
    }
}

// MARK: - GitHub Release Models

public struct GitHubReleaseAsset: Codable, Equatable, Sendable {
    public let name: String
    public let browserDownloadURL: URL
    public let size: Int64
    public let contentType: String?

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
        case size
        case contentType = "content_type"
    }

    public init(name: String, browserDownloadURL: URL, size: Int64 = 0, contentType: String? = nil) {
        self.name = name
        self.browserDownloadURL = browserDownloadURL
        self.size = size
        self.contentType = contentType
    }
}

public struct GitHubReleasePayload: Codable, Equatable, Sendable {
    public let tagName: String
    public let name: String?
    public let body: String?
    public let htmlURL: URL
    public let draft: Bool?
    public let prerelease: Bool?
    public let publishedAt: String?
    public let assets: [GitHubReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlURL = "html_url"
        case draft
        case prerelease
        case publishedAt = "published_at"
        case assets
    }

    public init(
        tagName: String,
        name: String? = nil,
        body: String? = nil,
        htmlURL: URL,
        draft: Bool? = false,
        prerelease: Bool? = false,
        publishedAt: String? = nil,
        assets: [GitHubReleaseAsset] = []
    ) {
        self.tagName = tagName
        self.name = name
        self.body = body
        self.htmlURL = htmlURL
        self.draft = draft
        self.prerelease = prerelease
        self.publishedAt = publishedAt
        self.assets = assets
    }
}

public struct AppReleaseInfo: Equatable, Sendable {
    public let version: AppVersion
    public let tagName: String
    public let title: String
    public let releaseNotes: String
    public let releasePageURL: URL
    public let zipAsset: GitHubReleaseAsset?
    public let sha256Asset: GitHubReleaseAsset?
    public let inlineSHA256: String?
    public let publishedAt: String?

    public init(
        version: AppVersion,
        tagName: String,
        title: String,
        releaseNotes: String,
        releasePageURL: URL,
        zipAsset: GitHubReleaseAsset?,
        sha256Asset: GitHubReleaseAsset?,
        inlineSHA256: String?,
        publishedAt: String?
    ) {
        self.version = version
        self.tagName = tagName
        self.title = title
        self.releaseNotes = releaseNotes
        self.releasePageURL = releasePageURL
        self.zipAsset = zipAsset
        self.sha256Asset = sha256Asset
        self.inlineSHA256 = inlineSHA256
        self.publishedAt = publishedAt
    }

    public var hasDirectZipBinary: Bool {
        zipAsset != nil
    }
}

public struct StagedAppUpdate: Equatable, Sendable {
    public let release: AppReleaseInfo
    public let stagingRootURL: URL
    public let stagedAppURL: URL
    public let verifiedVersion: AppVersion

    public init(
        release: AppReleaseInfo,
        stagingRootURL: URL,
        stagedAppURL: URL,
        verifiedVersion: AppVersion
    ) {
        self.release = release
        self.stagingRootURL = stagingRootURL
        self.stagedAppURL = stagedAppURL
        self.verifiedVersion = verifiedVersion
    }
}

public enum UpdateStatus: Equatable, Sendable {
    case idle
    case checking
    case upToDate(Date)
    case available(AppReleaseInfo)
    case downloading(AppReleaseInfo, Double)
    case verifying(AppReleaseInfo)
    case readyToInstall(StagedAppUpdate)
    case installing(AppReleaseInfo)
    case failed(String)
}

public enum AppUpdateError: LocalizedError, Equatable {
    case invalidReleaseData
    case noZipAssetFound
    case downloadFailed(String)
    case checksumMismatch
    case extractionFailed(String)
    case invalidAppBundle(String)
    case signatureInvalid
    case installScriptFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidReleaseData:
            return L10n.t(.updErrInvalidRelease)
        case .noZipAssetFound:
            return L10n.t(.updErrNoBinary)
        case .downloadFailed(let detail):
            return detail
        case .checksumMismatch:
            return L10n.t(.updErrChecksum)
        case .extractionFailed(let detail):
            return detail
        case .invalidAppBundle(let detail):
            return detail
        case .signatureInvalid:
            return L10n.t(.updErrSignature)
        case .installScriptFailed(let detail):
            return detail
        }
    }
}

// MARK: - Release Parsing, Checksum & Seamless Atomic Script Builder (Pure & Testable)

public enum ReleaseAssetSelector {
    public static var currentArchitecture: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "universal"
        #endif
    }

    /// Selects the best direct `.zip` app archive for seamless zero-DMG replacement (never picks `.dmg`).
    public static func selectZipAsset(
        from assets: [GitHubReleaseAsset],
        architecture: String = currentArchitecture
    ) -> GitHubReleaseAsset? {
        let zipAssets = assets.filter { asset in
            let lower = asset.name.lowercased()
            return lower.hasSuffix(".zip") && !lower.hasSuffix(".dsym.zip")
        }
        guard !zipAssets.isEmpty else { return nil }

        let arch = architecture.lowercased()
        let archTokens: [String] = (arch == "arm64") ? ["arm64", "aarch64", "apple-silicon"] : ["x86_64", "intel", "amd64"]
        let otherArchTokens: [String] = (arch == "arm64") ? ["x86_64", "intel", "amd64"] : ["arm64", "aarch64", "apple-silicon"]

        func score(_ asset: GitHubReleaseAsset) -> Int {
            let n = asset.name.lowercased()
            var s = 0
            if n.contains("xshot") { s += 20 }
            if n.contains("macos") || n.contains("darwin") || n.contains("mac") { s += 15 }
            if archTokens.contains(where: { n.contains($0) }) { s += 50 }
            if n.contains("universal") { s += 35 }
            if otherArchTokens.contains(where: { n.contains($0) }) { s -= 80 }
            return s
        }

        return zipAssets.max(by: { score($0) < score($1) })
    }

    public static func selectSHA256Asset(
        for zipAsset: GitHubReleaseAsset?,
        from assets: [GitHubReleaseAsset]
    ) -> GitHubReleaseAsset? {
        guard let zipAsset else { return nil }
        let exactName = (zipAsset.name + ".sha256").lowercased()
        if let exact = assets.first(where: { $0.name.lowercased() == exactName }) {
            return exact
        }
        return assets.first(where: { asset in
            let lower = asset.name.lowercased()
            return lower.hasSuffix(".sha256") || lower == "sha256sums.txt" || lower == "checksums.txt"
        })
    }

    /// Parses a 64-character lowercase SHA-256 hex digest from a `.sha256` file or release notes text.
    public static func parseSHA256Hex(from text: String, matchingFilename: String? = nil) -> String? {
        let lines = text.components(separatedBy: .newlines)
        if let file = matchingFilename?.lowercased() {
            for line in lines where line.lowercased().contains(file) {
                if let hex = firstSHA256Hex(in: line) {
                    return hex
                }
            }
        }
        for line in lines {
            if let hex = firstSHA256Hex(in: line) {
                return hex
            }
        }
        return nil
    }

    private static func firstSHA256Hex(in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"\b([0-9a-fA-F]{64})\b"#) else {
            return nil
        }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges >= 2 else {
            return nil
        }
        return ns.substring(with: match.range(at: 1)).lowercased()
    }

    public static func sha256Hex(of fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        while autoreleasepool(invoking: {
            let chunk = handle.readData(ofLength: 1_048_576)
            if chunk.isEmpty { return false }
            hasher.update(data: chunk)
            return true
        }) {}
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    public static func parseRelease(_ payload: GitHubReleasePayload, architecture: String = currentArchitecture) -> AppReleaseInfo? {
        guard let ver = AppVersion(payload.tagName) else { return nil }
        let zip = selectZipAsset(from: payload.assets, architecture: architecture)
        let shaAsset = selectSHA256Asset(for: zip, from: payload.assets)
        let inlineSha = payload.body.flatMap { parseSHA256Hex(from: $0, matchingFilename: zip?.name) }
        return AppReleaseInfo(
            version: ver,
            tagName: payload.tagName,
            title: (payload.name?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? payload.tagName,
            releaseNotes: payload.body ?? "",
            releasePageURL: payload.htmlURL,
            zipAsset: zip,
            sha256Asset: shaAsset,
            inlineSHA256: inlineSha,
            publishedAt: payload.publishedAt
        )
    }
}

public enum SeamlessUpdateInstaller {
    /// Resolves where the updated `.app` bundle should be installed in-place.
    /// If running inside an `.app` bundle (e.g., `/Applications/XShot.app`), replaces THAT exact bundle;
    /// otherwise installs cleanly into `/Applications/XShot.app`.
    public static func resolveTargetAppURL(bundleURL: URL = Bundle.main.bundleURL) -> URL {
        if bundleURL.pathExtension.lowercased() == "app" {
            return bundleURL.standardizedFileURL
        }
        return URL(fileURLWithPath: "/Applications/XShot.app", isDirectory: true)
    }

    public static func shellQuote(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    /// Generates an atomic, rollback-safe POSIX shell script that:
    /// 1. Waits for the old XShot PID to quit cleanly;
    /// 2. Removes `com.apple.quarantine` on the verified staged `.app`;
    /// 3. Atomically replaces the existing `.app` bundle in-place (with automatic rollback on failure,
    ///    or macOS admin prompt only if the target directory is not user-writable);
    /// 4. Immediately relaunches the new `XShot.app` — ZERO DMG, ZERO drag-and-drop!
    public static func buildInPlaceInstallScript(
        oldPID: Int32,
        stagedAppURL: URL,
        targetAppURL: URL,
        stagingRootURL: URL
    ) -> String {
        #if MAC_APP_STORE
        return ""
        #else
        let qStaged = shellQuote(stagedAppURL.path)
        let qTarget = shellQuote(targetAppURL.path)
        let qParent = shellQuote(targetAppURL.deletingLastPathComponent().path)
        let qBackup = shellQuote(targetAppURL.path + ".prev.\(oldPID)")
        let qRoot = shellQuote(stagingRootURL.path)

        return """
        #!/bin/sh
        set -u

        OLD_PID=\(oldPID)
        STAGED_APP=\(qStaged)
        TARGET_APP=\(qTarget)
        TARGET_DIR=\(qParent)
        BACKUP_APP=\(qBackup)
        STAGING_ROOT=\(qRoot)

        # 1. Wait cleanly for old XShot process to terminate (up to 20s)
        i=0
        while kill -0 "$OLD_PID" 2>/dev/null && [ "$i" -lt 100 ]; do
          sleep 0.2
          i=$((i + 1))
        done

        # 2. Clear quarantine attribute so macOS relaunches seamlessly without Gatekeeper friction
        xattr -dr com.apple.quarantine "$STAGED_APP" 2>/dev/null || true

        # 3. Atomic in-place .app swap (with rollback protection)
        if [ -w "$TARGET_DIR" ] && { [ ! -e "$TARGET_APP" ] || [ -w "$TARGET_APP" ]; }; then
          rm -rf "$BACKUP_APP" 2>/dev/null || true
          if [ -d "$TARGET_APP" ]; then
            mv "$TARGET_APP" "$BACKUP_APP" || exit 1
          fi
          if mv "$STAGED_APP" "$TARGET_APP"; then
            rm -rf "$BACKUP_APP" 2>/dev/null || true
          else
            # Roll back immediately if swap failed
            [ -d "$BACKUP_APP" ] && mv "$BACKUP_APP" "$TARGET_APP" 2>/dev/null || true
            exit 1
          fi
        else
          # Fallback only if target folder requires admin privileges (still zero DMG / zero drag)
          /usr/bin/osascript -e "do shell script \\"rm -rf '$BACKUP_APP' && ([ -d '$TARGET_APP' ] && mv '$TARGET_APP' '$BACKUP_APP' || true) && mv '$STAGED_APP' '$TARGET_APP' && rm -rf '$BACKUP_APP'\\" with administrator privileges" || exit 1
        fi

        # 4. Relaunch freshly installed XShot immediately and clean up temp staging
        open -n "$TARGET_APP"
        rm -rf "$STAGING_ROOT" 2>/dev/null || true
        rm -f "$0" 2>/dev/null || true
        """
        #endif
    }
}

// MARK: - Live App Updater Manager

@MainActor
public final class AppUpdaterManager: ObservableObject {
    public nonisolated static let defaultRepoSlug = "zsai001/xshot"
    public nonisolated static let autoUpdateDefaultsKey = "xshot.autoUpdateEnabled"
    private static let checkIntervalSeconds: TimeInterval = 4 * 3600 // Every 4 hours

    @Published public private(set) var status: UpdateStatus = .idle
    @Published public private(set) var latestRelease: AppReleaseInfo?
    @Published public private(set) var lastCheckedAt: Date?
    @Published public var autoUpdateEnabled: Bool {
        didSet {
            defaults.set(autoUpdateEnabled, forKey: Self.autoUpdateDefaultsKey)
            if autoUpdateEnabled && isSignedInProvider() {
                schedulePeriodicChecks()
                Task { [weak self] in
                    await self?.checkForUpdates(userInitiated: false)
                }
            }
        }
    }

    public let currentVersion: AppVersion
    public let repoSlug: String

    private let defaults: UserDefaults
    private let fetcher: XTagsDataFetcher
    private let isSignedInProvider: @MainActor () -> Bool
    private let canAutoApplyImmediatelyProvider: @MainActor () -> Bool

    private var periodicTimer: Timer?
    private var activeTask: Task<Void, Never>?

    public var isAutoUpdateUnlocked: Bool {
        isSignedInProvider()
    }

    public var isAutoUpdateEffectivelyActive: Bool {
        isSignedInProvider() && autoUpdateEnabled
    }

    public var releasesPageURL: URL {
        URL(string: "https://github.com/\(repoSlug)/releases")!
    }

    public init(
        repoSlug: String = AppUpdaterManager.defaultRepoSlug,
        currentVersion: AppVersion? = nil,
        defaults: UserDefaults = .standard,
        fetcher: @escaping XTagsDataFetcher = { request in
            try await URLSession.shared.data(for: request)
        },
        isSignedInProvider: @escaping @MainActor () -> Bool,
        canAutoApplyImmediatelyProvider: @escaping @MainActor () -> Bool = { false }
    ) {
        self.repoSlug = repoSlug
        if let currentVersion {
            self.currentVersion = currentVersion
        } else {
            let isXShotBundle = (Bundle.main.bundleIdentifier == "top.xtags.xshot")
            let bundleVer = isXShotBundle
                ? (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0")
                : "1.0.0"
            self.currentVersion = AppVersion(bundleVer) ?? AppVersion(major: 1, minor: 0, patch: 0)
        }
        self.defaults = defaults
        self.fetcher = fetcher
        self.isSignedInProvider = isSignedInProvider
        self.canAutoApplyImmediatelyProvider = canAutoApplyImmediatelyProvider

        if defaults.object(forKey: Self.autoUpdateDefaultsKey) != nil {
            self.autoUpdateEnabled = defaults.bool(forKey: Self.autoUpdateDefaultsKey)
        } else {
            self.autoUpdateEnabled = true
        }
    }

    /// Starts background auto-update schedule if signed in with XTags.
    public func startLifecycle() {
        #if !MAC_APP_STORE
        schedulePeriodicChecks()
        if isAutoUpdateEffectivelyActive {
            // Brief 6-second startup delay so XShot launches instantaneously with zero main-thread stalls
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                guard let self, self.isAutoUpdateEffectivelyActive else { return }
                await self.checkForUpdates(userInitiated: false)
            }
        }
        #endif
    }

    /// Called whenever XTags login state changes. Signing in immediately triggers a seamless auto-update check!
    public func handleAuthStateChanged(signedIn: Bool) {
        if signedIn {
            schedulePeriodicChecks()
            if autoUpdateEnabled {
                Task { @MainActor [weak self] in
                    await self?.checkForUpdates(userInitiated: false)
                }
            }
        } else {
            periodicTimer?.invalidate()
            periodicTimer = nil
            // If an update was already staged while signed in, keep available state cleanly
            if case .readyToInstall(let staged) = status {
                status = .available(staged.release)
            }
        }
    }

    private func schedulePeriodicChecks() {
        periodicTimer?.invalidate()
        guard isAutoUpdateEffectivelyActive else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: Self.checkIntervalSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isAutoUpdateEffectivelyActive else { return }
                await self.checkForUpdates(userInitiated: false)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        periodicTimer = timer
    }

    /// Queries GitHub Releases for the latest XShot release.
    /// If signed in with XTags and `autoUpdateEnabled` is on, automatically downloads, verifies,
    /// and seamlessly applies the update in-place without opening any DMG!
    public func checkForUpdates(userInitiated: Bool) async {
        #if MAC_APP_STORE
        return
        #else
        switch status {
        case .checking, .downloading, .verifying, .installing:
            return
        case .readyToInstall(let staged):
            if userInitiated {
                applyStagedUpdateAndRelaunch(staged)
            }
            return
        default:
            break
        }

        status = .checking
        do {
            let release = try await fetchLatestRelease()
            let now = Date()
            lastCheckedAt = now
            latestRelease = release

            if release.version > currentVersion {
                status = .available(release)
                // Logged-in XTags users get seamless background auto-update automatically!
                if isAutoUpdateEffectivelyActive && release.hasDirectZipBinary {
                    await downloadStageAndAutoApply(release, forceImmediateRelaunch: false)
                }
            } else {
                status = .upToDate(now)
            }
        } catch {
            if userInitiated {
                status = .failed(error.localizedDescription)
            } else {
                // Keep quiet on silent background network hiccups
                status = .idle
            }
        }
        #endif
    }

    /// Starts immediate one-click seamless in-place update (zero DMG, zero dragging, auto-relaunch).
    public func startSeamlessUpdateNow() {
        switch status {
        case .readyToInstall(let staged):
            applyStagedUpdateAndRelaunch(staged)
            return
        case .available(let release):
            activeTask?.cancel()
            activeTask = Task { @MainActor [weak self] in
                await self?.downloadStageAndAutoApply(release, forceImmediateRelaunch: true)
            }
        default:
            activeTask?.cancel()
            activeTask = Task { @MainActor [weak self] in
                guard let self else { return }
                await self.checkForUpdates(userInitiated: true)
                if case .available(let release) = self.status, self.isSignedInProvider(), release.hasDirectZipBinary {
                    await self.downloadStageAndAutoApply(release, forceImmediateRelaunch: true)
                }
            }
        }
    }

    /// Applies an already-downloaded & verified update cleanly in-place and relaunches XShot.
    public func applyStagedUpdateAndRelaunch(_ staged: StagedAppUpdate) {
        #if !MAC_APP_STORE
        status = .installing(staged.release)
        let targetApp = SeamlessUpdateInstaller.resolveTargetAppURL()
        let scriptContent = SeamlessUpdateInstaller.buildInPlaceInstallScript(
            oldPID: ProcessInfo.processInfo.processIdentifier,
            stagedAppURL: staged.stagedAppURL,
            targetAppURL: targetApp,
            stagingRootURL: staged.stagingRootURL
        )
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("xshot-apply-update-\(UUID().uuidString).sh")

        do {
            try scriptContent.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)

            // Launch completely detached so the updater survives NSApp.terminate(nil)
            let launcher = Process()
            launcher.executableURL = URL(fileURLWithPath: "/bin/sh")
            launcher.arguments = ["-c", "nohup \(SeamlessUpdateInstaller.shellQuote(scriptURL.path)) >/dev/null 2>&1 &"]
            launcher.standardInput = FileHandle.nullDevice
            launcher.standardOutput = FileHandle.nullDevice
            launcher.standardError = FileHandle.nullDevice
            try launcher.run()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                NSApp.terminate(nil)
            }
        } catch {
            status = .failed(AppUpdateError.installScriptFailed(error.localizedDescription).localizedDescription)
        }
        #endif
    }

    // MARK: - Download, Verify & Stage

    private func downloadStageAndAutoApply(_ release: AppReleaseInfo, forceImmediateRelaunch: Bool) async {
        guard let zipAsset = release.zipAsset else {
            status = .failed(AppUpdateError.noZipAssetFound.localizedDescription)
            return
        }

        status = .downloading(release, 0.02)
        let stagingRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("xshot-update-\(release.version.description)-\(UUID().uuidString)", isDirectory: true)
        let zipLocalURL = stagingRoot.appendingPathComponent(zipAsset.name)
        let extractDir = stagingRoot.appendingPathComponent("extracted", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)

            // 1. Download .zip with smooth progress reporting
            try await downloadFile(from: zipAsset.browserDownloadURL, to: zipLocalURL) { [weak self] frac in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.status = .downloading(release, frac)
                }
            }

            // 2. Verify SHA-256 digest if published via .sha256 asset or release notes
            status = .verifying(release)
            var expectedSHA = release.inlineSHA256
            if expectedSHA == nil, let shaAsset = release.sha256Asset {
                var shaReq = URLRequest(url: shaAsset.browserDownloadURL)
                shaReq.timeoutInterval = 15
                shaReq.setValue("XShot/\(currentVersion.description)", forHTTPHeaderField: "User-Agent")
                if let (shaData, shaResp) = try? await fetcher(shaReq),
                   let http = shaResp as? HTTPURLResponse,
                   (200..<300).contains(http.statusCode),
                   let shaText = String(data: shaData, encoding: .utf8) {
                    expectedSHA = ReleaseAssetSelector.parseSHA256Hex(from: shaText, matchingFilename: zipAsset.name)
                }
            }

            if let expectedSHA {
                let actualSHA = try await Task.detached(priority: .userInitiated) {
                    try ReleaseAssetSelector.sha256Hex(of: zipLocalURL)
                }.value
                guard actualSHA.lowercased() == expectedSHA.lowercased() else {
                    try? FileManager.default.removeItem(at: stagingRoot)
                    throw AppUpdateError.checksumMismatch
                }
            }

            // 3. Extract via native macOS `ditto` (zero DMG, preserves code signatures & resource forks)
            try await Task.detached(priority: .userInitiated) {
                try Self.runTool("/usr/bin/ditto", arguments: ["-xk", zipLocalURL.path, extractDir.path])
            }.value
            try? FileManager.default.removeItem(at: zipLocalURL)

            // 4. Locate & validate XShot.app bundle
            let (stagedAppURL, bundleVersion) = try await Task.detached(priority: .userInitiated) {
                try Self.locateAndValidateStagedApp(in: extractDir)
            }.value

            let staged = StagedAppUpdate(
                release: release,
                stagingRootURL: stagingRoot,
                stagedAppURL: stagedAppURL,
                verifiedVersion: bundleVersion
            )

            // 5. Seamlessly replace & relaunch right away if user clicked Update Now OR XShot is idle in menu bar!
            if forceImmediateRelaunch || canAutoApplyImmediatelyProvider() {
                applyStagedUpdateAndRelaunch(staged)
            } else {
                status = .readyToInstall(staged)
            }
        } catch {
            try? FileManager.default.removeItem(at: stagingRoot)
            status = .failed(error.localizedDescription)
        }
    }

    private func fetchLatestRelease() async throws -> AppReleaseInfo {
        guard let latestURL = URL(string: "https://api.github.com/repos/\(repoSlug)/releases/latest") else {
            throw AppUpdateError.invalidReleaseData
        }
        var request = URLRequest(url: latestURL)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("XShot/\(currentVersion.description)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await fetcher(request)
        guard let http = response as? HTTPURLResponse else {
            throw AppUpdateError.invalidReleaseData
        }

        if (200..<300).contains(http.statusCode) {
            let payload = try JSONDecoder().decode(GitHubReleasePayload.self, from: data)
            guard let info = ReleaseAssetSelector.parseRelease(payload) else {
                throw AppUpdateError.invalidReleaseData
            }
            return info
        }

        // Fallback to /releases list if /releases/latest returns 404
        if http.statusCode == 404,
           let listURL = URL(string: "https://api.github.com/repos/\(repoSlug)/releases?per_page=5") {
            var listReq = URLRequest(url: listURL)
            listReq.timeoutInterval = 15
            listReq.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            listReq.setValue("XShot/\(currentVersion.description)", forHTTPHeaderField: "User-Agent")
            let (listData, listResp) = try await fetcher(listReq)
            if let listHTTP = listResp as? HTTPURLResponse,
               (200..<300).contains(listHTTP.statusCode),
               let payloads = try? JSONDecoder().decode([GitHubReleasePayload].self, from: listData),
               let firstValid = payloads.first(where: { ($0.draft ?? false) == false }),
               let info = ReleaseAssetSelector.parseRelease(firstValid) {
                return info
            }
        }

        throw AppUpdateError.invalidReleaseData
    }

    private func downloadFile(
        from remoteURL: URL,
        to destinationURL: URL,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let delegate = ProgressDownloadDelegate(onProgress: onProgress)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }

        var req = URLRequest(url: remoteURL)
        req.setValue("XShot/\(currentVersion.description)", forHTTPHeaderField: "User-Agent")

        let (tempURL, response) = try await session.download(for: req, delegate: delegate)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AppUpdateError.downloadFailed("HTTP download failed")
        }
        try? FileManager.default.removeItem(at: destinationURL)
        try FileManager.default.moveItem(at: tempURL, to: destinationURL)
        onProgress(1.0)
    }

    private nonisolated static func locateAndValidateStagedApp(in extractDir: URL) throws -> (URL, AppVersion) {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: extractDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw AppUpdateError.invalidAppBundle("Unable to inspect extracted archive")
        }

        var foundApp: URL?
        for case let candidate as URL in enumerator {
            if candidate.pathExtension.lowercased() == "app" {
                foundApp = candidate
                enumerator.skipDescendants()
                break
            }
        }

        guard let appURL = foundApp else {
            throw AppUpdateError.invalidAppBundle("XShot.app not found in release archive")
        }

        let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard let plistData = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
              let bundleID = plist["CFBundleIdentifier"] as? String,
              bundleID == "top.xtags.xshot",
              let shortVer = plist["CFBundleShortVersionString"] as? String,
              let parsedVer = AppVersion(shortVer) else {
            throw AppUpdateError.invalidAppBundle("Invalid XShot bundle metadata")
        }

        let executableName = (plist["CFBundleExecutable"] as? String) ?? "XShot"
        let execURL = appURL.appendingPathComponent("Contents/MacOS/\(executableName)")
        guard fm.isExecutableFile(atPath: execURL.path) else {
            throw AppUpdateError.invalidAppBundle("Missing executable inside XShot.app")
        }

        // Verify code signature integrity (works for both Developer ID and ad-hoc signed releases)
        do {
            try runTool("/usr/bin/codesign", arguments: ["--verify", "--deep", appURL.path])
        } catch {
            throw AppUpdateError.signatureInvalid
        }

        return (appURL, parsedVer)
    }

    private nonisolated static func runTool(_ launchPath: String, arguments: [String]) throws {
        #if MAC_APP_STORE
        throw AppUpdateError.installScriptFailed("Managed by Mac App Store")
        #else
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: launchPath)
        proc.arguments = arguments
        let stderrPipe = Pipe()
        proc.standardError = stderrPipe
        proc.standardOutput = Pipe()
        try proc.run()
        proc.waitUntilExit()
        if proc.terminationStatus != 0 {
            let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let msg = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw AppUpdateError.extractionFailed(msg?.isEmpty == false ? msg! : "Tool failed (\(proc.terminationStatus))")
        }
        #endif
    }
}

private final class ProgressDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let onProgress: @Sendable (Double) -> Void

    init(onProgress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let fraction = min(max(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite), 0.02), 0.99)
        onProgress(fraction)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Handled by async session.download(for:)
    }
}
