//
//  Analytics+ErrorModal.swift
//  Flipcash
//

import Foundation

extension Analytics {

    enum ErrorEvent: String, AnalyticsEvent {
        case modalDisplayed = "Error Modal Displayed"
    }

    /// Ports the Android `displayedErrorModal(...)` Mixpanel event. Fires once
    /// per visible error dialog. `title` and `message` empty-string-default so
    /// the keys are always present on the event for analytics queries.
    static func errorModalDisplayed(
        title: String?,
        message: String?,
        screen: String?,
        callSite: String?
    ) {
        var properties: [Property: AnalyticsValue] = [
            .title: title ?? "",
            .message: message ?? "",
        ]
        if let screen { properties[.screen] = screen }
        if let callSite { properties[.callSite] = callSite }
        track(event: ErrorEvent.modalDisplayed, properties: properties)
    }
}
