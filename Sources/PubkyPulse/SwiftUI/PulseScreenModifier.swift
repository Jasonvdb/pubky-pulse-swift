#if canImport(SwiftUI)
import SwiftUI

/// A view modifier that automatically tracks screen appearances and
/// time-on-screen. Emits `sdk:screen_appeared` (debug) on appear with the
/// given `screenName`, and `sdk:screen_disappeared` (debug) on disappear with
/// a `_duration_ms` attribute recording how long the screen was visible.
private struct PulseScreenModifier: ViewModifier {
    let screenName: String
    @State private var appearedAt: Date?

    func body(content: Content) -> some View {
        content
            .onAppear {
                appearedAt = Date()
                Pulse.debug("sdk:screen_appeared", screenName: screenName)
            }
            .onDisappear {
                let durationMs: String? = appearedAt.map { String(Int(Date().timeIntervalSince($0) * 1000)) }
                Pulse.debug("sdk:screen_disappeared", screenName: screenName, attributes: ["_duration_ms": durationMs])
                appearedAt = nil
            }
    }
}

public extension View {
    /// Automatically tracks screen appearances and time-on-screen.
    ///
    /// Attach to the outermost view of each screen:
    /// ```swift
    /// struct HomeView: View {
    ///     var body: some View {
    ///         VStack { ... }
    ///             .pulseScreen("Home")
    ///     }
    /// }
    /// ```
    ///
    /// On appear, emits an `sdk:screen_appeared` event with the given
    /// `screenName`. On disappear, emits `sdk:screen_disappeared` with
    /// a `_duration_ms` attribute recording how long the screen was visible.
    func pulseScreen(_ name: String) -> some View {
        modifier(PulseScreenModifier(screenName: name))
    }
}
#endif
