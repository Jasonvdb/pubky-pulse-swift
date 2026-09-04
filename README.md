# Pubky Pulse Swift SDK

[![Tests](https://github.com/pubky/pubky-pulse-swift/actions/workflows/test.yml/badge.svg)](https://github.com/pubky/pubky-pulse-swift/actions/workflows/test.yml)
[![Release](https://img.shields.io/github/v/release/pubky/pubky-pulse-swift?display_name=tag&sort=semver)](https://github.com/pubky/pubky-pulse-swift/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)
[![Platforms](https://img.shields.io/badge/platforms-iOS%2016%2B%20%7C%20macOS%2013%2B%20%7C%20watchOS%2010%2B-lightgrey)](./Package.swift)

Native Swift SDK for iOS, iPadOS, macOS, and watchOS — event logging, structured metrics, funnels, identity, screen tracking, drop-in feedback and questionnaire views, and Apple Search Ads attribution capture. Zero external runtime dependencies.

Part of the [Pubky Pulse](https://pulse.pubky.org) self-hosted metrics platform.

**Full setup guide & API reference: [pulse.pubky.org/docs/sdks/swift](https://pulse.pubky.org/docs/sdks/swift)**

## Install

### Package.swift

```swift
dependencies: [
    .package(url: "https://github.com/pubky/pubky-pulse-swift.git", branch: "main"),
]
```

Add `PubkyPulse` to your target's `dependencies`.

> For stable releases, pin to a version instead: `.package(url: "…", from: "X.Y.Z")`. See [releases](https://github.com/pubky/pubky-pulse-swift/releases/latest) for the latest.

### Xcode

`File` → `Add Package Dependencies…` → enter `https://github.com/pubky/pubky-pulse-swift.git`, choose `main` branch (or a specific version), add to your app target.

## Quickstart

```swift
import PubkyPulse

try Pulse.configure(
    endpoint: "https://ingest.pulse.pubky.org",
    apiKey: "pulse_client_..."
)

Pulse.info("app_launched")
```

Call `configure` once at app launch (e.g. from your `App` init). It throws on invalid input.

## Examples

### Logging

```swift
Pulse.info("feed_loaded", screenName: "Feed")
Pulse.warn("cache_miss", attributes: ["key": "user_profile"])
Pulse.error("upload_failed", attributes: ["reason": "timeout"])

// Passing a Swift `Error` extracts its type, cause chain, and call stack.
do {
    try await uploadPhoto()
} catch {
    Pulse.error(error, "photo upload failed", screenName: "Gallery")
}

// Optional values pass through `attributes:` directly. Nil values are
// dropped before the event ships, so you don't need to unwrap first.
let draftId: String? = session.draftId
Pulse.info("draft_created", attributes: ["context": "createDraft", "draftId": draftId])
```

### Track a screen

```swift
VStack { … }
    .pulseScreen("Home")
```

### Identify a user

```swift
Pulse.setUser("user_12345")
Pulse.setUserProperties(["plan": "premium"])
```

### Measure an operation

```swift
let op = Pulse.startOperation("photo-upload", attributes: ["format": "heic"])
// … do work …
op.complete(attributes: ["size_kb": "512"])
// or op.fail(error: "network")
```

### Record a funnel step

```swift
Pulse.step("welcome-screen")
Pulse.step("create-account")
Pulse.step("first-post")
```

### Collect user feedback

Drop `PulseFeedbackView` into a sheet, push it onto a `NavigationStack`, or embed it inline:

```swift
.sheet(isPresented: $showFeedback) {
    NavigationStack {
        PulseFeedbackView(
            onSubmitted: { _ in showFeedback = false },
            onCancel: { showFeedback = false }
        )
        .navigationTitle("Feedback")
    }
}
```

For programmatic submission (e.g., forwarding feedback from your own form):

```swift
let receipt = try await Pulse.sendFeedback(message: "Love the new update!", email: "me@example.com")
```

Every label, placeholder, and error message is overridable via `PulseFeedbackStrings`. See [User Feedback](https://pulse.pubky.org/docs/sdks/swift/feedback) for presentation modes, localization, and submission lifecycle.

### Ask a questionnaire

```swift
ContentView()
    .pulseQuestionnaire(slug: "post-onboarding", trigger: .afterLaunches(3))
```

The questionnaire is authored on the server (dashboard or MCP) and only appears when the trigger conditions hold and the user hasn't already responded. See [Questionnaires](https://pulse.pubky.org/docs/sdks/swift/questionnaires).

### Apple Search Ads attribution

Attribution is auto-captured on `Pulse.configure()` — no extra code needed. To opt out:

```swift
try Pulse.configure(
    endpoint: "https://ingest.pulse.pubky.org",
    apiKey: "pulse_client_...",
    attributionEnabled: false
)
```

Each capture attempt emits an `sdk:attribution_capture` event, so the capture → resolve → retry path is visible in the dashboard without extra instrumentation.

### Apple Watch

`Pulse` works unchanged on watchOS. Events fall back from direct HTTP to `WCSession.transferUserInfo` to an on-disk queue, so a watch that's off-network still delivers once it reaches its iPhone — forward the payload with `Pulse.handleWatchUserInfo(_:)` from your iPhone app's `WCSessionDelegate`. See [Apple Watch](https://pulse.pubky.org/docs/sdks/swift/watchos).

## Privacy

The SDK ships an Apple-compliant `PrivacyInfo.xcprivacy` manifest. SPM merges it into your app at build time — no code, no configuration. We don't use IDFA, don't link against `AdSupport`, and never require an App Tracking Transparency prompt.

On your **next** App Store submission, tick these categories under **App Store Connect → App Privacy**: Crash Data, Other Diagnostic Data, Product Interaction, Performance Data, Other User Content, and (if you call `Pulse.setUser`) User ID. Subsequent submissions are unchanged.

Full guide: [Privacy & App Store compliance](https://pulse.pubky.org/docs/sdks/swift/privacy-compliance).

## Example app

[`Examples/Demo/`](./Examples/Demo/) is a SwiftUI demo that exercises the full SDK surface — screen tracking, events, metrics, funnels, feedback, questionnaires, attribution, and a watchOS companion. It doubles as the SDK's pre-release canary: a build failure in the demo means `main` is broken before a release cuts.

Open `Examples/Demo/PubkyPulseDemo.xcodeproj` in Xcode and run on any iOS simulator, or from the command line:

```bash
xcodebuild -project Examples/Demo/PubkyPulseDemo.xcodeproj \
  -scheme PubkyPulseDemo \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -quiet build
```

The "Backend Demo" section of the app hits `http://localhost:4007` to exercise session correlation across the Swift SDK and Node SDK. Start the Node demo from the sibling [`pubky-pulse-node`](https://github.com/Jasonvdb/pubky-pulse-node) repo first — see [`Examples/Demo/README.md`](https://github.com/Jasonvdb/pubky-pulse-node/blob/main/Examples/Demo/README.md) there for the exact commands.

## Testing

Unit tests run self-contained:

```bash
swift test --skip SDKIntegrationTests --skip AppleSearchAdsAttributionTests
```

Integration tests need a Pubky Pulse server on `http://127.0.0.1:4111` with the seeded test database, so they are not part of CI. See the [main repo](https://github.com/pubky/pubky-pulse) for running the server locally; then:

```bash
PULSE_TEST_ENDPOINT=http://127.0.0.1:4111 \
    swift test --filter "(SDKIntegrationTests|AppleSearchAdsAttributionTests)"
```

## Related repos

- **[pubky/pubky-pulse](https://github.com/pubky/pubky-pulse)** — server, dashboard, MCP endpoint, documentation.
- **[Jasonvdb/pubky-pulse-node](https://github.com/Jasonvdb/pubky-pulse-node)** — Node.js server SDK.
- **[Jasonvdb/pubky-pulse-web](https://github.com/Jasonvdb/pubky-pulse-web)** — browser SDK.

## License

MIT. See [LICENSE](./LICENSE).
