import XCTest
@testable import PubkyPulse

final class EventTransportTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        MockURLProtocol.reset()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testFlushSendsEventsToServer() async {
        var receivedBody: Data?
        MockURLProtocol.handler = { request in
            receivedBody = request.httpBody ?? request.httpBodyStream.flatMap { stream in
                stream.open()
                let data = Data(reading: stream)
                stream.close()
                return data
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"accepted":1,"rejected":0}"#.data(using: .utf8)!
            return (response, body)
        }

        let transport = makeTransport()
        await transport.enqueue(LogEvent.stub(message: "hello"))
        await transport.flush()

        try? await Task.sleep(nanoseconds: 500_000_000)

        XCTAssertNotNil(receivedBody)
        if let data = receivedBody {
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            XCTAssertEqual(json?["bundle_id"] as? String, "org.pubky.pulse.test")
            let events = json?["events"] as? [[String: Any]]
            XCTAssertEqual(events?.count, 1)
            XCTAssertEqual(events?.first?["message"] as? String, "hello")
        }
    }

    func testFetchQuestionnaireOmitsForceWhenFalse() async {
        var receivedURL: URL?
        MockURLProtocol.handler = { request in
            receivedURL = request.url
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"eligible":false,"reason":"inactive"}"#.data(using: .utf8)!
            return (response, body)
        }

        let transport = makeTransport()
        _ = await transport.fetchQuestionnaire(slug: "preview-slug", userId: "user_42", force: false)

        XCTAssertNotNil(receivedURL)
        let items = receivedURL.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
        XCTAssertEqual(items.first(where: { $0.name == "bundle_id" })?.value, "org.pubky.pulse.test")
        XCTAssertEqual(items.first(where: { $0.name == "user_id" })?.value, "user_42")
        XCTAssertNil(items.first(where: { $0.name == "force" }))
    }

    func testFetchQuestionnaireAppendsForceQueryParamWhenTrue() async {
        var receivedURL: URL?
        MockURLProtocol.handler = { request in
            receivedURL = request.url
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"eligible":false,"reason":"inactive"}"#.data(using: .utf8)!
            return (response, body)
        }

        let transport = makeTransport()
        _ = await transport.fetchQuestionnaire(slug: "preview-slug", userId: "user_42", force: true)

        XCTAssertNotNil(receivedURL)
        let items = receivedURL.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
        XCTAssertEqual(items.first(where: { $0.name == "force" })?.value, "true")
    }

    func testAuthorizationHeaderSet() async {
        var receivedAuth: String?
        MockURLProtocol.handler = { request in
            receivedAuth = request.value(forHTTPHeaderField: "Authorization")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"accepted":1,"rejected":0}"#.data(using: .utf8)!
            return (response, body)
        }

        let transport = makeTransport()
        await transport.enqueue(LogEvent.stub(message: "test"))
        await transport.flush()

        try? await Task.sleep(nanoseconds: 500_000_000)

        XCTAssertEqual(receivedAuth, "Bearer pulse_client_test123")
    }

    // MARK: - Retry policy

    func testRateLimitIsRetriedAndHonorsRetryAfter() async {
        let attempts = AttemptCounter()
        MockURLProtocol.handler = { request in
            if attempts.increment() == 1 {
                let response = HTTPURLResponse(
                    url: request.url!, statusCode: 429, httpVersion: nil,
                    headerFields: ["Retry-After": "2"]
                )!
                return (response, Data())
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, #"{"accepted":1,"rejected":0}"#.data(using: .utf8)!)
        }

        let queue = OfflineQueue(directory: tempDir)
        let transport = makeTransport(offlineQueue: queue)
        await transport.enqueue(LogEvent.stub(message: "rate-limited"))

        let start = Date()
        await transport.flush()
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertEqual(attempts.count, 2)
        // The ladder's own first step is 1s; `Retry-After: 2` widens it.
        XCTAssertGreaterThan(elapsed, 1.8)
        XCTAssertLessThan(elapsed, 5)
        let parked = await queue.count
        XCTAssertEqual(parked, 0, "a delivered batch must not be parked")
    }

    func testClientErrorIsDroppedWithoutRetry() async {
        let attempts = AttemptCounter()
        MockURLProtocol.handler = { request in
            _ = attempts.increment()
            let response = HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let queue = OfflineQueue(directory: tempDir)
        let transport = makeTransport(offlineQueue: queue)
        await transport.enqueue(LogEvent.stub(message: "malformed"))

        await transport.flush()

        XCTAssertEqual(attempts.count, 1)
    }

    func testPersistDuringRetryParksInFlightBatchExactlyOnce() async {
        let attempts = AttemptCounter()
        MockURLProtocol.handler = { request in
            _ = attempts.increment()
            let response = HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let queue = OfflineQueue(directory: tempDir)
        let transport = makeTransport(offlineQueue: queue)
        await transport.enqueue(LogEvent.stub(message: "in-flight"))

        let flush = Task { await transport.flush() }
        await waitUntil { attempts.count >= 1 }

        // Background time expired while the batch is inside the retry ladder:
        // it is no longer in `buffer`, so it has to be parked from here or a
        // suspended process loses it.
        await transport.persistBufferToDisk()
        let parkedWhileInFlight = await queue.count
        XCTAssertEqual(parkedWhileInFlight, 1, "an in-flight batch must be parked on persist")

        await flush.value

        let drained = await queue.drain()
        XCTAssertEqual(drained.count, 1, "the failed send must not park a second copy")
        XCTAssertEqual(drained.first?.message, "in-flight")
    }

    // MARK: - Helpers

    /// Poll the actor-free `condition` until it holds, so tests don't race
    /// `MockURLProtocol.handler` running on URLSession's own queue.
    private func waitUntil(
        timeout: TimeInterval = 5,
        _ condition: () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() >= deadline {
                XCTFail("Timed out waiting for condition", file: file, line: line)
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func makeTransport(offlineQueue: OfflineQueue? = nil) -> EventTransport {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)

        return EventTransport(
            endpoint: URL(string: "https://api.test.com")!,
            apiKey: "pulse_client_test123",
            bundleId: "org.pubky.pulse.test",
            compressionEnabled: true,
            offlineQueue: offlineQueue ?? OfflineQueue(directory: tempDir),
            networkMonitor: NetworkMonitor(),
            session: session
        )
    }
}

/// `MockURLProtocol.handler` runs on URLSession's loading queue, so attempt
/// bookkeeping shared with the test body needs its own lock.
private final class AttemptCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    @discardableResult
    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

// MARK: - Mock URL Protocol

final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (HTTPURLResponse, Data))?

    static func reset() {
        handler = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        let (response, data) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private extension Data {
    init(reading stream: InputStream) {
        self.init()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1024)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: 1024)
            if count > 0 {
                append(buffer, count: count)
            }
        }
    }
}
