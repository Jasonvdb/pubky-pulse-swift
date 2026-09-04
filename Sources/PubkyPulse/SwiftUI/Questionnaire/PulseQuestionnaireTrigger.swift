import Foundation

/// A single condition that must hold for an auto-triggered questionnaire to
/// present. Conditions read from the persistent `PulseQuestionnaireState`
/// (launch / foreground counts) and a wall-clock `now`.
public enum PulseQuestionnaireCondition: Sendable, Equatable {
    /// Number of times `Pulse.configure(...)` has completed (one bump per process).
    case launches(atLeast: Int)
    /// Number of foreground transitions since install.
    case foregrounds(atLeast: Int)
    /// Days since the very first `Pulse.configure(...)` call.
    case daysSinceFirstLaunch(atLeast: Int)
    /// Hours since the very first `Pulse.configure(...)` call.
    case hoursSinceFirstLaunch(atLeast: Int)

    /// Pure evaluator used by the view modifier and unit tests.
    public func isSatisfied(state: PulseQuestionnaireState.Snapshot) -> Bool {
        switch self {
        case .launches(let n):
            return state.launchCount >= n
        case .foregrounds(let n):
            return state.foregroundCount >= n
        case .daysSinceFirstLaunch(let d):
            return state.daysSinceFirstLaunch() >= Double(d)
        case .hoursSinceFirstLaunch(let h):
            return state.hoursSinceFirstLaunch() >= Double(h)
        }
    }
}

/// A composable trigger for the `.pulseQuestionnaire(...)` view modifier. All
/// conditions are ANDed — if you want OR logic, use the `isEligible` closure
/// or split into two modifier applications. `.manual` opts out of auto-trigger
/// entirely.
public struct PulseQuestionnaireTrigger: Sendable, Equatable {
    public let conditions: [PulseQuestionnaireCondition]
    public let isManual: Bool

    /// Never auto-trigger. The consumer drives presentation directly via
    /// `PulseQuestionnaireView` or by binding to a `@State` flag.
    public static let manual = PulseQuestionnaireTrigger(conditions: [], isManual: true)

    /// Shortcut for `.launches(atLeast: 1)` — fire on first launch.
    public static let afterLaunch = PulseQuestionnaireTrigger(
        conditions: [.launches(atLeast: 1)],
        isManual: false
    )

    /// Shortcut for `.launches(atLeast: n)`.
    public static func afterLaunches(_ n: Int) -> PulseQuestionnaireTrigger {
        PulseQuestionnaireTrigger(conditions: [.launches(atLeast: n)], isManual: false)
    }

    /// Composable form — ALL conditions must evaluate true (ANDed). An empty
    /// argument list means "always", which combined with `isEligible` is the
    /// hook for fully custom gating.
    public static func when(_ conditions: PulseQuestionnaireCondition...) -> PulseQuestionnaireTrigger {
        PulseQuestionnaireTrigger(conditions: conditions, isManual: false)
    }

    /// Evaluate against a state snapshot. Returns true only when every
    /// condition is satisfied; `.manual` always returns false (handled
    /// separately by the modifier).
    public func isSatisfied(state: PulseQuestionnaireState.Snapshot) -> Bool {
        if isManual { return false }
        for c in conditions {
            if !c.isSatisfied(state: state) { return false }
        }
        return true
    }
}
