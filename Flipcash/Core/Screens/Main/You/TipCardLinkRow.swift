//
//  TipCardLinkRow.swift
//  Flipcash
//

import SwiftUI
import UIKit
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

    /// The link with its scheme dropped and its identifier clipped to a stub,
    /// so a full-width uuid doesn't push the row's copy button off the edge.
    static func displayText(for url: URL) -> String {
        let stripped = url.absoluteString
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")

        guard let slash = stripped.lastIndex(of: "/") else { return stripped }

        let identifier = stripped[stripped.index(after: slash)...]
        guard identifier.count > identifierStubLength else { return stripped }

        return String(stripped[...slash]) + String(identifier.prefix(identifierStubLength)) + "…"
    }

    /// Leading characters of the identifier kept in the shortened link.
    private static let identifierStubLength = 5
}
