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

    /// Display name of the requirement's mint, once resolved. Nil for a requirement that names no
    /// mint — it applies across every holding — and until the metadata lookup lands, so the copy
    /// drops the "of X" clause rather than printing a placeholder.
    let mintName: String?

    /// How much more the user must hold to meet a minimum-balance requirement, in its currency.
    /// Nil when there is none to buy or no rate can state it, and the button falls back to a
    /// bare Buy More / Add Cash.
    let shortfall: FiatAmount?

    /// Opens the buy flow for the requirement's mint, or add-cash when the requirement spans every
    /// mint. Never called for ``ConversationGateRequirement/staff``, which has no button.
    let onAddFunds: () -> Void

    /// Joins the chat from the ``ConversationGatePresentation/join`` state's button.
    let onJoin: () -> Void

    /// Whether a join is in flight; the button holds its title and stops taking taps.
    let isJoining: Bool

    var body: some View {
        if case .readOnly(let requirement) = presentation, requirement.isStaticReadOnly, let sentence {
            readOnlyPill(sentence)
        } else {
            card
        }
    }

    /// A rule the viewer can do nothing about (`never`, `creator`, `unsupported`; node 10588:1969): the
    /// composer's place is taken by a disabled, full-width rounded rectangle of glass with one muted
    /// line — no field, no controls, no action. For `never` the brand is named, not the chat, because
    /// that rule is what the welcome chat runs on.
    private func readOnlyPill(_ sentence: String) -> some View {
        Text(sentence)
            .font(.appTextMedium)
            .foregroundStyle(Color.textMain.opacity(Layout.pillTextOpacity))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity)
            .frame(height: BarMetrics.contentHeight)
            .padding(.horizontal, BarMetrics.edgeInset)
            .modifier(ReadOnlyPillGlass())
            .padding(.horizontal, BarMetrics.compactInset)
            .padding(.vertical, BarMetrics.contentPadding)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(sentence))
            .accessibilityAddTraits(.isStaticText)
    }

    /// The pill's surface: non-interactive glass at `Metrics.boxRadius`, darkened to the design's fill
    /// (node 10588:1969 draws 46% of a near-black; `backgroundMain` is the nearest token). Below iOS 26
    /// the same fill lies over the standard ultra-thin material.
    private struct ReadOnlyPillGlass: ViewModifier {
        func body(content: Content) -> some View {
            let shape = RoundedRectangle(cornerRadius: Metrics.boxRadius)
            let fill = Color.backgroundMain.opacity(Layout.pillFillOpacity)
            if #available(iOS 26, *) {
                content.glassEffect(.regular.tint(fill), in: shape)
            } else {
                content
                    .background(fill, in: shape)
                    .background(.ultraThinMaterial, in: shape)
            }
        }
    }

    static let neverSentence = "Only Flipcash can send messages"
    static let creatorSentence = "Only the creator can send messages"
    static let unsupportedSentence = "Update Flipcash to send messages"

    private var card: some View {
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
            // Frosted like Android's card: the transcript scrolling behind it blurs, tinted toward
            // the screen so the line stays readable.
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Color.backgroundMain.opacity(0.3)
                Color.backgroundRow
            }
            .clipShape(.rect(cornerRadius: Metrics.boxRadius))
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
            case .readOnly:                               return "\(holding) Required to Chat"
            case .open, .undetermined, .join, .blocked:   return "\(holding) Required to Join"
            }
        case .staff:
            switch presentation {
            case .readOnly:                               return "Only Flipcash staff can send messages here"
            case .open, .undetermined, .join, .blocked:   return "This chat is for Flipcash staff"
            }
        case .never:
            // Drawn as the composer-shaped pill instead of this card; see ``readOnlyPill(_:)``.
            return Self.neverSentence
        case .creator:
            // Drawn as the pill too.
            return Self.creatorSentence
        case .unsupported:
            return Self.unsupportedSentence
        }
    }

    /// The requirement's amount, naming the token it has to be held in unless that token is the
    /// dollar one.
    ///
    /// Every requirement is denominated in dollars, so a dollar-token rule is already fully stated
    /// by the amount — spelling the token out as well says the same thing twice. A rule naming any
    /// other token genuinely needs it: the same $100 is a different quantity of each.
    private func requirementAmount(_ amount: FiatAmount, mint: PublicKey?) -> String {
        let formatted = amount.formattedDroppingZeroFraction()
        guard mint != .usdf, let mintName else { return formatted }
        return "\(formatted) of \(mintName)"
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
                ButtonStateLabel("Join", state: isJoining ? .loading : .normal)
            }
                .buttonStyle(.filled)
                .disabled(isJoining)

        case .blocked(let requirement), .readOnly(let requirement):
            switch requirement {
            case .minimumBalance(_, let mint):
                Button(addFundsTitle(mint: mint), action: onAddFunds)
                    .accessibilityIdentifier("conversation-gate-add-funds")
                    .buttonStyle(.filled)
            case .staff, .never, .creator, .unsupported:
                // Nothing the user can do about being staff, about a chat nobody may post in, or about not being its creator,
                // so a button here would be a lie.
                EmptyView()
            }
        }
    }

    /// Names the action in the token the chat asks for. A requirement spanning every mint is
    /// satisfied by any holding, and a dollar-token one by adding cash, so both send the user to
    /// add cash rather than to a buy flow; a named mint whose metadata hasn't arrived yet still
    /// buys the right thing, it just can't say which.
    private func addFundsTitle(mint: PublicKey?) -> String {
        let action: String
        switch presentation {
        case .readOnly:                               action = "Chat"
        case .open, .undetermined, .join, .blocked:   action = "Join"
        }
        let amount = shortfall?.formatted()
        guard let mint, mint != .usdf else {
            guard let amount else { return "Add Cash" }
            return "Add \(amount) to \(action)"
        }
        switch (amount, mintName) {
        case let (amount?, name?):  return "Buy \(amount) of \(name) to \(action)"
        case let (amount?, nil):    return "Buy \(amount) to \(action)"
        case let (nil, name?):      return "Buy More \(name)"
        case (nil, nil):            return "Buy More"
        }
    }

    /// Node 10125:19197 — a 356pt card in a 402pt frame, 12pt above its contents and 6pt around
    /// the rest, with 12pt between the sentence and the button.
    private enum Layout {
        static let screenInset: CGFloat = 23
        static let cardTopPadding: CGFloat = 12
        static let cardPadding: CGFloat = 6
        static let gap: CGFloat = 12
        /// The pill's line, muted as the design draws it (node 10588:1969).
        static let pillTextOpacity: Double = 0.4
        static let pillFillOpacity: Double = 0.46
    }
}

private extension ConversationGateRequirement {
    /// Whether the read-only state is drawn as the composer-shaped pill: the ones with no action.
    var isStaticReadOnly: Bool {
        switch self {
        case .never, .creator, .unsupported:  true
        case .minimumBalance, .staff:         false
        }
    }
}
