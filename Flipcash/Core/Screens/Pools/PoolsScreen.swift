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
    
    @Binding var isPresented: Bool
    
    @StateObject private var viewModel: PoolViewModel
    
    @StateObject private var updateablePools: Updateable<[PoolContainer]>
    
    private let container: Container
    private let sessionContainer: SessionContainer
    private let database: Database
    
    private var pools: [PoolContainer] {
        updateablePools.value
    }
    
    // MARK: - Init -
    
    init(isPresented: Binding<Bool>, container: Container, sessionContainer: SessionContainer) {
        self._isPresented     = isPresented
        self.container        = container
        self.sessionContainer = sessionContainer
        let database          = sessionContainer.database
        self.database         = database
        
        _viewModel = StateObject(
            wrappedValue: PoolViewModel(
                container: container,
                sessionContainer: sessionContainer
            )
        )
        
        _updateablePools = .init(wrappedValue: Updateable {
            (try? database.getPools()) ?? []
        })
    }
    
    // MARK: - Lifecycle -
    
    private func onAppear() {
        
    }
    
    // MARK: - Body -
    
    var body: some View {
        NavigationStack {
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
                        ToolbarCloseButton(binding: $isPresented)
                    }
                }
            }
            .ignoresSafeArea(.keyboard)
            .onAppear(perform: onAppear)
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
        GeometryReader { g in
            List {
                Section {
                    ForEach(pools) { poolContainer in
                        row(poolContainer: poolContainer)
                    }
                    
                } header: {
                    Text("Open")
                        .padding(.horizontal, 20)
                        .padding(.vertical, 5)
                }
                //.listSectionSeparator(.hidden)
                .listRowInsets(EdgeInsets())
                .listRowSeparatorTint(.rowSeparator)
            }
            .listStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
        .sheet(item: $viewModel.selectedRendezvous) { rendezvous in
            PoolDetailsScreen(
                userID: sessionContainer.session.userID,
                poolRendezvous: rendezvous,
                database: database,
                viewModel: viewModel
            )
        }
    }
    
    @ViewBuilder private func row(poolContainer: PoolContainer) -> some View {
        let pool = poolContainer.metadata
        Button {
            if let rendezvous = pool.rendezvous {
                viewModel.selectPoolAction(rendezvous: rendezvous)
            }
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text(pool.name)
                    .font(.appTextMedium)
                    .foregroundStyle(Color.textMain)
                    .multilineTextAlignment(.leading)
                
                HStack(spacing: 8) {
                    if pool.rendezvous == nil {
                        Text("Missing Rendezvous")
                            .font(.appTextMedium)
                            .foregroundStyle(Color.textError)
                    }
                    Text("\(poolContainer.amountInPool.formatted(suffix: nil)) in pool so far")
                        .font(.appTextMedium)
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
        .listRowBackground(Color.clear)
        .padding(.horizontal, 20)
        .padding(.vertical, 15)
    }
    
    // MARK: - Action -
    
//    private func rowAction(activity: Activity) {
//        if let cashLinkMetadata = activity.cancellableCashLinkMetadata {
//            cancelCashLinkAction(
//                activity: activity,
//                metadata: cashLinkMetadata
//            )
//        }
//    }
    
    private func createPoolAction() {
        
    }
}

extension KeyPair: Identifiable {
    public var id: PublicKey {
        publicKey
    }
}
