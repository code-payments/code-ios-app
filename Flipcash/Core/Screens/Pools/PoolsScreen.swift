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
    
    private let container: Container
    private let sessionContainer: SessionContainer
    
    // MARK: - Init -
    
    init(isPresented: Binding<Bool>, container: Container, sessionContainer: SessionContainer) {
        self._isPresented     = isPresented
        self.container        = container
        self.sessionContainer = sessionContainer
        
        _viewModel = StateObject(
            wrappedValue: PoolViewModel(
                container: container,
                sessionContainer: sessionContainer
            )
        )
    }
    
    // MARK: - Lifecycle -
    
    private func onAppear() {
        
    }
    
    // MARK: - Body -
    
    var body: some View {
        NavigationStack {
            Background(color: .backgroundMain) {
                VStack(spacing: 0) {
                    emptyState()
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
                Image.asset(.graphicPoolQuestion)
                
                Text("Create a pool, collect money from your friends, and then decide who was right!")
                    .font(.appTextMedium)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
            }
            
            Spacer()
            
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
        }
        .listRowBackground(Color.clear)
        .foregroundStyle(Color.textMain)
        .padding(20)
    }
    
//    @ViewBuilder private func list() -> some View {
//        GeometryReader { g in
//            List {
//                Section {
//                    if hasActivities {
//                        ForEach(activities) { activity in
//                            row(activity: activity)
//                        }
//                    } else {
//                        emptyState()
//                    }
//                    
//                } header: {
//                    header(geometry: g)
//                        .textCase(.none)
//                }
//                //.listSectionSeparator(.hidden)
//                .listRowInsets(EdgeInsets())
//                .listRowSeparatorTint(hasActivities ? .rowSeparator : .clear)
//            }
//            .listStyle(.grouped)
//            .scrollContentBackground(.hidden)
//        }
//    }
//    
//    @ViewBuilder private func row(activity: Activity) -> some View {
//        Button {
//            if BetaFlags.shared.hasEnabled(.transactionDetails) {
//                selectedActivity = activity
//            } else {
//                rowAction(activity: activity)
//            }
//        } label: {
//            VStack {
//                HStack {
//                    Text(activity.title)
//                        .font(.appTextMedium)
//                        .foregroundStyle(Color.textMain)
//                    Spacer()
//                    AmountText(
//                        flagStyle: activity.exchangedFiat.converted.currencyCode.flagStyle,
//                        flagSize: .small,
//                        content: activity.exchangedFiat.converted.formatted(suffix: nil)
//                    )
//                    .font(.appTextMedium)
//                    .foregroundStyle(Color.textMain)
//                }
//                
//                HStack {
//                    Text(activity.date.formattedRelatively(useTimeForToday: true))
//                        .font(.appTextSmall)
//                        .foregroundStyle(Color.textSecondary)
//                    Spacer()
////                    if activity.exchangedFiat.converted.currencyCode != .usd {
////                        Text(activity.exchangedFiat.usdc.formatted(suffix: " USD"))
////                            .font(.appTextSmall)
////                            .foregroundStyle(Color.textSecondary)
////                    }
//                }
//            }
//        }
//        .listRowBackground(Color.clear)
//        .padding(.horizontal, 20)
//        .padding(.vertical, 20)
//    }
    
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
