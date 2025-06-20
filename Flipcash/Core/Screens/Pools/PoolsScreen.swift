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
    
    @StateObject private var updateablePools: Updateable<[PoolMetadata]>
    
    @State private var selectedPoolID: PublicKey?
    
    private let container: Container
    private let sessionContainer: SessionContainer
    private let database: Database
    
    private var pools: [PoolMetadata] {
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
                        Text("Will Jimmy and\nSally have a girl?")
                            .font(.appTextLarge)
                            .foregroundStyle(Color.white.opacity(0.5))
                            .multilineTextAlignment(.center)
                            .offset(y: -70)
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
                    ForEach(pools) { pool in
                        row(pool: pool)
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
        .sheet(item: $selectedPoolID) { poolID in
            PoolDetailsScreen(
                poolID: poolID,
                database: database
            )
        }
    }
    
    @ViewBuilder private func row(pool: PoolMetadata) -> some View {
        Button {
            selectedPoolID = pool.id
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text(pool.name)
                    .font(.appTextMedium)
                    .foregroundStyle(Color.textMain)
                    .multilineTextAlignment(.leading)
                
                Text("\(pool.buyIn.formatted(suffix: nil)) Buy In")
                    .font(.appTextMedium)
                    .foregroundStyle(Color.textSecondary)
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
