import Foundation
@testable import PubkyPulse

extension LogEvent {
    static func stub(
        message: String,
        level: PulseLogLevel = .info,
        screenName: String? = nil,
        customAttributes: [String: String]? = nil,
        userId: String? = nil
    ) -> LogEvent {
        LogEvent(
            clientEventId: UUID().uuidString,
            sessionId: "test-session-id",
            userId: userId,
            level: level,
            sourceModule: "Test.swift:test:1",
            message: message,
            screenName: screenName,
            customAttributes: customAttributes,
            environment: .ios,
            osVersion: "17.0.0",
            appVersion: "1.0",
            sdkName: PubkyPulseVersion.name,
            sdkVersion: PubkyPulseVersion.current,
            buildNumber: "1",
            deviceModel: "iPhone16,1",
            locale: "en_US",
            preferredLanguage: "en-US",
            supportedLanguages: ["en"],
            isDev: true,
            timestamp: "2026-01-01T00:00:00.000Z"
        )
    }
}
