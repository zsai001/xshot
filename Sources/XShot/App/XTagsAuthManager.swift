import AppKit
import Foundation

public struct XTagsUserProfile: Codable, Equatable, Sendable {
    public let id: String
    public let email: String?
    public let displayName: String
    public let avatarUrl: String?
    public let role: String
    public let providers: [String]
    public let createdAt: Int64?

    public init(
        id: String,
        email: String? = nil,
        displayName: String,
        avatarUrl: String? = nil,
        role: String = "user",
        providers: [String] = [],
        createdAt: Int64? = nil
    ) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.avatarUrl = avatarUrl
        self.role = role
        self.providers = providers
        self.createdAt = createdAt
    }

    public var primarySubtitle: String {
        if let email, !email.isEmpty {
            return email
        }
        if !providers.isEmpty {
            return providers.map { $0.uppercased() }.joined(separator: " · ")
        }
        return "XTags Account"
    }

    public var initials: String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "X" }
        return String(first).uppercased()
    }
}

public struct XTagsAuthSession: Codable, Equatable, Sendable {
    public let token: String
    public let user: XTagsUserProfile
    public let signedInAt: Date
    public let apiOrigin: String

    public init(token: String, user: XTagsUserProfile, signedInAt: Date = Date(), apiOrigin: String) {
        self.token = token
        self.user = user
        self.signedInAt = signedInAt
        self.apiOrigin = apiOrigin
    }
}

public enum XTagsAuthError: LocalizedError, Equatable {
    case invalidTokenFormat
    case unauthorized
    case invalidServerResponse
    case networkFailure(String)

    public var errorDescription: String? {
        switch self {
        case .invalidTokenFormat:
            return L10n.t(.authErrInvalidToken)
        case .unauthorized:
            return L10n.t(.authErrUnauthorized)
        case .invalidServerResponse:
            return L10n.t(.authErrServer)
        case .networkFailure(let detail):
            return detail
        }
    }
}

public enum XTagsTokenParser {
    /// Extracts a valid XTags bearer token from raw text, a pasted token, or a `xshot://auth?token=...` URL.
    public static func extractToken(from rawInput: String) -> String? {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed),
           let extracted = extractToken(from: url) {
            return extracted
        }

        return isValidTokenFormat(trimmed) ? trimmed : nil
    }

    /// Extracts an XTags token from an incoming `xshot://auth?token=...` custom URL callback.
    public static func extractToken(from url: URL) -> String? {
        guard url.scheme?.lowercased() == "xshot" else { return nil }
        let host = url.host?.lowercased() ?? ""
        let path = url.path.lowercased()
        guard host == "auth" || path.contains("auth") else { return nil }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let token = components.queryItems?.first(where: { $0.name == "token" })?.value else {
            return nil
        }
        let cleaned = token.trimmingCharacters(in: .whitespacesAndNewlines)
        return isValidTokenFormat(cleaned) ? cleaned : nil
    }

    /// XTags issues `xtags_ext_<random>` or `xtags_web_<random>` tokens.
    public static func isValidTokenFormat(_ candidate: String) -> Bool {
        let s = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.hasPrefix("xtags_ext_") || s.hasPrefix("xtags_web_") else { return false }
        guard s.count >= 28, s.count <= 256 else { return false }
        return s.unicodeScalars.allSatisfy { scalar in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "_" || scalar == "-"
        }
    }
}

public struct XTagsAuthMeResponse: Codable, Sendable {
    public let authenticated: Bool
    public let user: XTagsUserProfile?
}

public typealias XTagsDataFetcher = @Sendable (URLRequest) async throws -> (Data, URLResponse)

@MainActor
public final class XTagsAuthManager: ObservableObject {
    public nonisolated static let defaultWebOrigin = "https://xtags.top"
    public nonisolated static let defaultAPIOrigin = "https://api.xtags.top"

    @Published public private(set) var session: XTagsAuthSession?
    @Published public private(set) var isAuthenticating: Bool = false
    @Published public private(set) var isWaitingForBrowserCallback: Bool = false
    @Published public var lastErrorMessage: String?

    public var isSignedIn: Bool { session != nil }
    public var currentUser: XTagsUserProfile? { session?.user }

    public let webOrigin: String
    public let apiOrigin: String
    private let sessionFileURL: URL
    private let fetcher: XTagsDataFetcher

    private var clipboardWatchTimer: Timer?
    private var lastClipboardChangeCount: Int = 0
    private var lastAutoTriedToken: String?

    /// Invoked whenever authentication state transitions (e.g., signed in → triggers seamless auto-updater!).
    public var onAuthStateChanged: ((Bool) -> Void)?

    public init(
        webOrigin: String = XTagsAuthManager.defaultWebOrigin,
        apiOrigin: String = XTagsAuthManager.defaultAPIOrigin,
        sessionFileURL: URL? = nil,
        fetcher: @escaping XTagsDataFetcher = { request in
            try await URLSession.shared.data(for: request)
        },
        loadPersistedSession: Bool = true
    ) {
        self.webOrigin = webOrigin.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.apiOrigin = apiOrigin.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.sessionFileURL = sessionFileURL ?? Self.defaultSessionFileURL()
        self.fetcher = fetcher

        if loadPersistedSession {
            self.session = loadSessionFromDisk()
        }
    }

    public var browserSignInURL: URL {
        URL(string: "\(webOrigin)/auth/extension?client=xshot")!
    }

    /// Opens the XTags web login & token authorization page in the default browser and listens
    /// for either `xshot://auth?token=...` deep-link callback or a copied XTags token on clipboard.
    public func beginBrowserSignIn(openBrowser: Bool = true) {
        lastErrorMessage = nil
        isWaitingForBrowserCallback = true
        lastAutoTriedToken = nil
        startClipboardTokenMonitor()
        if openBrowser {
            NSWorkspace.shared.open(browserSignInURL)
        }
    }

    public func stopWaitingForBrowserSignIn() {
        isWaitingForBrowserCallback = false
        stopClipboardTokenMonitor()
    }

    /// Handles incoming macOS custom URL callback (`xshot://auth?token=...`).
    @discardableResult
    public func handleCallbackURL(_ url: URL) -> Bool {
        guard let token = XTagsTokenParser.extractToken(from: url) else {
            return false
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            _ = try? await self.signIn(withToken: token)
        }
        return true
    }

    /// Verifies an XTags token live against `GET /v1/auth/me` and persists the session locally (`0600`).
    @discardableResult
    public func signIn(withToken rawInput: String) async throws -> XTagsUserProfile {
        guard let token = XTagsTokenParser.extractToken(from: rawInput) else {
            lastErrorMessage = XTagsAuthError.invalidTokenFormat.localizedDescription
            throw XTagsAuthError.invalidTokenFormat
        }

        isAuthenticating = true
        lastErrorMessage = nil
        defer { isAuthenticating = false }

        let user = try await verifyTokenWithServer(token)
        let newSession = XTagsAuthSession(
            token: token,
            user: user,
            signedInAt: Date(),
            apiOrigin: apiOrigin
        )
        let wasSignedIn = (session != nil)
        session = newSession
        saveSessionToDisk(newSession)
        stopWaitingForBrowserSignIn()

        if !wasSignedIn {
            onAuthStateChanged?(true)
        }
        return user
    }

    /// Re-verifies the persisted session against XTags API in background.
    /// Keeps the local session intact during transient offline errors; clears only on explicit 401 / unauthenticated.
    public func refreshSessionIfNeeded() async {
        guard let current = session else { return }
        do {
            let latestUser = try await verifyTokenWithServer(current.token)
            let updated = XTagsAuthSession(
                token: current.token,
                user: latestUser,
                signedInAt: current.signedInAt,
                apiOrigin: current.apiOrigin
            )
            session = updated
            saveSessionToDisk(updated)
        } catch XTagsAuthError.unauthorized {
            clearLocalSession()
            onAuthStateChanged?(false)
        } catch {
            // Keep cached session on temporary network/offline errors
        }
    }

    /// Revokes the active bearer token on XTags API (best-effort) and signs out locally.
    public func signOut() async {
        let tokenToRevoke = session?.token
        clearLocalSession()
        onAuthStateChanged?(false)

        if let token = tokenToRevoke,
           let url = URL(string: "\(apiOrigin)/v1/auth/logout") {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.timeoutInterval = 8
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("XShot-macOS", forHTTPHeaderField: "User-Agent")
            _ = try? await fetcher(req)
        }
    }

    // MARK: - Network Verification

    private func verifyTokenWithServer(_ token: String) async throws -> XTagsUserProfile {
        guard let url = URL(string: "\(apiOrigin)/v1/auth/me") else {
            throw XTagsAuthError.invalidServerResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("XShot-macOS", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await fetcher(request)
        } catch {
            let err = XTagsAuthError.networkFailure(error.localizedDescription)
            lastErrorMessage = err.localizedDescription
            throw err
        }

        guard let http = response as? HTTPURLResponse else {
            lastErrorMessage = XTagsAuthError.invalidServerResponse.localizedDescription
            throw XTagsAuthError.invalidServerResponse
        }

        if http.statusCode == 401 || http.statusCode == 403 {
            lastErrorMessage = XTagsAuthError.unauthorized.localizedDescription
            throw XTagsAuthError.unauthorized
        }

        guard (200..<300).contains(http.statusCode) else {
            lastErrorMessage = XTagsAuthError.invalidServerResponse.localizedDescription
            throw XTagsAuthError.invalidServerResponse
        }

        guard let decoded = try? JSONDecoder().decode(XTagsAuthMeResponse.self, from: data) else {
            lastErrorMessage = XTagsAuthError.invalidServerResponse.localizedDescription
            throw XTagsAuthError.invalidServerResponse
        }

        guard decoded.authenticated, let user = decoded.user else {
            lastErrorMessage = XTagsAuthError.unauthorized.localizedDescription
            throw XTagsAuthError.unauthorized
        }

        return user
    }

    // MARK: - Smart Clipboard Token Detection (Active ONLY While Sign-In Sheet Is Open)

    private func startClipboardTokenMonitor() {
        stopClipboardTokenMonitor()
        lastClipboardChangeCount = NSPasteboard.general.changeCount
        let timer = Timer.scheduledTimer(withTimeInterval: 0.65, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pollClipboardForToken()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        clipboardWatchTimer = timer
    }

    private func stopClipboardTokenMonitor() {
        clipboardWatchTimer?.invalidate()
        clipboardWatchTimer = nil
    }

    private func pollClipboardForToken() {
        guard isWaitingForBrowserCallback, !isAuthenticating else { return }
        let pb = NSPasteboard.general
        guard pb.changeCount != lastClipboardChangeCount else { return }
        lastClipboardChangeCount = pb.changeCount

        guard let str = pb.string(forType: .string),
              let token = XTagsTokenParser.extractToken(from: str),
              token != lastAutoTriedToken else {
            return
        }
        lastAutoTriedToken = token
        Task { @MainActor [weak self] in
            guard let self else { return }
            _ = try? await self.signIn(withToken: token)
        }
    }

    // MARK: - Private Session Persistence (POSIX 0600 — Zero Keychain Prompts Across Auto-Updates)

    public static func defaultSessionFileURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return appSupport
            .appendingPathComponent("XShot", isDirectory: true)
            .appendingPathComponent("auth-session.json")
    }

    private func loadSessionFromDisk() -> XTagsAuthSession? {
        guard let data = try? Data(contentsOf: sessionFileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(XTagsAuthSession.self, from: data)
    }

    private func saveSessionToDisk(_ session: XTagsAuthSession) {
        let dir = sessionFileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(session) else { return }
        try? data.write(to: sessionFileURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: sessionFileURL.path)
    }

    private func clearLocalSession() {
        session = nil
        lastErrorMessage = nil
        stopWaitingForBrowserSignIn()
        try? FileManager.default.removeItem(at: sessionFileURL)
    }
}
