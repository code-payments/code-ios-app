//
//  TrayPage.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI

/// One step's body in a tray: a title, an optional message, and optional content under them.
public struct TrayPage<Content: View>: View {

    private let title: String?
    private let message: String?
    private let content: Content?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Creates a page with `content` under the title and message.
    public init(title: String, message: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title: title, message: message, content: content())
    }

    /// Creates a page of an optional message and `content`, for a step whose title sits in the
    /// tray's header (see ``TrayStack``'s `headerTitle`).
    public init(message: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title: nil, message: message, content: content())
    }

    /// Creates a page whose content may be absent, for ``Tray``.
    init(title: String?, message: String?, content: Content?) {
        self.title = title
        self.message = message
        self.content = content
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                Text(title)
                    // SF Pro until type tokens are decided (Phase 2).
                    .font(.system(size: TrayMetrics.scaled(TrayMetrics.titleSize, .title2, dynamicTypeSize), weight: TrayMetrics.titleWeight))
                    .tracking(TrayMetrics.titleTracking)
                    .foregroundStyle(Color.textMain)
                    .accessibilityAddTraits(.isHeader)
            }

            if let message {
                Text(message)
                    .font(.system(size: TrayMetrics.scaled(TrayMetrics.bodySize, .subheadline, dynamicTypeSize)))
                    .lineSpacing(TrayMetrics.bodyLineSpacing(dynamicTypeSize))
                    .trayBodyStyle(TrayMetrics.bodyStyle) // LOCAL-TUNER
                    .padding(.top, title == nil ? 0 : TrayMetrics.titleToBody)
            }

            if let content {
                content
                    .padding(.top, title == nil && message == nil ? 0 : TrayMetrics.bodyToContent)
            }
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .preference(key: TrayTitleKey.self, value: title)
    }
}

extension TrayPage where Content == EmptyView {

    /// Creates a page of a title and an optional message.
    public init(title: String, message: String? = nil) {
        self.init(title: title, message: message, content: nil)
    }
}

/// The title of the page on screen, which names the tray for VoiceOver and UI tests.
struct TrayTitleKey: PreferenceKey {
    static let defaultValue: String? = nil

    static func reduce(value: inout String?, nextValue: () -> String?) {
        value = nextValue() ?? value
    }
}

extension View {
    /// The body's ink: a flat colour, or vibrancy that lets the card's colour show through. // LOCAL-TUNER
    @ViewBuilder // LOCAL-TUNER
    func trayBodyStyle(_ style: TrayBodyStyle) -> some View { // LOCAL-TUNER
        switch style { // LOCAL-TUNER
        case .flat: // LOCAL-TUNER
            foregroundStyle(Color.textMain.opacity(TrayMetrics.bodyOpacity)) // LOCAL-TUNER
        case .vibrant: // LOCAL-TUNER
            // Dark-mode vibrancy: light ink added onto what's beneath it. // LOCAL-TUNER
            foregroundStyle(Color.white.opacity(TrayMetrics.bodyOpacity)).blendMode(.plusLighter) // LOCAL-TUNER
        case .hierarchical: // LOCAL-TUNER
            foregroundStyle(.secondary) // LOCAL-TUNER
        } // LOCAL-TUNER
    } // LOCAL-TUNER
} // LOCAL-TUNER
