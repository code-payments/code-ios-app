//
//  OnboardingFunnel.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

/// A step in the wallet onboarding funnel (Figma frame 8966:1516, ported from
/// Android's `OnboardingItem`).
enum OnboardingItem: Identifiable, Equatable {
    case addMoney(isCompleted: Bool)
    case scanTipCard(isCompleted: Bool)

    var id: String { title }

    var isCompleted: Bool {
        switch self {
        case .addMoney(let done), .scanTipCard(let done): return done
        }
    }

    var title: String {
        switch self {
        case .addMoney:    return "Add Money"
        case .scanTipCard: return "Scan a Tip Card"
        }
    }

    var subtitle: String {
        switch self {
        case .addMoney:    return "Add money to your account"
        case .scanTipCard: return "Give your first tip"
        }
    }
}

/// The "Send Your First Tip" onboarding funnel shown on the v2 Wallet: a title +
/// completed-count, then a card of tappable steps. Completed steps show a green
/// check, dim, and stop responding to taps. Ported from Android's
/// `OnboardingFunnel`.
struct OnboardingFunnelView: View {

    let title: String
    let items: [OnboardingItem]
    let onTap: (OnboardingItem) -> Void

    private var completedCount: Int { items.filter(\.isCompleted).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(title)
                    .font(.appTextLarge)
                    .foregroundStyle(Color.textMain)
                Spacer()
                Text("\(completedCount) / \(items.count)")
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(.horizontal, 16)

            VStack(spacing: 0) {
                ForEach(items) { item in
                    row(item)
                }
            }
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: Metrics.boxRadius, style: .continuous))
        }
    }

    private func row(_ item: OnboardingItem) -> some View {
        Button {
            onTap(item)
        } label: {
            HStack(spacing: 12) {
                icon(item)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.appTextMedium)
                        .foregroundStyle(Color.textMain)
                    Text(item.subtitle)
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textSecondary)
                }
                .opacity(item.isCompleted ? 0.38 : 1)

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(item.isCompleted)
    }

    @ViewBuilder private func icon(_ item: OnboardingItem) -> some View {
        if item.isCompleted {
            Image(systemName: "checkmark.circle.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color.Sentiment.positive)
        } else {
            switch item {
            case .addMoney:
                Image(systemName: "plus.circle")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.textMain)
            case .scanTipCard:
                Image("NavScan")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.textMain)
            }
        }
    }
}
