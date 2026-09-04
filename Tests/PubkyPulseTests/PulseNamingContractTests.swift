import Foundation
import XCTest
@testable import PubkyPulse

/// Pins the identifiers that leave the SDK: strings a server, a wire payload,
/// or a string catalog matches on by value. Renaming one of these compiles
/// cleanly and only fails in production — as unattributed events, rejected API
/// keys, or untranslated UI — so each is asserted literally here.
///
/// The wire-facing values are the same ones the server's test fixtures use
/// (`apps/server/src/__tests__/setup.ts`) and the SDK docs publish.
final class PulseNamingContractTests: XCTestCase {
    func testSdkNameIsReportedAsPubkyPulseSwift() {
        XCTAssertEqual(PubkyPulseVersion.name, "pubky-pulse-swift")
    }

    func testSdkVersionIsSemantic() {
        XCTAssertNotNil(
            PubkyPulseVersion.current.range(of: #"^\d+\.\d+\.\d+$"#, options: .regularExpression),
            "sdk_version ships on every event and the release workflow rewrites it — keep it semver"
        )
    }

    func testAnonymousIdsUsePulsePrefix() {
        // Server-side claim matches anonymous ids by this prefix.
        XCTAssertEqual(IdentityManager.anonymousIdPrefix, "pulse_anon_")
    }

    func testLogSubsystemIsReverseDnsPulse() {
        // Host apps filter Console output and OSLog archives on this literal.
        XCTAssertEqual(Pulse.logSubsystem, "org.pubky.pulse.sdk")
    }

    /// UserDefaults keys live in the *host app's* domain, not a suite of our
    /// own, so they carry the brand-qualified `pubky-pulse.` prefix rather than
    /// the bare `pulse.` used for string-catalog keys. Renaming one silently
    /// resets install-scoped state on every existing install.
    func testHostAppDefaultsKeysAreBrandQualified() {
        XCTAssertEqual(PulseQuestionnaireState.launchCountKey, "pubky-pulse.questionnaire.launch_count")
        XCTAssertEqual(PulseQuestionnaireState.foregroundCountKey, "pubky-pulse.questionnaire.foreground_count")
        XCTAssertEqual(PulseQuestionnaireState.firstLaunchAtKey, "pubky-pulse.questionnaire.first_launch_at")
        XCTAssertEqual(
            PulseAttributionNetwork.appleSearchAds.userDefaultsNamespace,
            "pubky-pulse.attribution.apple-search-ads"
        )
    }

    func testFeedbackStringsUsePulseCatalogKeys() {
        assertCatalogKeys(of: PulseFeedbackStrings.default, allHavePrefix: "pulse.feedback.")
    }

    func testQuestionnaireStringsUsePulseCatalogKeys() {
        assertCatalogKeys(of: PulseQuestionnaireStrings.default, allHavePrefix: "pulse.questionnaire.")
    }

    // MARK: - Helpers

    /// Reflects over a strings struct so new fields are covered automatically:
    /// every stored property must be a `LocalizedStringResource` keyed into the
    /// SDK's bundled catalog under `prefix`.
    private func assertCatalogKeys(
        of strings: Any,
        allHavePrefix prefix: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let fields = Mirror(reflecting: strings).children
        let keys = fields.compactMap { ($0.value as? LocalizedStringResource)?.key }

        XCTAssertFalse(keys.isEmpty, "reflection found no localized strings", file: file, line: line)
        XCTAssertEqual(
            keys.count,
            fields.count,
            "every field must be a LocalizedStringResource so it can be localized and overridden",
            file: file,
            line: line
        )
        for key in keys {
            XCTAssertTrue(key.hasPrefix(prefix), "catalog key \"\(key)\" is outside \"\(prefix)\"", file: file, line: line)
        }
    }
}
