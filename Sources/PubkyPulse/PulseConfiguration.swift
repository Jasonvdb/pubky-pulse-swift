import Foundation

public struct PulseConfiguration: Sendable {
    let endpoint: URL
    let apiKey: String
    let bundleId: String?
    let flushOnBackground: Bool
    let compressionEnabled: Bool
    let networkTrackingEnabled: Bool
    let consoleLogging: Bool
    let attributionEnabled: Bool

    private static let clientKeyPrefix = "pulse_client_"

    /// Pubky's own hosted ingest host, used when the caller omits `endpoint`.
    ///
    /// The fallback is silent — nothing is logged, warned, or thrown when it is
    /// taken — so a self-hoster must pass their own ingest host explicitly, or
    /// their data silently goes to Pubky's instance instead of theirs.
    public static let defaultEndpoint = "https://ingest.pubkypulse.com"

    public init(
        endpoint: String = Self.defaultEndpoint,
        apiKey: String,
        flushOnBackground: Bool = true,
        compressionEnabled: Bool = true,
        networkTrackingEnabled: Bool = true,
        consoleLogging: Bool = true,
        attributionEnabled: Bool = true
    ) throws {
        try self.init(
            endpoint: endpoint,
            apiKey: apiKey,
            bundleId: Self.resolveBundleId(),
            flushOnBackground: flushOnBackground,
            compressionEnabled: compressionEnabled,
            networkTrackingEnabled: networkTrackingEnabled,
            consoleLogging: consoleLogging,
            attributionEnabled: attributionEnabled
        )
    }

    /// On watchOS, prefer the iOS counterpart's bundle ID (via
    /// `WKCompanionAppBundleIdentifier` in Info.plist) to preserve the existing
    /// companion identifier. Falls back to the watch's own bundle ID for
    /// standalone watch apps. The client key determines which app receives
    /// requests; the server checks supplied identifiers for native app keys.
    private static func resolveBundleId() -> String? {
        #if os(watchOS)
        if let companion = Bundle.main.object(forInfoDictionaryKey: "WKCompanionAppBundleIdentifier") as? String,
           !companion.isEmpty {
            return companion
        }
        #endif
        return Bundle.main.bundleIdentifier
    }

    /// Internal initializer for testing with an explicit bundle ID.
    init(
        endpoint: String = Self.defaultEndpoint,
        apiKey: String,
        bundleId: String?,
        flushOnBackground: Bool = true,
        compressionEnabled: Bool = true,
        networkTrackingEnabled: Bool = true,
        consoleLogging: Bool = true,
        attributionEnabled: Bool = true
    ) throws {
        // Only an absent `endpoint` falls back to `defaultEndpoint`. An
        // explicitly supplied empty or malformed value still throws:
        // an explicitly empty one is almost always an environment variable that
        // failed to load, and silently redirecting that traffic to Pubky's
        // hosted instance would send a self-hoster's data to the wrong company.
        // `URL(string: "")` is nil, so the existing guard already rejects it.
        guard let url = URL(string: endpoint) else {
            throw PulseConfigurationError.invalidEndpoint(endpoint)
        }
        guard apiKey.hasPrefix(Self.clientKeyPrefix) else {
            throw PulseConfigurationError.invalidApiKey("API key must start with \"\(Self.clientKeyPrefix)\"")
        }
        self.endpoint = url
        self.apiKey = apiKey
        self.bundleId = bundleId.flatMap { $0.isEmpty ? nil : $0 }
        self.flushOnBackground = flushOnBackground
        self.compressionEnabled = compressionEnabled
        self.networkTrackingEnabled = networkTrackingEnabled
        self.consoleLogging = consoleLogging
        self.attributionEnabled = attributionEnabled
    }
}

public enum PulseConfigurationError: LocalizedError {
    case invalidEndpoint(String)
    case invalidApiKey(String)
    /// Retained for source compatibility; missing bundle metadata no longer throws.
    case missingBundleId

    public var errorDescription: String? {
        switch self {
        case .invalidEndpoint(let value):
            return "Invalid endpoint URL: \(value)"
        case .invalidApiKey(let message):
            return message
        case .missingBundleId:
            return "Bundle ID could not be determined. Ensure the app has a valid bundle identifier."
        }
    }
}
