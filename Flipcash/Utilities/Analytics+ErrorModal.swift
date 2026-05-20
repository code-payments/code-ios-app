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
    /// per visible error dialog. `title` and `message` are non-optional —
    /// every `.error` factory requires both, so the parameters can't be nil.
    static func errorModalDisplayed(
        title: String,
        message: String,
        screen: String?,
        callSite: String?
    ) {
        var properties: [Property: AnalyticsValue] = [
            .title: title,
            .message: message,
        ]
        if let screen { properties[.screen] = screen }
        if let callSite { properties[.callSite] = callSite }
        track(event: ErrorEvent.modalDisplayed, properties: properties)
    }
}
