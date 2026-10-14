//
//  AttachEvent.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore

/// The one log label for the attach surface, whichever host draws it.
let attachLogger = Logger(label: "flipcash.attach")

/// Where the attach panel and its cards are drawn while an event arrives.
enum AttachHost: Equatable {
    /// In the bottom bar, with the keyboard down.
    case bar

    /// In the keyboard's own window, over the keys.
    case keyboardWindow

    /// In a backdrop that replaced the composer's input view.
    case inputView
}

/// Something outside the attach surface that may take the panel or card down.
enum AttachEvent: Equatable {
    /// The composer's draft text changed.
    case draftChanged

    /// The composer started editing a sent message.
    case editBegan

    /// The composer's field gained focus.
    case fieldFocused

    /// The composer's field lost focus.
    case fieldBlurred

    /// The app left the foreground.
    case appBackgrounded

    /// The keyboard announced it is going down.
    case keyboardWillHide

    /// The keyboard's window could not be found again after the keyboard rebuilt its view tree.
    case keyboardWindowLost

    /// What this event does to the attach surface drawn in `host`.
    func response(in host: AttachHost) -> AttachEventResponse {
        switch self {
        case .draftChanged:
            return .dismissPanel
        case .editBegan:
            return .clearForEdit
        case .fieldFocused:
            // Focusing the field uncovers the send end the panel covers. Over the keyboard the field
            // is already focused.
            return host == .bar ? .dismissPanel : .none
        case .fieldBlurred, .appBackgrounded:
            // The bar's panel doesn't depend on the keyboard or the foreground.
            return host == .bar ? .none : .reset
        case .keyboardWillHide:
            // The input view swap announces the keyboard going and coming; focus loss covers it.
            return host == .keyboardWindow ? .reset : .none
        case .keyboardWindowLost:
            return host == .bar ? .none : .reset
        }
    }
}

/// What an `AttachEvent` does to the attach surface.
enum AttachEventResponse: Equatable {
    /// Nothing.
    case none

    /// The panel animates down if it's open; an open card stays.
    case dismissPanel

    /// The card closes at once and the panel animates down: an edit takes `+`'s slot.
    case clearForEdit

    /// The panel and the card go at once, with nothing to animate out.
    case reset
}

extension ConversationBarModel {
    /// Applies what `event` does to the attach surface drawn in `host`, and returns it so the
    /// overlay can tear itself down on a `.reset`.
    @discardableResult
    func handle(_ event: AttachEvent, in host: AttachHost) -> AttachEventResponse {
        let response = event.response(in: host)
        if response != .none, attachPanel.isOpen || attachCard.isOpen {
            attachLogger.info("Attach event", metadata: [
                "event": "\(event)",
                "host": "\(host)",
                "response": "\(response)",
            ])
        }
        switch response {
        case .none:
            break
        case .dismissPanel:
            guard attachPanel.isOpen else { break }
            attachPanel.animate { $0.dismiss() }
        case .clearForEdit:
            if attachCard.isOpen {
                attachCard.close()
                attachCard.exitDidFinish()
            }
            if attachPanel.isOpen {
                attachPanel.animate { $0.dismiss() }
            }
        case .reset:
            resetAttach()
        }
        return response
    }
}
