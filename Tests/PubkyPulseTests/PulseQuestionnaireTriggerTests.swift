import XCTest
@testable import PubkyPulse

final class PulseQuestionnaireTriggerTests: XCTestCase {
    private func snapshot(
        launches: Int = 0,
        foregrounds: Int = 0,
        firstLaunch: Date? = nil,
        now: Date = Date()
    ) -> PulseQuestionnaireState.Snapshot {
        PulseQuestionnaireState.Snapshot(
            launchCount: launches,
            foregroundCount: foregrounds,
            firstLaunchAt: firstLaunch,
            now: now
        )
    }

    func testLaunchesAtLeast() {
        XCTAssertFalse(PulseQuestionnaireCondition.launches(atLeast: 3).isSatisfied(state: snapshot(launches: 2)))
        XCTAssertTrue(PulseQuestionnaireCondition.launches(atLeast: 3).isSatisfied(state: snapshot(launches: 3)))
        XCTAssertTrue(PulseQuestionnaireCondition.launches(atLeast: 3).isSatisfied(state: snapshot(launches: 10)))
    }

    func testForegroundsAtLeast() {
        XCTAssertFalse(PulseQuestionnaireCondition.foregrounds(atLeast: 5).isSatisfied(state: snapshot(foregrounds: 4)))
        XCTAssertTrue(PulseQuestionnaireCondition.foregrounds(atLeast: 5).isSatisfied(state: snapshot(foregrounds: 5)))
    }

    func testDaysSinceFirstLaunch() {
        let now = Date()
        let oneDayAgo = now.addingTimeInterval(-86_400)
        let eightDaysAgo = now.addingTimeInterval(-8 * 86_400)
        XCTAssertFalse(PulseQuestionnaireCondition.daysSinceFirstLaunch(atLeast: 7)
            .isSatisfied(state: snapshot(firstLaunch: oneDayAgo, now: now)))
        XCTAssertTrue(PulseQuestionnaireCondition.daysSinceFirstLaunch(atLeast: 7)
            .isSatisfied(state: snapshot(firstLaunch: eightDaysAgo, now: now)))
        // No firstLaunch yet => 0 days elapsed
        XCTAssertFalse(PulseQuestionnaireCondition.daysSinceFirstLaunch(atLeast: 1)
            .isSatisfied(state: snapshot(firstLaunch: nil, now: now)))
    }

    func testHoursSinceFirstLaunch() {
        let now = Date()
        let twoHoursAgo = now.addingTimeInterval(-2 * 3_600)
        XCTAssertTrue(PulseQuestionnaireCondition.hoursSinceFirstLaunch(atLeast: 1)
            .isSatisfied(state: snapshot(firstLaunch: twoHoursAgo, now: now)))
        XCTAssertFalse(PulseQuestionnaireCondition.hoursSinceFirstLaunch(atLeast: 3)
            .isSatisfied(state: snapshot(firstLaunch: twoHoursAgo, now: now)))
    }

    func testWhenAllConditionsTrue() {
        let now = Date()
        let trigger: PulseQuestionnaireTrigger = .when(.launches(atLeast: 3), .daysSinceFirstLaunch(atLeast: 7))
        XCTAssertTrue(trigger.isSatisfied(state: snapshot(launches: 5, firstLaunch: now.addingTimeInterval(-8 * 86_400), now: now)))
        // Only one true → trigger fails (AND-only)
        XCTAssertFalse(trigger.isSatisfied(state: snapshot(launches: 5, firstLaunch: now.addingTimeInterval(-1 * 86_400), now: now)))
        XCTAssertFalse(trigger.isSatisfied(state: snapshot(launches: 1, firstLaunch: now.addingTimeInterval(-8 * 86_400), now: now)))
    }

    func testEmptyConditionsListMatches() {
        let trigger = PulseQuestionnaireTrigger.when()
        XCTAssertTrue(trigger.isSatisfied(state: snapshot()))
    }

    func testManualNeverSatisfies() {
        XCTAssertFalse(PulseQuestionnaireTrigger.manual.isSatisfied(state: snapshot(launches: 100, foregrounds: 100)))
    }

    func testAfterLaunchShortcut() {
        XCTAssertTrue(PulseQuestionnaireTrigger.afterLaunch.isSatisfied(state: snapshot(launches: 1)))
        XCTAssertFalse(PulseQuestionnaireTrigger.afterLaunch.isSatisfied(state: snapshot(launches: 0)))
    }

    // MARK: - State persistence

    func testLaunchCounterIncrementsOnce() {
        let defaults = UserDefaults(suiteName: "pulse.test.questionnaire.\(UUID().uuidString)")!
        defer { defaults.removePersistentDomain(forName: defaults.dictionaryRepresentation().keys.first ?? "") }
        let state = PulseQuestionnaireState(defaults: defaults)
        state.markConfiguredOnce()
        state.markConfiguredOnce()  // idempotent within process
        state.markConfiguredOnce()
        XCTAssertEqual(state.launchCount, 1)
        XCTAssertNotNil(state.firstLaunchAt)
    }

    func testForegroundIncrementsRepeatedly() {
        let defaults = UserDefaults(suiteName: "pulse.test.questionnaire.\(UUID().uuidString)")!
        let state = PulseQuestionnaireState(defaults: defaults)
        state.incrementForeground()
        state.incrementForeground()
        state.incrementForeground()
        XCTAssertEqual(state.foregroundCount, 3)
    }

    func testFirstLaunchPreservedAcrossInstances() {
        let suite = "pulse.test.questionnaire.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let early = Date(timeIntervalSinceReferenceDate: 100_000)
        let later = Date(timeIntervalSinceReferenceDate: 200_000)

        let first = PulseQuestionnaireState(defaults: defaults)
        first.markConfiguredOnce(now: early)
        XCTAssertEqual(first.firstLaunchAt?.timeIntervalSinceReferenceDate, 100_000)

        // Second process / second instance shouldn't overwrite firstLaunchAt.
        let second = PulseQuestionnaireState(defaults: defaults)
        second.markConfiguredOnce(now: later)
        XCTAssertEqual(second.firstLaunchAt?.timeIntervalSinceReferenceDate, 100_000)
        XCTAssertEqual(second.launchCount, 2)
    }
}
