//
//  ConversationGatePanel.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// The card that stands in for the composer when the signed-in user may not take part in a group
/// chat: it names the rule the chat runs on, and offers the one action that can change the answer.
///
/// Per node 10125:19197. The card is deliberately the same shape in both gated states — blocked
/// and read-only — because the user's question is the same in each ("what does this chat want from
/// me?"); only the sentence and the button change.
struct ConversationGatePanel: View {

    /// What the gate resolved to. ``ConversationGatePresentation/open`` renders nothing; the caller
    /// shows the composer instead.
    let presentation: ConversationGatePresentation

    /// Ticker for the requirement's mint, once resolved. Nil for a requirement that names no mint —
    /// it applies across every holding — and until the metadata lookup lands, so the copy drops the
    /// "of $X" clause rather than printing a placeholder.
    let symbol: String?

    /// Opens the buy flow for the requirement's mint, or add-cash when the requirement spans every
    /// mint. Never called for ``ConversationGateRequirement/staff``, which has no button.
    let onAddFunds: () -> Void

    var body: some View {
        VStack(spacing: Layout.gap) {
            if let sentence {
                Text(sentence)
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textMain.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            callToAction
        }
        .padding(.top, Layout.cardTopPadding)
        .padding(.horizontal, Layout.cardPadding)
        .padding(.bottom, Layout.cardPadding)
        .background {
            RoundedRectangle(cornerRadius: Metrics.boxRadius)
                .fill(Color.backgroundRow)
        }
        .padding(.horizontal, Layout.screenInset)
        .padding(.vertical, BarMetrics.contentPadding)
    }

    /// The requirement this state is about, or nil when the chat is ungated and the panel is not
    /// on screen at all.
    private var requirement: ConversationGateRequirement? {
        switch presentation {
        case .open:                      nil
        case .blocked(let requirement):  requirement
        case .readOnly(let requirement): requirement
        }
    }

    /// The rule stated in the chat's own terms. Read-only phrases it as a sending requirement,
    /// since the user is already reading — saying "Minimum Balance" alone would read as a lie about
    /// the transcript they can see.
    private var sentence: String? {
        guard let requirement else { return nil }
        switch requirement {
        case .minimumBalance(let amount, _):
            let holding = symbol.map { "\(amount.formattedDroppingZeroFraction()) of $\($0)" }
                ?? amount.formattedDroppingZeroFraction()
            switch presentation {
            case .readOnly:          return "Minimum Balance to Send Messages: \(holding)"
            case .open, .blocked:    return "Minimum Balance: \(holding)"
            }
        case .staff:
            switch presentation {
            case .readOnly:          return "Only Flipcash staff can send messages here"
            case .open, .blocked:    return "This chat is for Flipcash staff"
            }
        }
    }

    @ViewBuilder private var callToAction: some View {
        switch presentation {
        case .open:
            EmptyView()

        case .blocked(let requirement), .readOnly(let requirement):
            switch requirement {
            case .minimumBalance(_, let mint):
                Button(addFundsTitle(mint: mint), action: onAddFunds)
                    .buttonStyle(.filled)
            case .staff:
                // Nothing the user can do about being staff, so a button here would be a lie.
                EmptyView()
            }
        }
    }

    /// Names the action in the token the chat asks for. A requirement spanning every mint is
    /// satisfied by any holding, so it sends the user to add cash instead of to one token's buy
    /// flow; a named mint whose metadata hasn't arrived yet still buys the right thing, it just
    /// can't say which.
    private func addFundsTitle(mint: PublicKey?) -> String {
        guard mint != nil else { return "Add Cash" }
        guard let symbol else { return "Buy More" }
        return "Buy More $\(symbol)"
    }

    /// Node 10125:19197 — a 356pt card in a 402pt frame, 12pt above its contents and 6pt around
    /// the rest, with 12pt between the sentence and the button.
    private enum Layout {
        static let screenInset: CGFloat = 23
        static let cardTopPadding: CGFloat = 12
        static let cardPadding: CGFloat = 6
        static let gap: CGFloat = 12
    }
}
