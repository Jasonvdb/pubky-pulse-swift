import XCTest
@testable import PubkyPulse

final class PulseQuestionnaireFlowTests: XCTestCase {

    // MARK: - Phase equality

    func testPhaseEquality() {
        let receipt = PulseQuestionnaireReceipt(id: "r1", createdAt: Date(timeIntervalSince1970: 0), wasSubmitted: true)
        XCTAssertEqual(PulseQuestionnairePhase.consent, .consent)
        XCTAssertEqual(PulseQuestionnairePhase.running(index: 2), .running(index: 2))
        XCTAssertNotEqual(PulseQuestionnairePhase.running(index: 0), .running(index: 1))
        XCTAssertEqual(PulseQuestionnairePhase.success(receipt), .success(receipt))
        XCTAssertNotEqual(PulseQuestionnairePhase.consent, .running(index: 0))
    }

    // MARK: - Answer store

    private func schemaWithEveryType() -> PulseQuestionnaireSchema {
        PulseQuestionnaireSchema(version: 1, questions: [
            .text(PulseQuestionnaireTextQuestion(
                id: "t1", title: "What's on your mind?", subtitle: nil,
                required: true, placeholder: nil, multiline: true
            )),
            .singleChoice(PulseQuestionnaireSingleChoiceQuestion(
                id: "s1", title: "Pick one", subtitle: nil, required: true,
                options: [
                    PulseQuestionnaireChoiceOption(id: "a", label: "A"),
                    PulseQuestionnaireChoiceOption(id: "b", label: "B"),
                ]
            )),
            .multiChoice(PulseQuestionnaireMultiChoiceQuestion(
                id: "m1", title: "Pick any", subtitle: nil, required: false,
                options: [
                    PulseQuestionnaireChoiceOption(id: "x", label: "X"),
                    PulseQuestionnaireChoiceOption(id: "y", label: "Y"),
                ]
            )),
            .rating(PulseQuestionnaireRatingQuestion(
                id: "r1", title: "Rate it", subtitle: nil, required: true, scale: 5
            )),
            .nps(PulseQuestionnaireNpsQuestion(
                id: "n1", title: "How likely", subtitle: nil, required: false
            )),
        ])
    }

    func testEmptyStoreNothingAnswered() {
        let store = PulseQuestionnaireAnswerStore()
        for q in schemaWithEveryType().questions {
            XCTAssertFalse(store.isAnswered(q), "empty store should not satisfy \(q.id)")
        }
    }

    func testTextWhitespaceOnlyIsNotAnswered() {
        var store = PulseQuestionnaireAnswerStore()
        store.text["t1"] = "   \n\t  "
        let q = schemaWithEveryType().questions.first { $0.id == "t1" }!
        XCTAssertFalse(store.isAnswered(q))
        XCTAssertTrue(store.collected(schemaWithEveryType())["t1"] == nil,
                      "whitespace-only text should not be collected")
    }

    func testTextTrimmedAndCollected() {
        var store = PulseQuestionnaireAnswerStore()
        store.text["t1"] = "  hello  "
        let collected = store.collected(schemaWithEveryType())
        XCTAssertEqual(collected["t1"], .text("hello"))
    }

    func testSingleChoiceAnsweredCollected() {
        var store = PulseQuestionnaireAnswerStore()
        store.single["s1"] = "b"
        let q = schemaWithEveryType().questions.first { $0.id == "s1" }!
        XCTAssertTrue(store.isAnswered(q))
        XCTAssertEqual(store.collected(schemaWithEveryType())["s1"], .choice("b"))
    }

    func testMultiChoiceEmptySetNotAnswered() {
        var store = PulseQuestionnaireAnswerStore()
        store.multi["m1"] = []
        let q = schemaWithEveryType().questions.first { $0.id == "m1" }!
        XCTAssertFalse(store.isAnswered(q))
        XCTAssertNil(store.collected(schemaWithEveryType())["m1"])
    }

    func testMultiChoiceCollectionSorted() {
        var store = PulseQuestionnaireAnswerStore()
        store.multi["m1"] = ["y", "x"]
        let collected = store.collected(schemaWithEveryType())
        // Sorted for deterministic wire output across encoder runs.
        XCTAssertEqual(collected["m1"], .choices(["x", "y"]))
    }

    func testRatingAndNpsCollected() {
        var store = PulseQuestionnaireAnswerStore()
        store.rating["r1"] = 4
        store.nps["n1"] = 9
        let collected = store.collected(schemaWithEveryType())
        XCTAssertEqual(collected["r1"], .rating(4))
        XCTAssertEqual(collected["n1"], .nps(9))
    }

    func testHasAllRequiredFalseUntilAllRequiredAnswered() {
        var store = PulseQuestionnaireAnswerStore()
        let schema = schemaWithEveryType()
        XCTAssertFalse(store.hasAllRequired(schema))
        store.text["t1"] = "ok"
        XCTAssertFalse(store.hasAllRequired(schema))
        store.single["s1"] = "a"
        XCTAssertFalse(store.hasAllRequired(schema))
        store.rating["r1"] = 5
        XCTAssertTrue(store.hasAllRequired(schema), "all required types (text, single, rating) now answered")
    }

    func testOptionalQuestionsDoNotBlockHasAllRequired() {
        var store = PulseQuestionnaireAnswerStore()
        let schema = schemaWithEveryType()
        store.text["t1"] = "hi"
        store.single["s1"] = "a"
        store.rating["r1"] = 3
        // multi/nps both optional, untouched — should not block
        XCTAssertTrue(store.hasAllRequired(schema))
    }

    // MARK: - Resume / prefill

    func testPrefillHydratesEveryAnswerType() {
        var store = PulseQuestionnaireAnswerStore()
        store.prefill(from: [
            "t1": .text("hello"),
            "s1": .choice("a"),
            "m1": .choices(["x", "y"]),
            "r1": .rating(3),
            "n1": .nps(8),
        ])
        XCTAssertEqual(store.text["t1"], "hello")
        XCTAssertEqual(store.single["s1"], "a")
        XCTAssertEqual(store.multi["m1"], ["x", "y"])
        XCTAssertEqual(store.rating["r1"], 3)
        XCTAssertEqual(store.nps["n1"], 8)
    }

    func testFirstUnansweredLandsOnFirstMissingRequiredOrOptional() {
        let schema = schemaWithEveryType()
        var store = PulseQuestionnaireAnswerStore()
        // Nothing answered → land on index 0 (t1)
        XCTAssertEqual(store.firstUnansweredIndex(in: schema), 0)
        // Answer t1 → land on s1 (index 1)
        store.text["t1"] = "ok"
        XCTAssertEqual(store.firstUnansweredIndex(in: schema), 1)
        // Answer s1 → land on m1 (index 2). m1 is optional but empty, so
        // it still counts as unanswered for landing-position purposes.
        store.single["s1"] = "a"
        XCTAssertEqual(store.firstUnansweredIndex(in: schema), 2)
    }

    func testFirstUnansweredLandsOnLastWhenAllAnswered() {
        let schema = schemaWithEveryType()
        var store = PulseQuestionnaireAnswerStore()
        store.prefill(from: [
            "t1": .text("hi"),
            "s1": .choice("a"),
            "m1": .choices(["x"]),
            "r1": .rating(4),
            "n1": .nps(9),
        ])
        // All five questions answered, no Submit yet → land on last index
        // so the Submit button is live on the resumed page.
        XCTAssertEqual(store.firstUnansweredIndex(in: schema), schema.questions.count - 1)
    }

    // MARK: - Public API surface (compile-time check)

    func testPublicViewCompilesWithAndWithoutConsent() {
        // Pure surface verification — if this compiles, the public init
        // signatures both still exist with the right defaults.
        let q = PulseQuestionnaire(
            id: "id", slug: "demo", name: "n", description: nil,
            schema: schemaWithEveryType()
        )
        #if canImport(SwiftUI) && !os(watchOS)
        _ = PulseQuestionnaireView(questionnaire: q)
        _ = PulseQuestionnaireView(questionnaire: q, showsConsent: true)
        #endif
        XCTAssertEqual(q.slug, "demo")
    }
}
