import Foundation
import os

actor EventTransport {
    private var buffer: [LogEvent] = []
    private let endpoint: URL
    private let ingestURL: URL
    private let claimURL: URL
    private let propertiesURL: URL
    private let feedbackURL: URL
    private let questionnaireDismissURL: URL
    private let apiKey: String
    private let bundleId: String
    private let session: URLSession
    private let offlineQueue: OfflineQueue
    private let networkMonitor: NetworkMonitor
    private let compressionEnabled: Bool
    private var flushTask: Task<Void, Never>?
    private let encoder = JSONEncoder()

    private let batchSize = 20
    private let maxBufferSize = 10_000
    private let flushInterval: UInt64 = 5_000_000_000 // 5 seconds
    private let maxRetries = 5
    private let maxBackoff: TimeInterval = 30
    private let maxRetryAfter: TimeInterval = 60
    private let compressionThreshold = 512

    // Batches currently inside `send(_:)`: already removed from `buffer`,
    // not yet delivered. Two things depend on them.
    //
    // `claimIdentity` waits for this to drain before POSTing the claim —
    // otherwise the auto-flush from `enqueue` (when buffer reaches
    // batchSize) and `flushAll`'s loop body can have parallel /v1/ingest
    // POSTs in flight on separate URLSession connections, and the server can
    // process the claim's `UPDATE events` before those parallel ingests have
    // committed → events orphan under the anon id.
    //
    // `persistBufferToDisk` parks their events too, so a batch asleep in the
    // retry ladder when the OS suspends or kills us isn't lost.
    private var inFlightBatches: [Int: InFlightBatch] = [:]
    private var nextInFlightBatchId = 0
    private var sendDrainContinuations: [CheckedContinuation<Void, Never>] = []

    private struct InFlightBatch {
        let events: [LogEvent]
        /// Set by `persistBufferToDisk()`. The still-running `send(_:)` reads
        /// it so a delivery that later fails doesn't park a second copy.
        var persisted = false
    }

    private static let logger = Logger(subsystem: Pulse.logSubsystem, category: "transport")

    init(
        endpoint: URL,
        apiKey: String,
        bundleId: String,
        compressionEnabled: Bool,
        offlineQueue: OfflineQueue,
        networkMonitor: NetworkMonitor,
        session: URLSession = .shared
    ) {
        self.endpoint = endpoint
        self.ingestURL = endpoint.appendingPathComponent("v1/ingest")
        self.claimURL = endpoint.appendingPathComponent("v1/identity/claim")
        self.propertiesURL = endpoint.appendingPathComponent("v1/identity/properties")
        self.feedbackURL = endpoint.appendingPathComponent("v1/feedback")
        self.questionnaireDismissURL = endpoint.appendingPathComponent("v1/questionnaires/dismiss")
        self.apiKey = apiKey
        self.bundleId = bundleId
        self.compressionEnabled = compressionEnabled
        self.offlineQueue = offlineQueue
        self.networkMonitor = networkMonitor
        self.session = session
    }

    /// Build the URL for an attribution submission to a specific network. Kept
    /// as a helper so future network methods share the same namespace.
    private func attributionURL(network: PulseAttributionNetwork) -> URL {
        endpoint.appendingPathComponent("v1/identity/attribution/\(network.slug)")
    }

    func start() {
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: self?.flushInterval ?? 5_000_000_000)
                guard let self else { break }
                await self.flush()
            }
        }
    }

    func shutdown() async {
        flushTask?.cancel()
        flushTask = nil
        await flushAll()
    }

    deinit {
        flushTask?.cancel()
    }

    func enqueue(_ event: LogEvent) {
        buffer.append(event)
        if buffer.count > maxBufferSize {
            buffer.removeFirst(buffer.count - maxBufferSize)
        }
        if buffer.count >= batchSize {
            Task { await flush() }
        }
    }

    func enqueue(_ events: [LogEvent]) {
        guard !events.isEmpty else { return }
        buffer.append(contentsOf: events)
        if buffer.count > maxBufferSize {
            buffer.removeFirst(buffer.count - maxBufferSize)
        }
        if buffer.count >= batchSize {
            Task { await flush() }
        }
    }

    func flush() async {
        let offlineEvents = await offlineQueue.drain()
        if !offlineEvents.isEmpty {
            buffer.insert(contentsOf: offlineEvents, at: 0)
        }

        guard !buffer.isEmpty else { return }

        let batch = Array(buffer.prefix(batchSize))
        buffer.removeFirst(min(batchSize, buffer.count))

        guard networkMonitor.isConnected else {
            await handleUndelivered(batch)
            return
        }

        let handled = await send(batch)
        if !handled {
            await handleUndelivered(batch)
        }
    }

    func flushAll() async {
        let offlineEvents = await offlineQueue.drain()
        if !offlineEvents.isEmpty {
            buffer.insert(contentsOf: offlineEvents, at: 0)
        }

        while !buffer.isEmpty {
            let batch = Array(buffer.prefix(batchSize))
            buffer.removeFirst(min(batchSize, buffer.count))

            guard networkMonitor.isConnected else {
                let remainder = batch + buffer
                buffer.removeAll()
                await handleUndelivered(remainder)
                return
            }

            let handled = await send(batch)
            if !handled {
                await handleUndelivered(batch)
            }
        }
    }

    /// On watchOS, prefer WatchConnectivity's OS-managed queue when a
    /// companion is reachable; otherwise (and on every other platform)
    /// fall back to OfflineQueue.
    private func handleUndelivered(_ batch: [LogEvent]) async {
        guard !batch.isEmpty else { return }
        #if os(watchOS) && canImport(WatchConnectivity)
        if WatchConnectivityBridge.shared.canRelay {
            WatchConnectivityBridge.shared.enqueue(batch)
            return
        }
        #endif
        await offlineQueue.enqueue(batch)
    }

    /// Park everything undelivered on disk. Called when background time
    /// expires or the app is terminating, so it covers the batches inside
    /// `send(_:)` as well as `buffer` — a retry ladder can sleep far longer
    /// than the OS gives us before suspending or killing the process. A
    /// parked batch whose POST later succeeds is delivered twice; ingest
    /// deduplicates on `client_event_id`, and losing it is not recoverable.
    func persistBufferToDisk() async {
        // In-flight batches left `buffer` before the ones still in it, so
        // they go in front to keep disk order matching emission order.
        let inFlightIds = inFlightBatches.keys.sorted()
        var pending = inFlightIds.flatMap { inFlightBatches[$0]?.events ?? [] }
        pending.append(contentsOf: buffer)
        guard !pending.isEmpty else { return }

        // Mark before the first await so the in-flight sends see it whenever
        // they next reach the actor.
        for id in inFlightIds { inFlightBatches[id]?.persisted = true }
        buffer.removeAll()

        await offlineQueue.enqueue(pending)
        await offlineQueue.persistNow()
    }

    func claimIdentity(anonymousId: String, userId: String) async {
        // Flush any buffered events first so the server has them before we claim
        await flushAll()
        // flushAll's `await send(batch)` releases the actor lock between
        // batches, and `enqueue`'s auto-flush + the periodic flush both spawn
        // their own flush Tasks. So even after flushAll's loop exits with an
        // empty buffer, parallel /v1/ingest POSTs from those other Tasks may
        // still be in flight on separate URLSession connections. Wait for
        // them to return before POSTing the claim — otherwise the server can
        // process our claim while ingests are mid-transaction and the
        // claim's `UPDATE events` misses them, orphaning rows under the
        // anon id. See CLAUDE.md "Identity" for the production bug.
        await awaitInFlightSends()

        let body: [String: String] = [
            "anonymous_id": anonymousId,
            "user_id": userId,
        ]

        guard let httpBody = try? encoder.encode(body) else {
            Self.logger.error("Failed to encode claim request")
            return
        }

        let request = makeRequest(url: claimURL, body: httpBody)
        let result = await performWithRetry(request, label: "Claim")

        if result {
            Self.logger.info("Identity claimed: \(anonymousId) → \(userId)")
        } else {
            Self.logger.error("Identity claim failed after \(self.maxRetries) attempts")
        }
    }

    func setUserProperties(userId: String, properties: [String: String]) async {
        let body: [String: Any] = [
            "user_id": userId,
            "properties": properties,
        ]

        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
            Self.logger.error("Failed to encode properties request")
            return
        }

        let request = makeRequest(url: propertiesURL, body: httpBody)
        let result = await performWithRetry(request, label: "Properties")

        if result {
            Self.logger.info("User properties set for \(userId)")
        } else {
            Self.logger.error("User properties update failed for \(userId)")
        }
    }

    /// One-shot submission of an Apple Search Ads attribution token.
    /// Retries on transport failures (5 attempts, exponential backoff up to
    /// 30s). The server resolves the token with Apple's Attribution API and
    /// writes `asa_*` / `attribution_source` properties on the user.
    ///
    /// `devMock` is honored only when the server runs with NODE_ENV != "production"
    /// and is used by tests to skip the upstream Apple call.
    func submitAppleSearchAdsAttributionToken(
        userId: String,
        token: String,
        devMock: String? = nil
    ) async -> AttributionSubmissionResult {
        var body: [String: String] = [
            "user_id": userId,
            "attribution_token": token,
        ]
        if let devMock { body["dev_mock"] = devMock }

        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
            Self.logger.error("Failed to encode attribution request")
            return .transportFailure
        }

        let request = makeRequest(url: attributionURL(network: .appleSearchAds), body: httpBody)

        for attempt in 0..<maxRetries {
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    if attempt < maxRetries - 1 { await sleepBeforeRetry(attempt: attempt) }
                    continue
                }

                if (200..<300).contains(http.statusCode) {
                    guard let decoded = try? JSONDecoder().decode(AttributionResponseBody.self, from: data) else {
                        Self.logger.warning("Attribution response decode failed")
                        return .transportFailure
                    }
                    if decoded.pending {
                        return .pending(retryAfterSeconds: decoded.retry_after_seconds ?? 60)
                    }
                    return .success(
                        attributionSource: decoded.properties["attribution_source"] ?? "unknown",
                        properties: decoded.properties
                    )
                }

                // 4xx: server rejected the token. Retrying won't change the outcome.
                if (400..<500).contains(http.statusCode) {
                    return .invalidToken
                }

                Self.logger.warning("Attribution returned \(http.statusCode), attempt \(attempt + 1)/\(self.maxRetries)")
            } catch {
                Self.logger.warning("Attribution failed: \(error.localizedDescription), attempt \(attempt + 1)/\(self.maxRetries)")
            }

            if attempt < maxRetries - 1 {
                await sleepBeforeRetry(attempt: attempt)
            }
        }

        return .transportFailure
    }

    /// Exponential backoff (1s, 2s, 4s … capped at `maxBackoff`), widened to
    /// the server's `Retry-After` when it asked for a longer wait and capped
    /// at `maxRetryAfter` so a single hint can't hold a batch in memory for
    /// minutes.
    private func sleepBeforeRetry(attempt: Int, retryAfter: TimeInterval? = nil) async {
        let backoff = min(pow(2.0, Double(attempt)), maxBackoff)
        let delay = retryAfter.map { min(max($0, backoff), maxRetryAfter) } ?? backoff
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
    }

    /// One-shot synchronous feedback submission. Does NOT queue offline — caller handles errors.
    func submitFeedback(_ payload: FeedbackRequestBody) async -> Result<PulseFeedbackReceipt, PulseFeedbackError> {
        let httpBody: Data
        do {
            httpBody = try encoder.encode(payload)
        } catch {
            return .failure(.transportFailure("encoding failed: \(error.localizedDescription)"))
        }

        let request = makeRequest(url: feedbackURL, body: httpBody)

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure(.transportFailure("no HTTP response"))
            }
            if (200..<300).contains(http.statusCode) {
                do {
                    let decoded = try JSONDecoder().decode(FeedbackResponseBody.self, from: data)
                    let date = Self.iso8601.date(from: decoded.created_at) ?? Date()
                    return .success(PulseFeedbackReceipt(id: decoded.id, createdAt: date))
                } catch {
                    return .failure(.transportFailure("decode failed: \(error.localizedDescription)"))
                }
            }
            let body = String(data: data, encoding: .utf8)
            return .failure(.serverError(statusCode: http.statusCode, body: body))
        } catch {
            return .failure(.transportFailure(error.localizedDescription))
        }
    }

    private func questionnaireURL(slug: String) -> URL {
        endpoint.appendingPathComponent("v1/questionnaires/\(slug)")
    }

    private func questionnaireResponsesURL(slug: String) -> URL {
        endpoint.appendingPathComponent("v1/questionnaires/\(slug)/responses")
    }

    /// Fetch a questionnaire spec + eligibility envelope. The success branch
    /// carries the spec (nil when the user is ineligible) plus, on eligible
    /// returns, any in-progress draft from a previous session so the flow
    /// container can pre-fill its answer store and resume. The ineligibility
    /// reason is surfaced for diagnostics but the SDK still treats
    /// already_responded / globally_dismissed / inactive as silent no-ops.
    /// Throws only for slug-not-found (404) and transport failures.
    func fetchQuestionnaire(slug: String, userId: String?, force: Bool = false) async -> Result<PulseQuestionnaireFetchResult, PulseQuestionnaireError> {
        var components = URLComponents(url: questionnaireURL(slug: slug), resolvingAgainstBaseURL: false)
        var items: [URLQueryItem] = [URLQueryItem(name: "bundle_id", value: bundleId)]
        if let userId { items.append(URLQueryItem(name: "user_id", value: userId)) }
        if force { items.append(URLQueryItem(name: "force", value: "true")) }
        components?.queryItems = items
        guard let url = components?.url else {
            return .failure(.transportFailure("invalid URL"))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure(.transportFailure("no HTTP response"))
            }
            if http.statusCode == 404 {
                return .failure(.slugNotFound)
            }
            if !(200..<300).contains(http.statusCode) {
                let body = String(data: data, encoding: .utf8)
                return .failure(.serverError(statusCode: http.statusCode, body: body))
            }
            let envelope: QuestionnaireFetchEnvelope
            do {
                envelope = try JSONDecoder().decode(QuestionnaireFetchEnvelope.self, from: data)
            } catch {
                return .failure(.transportFailure("decode failed: \(error.localizedDescription)"))
            }
            if envelope.eligible, let q = envelope.questionnaire {
                let draft = envelope.in_progress.map { body in
                    PulseQuestionnaireDraft(
                        responseId: body.response_id,
                        answers: hydrateDraftAnswers(body.answers, against: q.schema)
                    )
                }
                return .success(PulseQuestionnaireFetchResult(questionnaire: q, inProgress: draft))
            }
            // Ineligible — surface the reason for diagnostics so callers can
            // log or branch on it without parsing the raw envelope.
            let reason = envelope.reason.flatMap(PulseQuestionnaireIneligibleReason.init(rawValue:))
            return .success(PulseQuestionnaireFetchResult(questionnaire: nil, ineligibleReason: reason))
        } catch {
            return .failure(.transportFailure(error.localizedDescription))
        }
    }

    /// Save a draft (`isComplete: false`) or finalize a submission
    /// (`isComplete: true`). The server upserts by `(project, slug, user_id)`
    /// — the SDK is stateless across calls and doesn't track the response
    /// id. `receipt.wasSubmitted` is `true` exactly once per response (on
    /// the call that flipped `submitted_at` null → non-null) and is what the
    /// flow container uses to transition into the success phase.
    func saveQuestionnaireResponse(
        slug: String,
        userId: String?,
        sessionId: String?,
        answers: [String: PulseQuestionnaireAnswerValue],
        isComplete: Bool,
        deviceInfo: DeviceInfo?,
        environment: String?,
        appVersion: String?,
        isDev: Bool
    ) async -> Result<PulseQuestionnaireReceipt, PulseQuestionnaireError> {
        let payload = QuestionnaireSubmitRequestBody(
            bundle_id: bundleId,
            session_id: sessionId,
            user_id: userId,
            answers: PulseQuestionnaireAnswersWire(answers: answers),
            is_complete: isComplete,
            app_version: appVersion,
            sdk_name: PubkyPulseVersion.name,
            sdk_version: PubkyPulseVersion.current,
            environment: environment,
            device_model: deviceInfo?.deviceModel,
            os_version: deviceInfo?.osVersion,
            is_dev: isDev
        )
        let httpBody: Data
        do { httpBody = try encoder.encode(payload) }
        catch { return .failure(.transportFailure("encoding failed: \(error.localizedDescription)")) }

        let request = makeRequest(url: questionnaireResponsesURL(slug: slug), body: httpBody)
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure(.transportFailure("no HTTP response"))
            }
            if (200..<300).contains(http.statusCode) {
                do {
                    let decoded = try JSONDecoder().decode(QuestionnaireSubmitResponseBody.self, from: data)
                    let date = Self.iso8601.date(from: decoded.created_at) ?? Date()
                    return .success(PulseQuestionnaireReceipt(
                        id: decoded.id,
                        createdAt: date,
                        wasSubmitted: decoded.was_submitted ?? false
                    ))
                } catch {
                    return .failure(.transportFailure("decode failed: \(error.localizedDescription)"))
                }
            }
            if http.statusCode == 400 {
                let body = String(data: data, encoding: .utf8)
                return .failure(.invalidAnswers(body ?? "unknown"))
            }
            if http.statusCode == 404 {
                return .failure(.slugNotFound)
            }
            let body = String(data: data, encoding: .utf8)
            return .failure(.serverError(statusCode: http.statusCode, body: body))
        } catch {
            return .failure(.transportFailure(error.localizedDescription))
        }
    }

    func submitQuestionnaireDismiss(userId: String) async -> Result<Date, PulseQuestionnaireError> {
        let payload = QuestionnaireDismissRequestBody(bundle_id: bundleId, user_id: userId)
        let httpBody: Data
        do { httpBody = try encoder.encode(payload) }
        catch { return .failure(.transportFailure("encoding failed: \(error.localizedDescription)")) }

        let request = makeRequest(url: questionnaireDismissURL, body: httpBody)
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure(.transportFailure("no HTTP response"))
            }
            if (200..<300).contains(http.statusCode) {
                do {
                    let decoded = try JSONDecoder().decode(QuestionnaireDismissResponseBody.self, from: data)
                    return .success(Self.iso8601.date(from: decoded.dismissed_at) ?? Date())
                } catch {
                    return .failure(.transportFailure("decode failed: \(error.localizedDescription)"))
                }
            }
            let body = String(data: data, encoding: .utf8)
            return .failure(.serverError(statusCode: http.statusCode, body: body))
        } catch {
            return .failure(.transportFailure(error.localizedDescription))
        }
    }

    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// POST one batch to /v1/ingest. Returns `true` when the caller need not
    /// park the batch: either the POST succeeded, or `persistBufferToDisk()`
    /// already wrote the batch to the offline queue while the retry ladder
    /// was sleeping.
    private func send(_ events: [LogEvent]) async -> Bool {
        guard let httpBody = try? encoder.encode(IngestRequestBody(bundle_id: bundleId, events: events)) else {
            Self.logger.error("Failed to encode events")
            return false
        }

        let request = makeRequest(url: ingestURL, body: httpBody)
        let batchId = nextInFlightBatchId
        nextInFlightBatchId += 1
        inFlightBatches[batchId] = InFlightBatch(events: events)
        defer {
            inFlightBatches[batchId] = nil
            if inFlightBatches.isEmpty {
                let waiters = sendDrainContinuations
                sendDrainContinuations = []
                for waiter in waiters { waiter.resume() }
            }
        }

        let delivered = await performWithRetry(request, label: "Ingest", batchId: batchId)
        return delivered || inFlightBatches[batchId]?.persisted == true
    }

    /// Suspend until every in-flight ingest send has returned (HTTP response
    /// fully received). `claimIdentity` uses this after `flushAll()` to
    /// guarantee its POST happens after every parallel `send(_:)` started
    /// by `enqueue`'s auto-flush, the periodic flush, or `flushAll`'s loop —
    /// otherwise the server's `UPDATE events` could run while those parallel
    /// ingest POSTs are mid-transaction and miss their rows.
    private func awaitInFlightSends() async {
        if inFlightBatches.isEmpty { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            // Re-check inside the actor (we're already on it, but be explicit
            // about the invariant: by the time this closure runs, no other
            // actor message has interleaved between the count check and the
            // append).
            if inFlightBatches.isEmpty {
                continuation.resume()
            } else {
                sendDrainContinuations.append(continuation)
            }
        }
    }

    // MARK: - Private Helpers

    private func makeRequest(url: URL, body: Data) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        if compressionEnabled, body.count >= compressionThreshold,
           let compressed = try? body.gzipped() {
            request.httpBody = compressed
            request.setValue("gzip", forHTTPHeaderField: "Content-Encoding")
        } else {
            request.httpBody = body
        }

        return request
    }

    /// Retry ladder shared by ingest, claim and properties. Pass `batchId`
    /// for an ingest so the ladder can bail out once the batch is durable.
    private func performWithRetry(_ request: URLRequest, label: String, batchId: Int? = nil) async -> Bool {
        for attempt in 0..<maxRetries {
            var retryAfter: TimeInterval?

            do {
                let (data, response) = try await session.data(for: request)

                if let http = response as? HTTPURLResponse {
                    if (200..<300).contains(http.statusCode) {
                        if let ingestResponse = try? JSONDecoder().decode(IngestResponse.self, from: data),
                           ingestResponse.rejected > 0 {
                            Self.logger.warning("Server rejected \(ingestResponse.rejected) events")
                        }
                        return true
                    }

                    // Don't retry client errors — they won't succeed. 429 is
                    // the exception: it's a rate limit, so the same payload
                    // does land once the window moves.
                    if (400..<500).contains(http.statusCode), http.statusCode != 429 {
                        Self.logger.warning("\(label) returned \(http.statusCode), not retrying")
                        return false
                    }

                    // Only 429 and 503 define a `Retry-After`; elsewhere keep
                    // the plain ladder.
                    if http.statusCode == 429 || http.statusCode == 503 {
                        retryAfter = Self.retryAfterSeconds(http)
                    }

                    Self.logger.warning("\(label) returned \(http.statusCode), attempt \(attempt + 1)/\(self.maxRetries)")
                }
            } catch {
                Self.logger.warning("\(label) failed: \(error.localizedDescription), attempt \(attempt + 1)/\(self.maxRetries)")
            }

            guard attempt < maxRetries - 1 else { break }

            // The batch was parked to the offline queue while we were
            // retrying (background time expiring, or termination). It's
            // durable now, so stop spending the runtime we have left — the
            // next flush picks it up off disk.
            if let batchId, inFlightBatches[batchId]?.persisted == true {
                Self.logger.info("\(label) abandoned: batch already parked to the offline queue")
                return false
            }

            await sleepBeforeRetry(attempt: attempt, retryAfter: retryAfter)
        }

        return false
    }

    /// Parse a `Retry-After` header: delta-seconds ("2") or an HTTP-date
    /// ("Wed, 21 Oct 2026 07:28:00 GMT"). Returns nil when the header is
    /// absent or unparsable so the caller falls back to the plain ladder.
    private static func retryAfterSeconds(_ http: HTTPURLResponse) -> TimeInterval? {
        guard let raw = http.value(forHTTPHeaderField: "Retry-After")?
            .trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }

        if let seconds = TimeInterval(raw), seconds.isFinite {
            return max(0, seconds)
        }
        guard let date = Self.httpDate.date(from: raw) else { return nil }
        return max(0, date.timeIntervalSinceNow)
    }

    private static let httpDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "GMT")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return f
    }()
}

private struct IngestResponse: Codable {
    let accepted: Int
    let rejected: Int
}

private struct AttributionResponseBody: Decodable {
    let attributed: Bool?
    let pending: Bool
    let retry_after_seconds: Int?
    let properties: [String: String]
}

/// Project wire-format draft answers onto the strongly-typed
/// `PulseQuestionnaireAnswerValue` enum by dispatching on each question's type.
/// Answers whose question id is no longer in the schema (mid-draft schema
/// edits) or whose shape doesn't match the question type are skipped — the
/// SDK pre-fill is best-effort, and the server prunes unknown keys when the
/// user finally submits.
func hydrateDraftAnswers(
    _ raw: [String: AnyAnswerJSON],
    against schema: PulseQuestionnaireSchema
) -> [String: PulseQuestionnaireAnswerValue] {
    var out: [String: PulseQuestionnaireAnswerValue] = [:]
    for question in schema.questions {
        guard let value = raw[question.id] else { continue }
        switch (question, value) {
        case let (.text, .string(s)):
            out[question.id] = .text(s)
        case let (.singleChoice, .string(s)):
            out[question.id] = .choice(s)
        case let (.multiChoice, .strings(arr)):
            out[question.id] = .choices(arr)
        case let (.rating, .integer(n)):
            out[question.id] = .rating(n)
        case let (.nps, .integer(n)):
            out[question.id] = .nps(n)
        default:
            // Shape mismatch — drop the value rather than pre-fill incorrectly.
            continue
        }
    }
    return out
}
