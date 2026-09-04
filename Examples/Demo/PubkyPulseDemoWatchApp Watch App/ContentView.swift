import SwiftUI
import PubkyPulse

struct ContentView: View {
    @State private var lastSent: String = "—"

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text("Pubky Pulse Watch Demo")
                    .font(.headline)
                Text("last: \(lastSent)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Button("Fire event") {
                    Pulse.track("watch_button_tap", attributes: ["source": "manual"])
                    lastSent = "single"
                }
                Button("Start workout (metric)") {
                    let op = Pulse.startOperation("watch-workout")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        op.complete()
                    }
                    lastSent = "workout"
                }
                Button("Log error") {
                    Pulse.error("watch_demo_error", attributes: ["scenario": "manual"])
                    lastSent = "error"
                }
                Button("Burst 25 events") {
                    for i in 0..<25 {
                        Pulse.track("watch_burst", attributes: ["index": "\(i)"])
                    }
                    lastSent = "burst×25"
                }
            }
            .padding()
        }
    }
}

#Preview {
    ContentView()
}
