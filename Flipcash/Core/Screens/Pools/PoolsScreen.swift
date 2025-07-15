//
//  PoolsScreen.swift
//  Code
//
//  Created by Dima Bart on 2025-06-18.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

struct PoolsScreen: View {
    
    @ObservedObject private var viewModel: PoolViewModel
    
    @StateObject private var updateablePools: Updateable<[StoredPool]>
    
    private let container: Container
    private let sessionContainer: SessionContainer
    private let session: Session
    private let database: Database
    
    private var pools: [StoredPool] {
        updateablePools.value
    }
    
    // MARK: - Init -
    
    init(container: Container, sessionContainer: SessionContainer) {
        self.container        = container
        self.sessionContainer = sessionContainer
        self.session          = sessionContainer.session
        self.viewModel        = sessionContainer.poolViewModel
        let database          = sessionContainer.database
        self.database         = database
        
        _updateablePools = .init(wrappedValue: Updateable {
            (try? database.getPools()) ?? []
        })
    }
    
    // MARK: - Lifecycle -
    
    private func onAppear() {
        viewModel.syncPools()
    }
    
    // MARK: - Body -
    
    var body: some View {
        NavigationStack(path: $viewModel.poolListPath) {
            Background(color: .backgroundMain) {
                VStack(spacing: 0) {
                    if pools.isEmpty {
                        emptyState()
                    } else {
                        list()
                    }
                    
                    CodeButton(
                        style: .filled,
                        title: "Create a New Pool",
                        action: viewModel.startPoolCreationFlowAction
                    )
                    .sheet(isPresented: $viewModel.isShowingCreatePoolFlow) {
                        EnterPoolNameScreen(
                            isPresented: $viewModel.isShowingCreatePoolFlow,
                            viewModel: viewModel
                        )
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
                .navigationTitle("Pools")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        ToolbarCloseButton(binding: $viewModel.isShowingPoolList)
                    }
                }
            }
            .ignoresSafeArea(.keyboard)
            .onAppear(perform: onAppear)
            .navigationDestination(for: PoolListPath.self) { path in
                switch path {
                case .poolDetails(let poolID):
                    PoolDetailsScreen(
                        userID: session.userID,
                        poolID: poolID,
                        database: database,
                        viewModel: viewModel
                    )
                }
            }
        }
    }
    
    @ViewBuilder private func emptyState() -> some View {
        VStack(spacing: 20) {
            Spacer()
            
            VStack(spacing: 10) {
                Image.asset(.graphicPoolPlaceholder)
                    .overlay {
                        TextCarousel(
                            interval: 2,
                            items: [
                                "Will Joe and Sally\nhave a baby girl?",
                                "Will David get a\ngirl's number tonight?",
                                "Will Jack bring a\ndate to the wedding?",
                                "Will Caleb dunk\nthis basketball?",
                                "Will Jill text her\nex before dawn?",
                            ]
                        )
                        .font(.appTextLarge)
                        .foregroundStyle(Color.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .offset(y: -80)
                    }
                
                Text("Create a pool, collect money from your friends, and then decide who was right!")
                    .font(.appTextMedium)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
            }
            
            Spacer()
        }
        .padding(20)
        .foregroundStyle(Color.textMain)
    }
    
    @ViewBuilder private func list() -> some View {
        let openPools      = pools.filter { $0.resolution == nil }
        let completedPools = pools.filter { $0.resolution != nil }
        GeometryReader { g in
            List {
                if !openPools.isEmpty {
                    section(
                        name: "Open",
                        pools: openPools
                    )
                }
                
                if !completedPools.isEmpty {
                    section(
                        name: "Completed",
                        pools: completedPools
                    )
                }
            }
            .listStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
    }
    
    @ViewBuilder private func section(name: String, pools: [StoredPool]) -> some View {
        Section {
            ForEach(pools) { pool in
                row(pool: pool)
            }
        } header: {
            HeadingBadge(title: name)
                .textCase(nil)
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
                .padding(.top, 20)
        }
        //.listSectionSeparator(.hidden)
        .listRowInsets(EdgeInsets())
        .listRowSeparatorTint(.rowSeparator)
    }
    
    @ViewBuilder private func row(pool: StoredPool) -> some View {
        Button {
            viewModel.selectPoolAction(poolID: pool.id)
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    if pool.isHost {
                        HStack(spacing: 5) {
                            Image.system(.person)
                                .font(.appTextSmall)
                            Text("Host")
                                .font(.appTextMedium)
                        }
                        .foregroundStyle(Color.textSecondary)
                    }
                    
                    Text(pool.name)
                        .font(.appTextLarge)
                        .foregroundStyle(Color.textMain)
                        .multilineTextAlignment(.leading)
                    
                    HStack(spacing: 8) {
                        if let resolution = pool.resolution {
                            ResolutionBadge(resolution: resolution)
                            
                            switch pool.userOutcome {
                            case .none:
                                EmptyView()
                            case .won(let amount):
                                if amount.quarks > 0 {
                                    ResultBadge(
                                        style: .won,
                                        text: "Won",
                                        amount: amount
                                    )
                                }
                                
                            case .lost(let amount):
                                if amount.quarks > 0 {
                                    ResultBadge(
                                        style: .lost,
                                        text: "Lost",
                                        amount: amount
                                    )
                                }
                                
                            case .refunded:
                                ResultBadge(
                                    style: .tied,
                                    text: "Tie",
                                    amount: nil
                                )
                            }
                            
                        } else {
                            Text("\(pool.amountInPool.formatted(suffix: nil)) in pool so far")
                                .font(.appTextMedium)
                                .foregroundStyle(Color.textSecondary)
                        }
                        
                        if BetaFlags.shared.hasEnabled(.showMissingRendezvous), pool.rendezvous == nil {
                            ResultBadge(
                                style: .lost,
                                text: "Missing Rendezvous",
                                amount: nil
                            )
                        }
                    }
                }
                .padding(.top, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                
                Image.system(.chevronRight)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .listRowBackground(Color.clear)
        .padding(.horizontal, 20)
        .padding(.vertical, 15)
    }
}

// MARK: - HeadingBadge -

struct HeadingBadge: View {
    
    let title: String
    
    init(title: String) {
        self.title = title
    }
    
    var body: some View {
        Text(title)
            .font(.appTextMedium)
            .foregroundStyle(Color.textMain.opacity(0.5))
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background {
                RoundedRectangle(cornerRadius: 99)
                    .fill(Color.white.opacity(0.12))
            }
    }
}

// MARK: - ResolutionBadge -

struct ResolutionBadge: View {
    
    let resolution: PoolResoltion
    
    init(resolution: PoolResoltion) {
        self.resolution = resolution
    }
    
    var body: some View {
        Text("Result: \(resolution.name)")
            .font(.appTextSmall)
            .foregroundStyle(Color.textMain.opacity(0.5))
            .padding(.horizontal, 6)
            .frame(height: 26)
            .background {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.white.opacity(0.11))
            }
    }
}

// MARK: - ResultBadge -

extension Color {
    static let badgeWonBackground    = Color(r: 44, g: 77, b: 54)
    static let badgeLostBackground   = Color(r: 64, g: 44, b: 35)
    static let badgeNormalBackground = Color(r: 33, g: 50, b: 40)
}

struct ResultBadge: View {
    
    let style: Style
    let text: String
    let amount: Fiat?
    
    init(style: Style, text: String, amount: Fiat?) {
        self.style  = style
        self.text   = text
        self.amount = amount
    }
    
    var body: some View {
        HStack(spacing: 5) {
            Text(text)
            if let amount {
                Text(amount.formatted(suffix: nil))
            }
        }
        .font(.appTextSmall)
        .padding(.horizontal, 6)
        .frame(height: 26)
        .foregroundStyle(style.textColor)
        .background {
            RoundedRectangle(cornerRadius: 5)
                .fill(style.backgroundColor)
        }
    }
}

extension ResultBadge {
    enum Style {
        case won
        case lost
        case tied
        
        var textColor: Color {
            switch self {
            case .won:  return Color(r: 115, g: 234, b: 164)
            case .lost: return Color(r: 214, g: 94,  b: 89)
            case .tied: return .textMain.opacity(0.5)
            }
        }
        
        var backgroundColor: Color {
            switch self {
            case .won:  return .badgeWonBackground
            case .lost: return .badgeLostBackground
            case .tied: return .badgeNormalBackground
            }
        }
    }
}

extension PoolResoltion {
    var name: String {
        switch self {
        case .yes:    return "Yes"
        case .no:     return "No"
        case .refund: return "Tie"
        }
    }
}
