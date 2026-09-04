import XCTest
@testable import PubkyPulse

final class PulseIntegrationTests: XCTestCase {
    func testEventsDroppedBeforeConfigure() {
        // Should not crash
        Pulse.info("this should be silently dropped")
        Pulse.error("this too")
        Pulse.recordMetric("also.this")
    }

    func testConfigurationRejectsAgentKey() {
        XCTAssertThrowsError(try PulseConfiguration(endpoint: "https://api.test.com", apiKey: "owl_agent_abc")) { error in
            XCTAssertTrue(error.localizedDescription.contains("owl_client_"))
        }
    }

    func testConfigurationRejectsInvalidEndpoint() {
        XCTAssertThrowsError(try PulseConfiguration(endpoint: "", apiKey: "owl_client_abc"))
    }

    func testConfigurationAcceptsValidInput() {
        XCTAssertNoThrow(try PulseConfiguration(endpoint: "https://api.example.com", apiKey: "owl_client_test123"))
    }

    /// The not-configured messages are public API copy: they name the product and
    /// the entry point developers must call, so a rename must carry through them.
    func testNotConfiguredErrorsNamePulseEntryPoint() {
        XCTAssertEqual(
            PulseFeedbackError.notConfigured.errorDescription,
            "Pubky Pulse is not configured. Call Pulse.configure(...) before sending feedback."
        )
        XCTAssertEqual(
            PulseQuestionnaireError.notConfigured.errorDescription,
            "Pubky Pulse is not configured. Call Pulse.configure(...) first."
        )
    }
}
