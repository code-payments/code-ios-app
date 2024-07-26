//
//  BalanceScreen.swift
//  Code
//
//  Created by Dima Bart on 2021-03-04.
//

import SwiftUI
import CodeUI
import CodeServices

struct BalanceScreen: View {
    
    @EnvironmentObject private var bannerController: BannerController
    @EnvironmentObject private var notificationController: NotificationController
    
    @Binding public var isPresented: Bool
    
    @ObservedObject private var session: Session
    @ObservedObject private var chatController: ChatController

    @EnvironmentObject private var exchange: Exchange
    @EnvironmentObject private var client: Client
    @EnvironmentObject private var betaFlags: BetaFlags
    
    @State private var isShowingFAQ: Bool = false
    @State private var isShowingBuckets: Bool = false
    @State private var isShowingBuyMoreKin: Bool = false
    @State private var isShowingCurrencySelection: Bool = false
    
    @StateObject private var viewModel: ChatViewModel
    
    private var chats: [Chat] {
        chatController.chats
//        [
//            Chat(
//                id: .mock, 
//                cursor: .mock1,
//                title: .domain(Domain("wsj.com")!),
//                pointer: .unknown,
//                unreadCount: 0,
//                canMute: false,
//                isMuted: false,
//                canUnsubscribe: false,
//                isSubscribed: false,
//                isVerified: false,
//                messages: [
//                    Chat.Message(
//                        id: .mock2,
//                        date: .now,
//                        contents: [
//                            .localized("Welcome bonus! You've received a gift in Kin."),
//                            .kin(
//                                .exact(KinAmount(
//                                    fiat: 5.00,
//                                    rate: Rate(fx: 0.000014, currency: .usd)
//                                )), .received
//                            ),
//                        ]
//                    )
//                ]
//            )
//        ]
    }
    
    private var hasTransactions: Bool {
        !chats.isEmpty
    }
    
    // MARK: - Init -
    
    public init(session: Session, chatController: ChatController, isPresented: Binding<Bool>) {
        self.session = session
        self.chatController = chatController
        self._isPresented = isPresented
        
        let chatViewModel = ChatViewModel(
            chatController: chatController,
            tipController: session.tipController
        )
        
        self._viewModel = StateObject(wrappedValue: chatViewModel)
    }
    
    // MARK: - Appear -
    
    private func didAppear() {
        Analytics.open(screen: .balance)
        ErrorReporting.breadcrumb(.balanceScreen)
        fetchHistory()
    }
    
    private func fetchHistory() {
        chatController.fetchChats()
    }
    
    // MARK: - Body -
    
    var body: some View {
        NavigationStack(path: $viewModel.navigationPath) {
            Background(color: .backgroundMain) {
                GeometryReader { geometry in
                    if session.hasBalance && chatController.hasFetchedChats {
                        VStack(spacing: 0) {
                            if hasTransactions {
                                ScrollBox(color: .backgroundMain) {
                                    LazyTable(
                                        contentPadding: .scrollBox,
                                        content: {
                                            chatsView()
                                        },
                                        headerHeight: geometry.size.height * 0.4,
                                        header: {
                                            header()
                                        }
                                    )
                                }
                            } else {
                                header()
                                    .frame(maxHeight: geometry.size.height * 0.4)
                                emptyState()
                            }
                        }
                    } else {
                        VStack {}
                            .loading(
                                active: true,
                                text: Localized.Subtitle.loadingBalance,
                                color: .white,
                                padding: 80,
                                showOverlay: false
                            )
                    }
                }
            }
            .navigationDestination(for: Chat.self) { chat in
                ChatScreen(
                    chat: chat,
                    chatController: chatController,
                    viewModel: viewModel
                )
            }
            .navigationBarTitle(Text(Localized.Title.balance), displayMode: .inline)
            .sheet(isPresented: $isShowingBuckets) {
                BucketScreen(
                    isPresented: $isShowingBuckets,
                    organizer: session.organizer
                )
                .environmentObject(exchange)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    ToolbarCloseButton(binding: $isPresented)
                }
                
                ToolbarItem(placement: .navigationBarLeading) {
                    if betaFlags.hasEnabled(.bucketDebugger) {
                        Button {
                            isShowingBuckets.toggle()
                        } label: {
                            Image(systemName: "note.text")
                                .padding(5)
                        }
                    } else {
                        EmptyView()
                    }
                }
            }
        }
        .onAppear(perform: didAppear)
        .onChange(of: notificationController.messageReceived) { _ in
            fetchHistory()
        }
    }
    
    @ViewBuilder private func header() -> some View {
        VStack(alignment: .center) {
            Flow(isActive: $isShowingFAQ) {
                FAQScreen(isPresented: $isShowingFAQ)
            }
            
            Button {
                isShowingCurrencySelection.toggle()
            } label: {
                AmountText(
                    flagStyle: exchange.localRate.currency.flagStyle,
                    content: session.currentBalance.formattedFiat(
                        rate: exchange.localRate,
                        truncated: true,
                        showOfKin: true
                    ),
                    showChevron: true
                )
                .font(.appDisplayMedium)
                .foregroundColor(.textMain)
                .frame(maxWidth: .infinity)
            }
            .sheet(isPresented: $isShowingCurrencySelection) {
                CurrencySelectionScreen(
                    viewModel: CurrencySelectionViewModel(
                        isPresented: $isShowingCurrencySelection,
                        exchange: exchange,
                        kind: .local
                    )
                )
                .environmentObject(exchange)
            }
            
            if hasTransactions {
                HStack(spacing: 8) {
                    Text(Localized.Subtitle.valueKinChanges)
                    Button {
                        isShowingFAQ = true
                    } label: {
                        Text(Localized.Subtitle.learnMore)
                            .underline()
                    }
                }
                .font(.appTextMedium)
                .foregroundColor(.textSecondary)
                .frame(maxWidth: .infinity)
            }
            
            CodeButton(style: .filled, title: Localized.Action.addCash) {
                isShowingBuyMoreKin = true
            }
            .padding(.top, 15)
            .sheet(isPresented: $isShowingBuyMoreKin) {
                LazyView(
                    BuyKinScreen(
                        isPresented: $isShowingBuyMoreKin,
                        viewModel: BuyKinViewModel(
                            session: session,
                            client: client,
                            exchange: exchange,
                            bannerController: bannerController,
                            betaFlags: betaFlags,
                            isRootPresented: $isPresented
                        )
                    )
                )
            }
        }
        .padding(.horizontal, 20)
    }
    
    @ViewBuilder private func emptyState() -> some View {
        VStack {
            VStack {
                Text(Localized.Subtitle.dontHaveKin)
                    .multilineTextAlignment(.center)
                Button {
                    isShowingFAQ = true
                } label: {
                    Text(Localized.Subtitle.learnMore)
                        .underline()
                }
            }
            .padding(.bottom, 150)
        }
        .font(.appTextMedium)
        .foregroundColor(.textMain)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    @ViewBuilder private func chatsView() -> some View {
        ForEach(chats, id: \.id) { chat in
            NavigationLink(value: chat) {
                navigationLabel(for: chat)
            }
        }
    }
    
    @ViewBuilder
    private func navigationLabel(for chat: Chat) -> some View {
        let isUnread = !chat.isMuted && chat.unreadCount > 0
        
        HStack(spacing: 15) {
            GeneratedAvatarView(data: chat.id.data, diameter: 60.0)
            
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 10) {
                    Text(chat.displayName)
                        .foregroundColor(.textMain)
                        .font(.appTextMedium)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    if let newestMessage = chat.newestMessage {
                        Text(newestMessage.date.formattedRelatively(useTimeForToday: true))
                            .foregroundColor(isUnread ? .textSuccess : .textSecondary)
                            .font(.appTextSmall)
                            .lineLimit(1)
                    }
                }
                .frame(height: 23) // Ensures the same height with and without Bubble
                
                HStack(alignment: .top, spacing: 5) {
                    Text(chat.previewMessage)
                        .foregroundColor(.textSecondary)
                        .font(.appTextMedium)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    Spacer()
                    
                    if chat.isMuted {
                        Image.system(.speakerSlash)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 20, height: 20, alignment: .trailing)
                            .foregroundColor(.textSecondary)
                    }
                    
                    if isUnread {
                        Bubble(size: .large, count: chat.unreadCount)
                    }
                }
            }
        }
        .padding([.trailing, .top, .bottom], 20)
        .vSeparator(color: .rowSeparator)
        .padding(.leading, 20)
    }
    
    // MARK: - Formatting -
    
    private func formattedFiatAmount(kin: Kin, rate: Rate) -> String {
        if rate.currency == .kin {
            return "\(kin.formattedTruncatedKin()) \(Localized.Core.kin)"
        } else {
            return kin.formattedFiat(rate: rate, showOfKin: true)
        }
    }
    
    private func formattedKinAmount(kin: Kin, currency: CurrencyCode) -> String {
        if currency == .kin {
            return ""
        } else {
            return kin.formattedTruncatedKin()
        }
    }
}

// MARK: - Previews -

struct BalanceScreen_Previews: PreviewProvider {
    static var previews: some View {
        Preview(devices: .iPhoneSE, .iPhoneMini, .iPhoneMax) {
            BalanceScreen(
                session: .mock,
                chatController: .mock,
                isPresented: .constant(true)
            )
        }
        .environmentObjectsForSession()
    }
}
