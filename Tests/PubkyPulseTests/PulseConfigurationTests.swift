import XCTest
@testable import PubkyPulse

/// Covers the `endpoint` default: omitting it falls back to Pubky's hosted
/// ingest host, while an explicitly supplied value — including an empty one —
/// is still taken at face value.
final class PulseConfigurationTests: XCTestCase {
    func testClientKeyOnlyConfigurationSucceeds() throws {
        _ = try PulseConfiguration(apiKey: "pulse_client_test123")
    }

    func testBundleMetadataIsBestEffort() throws {
        for bundleId in [nil, "", "com.example.app"] as [String?] {
            let config = try PulseConfiguration(apiKey: "pulse_client_test123", bundleId: bundleId)
            XCTAssertEqual(config.bundleId, bundleId == "" ? nil : bundleId)
        }
    }

    func testMissingBundleMetadataDoesNotBypassValidation() {
        XCTAssertThrowsError(try PulseConfiguration(apiKey: "invalid", bundleId: nil)) { error in
            guard case PulseConfigurationError.invalidApiKey = error else {
                return XCTFail("Expected invalidApiKey, got \(error)")
            }
        }
        XCTAssertThrowsError(try PulseConfiguration(endpoint: "", apiKey: "pulse_client_test123", bundleId: nil)) { error in
            guard case PulseConfigurationError.invalidEndpoint = error else {
                return XCTFail("Expected invalidEndpoint, got \(error)")
            }
        }
    }

    func testOmittedEndpointFallsBackToHostedIngest() throws {
        let config = try PulseConfiguration(apiKey: "pulse_client_test123", bundleId: "com.example.app")
        XCTAssertEqual(config.endpoint.scheme, "https")
        XCTAssertEqual(config.endpoint.host, "ingest.pubkypulse.com")
        XCTAssertEqual(PulseConfiguration.defaultEndpoint, "https://ingest.pubkypulse.com")
    }

    /// An explicitly empty endpoint is almost always an environment variable
    /// that failed to load. It must keep throwing rather than silently
    /// redirecting a self-hoster's data to Pubky's hosted instance.
    func testExplicitlyEmptyEndpointStillThrows() {
        XCTAssertThrowsError(
            try PulseConfiguration(endpoint: "", apiKey: "pulse_client_test123", bundleId: "com.example.app")
        ) { error in
            guard case PulseConfigurationError.invalidEndpoint(let value) = error else {
                return XCTFail("Expected invalidEndpoint, got \(error)")
            }
            XCTAssertEqual(value, "")
        }
    }

    func testExplicitEndpointWinsOverDefault() throws {
        let config = try PulseConfiguration(
            endpoint: "https://ingest.example.com",
            apiKey: "pulse_client_test123",
            bundleId: "com.example.app"
        )
        XCTAssertEqual(config.endpoint.absoluteString, "https://ingest.example.com")
    }
}
