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
    
    @StateObject private var updateablePools: Updateable<[PoolContainer]>
    
    private let container: Container
    private let sessionContainer: SessionContainer
    private let session: Session
    private let database: Database
    
    private var pools: [PoolContainer] {
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
                        title: "Create Pool",
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
        let openPools      = pools.filter { $0.metadata.resolution == nil }
        let completedPools = pools.filter { $0.metadata.resolution != nil }
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
    
    @ViewBuilder private func section(name: String, pools: [PoolContainer]) -> some View {
        Section {
            ForEach(pools) { poolContainer in
                row(poolContainer: poolContainer)
            }
        } header: {
            Text(name)
                .font(.appTextSmall)
                .foregroundStyle(Color.textSecondary)
//                .textCase(nil)
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
                .padding(.top, 20)
        }
        //.listSectionSeparator(.hidden)
        .listRowInsets(EdgeInsets())
        .listRowSeparatorTint(.rowSeparator)
    }
    
    @ViewBuilder private func row(poolContainer: PoolContainer) -> some View {
        let pool = poolContainer.metadata
        let isHost = pool.creatorUserID == session.userID
        
        Button {
            viewModel.selectPoolAction(poolID: pool.id)
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    if isHost {
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
                        if BetaFlags.shared.hasEnabled(.showMissingRendezvous), pool.rendezvous == nil {
                            Text("Missing Rendezvous")
                                .font(.appTextMedium)
                                .foregroundStyle(Color.textError)
                        }
                        
                        if let resolution = pool.resolution {
                            Text("Result: \(resolution.name)")
                                .font(.appTextSmall)
                                .foregroundStyle(Color.textMain.opacity(0.5))
                                .padding(.horizontal, 6)
                                .frame(height: 26)
                                .background {
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(Color.white.opacity(0.11))
                                }
                            
                            if let payout = poolContainer.winningPayout {
                                HStack(spacing: 5) {
                                    Image.system(.trophy)
                                        .font(.appTextHeading)
                                    Text(payout.formatted(suffix: nil))
                                        .font(.appTextSmall)
                                }
                                .padding(.horizontal, 6)
                                .frame(height: 26)
                                .foregroundStyle(Color(r: 115, g: 234, b: 164))
                                .background {
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(Color(r: 44, g: 77, b: 54))
                                }
                            }
                            
                        } else {
                            Text("\(poolContainer.amountInPool.formatted(suffix: nil)) in pool so far")
                                .font(.appTextMedium)
                                .foregroundStyle(Color.textSecondary)
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

extension PoolResoltion {
    var name: String {
        switch self {
        case .yes:    return "Yes"
        case .no:     return "No"
        case .refund: return "Tie"
        }
    }
}

extension KeyPair: Identifiable {
    public var id: PublicKey {
        publicKey
    }
}
