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
    
    @Binding public var isPresented: Bool
    
    @ObservedObject private var session: Session
    @ObservedObject private var historyController: HistoryController

    @EnvironmentObject private var exchange: Exchange
    @EnvironmentObject private var client: Client
    @EnvironmentObject private var betaFlags: BetaFlags
    
//    @State private var selectedTransaction: TransactionSelection?
    @State private var isShowingFAQ: Bool = false
    @State private var isShowingBuckets: Bool = false
    
    private var chats: [Chat] {
        historyController.chats
//        [
//            Chat(
//                id: .mock, 
//                cursor: .mock1,
//                title: .domain("wsj.com"),
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
    
    public init(session: Session, historyController: HistoryController, isPresented: Binding<Bool>) {
        self.session = session
        self.historyController = historyController
        self._isPresented = isPresented
    }
    
    // MARK: - Appear -
    
    private func didAppear() {
        Analytics.open(screen: .balance)
        ErrorReporting.breadcrumb(.balanceScreen)
        fetchHistory()
    }
    
    private func fetchHistory() {
        historyController.fetchDelta()
        historyController.fetchChats()
    }
    
    // MARK: - Body -
    
    var body: some View {
        NavigationView {
            Background(color: .backgroundMain) {
                GeometryReader { geometry in
                    if session.hasBalance && historyController.hasFetchedTransactions {
                        VStack(spacing: 0) {
                            if hasTransactions {
                                ScrollBox(color: .backgroundMain) {
                                    LazyTable(
                                        contentPadding: .scrollBox,
                                        content: {
                                            chatsView()
                                        },
                                        headerHeight: geometry.size.height * 0.3,
                                        header: {
                                            header()
                                        }
                                    )
                                }
                            } else {
                                header()
                                    .frame(maxHeight: geometry.size.height * 0.3)
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
            .navigationBarTitle(Text(Localized.Title.balance), displayMode: .inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    ToolbarCloseButton(binding: $isPresented)
                }
            }
        }
        .onAppear(perform: didAppear)
    }
    
    @ViewBuilder private func header() -> some View {
        VStack(alignment: .center) {
            Flow(isActive: $isShowingFAQ) {
                FAQScreen(isPresented: $isShowingFAQ)
            }
            
            Button {
                isShowingBuckets.toggle()
            } label: {
                AmountText(
                    flagStyle: exchange.localRate.currency.flagStyle,
                    content: session.currentBalance.formattedFiat(
                        rate: exchange.localRate,
                        truncated: true,
                        showOfKin: true
                    )
                )
                .font(.appDisplayMedium)
                .foregroundColor(.textMain)
                .frame(maxWidth: .infinity)
            }
            .disabled(!betaFlags.hasEnabled(.bucketDebugger))
            .sheet(isPresented: $isShowingBuckets) {
                BucketScreen(
                    isPresented: $isShowingBuckets,
                    organizer: session.organizer
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
//                    .sheet(isPresented: $isShowingFAQ) {
//                        FAQScreen(isPresented: $isShowingFAQ)
//                    }
                }
                .font(.appTextMedium)
                .foregroundColor(.textSecondary)
                .frame(maxWidth: .infinity)
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
//                .sheet(isPresented: $isShowingFAQ) {
//                    FAQScreen(isPresented: $isShowingFAQ)
//                }
            }
            .padding(.bottom, 150)
        }
        .font(.appTextMedium)
        .foregroundColor(.textMain)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    @ViewBuilder private func chatsView() -> some View {
        ForEach(chats, id: \.id) { chat in
            NavigationLink {
                LazyView (
                    ChatScreen(
                        chat: chat,
                        historyController: historyController
                    )
                )
            } label: {
                let isUnread = !chat.isMuted && chat.unreadCount > 0
                
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 10) {
                        Text(chat.localizedTitle)
                            .foregroundColor(.textMain)
                            .font(.appTextMedium)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        if let latestMessage = chat.messages.last {
                            Text(latestMessage.date.formattedRelatively())
                                .foregroundColor(isUnread ? .textSuccess : .textSecondary)
                                .font(.appTextSmall)
                                .lineLimit(1)
                        }
                    }
                    .frame(height: 22) // Ensures the same height with and without Bubble
                    
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
                .padding([.trailing, .top, .bottom], 20)
                .vSeparator(color: .rowSeparator)
                .padding(.leading, 20)
            }
        }
    }
    
    @ViewBuilder private func transactionRow(for transaction: HistoricalTransaction) -> some View {
        HStack {
            VStack(alignment: .leading) {
                HStack(spacing: 10) {
                    Text(title(for: transaction))
                        .foregroundColor(.textMain)
                        .font(.appTextMedium)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    CurrencyText(
                        currency: transaction.kinAmount.rate.currency,
                        text: formattedFiatAmount(
                            kin: transaction.kinAmount.kin,
                            rate: transaction.kinAmount.rate
                        )
                    )
                    .foregroundColor(.textMain)
                    .font(.appTextMedium)
//                    Flag(style: transaction.kinAmount.rate.currency.flagStyle, size: .small)
//                    Text(formattedFiatAmount(
//                        kin: transaction.kinAmount.kin,
//                        rate: transaction.kinAmount.rate
//                    ))
//                    .foregroundColor(.textMain)
//                    .font(.appTextMedium)
//                    .lineLimit(1)
//                    .layoutPriority(10)
                }
                HStack(spacing: 5) {
                    Text(DateFormatter.relative.string(from: transaction.date))
                        .foregroundColor(.textSecondary)
                        .font(.appTextSmall)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    KinText(formattedKinAmount(
                        kin: transaction.kinAmount.kin,
                        currency: transaction.kinAmount.rate.currency
                    ), format: .large)
                    .foregroundColor(.textSecondary)
                    .font(.appTextSmall)
                    .lineLimit(1)
                    .truncationMode(.middle)
                }
            }
        }
    }
    
    private func title(for transaction: HistoricalTransaction) -> String {
        switch transaction.paymentType {
        case .send:
            if transaction.isWithdrawal {
                if transaction.isMicroPayment {
                    return Localized.Subtitle.youSpent
                } else {
                    return Localized.Subtitle.youWithdrew
                }
            } else {
                if transaction.isRemoteSend {
                    return Localized.Subtitle.youSent
                } else {
                    return Localized.Subtitle.youGave
                }
            }
            
        case .receive:
            
            if let airdropType = transaction.airdropType {
                switch airdropType {
                case .unknown:
                    break
                case .giveFirstKin:
                    return Localized.Title.referralBonus
                case .getFirstKin:
                    return Localized.Title.welcomeBonus
                }    
            }
            
            if transaction.isDeposit {
                return Localized.Subtitle.youDeposited
            }
            
            if transaction.isReturned {
                return Localized.Subtitle.wasReturnedToYou
            }
            
            return Localized.Subtitle.youReceived
            
        case .unknown:
            return Localized.Title.unknown
        }
    }
    
    // MARK: - Actions -
    
//    private func selectTransaction(_ transaction: HistoricalTransaction) {
//        guard let signature = transaction.transactionSignature else {
//            return
//        }
//
//        selectedTransaction = TransactionSelection(
//            transaction: transaction,
//            url: .solscanTransaction(with: signature)
//        )
//    }
    
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

// MARK: - Chats -

extension Chat {
    public var localizedTitle: String {
        switch title {
        case .domain(let domain):
            var string = domain
            let firstCharacter = string.prefix(1).capitalized
            return "\(firstCharacter)\(string.suffix(string.count - 1))"
            
        case .localized(let key):
            return key.localizedStringByKey
        case .none:
            return "Anonymous"
        }
    }
    
    public var previewMessage: String {
        guard let contents = messages.last?.contents else {
            return "No content"
        }
        
        var filtered = contents.filter {
            if case .localized = $0 {
                true
            } else {
                false
            }
        }
            
        if filtered.isEmpty {
            filtered = contents
        }
        
        return filtered.map { $0.localizedText }.joined(separator: " ")
    }
}

extension Chat.Content {
    public var localizedText: String {
        switch self {
        case .localized(let key):
            return key.localizedStringByKey
            
        case .kin(let genericAmount, let verb):
            let amount: String
            
            switch genericAmount {
            case .exact(let kinAmount):
                amount = kinAmount.kin.formattedFiat(rate: kinAmount.rate, showOfKin: true)
                
            case .partial(let fiat):
                amount = fiat.formatted(showOfKin: true)
            }
            
            return "\(verb.localizedText) \(amount)"
            
        case .sodiumBox:
            return "<! encrypted content !>"
        }
    }
}

extension Chat.Verb {
    public var localizedText: String {
        switch self {
        case .unknown:
            return Localized.Title.unknown
        case .gave:
            return Localized.Subtitle.youGave
        case .received:
            return Localized.Subtitle.youReceived
        case .withdrew:
            return Localized.Subtitle.youWithdrew
        case .deposited:
            return Localized.Subtitle.youDeposited
        case .sent:
            return Localized.Subtitle.youSent
        case .returned:
            return Localized.Subtitle.wasReturnedToYou
        case .spent:
            return Localized.Subtitle.youSpent
        case .paid:
            return Localized.Subtitle.youPaid
        case .purchased:
            return Localized.Subtitle.youPurchased
        }
    }
}

// MARK: -  Title BalanceDescription -

private struct TransactionSelection: Identifiable {
    var transaction: HistoricalTransaction
    var url: URL
    var id: ID {
        transaction.id
    }
}

// MARK: - Previews -

struct BalanceScreen_Previews: PreviewProvider {
    static var previews: some View {
        Preview(devices: .iPhoneSE, .iPhoneMini, .iPhoneMax) {
            BalanceScreen(
                session: .mock,
                historyController: .mock,
                isPresented: .constant(true)
            )
        }
        .environmentObjectsForSession()
    }
}

private extension HistoricalTransaction {
    static func mock() -> [HistoricalTransaction] {
        (0..<3).flatMap { _ in
            [
                HistoricalTransaction(
                    id: .random,
                    paymentType: .receive,
                    date: .now(),
                    kinAmount: KinAmount(kin: 357_142, rate: Rate(fx: 0.000014, currency: .usd)),
                    nativeAmount: 5.00,
                    isDeposit: false,
                    isWithdrawal: false,
                    isRemoteSend: false,
                    isReturned: false,
                    isMicroPayment: false,
                    airdropType: nil
                ),
            ]
        }
    }
}
