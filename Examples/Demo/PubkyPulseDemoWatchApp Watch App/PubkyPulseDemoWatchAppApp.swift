import SwiftUI
import PubkyPulse

@main
struct PubkyPulseDemoWatchApp_Watch_AppApp: App {
    init() {
        do {
            try Pulse.configure(
                endpoint: "http://localhost:4000",
                apiKey: "pulse_client_demo_000000000000000000000000000000000000000000"
            )
        } catch {
            print("Pubky Pulse configuration failed: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
