//
//  PoolDetailsScreen.swift
//  Code
//
//  Created by Dima Bart on 2025-06-18.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

struct PoolDetailsScreen: View {
    
    @ObservedObject private var viewModel: PoolViewModel
    
    @StateObject private var updateablePool: Updateable<StoredPool?>
    @StateObject private var updateableBets: Updateable<[StoredBet]>
    
    @State private var showingConfirmationForBetOutcome: PoolResoltion?
    @State private var showingDeclareOutcome: PoolResoltion?
    
    @State private var dialogItem: DialogItem?
    
    private let userID: UserID
    private let poolID: PublicKey
    private let database: Database
    
    private var pool: StoredPool? {
        updateablePool.value
    }
    
    private var bets: [StoredBet] {
        updateableBets.value
    }
    
    private var isHost: Bool {
        pool?.creatorUserID == userID
    }
    
    private var hasResolution: Bool {
        pool?.resolution != nil
    }
    
    private var userBet: StoredBet? {
        // Disregard existing user bets that
        // are not fulfilled. Subsequent bet
        // will replace existing ones
        bets.filter { $0.isFulfilled && $0.userID == userID }.first
    }
    
    private var hasUserBet: Bool {
        userBet != nil
    }
    
    private var countOnYes: Int {
        pool?.betCountYes ?? 0
    }
    
    private var countOnNo: Int {
        pool?.betCountNo ?? 0
    }
    
    private var winningsForYes: Fiat {
        pool?.winningsForYes ?? 0
    }
    
    private var winningsForNo: Fiat {
        pool?.winningsForNo ?? 0
    }
    
    private var amountOnYes: Fiat {
        pool?.amountOnYes ?? 0
    }
    
    private var amountOnNo: Fiat {
        pool?.amountOnNo ?? 0
    }
    
    private var amountInPool: Fiat {
        pool?.amountInPool ?? 0
    }
    
    private var buyIn: Fiat {
        pool?.buyIn ?? 0
    }
    
    private var stateForYes: VoteButton.State {
        if let resoltion = pool?.resolution {
            if resoltion == .yes {
                .winner
            } else {
                .normal
            }
        } else if let userBet, userBet.selectedOutcome == .yes {
            .selected
        } else {
            .normal
        }
    }
    
    private var stateForNo: VoteButton.State {
        if let resoltion = pool?.resolution {
            if resoltion == .no {
                .winner
            } else {
                .normal
            }
        } else if let userBet, userBet.selectedOutcome == .no {
            .selected
        } else {
            .normal
        }
    }
    
    // MARK: - Init -
    
    init(userID: UserID, poolID: PublicKey, database: Database, viewModel: PoolViewModel) {
        self.userID    = userID
        self.poolID    = poolID
        self.database  = database
        self.viewModel = viewModel
        
        _updateablePool = .init(wrappedValue: Updateable {
            try? database.getPool(poolID: poolID)
        })
        
        _updateableBets = .init(wrappedValue: Updateable {
            (try? database.getBets(poolID: poolID)) ?? []
        })
    }
    
    // MARK: - Body -
    
    var body: some View {
        Background(color: .backgroundMain) {
            if let pool {
                poolDetails(pool: pool)
            } else {
                VStack {
                    LoadingView(color: .white)
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .dialog(item: $dialogItem)
    }
    
    @ViewBuilder private func poolDetails(pool: StoredPool) -> some View {
        VStack {
            Spacer()
            
            Text(pool.name)
                .font(.appTextXL)
                .foregroundStyle(Color.textMain)
            
            Spacer()
                
            VStack(spacing: 10) {
                AmountText(
                    flagStyle: amountInPool.currencyCode.flagStyle,
                    content: amountInPool.formatted(suffix: nil),
                    showChevron: false,
                    canScale: false
                )
                .font(.appDisplayMedium)
                .foregroundStyle(Color.textMain)
                
                Text(hasResolution ? "was in pool" : "in pool so far")
                    .font(.appTextLarge)
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 30)
            
            Spacer()
            
            VStack(spacing: 0) {
                HStack {
                    VStack(spacing: 0) {
                        VoteButton(
                            state: stateForYes,
                            name: "Yes",
                            fiat: amountOnYes,
                        ) {
                            showingConfirmationForBetOutcome = .yes
                        }
                        .disabled(hasUserBet)
                        .zIndex(1)
                        
                        YouVotedBadge()
                            .offset(y: -Metrics.boxRadius)
                            .zIndex(0)
                            .opacity(userBet?.selectedOutcome == .yes ? 1 : 0)
                    }
                    
                    VStack(spacing: 0) {
                        VoteButton(
                            state: stateForNo,
                            name: "No",
                            fiat: amountOnNo
                        ) {
                            showingConfirmationForBetOutcome = .no
                        }
                        .disabled(hasUserBet)
                        .zIndex(1)
                        
                        YouVotedBadge()
                            .offset(y: -Metrics.boxRadius)
                            .zIndex(0)
                            .opacity(userBet?.selectedOutcome == .no ? 1 : 0)
                    }
                }
            }
            
            Spacer()
            
            if !hasResolution && !hasUserBet {
                VStack {
                    Text("Tap Yes or No to buy in")
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textSecondary)
                    
                    AmountText(
                        flagStyle: buyIn.currencyCode.flagStyle,
                        flagSize: .small,
                        content: buyIn.formatted(suffix: nil),
                        showChevron: false,
                        canScale: false
                    )
                    .font(.appTextMedium)
                    .foregroundStyle(Color.textMain)
                }
                .padding(.top, -40) // Offset for YouVotedBadge
            }
            
            Spacer()
            
            if let resolution = pool.resolution {
                bottomViewForResoultion(resolution: resolution)
            } else {
                if isHost {
                    bottomViewForHost()
                } else {
                    bottomView(pool: pool)
                }
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .sheet(item: $showingConfirmationForBetOutcome) { outcome in
            PartialSheet {
                ModalSwipeToBet(
                    fiat: pool.buyIn,
                    subtext: outcome == .yes ? "for Yes" : "for No",
                    swipeText: "Swipe To Pay",
                    cancelTitle: "Cancel"
                ) {
                    try await viewModel.betAction(
                        pool: pool,
                        outcome: outcome
                    )
                    
                } dismissAction: {
                    showingConfirmationForBetOutcome = nil
                } cancelAction: {
                    showingConfirmationForBetOutcome = nil
                }
            }
        }
        .sheet(item: $showingDeclareOutcome) { outcome in
            PartialSheet {
                ModalSwipeToDeclareWinner(
                    outcome: outcome,
                    amount: winningsForDeclaredOutcome(outcome),
                    swipeText: "Swipe To Confirm",
                    cancelTitle: "Cancel"
                ) {
                    try await viewModel.declarOutcomeAction(
                        pool: pool,
                        outcome: outcome
                    )
                    
                } dismissAction: {
                    showingDeclareOutcome = nil
                } cancelAction: {
                    showingDeclareOutcome = nil
                }
            }
        }
    }
    
    @ViewBuilder private func bottomViewForResoultion(resolution: PoolResoltion) -> some View {
        VStack {
            Group {
                switch resolution {
                case .yes:
                    Text("Each winner received \(winningsForYes.formatted(suffix: nil))")
                case .no:
                    Text("Each winner received \(winningsForNo.formatted(suffix: nil))")
                case .refund:
                    Text("Everyone got their money back")
                }
            }
            .font(.appTextMedium)
            .foregroundStyle(Color.textSecondary)
        }
        
        Spacer()
    }
    
    @ViewBuilder private func bottomView(pool: StoredPool) -> some View {
        VStack(spacing: 25) {
            Text("The person who created the pool gets to decide the outcome of the pool in their sole discretion")
                .font(.appTextSmall)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
            
            // Pool rendezvous is required
            // to create the share link
            if pool.rendezvous != nil {
                CodeButton(
                    style: .filled,
                    title: "Share Pool With Friends",
                    action: sharePoolAction
                )
            }
        }
    }
    
    @ViewBuilder private func bottomViewForHost() -> some View {
        VStack(spacing: 0) {
            CodeButton(
                style: .filled,
                title: "Share Pool With Friends",
                action: sharePoolAction
            )
            
            CodeButton(
                style: .subtle,
                title: "Declare the Outcome"
            ) {
                dialogItem = .init(
                    style: .standard,
                    title: "What was the winning outcome?",
                    subtitle: nil,
                    dismissable: true,
                    actions: {
                        .standard("Yes") {
                            showingDeclareOutcome = .yes
                        };
                        .standard("No") {
                            showingDeclareOutcome = .no
                        };
                        .outline("Tie (Refund Everyone)") {
                            showingDeclareOutcome = .refund
                        };
                        .cancel()
                    }
                )
            }
        }
        .padding(.bottom, -20)
    }
    
    private func winningsForDeclaredOutcome(_ outcome: PoolResoltion) -> Fiat {
        switch outcome {
        case .yes:
            winningsForYes
        case .no:
            winningsForNo
        case .refund:
            buyIn
        }
    }
    
    // MARK: - Actions -
    
    private func sharePoolAction() {
        guard let pool, let rendezvous = pool.rendezvous else {
            return
        }
        
        ShareSheet.present(url: .poolLink(rendezvous: rendezvous))
    }
}

private struct YouVotedBadge: View {
    var body: some View {
        VStack {
            Text("You said")
                .font(.appTextSmall)
                .offset(y: Metrics.boxRadius * 0.4)
        }
        .foregroundStyle(.white.opacity(0.6))
        .frame(width: 90, height: 45)
        .background(
            RoundedRectangle(cornerRadius: Metrics.boxRadius)
                .fill(Color.extraLightFill)
                .strokeBorder(Color.lightStroke, lineWidth: Metrics.inputFieldBorderWidth(highlighted: false))
        )
    }
}

// MARK: - Colors -

extension Color {
    static let extraLightFill = Color(r: 12, g: 37, b: 24)
    static let winnerGreen    = Color(r: 67, g: 144, b: 84)
    static let lightStroke    = Color.textSecondary.opacity(0.15)
}

// MARK: - VoteButton -

private struct VoteButton: View {
    
    let state: State
    let name: String
    let fiat: Fiat
    let action: () -> Void
    
    private var strokeColor: Color {
        switch state {
        case .normal:
            .lightStroke
        case .selected:
            .clear
        case .winner:
            .clear
        }
    }
    
    private var fillColor: Color {
        switch state {
        case .normal:
            .extraLightFill
        case .selected:
            .white
        case .winner:
            .winnerGreen
        }
    }
    
    private var textColor: Color {
        switch state {
        case .normal:
            .white.opacity(0.6)
        case .selected:
            .backgroundMain
        case .winner:
            .white
        }
    }
    
    init(state: State, name: String, fiat: Fiat, action: @escaping () -> Void) {
        self.state      = state
        self.name       = name
        self.fiat       = fiat
        self.action     = action
    }
    
    var body: some View {
        Button {
            action()
        } label: {
            VStack {
                Text(name)
                    .font(.appDisplaySmall)
                Text(fiat.formatted(suffix: nil))
                    .font(.appTextSmall)
            }
            .foregroundStyle(textColor)
            .frame(height: 150)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Metrics.boxRadius)
                    .fill(fillColor)
                    .strokeBorder(strokeColor, lineWidth: 1)
            )
        }
    }
}

extension VoteButton {
    enum State {
        case normal
        case selected
        case winner
    }
}
