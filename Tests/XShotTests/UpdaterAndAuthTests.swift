import Foundation
import XCTest
@testable import XShot

final class UpdaterAndAuthTests: XCTestCase {

    func testAppVersionSemVerParsingAndOrdering() {
        let v100 = AppVersion("v1.0.0")!
        let v101Beta = AppVersion("1.0.1-beta.1")!
        let v101 = AppVersion("v1.0.1")!
        let v120 = AppVersion("1.2")!
        let v200 = AppVersion("V2.0.0+build42")!

        XCTAssertTrue(v100 < v101Beta)
        XCTAssertTrue(v101Beta < v101)
        XCTAssertTrue(v101 < v120)
        XCTAssertTrue(v120 < v200)
        XCTAssertEqual(AppVersion("1.0.0"), v100)
        XCTAssertNil(AppVersion("not-a-version"))
    }

    func testReleaseAssetSelectorPrefersMatchingArchZipAndNeverPicksDMG() {
        let assets: [GitHubReleaseAsset] = [
            GitHubReleaseAsset(name: "XShot-v1.1.0-macos.dmg", browserDownloadURL: URL(string: "https://example.com/xshot.dmg")!, size: 12_000_000),
            GitHubReleaseAsset(name: "XShot-v1.1.0-macos-x86_64.zip", browserDownloadURL: URL(string: "https://example.com/x86.zip")!, size: 9_000_000),
            GitHubReleaseAsset(name: "XShot-v1.1.0-macos-arm64.zip", browserDownloadURL: URL(string: "https://example.com/arm64.zip")!, size: 9_100_000),
            GitHubReleaseAsset(name: "XShot-v1.1.0-macos-arm64.zip.sha256", browserDownloadURL: URL(string: "https://example.com/arm64.zip.sha256")!, size: 96),
            GitHubReleaseAsset(name: "XShot.dSYM.zip", browserDownloadURL: URL(string: "https://example.com/dsym.zip")!, size: 4_000_000)
        ]

        let armZip = ReleaseAssetSelector.selectZipAsset(from: assets, architecture: "arm64")
        XCTAssertEqual(armZip?.name, "XShot-v1.1.0-macos-arm64.zip")

        let armSha = ReleaseAssetSelector.selectSHA256Asset(for: armZip, from: assets)
        XCTAssertEqual(armSha?.name, "XShot-v1.1.0-macos-arm64.zip.sha256")

        let x86Zip = ReleaseAssetSelector.selectZipAsset(from: assets, architecture: "x86_64")
        XCTAssertEqual(x86Zip?.name, "XShot-v1.1.0-macos-x86_64.zip")

        let dmgOnly = [GitHubReleaseAsset(name: "XShot-v1.1.0.dmg", browserDownloadURL: URL(string: "https://example.com/only.dmg")!)]
        XCTAssertNil(ReleaseAssetSelector.selectZipAsset(from: dmgOnly, architecture: "arm64"))
    }

    func testSHA256ComputationAndParsing() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("xshot-sha-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try Data("hello xshot".utf8).write(to: tmp)

        let digest = try ReleaseAssetSelector.sha256Hex(of: tmp)
        XCTAssertEqual(digest.count, 64)

        let checksumText = """
        0000000000000000000000000000000000000000000000000000000000000000  other.zip
        \(digest.uppercased())  XShot-v1.0.1-macos-arm64.zip
        """
        let parsed = ReleaseAssetSelector.parseSHA256Hex(from: checksumText, matchingFilename: "XShot-v1.0.1-macos-arm64.zip")
        XCTAssertEqual(parsed, digest)
    }

    func testSeamlessInPlaceInstallScriptHandlesSpacesRollbackAndZeroDMG() {
        let script = SeamlessUpdateInstaller.buildInPlaceInstallScript(
            oldPID: 4242,
            stagedAppURL: URL(fileURLWithPath: "/tmp/xshot stage/XShot.app"),
            targetAppURL: URL(fileURLWithPath: "/Applications/XShot.app"),
            stagingRootURL: URL(fileURLWithPath: "/tmp/xshot stage")
        )

        XCTAssertTrue(script.contains("OLD_PID=4242"))
        XCTAssertTrue(script.contains("xattr -dr com.apple.quarantine"))
        XCTAssertTrue(script.contains("mv \"$STAGED_APP\" \"$TARGET_APP\""))
        XCTAssertTrue(script.contains("open -n \"$TARGET_APP\""))
        XCTAssertTrue(script.contains("'/tmp/xshot stage/XShot.app'"))
        XCTAssertFalse(script.lowercased().contains("hdiutil"))
    }

    func testXTagsTokenParserSupportsRawTokensAndDeepLinks() {
        let validToken = "xtags_ext_0123456789abcdefABCDEF0123456789"
        XCTAssertEqual(XTagsTokenParser.extractToken(from: validToken), validToken)
        XCTAssertEqual(
            XTagsTokenParser.extractToken(from: "  \(validToken)\n"),
            validToken
        )

        let deepLink = URL(string: "xshot://auth?token=\(validToken)")!
        XCTAssertEqual(XTagsTokenParser.extractToken(from: deepLink), validToken)
        XCTAssertEqual(XTagsTokenParser.extractToken(from: deepLink.absoluteString), validToken)

        XCTAssertNil(XTagsTokenParser.extractToken(from: "short_token"))
        XCTAssertNil(XTagsTokenParser.extractToken(from: "https://example.com?token=\(validToken)"))
        XCTAssertNil(XTagsTokenParser.extractToken(from: "xtags_ext_bad space token 123456789012345"))
    }

    @MainActor
    func testXTagsAuthManagerSignInPersistReloadAndSignOut() async throws {
        let tmpFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("xshot-auth-test-\(UUID().uuidString)")
            .appendingPathComponent("auth-session.json")
        defer { try? FileManager.default.removeItem(at: tmpFile.deletingLastPathComponent()) }

        let validToken = "xtags_ext_9876543210abcdefABCDEF0123456789"
        let mockFetcher: XTagsDataFetcher = { request in
            let url = request.url!
            if url.path == "/v1/auth/me" {
                let auth = request.value(forHTTPHeaderField: "Authorization")
                if auth == "Bearer \(validToken)" {
                    let body = """
                    {"authenticated":true,"user":{"id":"usr_1","email":"creator@xtags.top","displayName":"Creator","avatarUrl":null,"role":"user","providers":["x","github"],"createdAt":1700000000}}
                    """
                    let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                    return (Data(body.utf8), resp)
                }
                let resp = HTTPURLResponse(url: url, statusCode: 401, httpVersion: nil, headerFields: nil)!
                return (Data("{\"authenticated\":false,\"user\":null}".utf8), resp)
            }
            let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data("{\"ok\":true}".utf8), resp)
        }

        let manager = XTagsAuthManager(
            sessionFileURL: tmpFile,
            fetcher: mockFetcher,
            loadPersistedSession: false
        )
        var authTransitions: [Bool] = []
        manager.onAuthStateChanged = { authTransitions.append($0) }

        let user = try await manager.signIn(withToken: validToken)
        XCTAssertEqual(user.displayName, "Creator")
        XCTAssertTrue(manager.isSignedIn)
        XCTAssertEqual(authTransitions, [true])

        // Verify persisted file has strict 0600 permissions
        let attrs = try FileManager.default.attributesOfItem(atPath: tmpFile.path)
        let perms = (attrs[.posixPermissions] as? NSNumber)?.intValue
        XCTAssertEqual(perms, 0o600)

        // Reload in a fresh manager instance and confirm persistence works seamlessly
        let reloaded = XTagsAuthManager(
            sessionFileURL: tmpFile,
            fetcher: mockFetcher,
            loadPersistedSession: true
        )
        XCTAssertEqual(reloaded.currentUser?.email, "creator@xtags.top")

        await reloaded.signOut()
        XCTAssertFalse(reloaded.isSignedIn)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tmpFile.path))
    }

    @MainActor
    func testUpdaterChecksReleaseAndGatesAutoDownloadBehindXTagsLogin() async throws {
        let suiteName = "top.xtags.xshot.tests.updater.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let mockReleaseJSON = """
        {
          "tag_name": "v1.2.0",
          "name": "XShot v1.2.0",
          "body": "Seamless updates & bug fixes",
          "html_url": "https://github.com/zsai001/xshot/releases/tag/v1.2.0",
          "draft": false,
          "prerelease": false,
          "assets": [
            {
              "name": "XShot-v1.2.0-macos-arm64.zip",
              "browser_download_url": "https://github.com/zsai001/xshot/releases/download/v1.2.0/XShot-v1.2.0-macos-arm64.zip",
              "size": 8500000
            }
          ]
        }
        """

        let mockFetcher: XTagsDataFetcher = { request in
            let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(mockReleaseJSON.utf8), resp)
        }

        // Signed out: detects v1.2.0 cleanly, stays in `.available` without auto-downloading
        let updater = AppUpdaterManager(
            currentVersion: AppVersion("1.0.0")!,
            defaults: defaults,
            fetcher: mockFetcher,
            isSignedInProvider: { false }
        )
        XCTAssertFalse(updater.isAutoUpdateUnlocked)
        XCTAssertFalse(updater.isAutoUpdateEffectivelyActive)

        await updater.checkForUpdates(userInitiated: true)
        if case .available(let release) = updater.status {
            XCTAssertEqual(release.version, AppVersion("1.2.0")!)
            XCTAssertTrue(release.hasDirectZipBinary)
        } else {
            XCTFail("Expected .available(v1.2.0) when signed out, got \(updater.status)")
        }
    }
}
