import Foundation

/// User-facing strings rendered by the questionnaire flow. Same convention as
/// `PulseFeedbackStrings` — every field is a `LocalizedStringResource` so
/// defaults flow through the SDK's bundled string catalog while callers can
/// override individual entries via `.default.with(...)`.
public struct PulseQuestionnaireStrings: Sendable {
    // Phase: running flow (questions + nav)
    public var title: LocalizedStringResource
    public var loadingTitle: LocalizedStringResource
    public var submitButton: LocalizedStringResource
    public var submittingButton: LocalizedStringResource
    public var skipButton: LocalizedStringResource
    public var nextButton: LocalizedStringResource
    public var backButton: LocalizedStringResource
    public var doneButton: LocalizedStringResource
    public var cancelButton: LocalizedStringResource

    // Phase: consent (small detent)
    public var consentTitle: LocalizedStringResource
    public var consentBody: LocalizedStringResource
    public var consentAccept: LocalizedStringResource
    public var consentLater: LocalizedStringResource
    public var consentNever: LocalizedStringResource

    // Global dismiss confirmation (still used; reused from consent "never" path)
    public var doNotShowAgain: LocalizedStringResource
    public var doNotShowAgainConfirmTitle: LocalizedStringResource
    public var doNotShowAgainConfirmMessage: LocalizedStringResource
    public var doNotShowAgainConfirmAction: LocalizedStringResource
    public var doNotShowAgainCancel: LocalizedStringResource

    // Misc
    public var requiredLabel: LocalizedStringResource
    public var successTitle: LocalizedStringResource
    public var successBody: LocalizedStringResource
    public var errorTitle: LocalizedStringResource
    public var errorRequiredMissing: LocalizedStringResource
    public var errorGeneric: LocalizedStringResource
    public var npsLowLabel: LocalizedStringResource
    public var npsHighLabel: LocalizedStringResource

    public init(
        title: LocalizedStringResource = .init("owl.questionnaire.title", defaultValue: "Quick survey", bundle: .atURL(PubkyPulseBundle.resources.bundleURL)),
        loadingTitle: LocalizedStringResource = .init("owl.questionnaire.loading", defaultValue: "Loading…", bundle: .atURL(PubkyPulseBundle.resources.bundleURL)),
        submitButton: LocalizedStringResource = .init("owl.questionnaire.submit", defaultValue: "Submit", bundle: .atURL(PubkyPulseBundle.resources.bundleURL)),
        submittingButton: LocalizedStringResource = .init("owl.questionnaire.submitting", defaultValue: "Sending…", bundle: .atURL(PubkyPulseBundle.resources.bundleURL)),
        skipButton: LocalizedStringResource = .init("owl.questionnaire.skip", defaultValue: "Not now", bundle: .atURL(PubkyPulseBundle.resources.bundleURL)),
        nextButton: LocalizedStringResource = .init("owl.questionnaire.button.next", defaultValue: "Next", bundle: .atURL(PubkyPulseBundle.resources.bundleURL)),
        backButton: LocalizedStringResource = .init("owl.questionnaire.button.back", defaultValue: "Back", bundle: .atURL(PubkyPulseBundle.resources.bundleURL)),
        doneButton: LocalizedStringResource = .init("owl.questionnaire.button.done", defaultValue: "Done", bundle: .atURL(PubkyPulseBundle.resources.bundleURL)),
        cancelButton: LocalizedStringResource = .init("owl.questionnaire.button.cancel", defaultValue: "Cancel", bundle: .atURL(PubkyPulseBundle.resources.bundleURL)),
        consentTitle: LocalizedStringResource = .init("owl.questionnaire.consent.title", defaultValue: "Quick favor?", bundle: .atURL(PubkyPulseBundle.resources.bundleURL)),
        consentBody: LocalizedStringResource = .init("owl.questionnaire.consent.body", defaultValue: "We'd love a few minutes of your feedback to help us improve.", bundle: .atURL(PubkyPulseBundle.resources.bundleURL)),
        consentAccept: LocalizedStringResource = .init("owl.questionnaire.consent.accept", defaultValue: "Sure, happy to help", bundle: .atURL(PubkyPulseBundle.resources.bundleURL)),
        consentLater: LocalizedStringResource = .init("owl.questionnaire.consent.later", defaultValue: "Maybe later", bundle: .atURL(PubkyPulseBundle.resources.bundleURL)),
        consentNever: LocalizedStringResource = .init("owl.questionnaire.consent.never", defaultValue: "Don't ask again", bundle: .atURL(PubkyPulseBundle.resources.bundleURL)),
        doNotShowAgain: LocalizedStringResource = .init("owl.questionnaire.dismiss", defaultValue: "Don't show again", bundle: .atURL(PubkyPulseBundle.resources.bundleURL)),
        doNotShowAgainConfirmTitle: LocalizedStringResource = .init("owl.questionnaire.dismiss.confirm.title", defaultValue: "Don't show questionnaires?", bundle: .atURL(PubkyPulseBundle.resources.bundleURL)),
        doNotShowAgainConfirmMessage: LocalizedStringResource = .init("owl.questionnaire.dismiss.confirm.message", defaultValue: "We won't ask you to fill in another questionnaire.", bundle: .atURL(PubkyPulseBundle.resources.bundleURL)),
        doNotShowAgainConfirmAction: LocalizedStringResource = .init("owl.questionnaire.dismiss.confirm.action", defaultValue: "Don't show again", bundle: .atURL(PubkyPulseBundle.resources.bundleURL)),
        doNotShowAgainCancel: LocalizedStringResource = .init("owl.questionnaire.dismiss.cancel", defaultValue: "Keep showing", bundle: .atURL(PubkyPulseBundle.resources.bundleURL)),
        requiredLabel: LocalizedStringResource = .init("owl.questionnaire.required", defaultValue: "Required", bundle: .atURL(PubkyPulseBundle.resources.bundleURL)),
        successTitle: LocalizedStringResource = .init("owl.questionnaire.success.title", defaultValue: "Thanks!", bundle: .atURL(PubkyPulseBundle.resources.bundleURL)),
        successBody: LocalizedStringResource = .init("owl.questionnaire.success.body", defaultValue: "Your answers help us improve.", bundle: .atURL(PubkyPulseBundle.resources.bundleURL)),
        errorTitle: LocalizedStringResource = .init("owl.questionnaire.error.title", defaultValue: "Couldn't send response", bundle: .atURL(PubkyPulseBundle.resources.bundleURL)),
        errorRequiredMissing: LocalizedStringResource = .init("owl.questionnaire.error.required", defaultValue: "Please answer the required questions.", bundle: .atURL(PubkyPulseBundle.resources.bundleURL)),
        errorGeneric: LocalizedStringResource = .init("owl.questionnaire.error.generic", defaultValue: "Something went wrong. Please try again.", bundle: .atURL(PubkyPulseBundle.resources.bundleURL)),
        npsLowLabel: LocalizedStringResource = .init("owl.questionnaire.nps.low", defaultValue: "Not at all likely", bundle: .atURL(PubkyPulseBundle.resources.bundleURL)),
        npsHighLabel: LocalizedStringResource = .init("owl.questionnaire.nps.high", defaultValue: "Extremely likely", bundle: .atURL(PubkyPulseBundle.resources.bundleURL))
    ) {
        self.title = title
        self.loadingTitle = loadingTitle
        self.submitButton = submitButton
        self.submittingButton = submittingButton
        self.skipButton = skipButton
        self.nextButton = nextButton
        self.backButton = backButton
        self.doneButton = doneButton
        self.cancelButton = cancelButton
        self.consentTitle = consentTitle
        self.consentBody = consentBody
        self.consentAccept = consentAccept
        self.consentLater = consentLater
        self.consentNever = consentNever
        self.doNotShowAgain = doNotShowAgain
        self.doNotShowAgainConfirmTitle = doNotShowAgainConfirmTitle
        self.doNotShowAgainConfirmMessage = doNotShowAgainConfirmMessage
        self.doNotShowAgainConfirmAction = doNotShowAgainConfirmAction
        self.doNotShowAgainCancel = doNotShowAgainCancel
        self.requiredLabel = requiredLabel
        self.successTitle = successTitle
        self.successBody = successBody
        self.errorTitle = errorTitle
        self.errorRequiredMissing = errorRequiredMissing
        self.errorGeneric = errorGeneric
        self.npsLowLabel = npsLowLabel
        self.npsHighLabel = npsHighLabel
    }

    public static let `default` = PulseQuestionnaireStrings()

    public func with(
        title: LocalizedStringResource? = nil,
        submitButton: LocalizedStringResource? = nil,
        skipButton: LocalizedStringResource? = nil,
        nextButton: LocalizedStringResource? = nil,
        backButton: LocalizedStringResource? = nil,
        doneButton: LocalizedStringResource? = nil,
        cancelButton: LocalizedStringResource? = nil,
        consentTitle: LocalizedStringResource? = nil,
        consentBody: LocalizedStringResource? = nil,
        consentAccept: LocalizedStringResource? = nil,
        consentLater: LocalizedStringResource? = nil,
        consentNever: LocalizedStringResource? = nil,
        doNotShowAgain: LocalizedStringResource? = nil,
        successTitle: LocalizedStringResource? = nil,
        successBody: LocalizedStringResource? = nil,
        errorTitle: LocalizedStringResource? = nil,
        errorRequiredMissing: LocalizedStringResource? = nil,
        errorGeneric: LocalizedStringResource? = nil,
        npsLowLabel: LocalizedStringResource? = nil,
        npsHighLabel: LocalizedStringResource? = nil
    ) -> PulseQuestionnaireStrings {
        var copy = self
        if let title { copy.title = title }
        if let submitButton { copy.submitButton = submitButton }
        if let skipButton { copy.skipButton = skipButton }
        if let nextButton { copy.nextButton = nextButton }
        if let backButton { copy.backButton = backButton }
        if let doneButton { copy.doneButton = doneButton }
        if let cancelButton { copy.cancelButton = cancelButton }
        if let consentTitle { copy.consentTitle = consentTitle }
        if let consentBody { copy.consentBody = consentBody }
        if let consentAccept { copy.consentAccept = consentAccept }
        if let consentLater { copy.consentLater = consentLater }
        if let consentNever { copy.consentNever = consentNever }
        if let doNotShowAgain { copy.doNotShowAgain = doNotShowAgain }
        if let successTitle { copy.successTitle = successTitle }
        if let successBody { copy.successBody = successBody }
        if let errorTitle { copy.errorTitle = errorTitle }
        if let errorRequiredMissing { copy.errorRequiredMissing = errorRequiredMissing }
        if let errorGeneric { copy.errorGeneric = errorGeneric }
        if let npsLowLabel { copy.npsLowLabel = npsLowLabel }
        if let npsHighLabel { copy.npsHighLabel = npsHighLabel }
        return copy
    }
}
