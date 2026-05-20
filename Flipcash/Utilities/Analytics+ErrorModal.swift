//
//  Analytics+ErrorModal.swift
//  Flipcash
//

import Foundation

extension Analytics {

    enum ErrorEvent: String, AnalyticsEvent {
        case modalDisplayed = "Error Modal Displayed"
    }

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
