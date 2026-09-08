import Foundation

/// A complete questionnaire spec fetched from `GET /v1/questionnaires/:slug`.
/// Public so consumers can render it manually via `PulseQuestionnaireView`.
public struct PulseQuestionnaire: Sendable, Equatable, Identifiable {
    public let id: String
    public let slug: String
    public let name: String
    public let description: String?
    public let schema: PulseQuestionnaireSchema

    public init(
        id: String,
        slug: String,
        name: String,
        description: String?,
        schema: PulseQuestionnaireSchema
    ) {
        self.id = id
        self.slug = slug
        self.name = name
        self.description = description
        self.schema = schema
    }
}

public struct PulseQuestionnaireSchema: Sendable, Equatable {
    public let version: Int
    public let questions: [PulseQuestionnaireQuestion]

    public init(version: Int, questions: [PulseQuestionnaireQuestion]) {
        self.version = version
        self.questions = questions
    }
}

public struct PulseQuestionnaireChoiceOption: Sendable, Equatable, Identifiable {
    public let id: String
    public let label: String
}

public enum PulseQuestionnaireQuestion: Sendable, Equatable, Identifiable {
    case text(PulseQuestionnaireTextQuestion)
    case singleChoice(PulseQuestionnaireSingleChoiceQuestion)
    case multiChoice(PulseQuestionnaireMultiChoiceQuestion)
    case rating(PulseQuestionnaireRatingQuestion)
    case nps(PulseQuestionnaireNpsQuestion)

    public var id: String {
        switch self {
        case .text(let q): return q.id
        case .singleChoice(let q): return q.id
        case .multiChoice(let q): return q.id
        case .rating(let q): return q.id
        case .nps(let q): return q.id
        }
    }

    public var title: String {
        switch self {
        case .text(let q): return q.title
        case .singleChoice(let q): return q.title
        case .multiChoice(let q): return q.title
        case .rating(let q): return q.title
        case .nps(let q): return q.title
        }
    }

    public var subtitle: String? {
        switch self {
        case .text(let q): return q.subtitle
        case .singleChoice(let q): return q.subtitle
        case .multiChoice(let q): return q.subtitle
        case .rating(let q): return q.subtitle
        case .nps(let q): return q.subtitle
        }
    }

    public var required: Bool {
        switch self {
        case .text(let q): return q.required
        case .singleChoice(let q): return q.required
        case .multiChoice(let q): return q.required
        case .rating(let q): return q.required
        case .nps(let q): return q.required
        }
    }
}

public struct PulseQuestionnaireTextQuestion: Sendable, Equatable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let required: Bool
    public let placeholder: String?
    public let multiline: Bool
}

public struct PulseQuestionnaireSingleChoiceQuestion: Sendable, Equatable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let required: Bool
    public let options: [PulseQuestionnaireChoiceOption]
}

public struct PulseQuestionnaireMultiChoiceQuestion: Sendable, Equatable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let required: Bool
    public let options: [PulseQuestionnaireChoiceOption]
}

public struct PulseQuestionnaireRatingQuestion: Sendable, Equatable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let required: Bool
    public let scale: Int  // V1: always 5
}

public struct PulseQuestionnaireNpsQuestion: Sendable, Equatable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let required: Bool
}

/// Heterogeneous answer value. Wire encodes as the underlying type directly,
/// not as a tagged union — the server validates against the schema.
public enum PulseQuestionnaireAnswerValue: Sendable, Equatable {
    case text(String)
    case choice(String)         // option id
    case choices([String])      // option ids
    case rating(Int)            // 1...scale
    case nps(Int)               // 0...10
}

/// Receipt returned by `POST /v1/questionnaires/:slug/responses`.
/// `wasSubmitted` is `true` only on the call that flipped the server-side
/// `submitted_at` from null to non-null — used by the flow container to know
/// whether to transition to the success phase. Subsequent draft-saves return
/// `wasSubmitted = false`.
public struct PulseQuestionnaireReceipt: Sendable, Equatable {
    public let id: String
    public let createdAt: Date
    public let wasSubmitted: Bool

    public init(id: String, createdAt: Date, wasSubmitted: Bool) {
        self.id = id
        self.createdAt = createdAt
        self.wasSubmitted = wasSubmitted
    }
}

/// An in-progress draft surfaced by `GET /v1/questionnaires/:slug` when the
/// caller already has an unsubmitted response. The flow container reads this
/// to pre-fill its answer store and skip to the first unanswered question.
public struct PulseQuestionnaireDraft: Sendable, Equatable {
    public let responseId: String
    public let answers: [String: PulseQuestionnaireAnswerValue]

    public init(responseId: String, answers: [String: PulseQuestionnaireAnswerValue]) {
        self.responseId = responseId
        self.answers = answers
    }
}

/// Result of `Pulse.fetchQuestionnaire(slug:)`. When `questionnaire` is non-nil
/// the questionnaire exists and is eligible to present; the `inProgress` field
/// carries the existing draft (if any) so the flow container can resume.
/// When `questionnaire` is nil, the questionnaire isn't eligible — typically
/// `already_responded`, `globally_dismissed`, or `inactive`.
public struct PulseQuestionnaireFetchResult: Sendable, Equatable {
    public let questionnaire: PulseQuestionnaire?
    public let inProgress: PulseQuestionnaireDraft?
    public let ineligibleReason: PulseQuestionnaireIneligibleReason?

    public init(
        questionnaire: PulseQuestionnaire?,
        inProgress: PulseQuestionnaireDraft? = nil,
        ineligibleReason: PulseQuestionnaireIneligibleReason? = nil
    ) {
        self.questionnaire = questionnaire
        self.inProgress = inProgress
        self.ineligibleReason = ineligibleReason
    }
}

/// Reason a questionnaire is not eligible to present right now. Mirrors the
/// server's eligibility envelope.
public enum PulseQuestionnaireIneligibleReason: String, Sendable {
    case alreadyResponded = "already_responded"
    case globallyDismissed = "globally_dismissed"
    case inactive = "inactive"
}

/// Errors surfaced by `Pulse.fetchQuestionnaire` / `Pulse.submitQuestionnaireResponse` /
/// `Pulse.dismissQuestionnaires`. Non-eligible fetches return `nil` instead of throwing.
public enum PulseQuestionnaireError: Error, LocalizedError, Equatable, Sendable {
    case notConfigured
    case slugNotFound
    case invalidAnswers(String)
    case serverError(statusCode: Int, body: String?)
    case transportFailure(String)

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Pubky Pulse is not configured. Call Pulse.configure(...) first."
        case .slugNotFound:
            return "Questionnaire slug not found."
        case .invalidAnswers(let msg):
            return "Invalid answers: \(msg)"
        case .serverError(let code, let body):
            if let body, !body.isEmpty { return "Server returned \(code): \(body)" }
            return "Server returned \(code)"
        case .transportFailure(let msg):
            return msg
        }
    }
}

// MARK: - Codable wire format

extension PulseQuestionnaire: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, slug, name, description, schema
    }
}

extension PulseQuestionnaireSchema: Codable {
    private enum CodingKeys: String, CodingKey {
        case version, questions
    }
}

extension PulseQuestionnaireChoiceOption: Codable {}

extension PulseQuestionnaireQuestion: Codable {
    private enum CodingKeys: String, CodingKey { case type }
    private enum QuestionType: String, Codable {
        case text, single_choice, multi_choice, rating, nps
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(QuestionType.self, forKey: .type)
        switch type {
        case .text:          self = .text(try PulseQuestionnaireTextQuestion(from: decoder))
        case .single_choice: self = .singleChoice(try PulseQuestionnaireSingleChoiceQuestion(from: decoder))
        case .multi_choice:  self = .multiChoice(try PulseQuestionnaireMultiChoiceQuestion(from: decoder))
        case .rating:        self = .rating(try PulseQuestionnaireRatingQuestion(from: decoder))
        case .nps:           self = .nps(try PulseQuestionnaireNpsQuestion(from: decoder))
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .text(let q):         try q.encodeWithType(to: encoder, type: "text")
        case .singleChoice(let q): try q.encodeWithType(to: encoder, type: "single_choice")
        case .multiChoice(let q):  try q.encodeWithType(to: encoder, type: "multi_choice")
        case .rating(let q):       try q.encodeWithType(to: encoder, type: "rating")
        case .nps(let q):          try q.encodeWithType(to: encoder, type: "nps")
        }
    }
}

private protocol _TypedQuestion: Codable {
    func encodeWithType(to encoder: Encoder, type: String) throws
}

extension PulseQuestionnaireTextQuestion: _TypedQuestion {
    enum CodingKeys: String, CodingKey {
        case id, title, subtitle, required, placeholder, multiline, type
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        subtitle = try c.decodeIfPresent(String.self, forKey: .subtitle)
        required = try c.decode(Bool.self, forKey: .required)
        placeholder = try c.decodeIfPresent(String.self, forKey: .placeholder)
        multiline = (try c.decodeIfPresent(Bool.self, forKey: .multiline)) ?? false
    }
    public func encode(to encoder: Encoder) throws { try encodeWithType(to: encoder, type: "text") }
    func encodeWithType(to encoder: Encoder, type: String) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(type, forKey: .type)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(subtitle, forKey: .subtitle)
        try c.encode(required, forKey: .required)
        try c.encodeIfPresent(placeholder, forKey: .placeholder)
        try c.encode(multiline, forKey: .multiline)
    }
}

extension PulseQuestionnaireSingleChoiceQuestion: _TypedQuestion {
    enum CodingKeys: String, CodingKey { case id, title, subtitle, required, options, type }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        subtitle = try c.decodeIfPresent(String.self, forKey: .subtitle)
        required = try c.decode(Bool.self, forKey: .required)
        options = try c.decode([PulseQuestionnaireChoiceOption].self, forKey: .options)
    }
    public func encode(to encoder: Encoder) throws { try encodeWithType(to: encoder, type: "single_choice") }
    func encodeWithType(to encoder: Encoder, type: String) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(type, forKey: .type)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(subtitle, forKey: .subtitle)
        try c.encode(required, forKey: .required)
        try c.encode(options, forKey: .options)
    }
}

extension PulseQuestionnaireMultiChoiceQuestion: _TypedQuestion {
    enum CodingKeys: String, CodingKey { case id, title, subtitle, required, options, type }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        subtitle = try c.decodeIfPresent(String.self, forKey: .subtitle)
        required = try c.decode(Bool.self, forKey: .required)
        options = try c.decode([PulseQuestionnaireChoiceOption].self, forKey: .options)
    }
    public func encode(to encoder: Encoder) throws { try encodeWithType(to: encoder, type: "multi_choice") }
    func encodeWithType(to encoder: Encoder, type: String) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(type, forKey: .type)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(subtitle, forKey: .subtitle)
        try c.encode(required, forKey: .required)
        try c.encode(options, forKey: .options)
    }
}

extension PulseQuestionnaireRatingQuestion: _TypedQuestion {
    enum CodingKeys: String, CodingKey { case id, title, subtitle, required, scale, type }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        subtitle = try c.decodeIfPresent(String.self, forKey: .subtitle)
        required = try c.decode(Bool.self, forKey: .required)
        scale = try c.decode(Int.self, forKey: .scale)
    }
    public func encode(to encoder: Encoder) throws { try encodeWithType(to: encoder, type: "rating") }
    func encodeWithType(to encoder: Encoder, type: String) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(type, forKey: .type)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(subtitle, forKey: .subtitle)
        try c.encode(required, forKey: .required)
        try c.encode(scale, forKey: .scale)
    }
}

extension PulseQuestionnaireNpsQuestion: _TypedQuestion {
    enum CodingKeys: String, CodingKey { case id, title, subtitle, required, type }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        subtitle = try c.decodeIfPresent(String.self, forKey: .subtitle)
        required = try c.decode(Bool.self, forKey: .required)
    }
    public func encode(to encoder: Encoder) throws { try encodeWithType(to: encoder, type: "nps") }
    func encodeWithType(to encoder: Encoder, type: String) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(type, forKey: .type)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(subtitle, forKey: .subtitle)
        try c.encode(required, forKey: .required)
    }
}

// MARK: - Answer payload encoder

/// Internal — encodes `[String: PulseQuestionnaireAnswerValue]` into the wire
/// shape (`Record<questionId, string | string[] | int>`).
struct PulseQuestionnaireAnswersWire: Encodable {
    let answers: [String: PulseQuestionnaireAnswerValue]

    private struct DynamicKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: DynamicKey.self)
        for (key, value) in answers {
            let k = DynamicKey(stringValue: key)!
            switch value {
            case .text(let s):        try c.encode(s, forKey: k)
            case .choice(let s):      try c.encode(s, forKey: k)
            case .choices(let arr):   try c.encode(arr, forKey: k)
            case .rating(let n):      try c.encode(n, forKey: k)
            case .nps(let n):         try c.encode(n, forKey: k)
            }
        }
    }
}

// Wire-format helpers used by EventTransport.

struct QuestionnaireFetchEnvelope: Decodable {
    let eligible: Bool
    let reason: String?
    let questionnaire: PulseQuestionnaire?
    let in_progress: QuestionnaireInProgressBody?
}

/// Wire-level representation of an in-progress draft as returned by the
/// server's eligibility envelope. Answers are decoded as opaque JSON values
/// here and projected back into `PulseQuestionnaireAnswerValue` keyed by the
/// question's type during flow-container hydration.
struct QuestionnaireInProgressBody: Decodable {
    let response_id: String
    let answers: [String: AnyAnswerJSON]
}

/// Minimal heterogeneous-JSON decoder for draft answers — supports the three
/// shapes the server emits: string, array-of-string, integer. We can't
/// decode straight into `PulseQuestionnaireAnswerValue` here because the value
/// type depends on the question type in the parent schema, which we hydrate
/// against in the flow container.
enum AnyAnswerJSON: Sendable {
    case string(String)
    case strings([String])
    case integer(Int)
}

extension AnyAnswerJSON: Decodable {
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) {
            self = .string(s)
            return
        }
        if let arr = try? c.decode([String].self) {
            self = .strings(arr)
            return
        }
        if let n = try? c.decode(Int.self) {
            self = .integer(n)
            return
        }
        throw DecodingError.dataCorruptedError(
            in: c,
            debugDescription: "Unsupported answer value shape"
        )
    }
}

struct QuestionnaireSubmitRequestBody: Encodable {
    let bundle_id: String?
    let session_id: String?
    let user_id: String?
    let answers: PulseQuestionnaireAnswersWire
    /// false = save a draft, true = final submit (flips server-side
    /// submitted_at and fires the team notification exactly once).
    let is_complete: Bool
    let app_version: String?
    let sdk_name: String?
    let sdk_version: String?
    let environment: String?
    let device_model: String?
    let os_version: String?
    let is_dev: Bool
}

struct QuestionnaireSubmitResponseBody: Decodable {
    let id: String
    let created_at: String
    /// True iff this call flipped server-side `submitted_at` null → non-null.
    /// Defaults to false for backwards compat if the server omits it.
    let was_submitted: Bool?
}

struct QuestionnaireDismissRequestBody: Encodable {
    let bundle_id: String?
    let user_id: String
}

struct QuestionnaireDismissResponseBody: Decodable {
    let dismissed_at: String
}
