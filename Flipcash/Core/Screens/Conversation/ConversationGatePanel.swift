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
/// Per node 10125:19197. The card is deliberately the same shape in all three gated states —
/// blocked, joinable, and read-only — because the user's question is the same in each ("what does
/// this chat want from me?"); only the sentence and the button change.
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

    /// Joins the chat from the ``ConversationGatePresentation/join`` state's button.
    let onJoin: () -> Void

    /// Whether a join is in flight; the button holds its title and stops taking taps.
    let isJoining: Bool

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

    /// The requirement this state is about, or nil when there is none to state — a chat with no
    /// rules still shows the panel to a non-member, with Join Chat and nothing above it.
    private var requirement: ConversationGateRequirement? {
        switch presentation {
        case .open, .undetermined:       nil
        case .join(let requirement):     requirement
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
        case .minimumBalance(let amount, let mint):
            let holding = requirementAmount(amount, mint: mint)
            switch presentation {
            case .readOnly:                               return "Minimum Balance to Send Messages: \(holding)"
            case .open, .undetermined, .join, .blocked:   return "Minimum Balance: \(holding)"
            }
        case .staff:
            switch presentation {
            case .readOnly:                               return "Only Flipcash staff can send messages here"
            case .open, .undetermined, .join, .blocked:   return "This chat is for Flipcash staff"
            }
        }
    }

    /// The requirement's amount, naming the token it has to be held in unless that token is the
    /// dollar one.
    ///
    /// Every requirement is denominated in dollars, so a dollar-token rule is already fully stated
    /// by the amount — spelling the token out as well reads as "$100 of $USDF". A rule naming any
    /// other token genuinely needs it: the same $100 is a different quantity of each.
    private func requirementAmount(_ amount: FiatAmount, mint: PublicKey?) -> String {
        let formatted = amount.formattedDroppingZeroFraction()
        guard mint != .usdf, let symbol else { return formatted }
        return "\(formatted) of $\(symbol)"
    }

    @ViewBuilder private var callToAction: some View {
        switch presentation {
        case .open, .undetermined:
            EmptyView()

        case .join:
            // The spinner is the whole of the in-flight state. There is no success hold to sit
            // through: `join` seats membership from the reply it gets back, so the gate has already
            // resolved to the composer by the time the call returns.
            Button(action: onJoin) {
                ButtonStateLabel("Join Chat", state: isJoining ? .loading : .normal)
            }
                .buttonStyle(.filled)
                .disabled(isJoining)

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
    /// satisfied by any holding, and a dollar-token one by adding cash, so both send the user to
    /// add cash rather than to a buy flow; a named mint whose metadata hasn't arrived yet still
    /// buys the right thing, it just can't say which.
    private func addFundsTitle(mint: PublicKey?) -> String {
        guard let mint, mint != .usdf else { return "Add Cash" }
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
