//
//  PaymentRequestViewerStatus.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

/// Where the viewer stands on one request, as every deck card says it.
enum PaymentRequestViewerStatus: Hashable {
    case paid(share: String)
    case owes(share: String)
    case creator
    case noShare

    /// `viewer`'s standing on `request`, their share worded by `copy`. The creator reads as the creator
    /// whatever their own share says.
    init(request: GroupPaymentRequest, viewer: UserID?, copy: PaymentRequestCopy) {
        guard let viewer else { self = .noShare; return }
        guard viewer != request.creator else { self = .creator; return }
        guard let share = request.share(for: viewer) else { self = .noShare; return }
        let text = copy.shareText(share, of: request)
        self = share.isPaid ? .paid(share: text) : .owes(share: text)
    }

    /// Whether the card's glyph carries the paid badge.
    var showsPaidBadge: Bool {
        switch self {
        case .paid: true
        case .owes, .creator, .noShare: false
        }
    }

    /// The viewer's part of the line: "✓ You paid $5" or "You owe $5" in the success color, or
    /// "Your request". Nil with no share.
    var lead: AttributedString? {
        switch self {
        case .paid(let share):
            var lead = AttributedString("✓ You paid \(share)")
            lead.foregroundColor = Color.textSuccess
            return lead
        case .owes(let share):
            return Self.owedLead(share)
        case .creator:
            return AttributedString("Your request")
        case .noShare:
            return nil
        }
    }

    /// "You owe <share>" in the success color, which the owed strip leads with too.
    static func owedLead(_ share: String) -> AttributedString {
        var lead = AttributedString("You owe \(share)")
        lead.foregroundColor = Color.textSuccess
        return lead
    }

    /// The card's line: "<lead> · <amounts>", or `amounts` alone with no share.
    func line(amounts: String) -> AttributedString {
        guard let lead else { return AttributedString(amounts) }
        return lead + AttributedString(" · \(amounts)")
    }

    /// The viewer's part for a screen reader: "you paid $5". Nil with no share.
    var accessibilityText: String? {
        switch self {
        case .paid(let share): "you paid \(share)"
        case .owes(let share): "you owe \(share)"
        case .creator: "your request"
        case .noShare: nil
        }
    }
}

/// A card's viewer status line, dropping the amounts first when the whole line doesn't fit.
struct PaymentRequestViewerStatusLine: View {
    let status: PaymentRequestViewerStatus
    let amounts: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            Text(status.line(amounts: amounts))
            Text(status.lead ?? AttributedString(amounts))
        }
        .lineLimit(1)
        .truncationMode(.tail)
    }
}

extension View {
    /// Marks a request glyph `diameter` across as paid by the viewer: a success-colored check at its
    /// bottom-right, ringed in the card surface, grey on an ended request. Drawn as an overlay, so the
    /// glyph keeps its own frame and the badge moves and scales with it.
    func paidBadge(_ isShown: Bool, diameter: CGFloat, isEnded: Bool) -> some View {
        overlay(alignment: .bottomTrailing) {
            if isShown {
                let size = diameter * 10 / 26
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.55, weight: .heavy))
                    .foregroundStyle(Color.black)
                    .frame(width: size, height: size)
                    .background(isEnded ? Color.textSecondary : Color.success, in: .circle)
                    .padding(size * 0.12)
                    .background(Color.backgroundSecondary, in: .circle)
                    .offset(x: size * 0.3, y: size * 0.3)
                    .accessibilityHidden(true)
            }
        }
    }
}
