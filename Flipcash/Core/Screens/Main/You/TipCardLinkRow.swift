//
//  TipCardLinkRow.swift
//  Flipcash
//

import SwiftUI
import UIKit
import FlipcashCore
import FlipcashUI

/// The tip-card link row (Figma node 9276:4748): a chain-link glyph, the
/// shortened public link, and a copy button that flips to a checkmark for a
/// beat after copying.
///
/// Owns the copy itself so the caller only supplies the URL.
struct TipCardLinkRow: View {

    let url: URL

    /// How long the copy button stays on the checkmark before reverting.
    private static let confirmationDuration: Duration = .seconds(1.5)

    @State private var didCopy = false

    var body: some View {
        Button(action: copy) {
            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image.asset(.chainLink)
                        .renderingMode(.template)
                        .frame(width: 20, height: 20)

                    Text(Self.displayText(for: url))
                        .font(.appTextMedium)
                        .lineLimit(1)
                        // Elides only when the handle genuinely doesn't fit —
                        // no shrinking to dodge it, which would render the row
                        // at a smaller size than the ones around it. The forced
                        // clip in `displayText` is for the uuid form alone; a
                        // handle keeps every character it has room for and
                        // loses the tail only past that. On the narrowest
                        // supported screen (375pt) the budget is 257pt, which
                        // covered a 15-character handle of average width even
                        // under the four-character-longer `app.flipcash.com`;
                        // the apex host only widens that margin.
                        .truncationMode(.tail)
                }

                Spacer(minLength: 8)

                Group {
                    if didCopy {
                        Image.system(.circleCheck)
                            .renderingMode(.template)
                    } else {
                        Image.asset(.squareBehindSquare)
                            .renderingMode(.template)
                    }
                }
                .frame(width: 20, height: 20)
            }
            .foregroundStyle(Color.textMain)
            .opacity(0.7)
            .padding(.horizontal, 12)
            .frame(height: 40)
            .frame(maxWidth: .infinity)
            .background(Color.backgroundRow, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Copy tip card link")
        .accessibilityIdentifier("you-copy-link-button")
    }

    private func copy() {
        UIPasteboard.general.string = url.absoluteString
        withAnimation(.easeInOut(duration: 0.15)) {
            didCopy = true
        }
        Task {
            try? await Task.sleep(for: Self.confirmationDuration)
            withAnimation(.easeInOut(duration: 0.15)) {
                didCopy = false
            }
        }
    }

    /// The link with its scheme dropped, and a uuid identifier clipped to a
    /// stub so a full-width one doesn't push the row's copy button off the edge.
    ///
    /// A claimed handle is never clipped here. It is at most 15 characters —
    /// shorter than the `/tip/` segment it replaces — so it is handed to the
    /// layout whole and elides only if it truly overruns the row.
    static func displayText(for url: URL) -> String {
        let stripped = url.absoluteString
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")

        guard let slash = stripped.lastIndex(of: "/") else { return stripped }

        let identifier = stripped[stripped.index(after: slash)...]
        guard identifier.count > identifierStubLength, Username(String(identifier)) == nil else {
            return stripped
        }

        return String(stripped[...slash]) + String(identifier.prefix(identifierStubLength)) + "…"
    }

    /// Leading characters of the identifier kept in the shortened link.
    private static let identifierStubLength = 5
}
