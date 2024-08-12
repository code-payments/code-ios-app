//
//  GetKinScreen.swift
//  Code
//
//  Created by Dima Bart on 2023-05-18.
//

import SwiftUI
import CodeUI
import CodeServices

struct GetKinScreen: View {
    
    @EnvironmentObject private var betaFlags: BetaFlags
    @EnvironmentObject private var client: Client
    @EnvironmentObject private var exchange: Exchange
    @EnvironmentObject private var bannerController: BannerController
    
    @ObservedObject private var session: Session
    @ObservedObject private var tipController: TipController
    
    @Binding public var isPresented: Bool
    
    @State private var isLoadingGetKin: Bool = false
    @State private var isShowingBuyKin: Bool = false
    
    private let insets: EdgeInsets = EdgeInsets(
        top: 20,
        leading: 0,
        bottom: 20,
        trailing: 0
    )
    
    // MARK: - Init -
    
    public init(session: Session, isPresented: Binding<Bool>) {
        self.session = session
        self.tipController = session.tipController
        self._isPresented = isPresented
    }
    
    // MARK: - Init -
    
    var body: some View {
        NavigationView {
            Background(color: .backgroundMain) {
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 40) {
                        Image.asset(.graphicWallet)
                        
                        VStack(alignment: .leading, spacing: 20) {
                            Text(Localized.Title.getCash)
                                .font(.appDisplayMedium)
                            
                            Text(Localized.Subtitle.getKin)
                                .font(.appTextMedium)
                        }
                    }
                    .frame(maxHeight: .infinity)
                    
                    VStack(spacing: 0) {
//                        row(
//                            asset: .gift,
//                            title: Localized.Subtitle.getYourFirstKinFree,
//                            subtitle: Localized.Title.limitedTimeOffer,
//                            disabled: !isEligibleForFreeKin(),
//                            strikethrough: !isEligibleForFreeKin(),
//                            accessory: getFreeKinAccessory()
//                        ) {
//                            Task {
//                                isLoadingGetKin = true
//                                let paymentMetadata = try await session.airdropFirstKin()
//                                isPresented.toggle()
//                                
//                                try await Task.delay(milliseconds: 500)
//                                isLoadingGetKin = false
//                                
//                                session.attemptSend(bill: .init(
//                                    kind: .firstKin,
//                                    amount: paymentMetadata.amount,
//                                    didReceive: true
//                                ))
//                            }
//                        }
//                        .vSeparator(color: .rowSeparator, position: .top)
//                        
//                        if isEligibleForReferalIncentive() {
//                            navigationRow(
//                                asset: .send2,
//                                title: Localized.Title.referFriend,
//                                subtitle: Localized.Title.limitedTimeOffer
//                            ) {
//                                GetFriendStartedScreen()
//                            }
//                        }
                        
                        row(
                            asset: .dollar,
                            title: Localized.Action.addCash,
                            accessory: nil
                        ) {
                            isShowingBuyKin = true
                        }
                        .vSeparator(color: .rowSeparator, position: .top)
                        .sheet(isPresented: $isShowingBuyKin) {
                            BuyKinScreen(
                                isPresented: $isShowingBuyKin,
                                viewModel: .init(
                                    session: session,
                                    client: client,
                                    exchange: exchange,
                                    bannerController: bannerController,
                                    betaFlags: betaFlags,
                                    isRootPresented: $isPresented
                                )
                            )
                        }
                        
                        if let user = tipController.twitterUser {
                            row(
                                asset: .tip,
                                title: Localized.Action.requestTip,
                                accessory: nil
                            ) {
                                isPresented = false
                                session.presentMyTipCard(user: user)
                            }
                        } else {
                            navigationRow(
                                asset: .tip,
                                title: Localized.Action.requestTip,
                                showChevron: false
                            ) {
                                RequestTipScreen(
                                    tipController: tipController,
                                    isPresented: $isPresented
                                )
                            }
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
                .padding(.top, -20)
                .padding(.bottom, 20)
                .padding(.horizontal, 20)
                .foregroundColor(.textMain)
            }
            .navigationBarTitle(Text(""), displayMode: .inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    ToolbarCloseButton(binding: $isPresented)
                }
            }
            .onAppear {
                Analytics.open(screen: .getKin)
                ErrorReporting.breadcrumb(.getKinScreen)
                
                Task {
                    try await session.updateUserInfo()
                }
            }
        }
    }
    
    // MARK: - Get Kin -
    
    private func isEligibleForFreeKin() -> Bool {
        session.user.eligibleAirdrops.contains(.getFirstKin)
    }
    
    private func isEligibleForReferalIncentive() -> Bool {
        session.user.eligibleAirdrops.contains(.giveFirstKin)
    }
    
    private func getFreeKinAccessory() -> RowAccessory? {
        guard isEligibleForFreeKin() else {
            return nil
        }
        
        return isLoadingGetKin ? .loader(.textMain) : .chevron
    }
    
    // MARK: - Rows -
    
    @ViewBuilder private func row(asset: Asset, title: String, subtitle: String? = nil, disabled: Bool = false, strikethrough: Bool = false, accessory: RowAccessory?, action: VoidAction? = nil) -> some View {
        Row(insets: insets, disabled: disabled, accessory: accessory) {
            rowContent(asset: asset, title: title, subtitle: subtitle, strikethrough: strikethrough)
        } action: {
            action?()
        }
    }
    
    @ViewBuilder private func navigationRow<D>(asset: Asset, title: String, subtitle: String? = nil, showChevron: Bool = true, @ViewBuilder destination: @escaping () -> D) -> some View where D: View {
        NavigationRow(insets: insets, accessory: showChevron ? .chevron : nil, destination: destination) {
            rowContent(asset: asset, title: title, subtitle: subtitle)
        }
    }
    
    @ViewBuilder private func rowContent(asset: Asset, title: String, subtitle: String?, strikethrough: Bool = false) -> some View {
        Image.asset(asset)
            .renderingMode(.template)
            .frame(minWidth: 45)
        
        VStack(alignment: .leading, spacing: 4) {
            Text(LocalizedStringKey(strikethrough ? "~\(title)~" : title))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
                .truncationMode(.tail)
                .font(.appTextMedium)
            
            if let subtitle {
                Text(subtitle)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .font(.appTextHeading)
                    .foregroundColor(.textSecondary)
            }
        }
        
        Spacer()
    }
}

struct GetKinScreen_Previews: PreviewProvider {
    static var previews: some View {
        GetKinScreen(session: .mock, isPresented: .constant(true))
            .environmentObjectsForSession()
    }
}
