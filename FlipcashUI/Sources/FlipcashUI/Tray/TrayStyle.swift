//
//  TrayStyle.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI

/// The tone of a tray: a standard one, or one reporting a success or an error.
///
/// Success draws as standard. Error fades red down from the card's top edge, over a darker card
/// in dark, and draws the icon red.
public enum TrayStyle: Hashable, Sendable {
    /// Information, a decision or a confirmation.
    case standard
    /// Something finished as hoped.
    case success
    /// Something failed, or a warning before an action that can't be undone.
    case error
}

extension TrayStyle {

    /// Whether red fades down from the card's top edge.
    var fadesRed: Bool {
        switch self {
        case .standard, .success: false
        case .error: true
        }
    }

    /// The icon's colour.
    var iconColor: Color {
        switch self {
        case .standard, .success: .textSecondary
        case .error: .textError
        }
    }
}
