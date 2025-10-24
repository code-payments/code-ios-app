//
//  Session.swift
//  Code
//
//  Created by Dima Bart on 2025-04-15.
//

import UIKit
import FlipcashUI
import FlipcashCore
import Combine

@MainActor
protocol SessionDelegate: AnyObject {
    func didDetectUnlockedAccount()
}

@MainActor
class Session: ObservableObject {
    
    @Published private(set) var limits: Limits?
    
    @Published var billState: BillState = .default()
    @Published var presentationState: PresentationState = .hidden(.slide)
    
    @Published var valuation: BillValuation? = nil
    @Published var toast: Toast? = nil
    
    @Published var dialogItem: DialogItem?
    
    @Published var profile: Profile?
    @Published var userFlags: UserFlags?

    @Published var coinbaseOrder: OnrampOrderResponse?

    let keyAccount: KeyAccount
    let owner: AccountCluster
    let userID: UserID
    
    var ownerKeyPair: KeyPair {
        owner.authority.keyPair
    }
    
//    var totalUSDC: Fiat {
//        try! Fiat(
//            fiatDecimal: aggregateBalance.totalUSDC,
//            currencyCode: .usd
//        )
//    }
//    
//    var exchangedBalance: ExchangedFiat {
//        try! ExchangedFiat(
//            usdc: totalUSDC,
//            rate: ratesController.rateForBalanceCurrency(),
//            mint: .usdc
//        )
//    }
//    
//    var exchangedEntryBalance: ExchangedFiat {
//        try! ExchangedFiat(
//            usdc: totalUSDC,
//            rate: ratesController.rateForEntryCurrency(),
//            mint: .usdc
//        )
//    }
    
    var nextTransactionLimit: Fiat? {
        guard let limits else {
            return nil
        }
        
        let rate = ratesController.rateForEntryCurrency()
        
        guard let limit = limits.sendLimitFor(currency: rate.currency) else {
            return nil
        }
        
        return limit.nextTransaction
    }
    
    var singleTransactionLimit: Fiat? {
        singleTransactionLimitFor(currency: ratesController.entryCurrency)
    }
    
    func singleTransactionLimitFor(currency: CurrencyCode) -> Fiat? {
        guard let limits else {
            return nil
        }
        
        guard let rate = ratesController.rate(for: currency) else {
            return nil
        }
        
        guard let limit = limits.sendLimitFor(currency: rate.currency) else {
            return nil
        }
        
        return limit.maxPerTransaction
    }
    
    var isShowingBill: Bool {
        billState.bill != nil
    }
    
    var hasCoinbaseOnramp: Bool {
        BetaFlags.shared.hasEnabled(.enableCoinbase) || userFlags?.hasCoinbase == true
    }
    
    var hasPreferredOnrampProvider: Bool {
        userFlags?.hasPreferredOnrampProvider == true
    }
    
    var balances: [StoredBalance] {
        updateableBalances.value
    }
    
    private let container: Container
    private let client: Client
    private let flipClient: FlipClient
    private let ratesController: RatesController
    private let historyController: HistoryController
    private let database: Database
    
    private var poller: Poller!
    
    private var scanOperation: ScanCashOperation?
    private var sendOperation: SendCashOperation?
    
    private var toastQueue = ToastQueue()
    
    private lazy var updateableBalances: Updateable<[StoredBalance]> = {
        Updateable { [weak self] in
            (try? self?.database.getBalances()) ?? []
        }
    }()
    
    private var cancellables: Set<AnyCancellable> = []
    
    // MARK: - Init -
    
    init(container: Container, historyController: HistoryController, ratesController: RatesController, database: Database, keyAccount: KeyAccount, owner: AccountCluster, userID: UserID) {
        self.container         = container
        self.client            = container.client
        self.flipClient        = container.flipClient
        self.ratesController   = ratesController
        self.historyController = historyController
        self.database          = database
        self.keyAccount        = keyAccount
        self.owner             = owner
        self.userID            = userID
        
        _ = updateableBalances
        
        registerPoller()
        attemptAirdrop()
        
        Task {
            try await updateProfile()
            try await updateUserFlags()
        }
    }
    
    func prepareForLogout() {
        
    }
    
    // MARK: - Info -
    
    func updateProfile() async throws {
        profile = try await flipClient.fetchProfile(userID: userID, owner: ownerKeyPair)
    }
    
    func unlinkProfile() async throws {
        if let profile {
            if let email = profile.email {
                try await flipClient.unlinkEmail(
                    email: email,
                    owner: ownerKeyPair
                )
            }
            
            if let phone = profile.phone {
                try await flipClient.unlinkPhone(
                    phone: phone.e164,
                    owner: ownerKeyPair
                )
            }
        }
        
        try await updateProfile()
    }
    
    func updateUserFlags() async throws {
        userFlags = try await flipClient.fetchUserFlags(userID: userID, owner: ownerKeyPair)
        print(userFlags)
    }
    
    // MARK: - Login -
    
    func attemptLogin(with mnemonic: MnemonicPhrase, completion: @escaping () async throws -> Void) {
        dialogItem = .init(
            style: .destructive,
            title: "Log In?",
            subtitle: "You're already logged into an account. Please ensure you have saved your Access Key before proceeding. Would you like to logout and login with a new account?",
            dismissable: true,
            actions: {
                .destructive("Log Out & Log In") {
                    Task {
                        try await completion()
                    }
                };
                
                .cancel()
            }
        )
    }
    
    // MARK: - Lifecycle -
    
    func didEnterBackground() {
        // If the sendOperation is ignoring stream, it's likely
        // presenting a share sheet or in some way mid-process
        // so we don't want to dismiss the bill from under it
        if let sendOperation, !sendOperation.ignoresStream {
            dismissCashBill(style: .slide)
        }
    }
    
    // MARK: - Airdrop -
    
    private func attemptAirdrop() {
        Task {
            let paymentMetadata = try await client.airdrop(type: .welcomeBonus, owner: ownerKeyPair)
            
            try await Task.delay(milliseconds: 750)
            let exchangedFiat = paymentMetadata.exchangedFiat
            
            enqueue(toast: .init(
                amount: exchangedFiat.converted,
                isDeposit: true
            ))
            
            showCashBill(.init(
                kind: .cash,
                exchangedFiat: exchangedFiat,
                received: true
            ))
        }
    }
    
    // MARK: - Balance -
    
    func hasLimitToSendFunds(for exchangedFiat: ExchangedFiat) -> Bool {
        guard let nextTransactionLimit else {
            return false
        }
        
        guard exchangedFiat.converted.currencyCode == nextTransactionLimit.currencyCode else {
            return false
        }
        
        let (amountToSend, limit, _) = try! exchangedFiat.converted.aligned(with: nextTransactionLimit)
        
        return amountToSend.quarks <= limit.quarks
    }
    
//    func hasSufficientFunds(for exchangedFiat: ExchangedFiat) -> Bool {
//        hasSufficientFundsWithDelta(for: exchangedFiat).0
//    }
//    
//    func hasSufficientFundsWithDelta(for exchangedFiat: ExchangedFiat) -> (Bool, ExchangedFiat?) {
//        guard exchangedFiat.usdc.quarks > 0 else {
//            return (false, nil)
//        }
//        
//        if balance.quarks < exchangedFiat.usdc.quarks {
//            assert(exchangedEntryBalance.converted.currencyCode == exchangedFiat.converted.currencyCode)
//            let delta = try! ExchangedFiat(
//                converted: Fiat(
//                    quarks: exchangedFiat.converted.quarks - exchangedEntryBalance.converted.quarks,
//                    currencyCode: exchangedFiat.converted.currencyCode
//                ),
//                rate: exchangedEntryBalance.rate,
//                mint: .usdc
//            )
//            return (false, delta)
//        } else {
//            return (exchangedFiat.usdc.quarks <= balance.quarks, nil)
//        }
//    }
    
    // MARK: - Poller -
    
    private func registerPoller() {
        poller = Poller(seconds: 10, fireImmediately: true) { [weak self] in
            Task {
                try await self?.poll()
            }
        }
    }
    
    private func poll() async throws {
        try await fetchLimitsIfNeeded()
        try await fetchBalance()
    }
    
    // MARK: - Limits -
    
    private func fetchLimitsIfNeeded() async throws {
        if limits == nil || limits?.isStale == true {
            try await fetchLimits()
        }
    }
    
    private func fetchLimits() async throws {
        limits = try await client.fetchTransactionLimits(
            owner: ownerKeyPair,
            since: .todayAtMidnight()
        )
        
        trace(.note, components: "Daily limit updated (USD): \(limits?.sendLimitFor(currency: .usd)?.maxPerDay.decimalValue ?? -1)")
    }
    
    private func updateLimits() {
        Task {
            try await fetchLimits()
        }
    }
    
    // MARK: - Balance -
    
    func fetchBalance() async throws {
        let now = Date.now
        
        let accounts     = try await client.fetchPrimaryAccounts(owner: ownerKeyPair)
        let mints        = Set(accounts.map { $0.mint })
        let mintMetadata = try await client.fetchMints(mints: Array(mints))
        
        // Insert mints before balances, while the
        // insertion itself isn't order dependant,
        // fetching balanaces requires an up-to-date
        // mints table. No transaction necessary here
        // since balances will trigger any update.
        try database.insert(
            mints: mintMetadata.map { $0.value },
            date: now
        )
        
        // Insert all the database in a single
        // atomic operation after the mints
        database.transaction { database in
            accounts.forEach { account in
                try? database.insertBalance(
                    quarks: account.quarks,
                    mint: account.mint,
                    date: now
                )
            }
        }
    }
    
    func updateBalance() {
        Task {
            try await fetchBalance()
        }
    }
    
    func updatePostTransaction() {
        updateBalance()
        updateLimits()
        historyController.sync()
    }
    
    func fetchMintMetadata(mint: PublicKey) async throws -> StoredMintMetadata {
        if let metadata = try database.getMintMetadata(mint: mint) {
            return metadata
        } else {
            let mints = try await client.fetchMints(mints: [mint])
            guard let mintMetadata = mints[mint] else {
                throw Error.mintNotFound
            }
            
            try database.insert(mints: [mintMetadata], date: .now)
            return try await fetchMintMetadata(mint: mint)
        }
    }
    
    // MARK: - Toast -
    
    private func show(toast: Toast) {
        enqueue(toast: toast)
        if self.toast == nil {
            consumeToast()
        }
    }
    
    private func enqueue(toast: Toast) {
        toastQueue.insert(toast)
    }
    
    private func consumeToast() {
        guard toastQueue.hasToasts else {
            return
        }
        
        Task {
            // Wait for bill animation to finish
            // before showing the toast
            try await Task.delay(milliseconds: 500)
            
            // Ensure that there's no bills showing
            // otherwise we'll wait for dismissBill
            // to consume the toast
            guard !isShowingBill else {
                trace(.note, components: "Bill showing, waiting for toasts to resume...")
                return
            }
            
            guard toastQueue.hasToasts else {
                return
            }
            
            toast = toastQueue.pop()
//            trace(.note, components: "Showing toast: \(toast!.amount.formatted(suffix: nil))")
            
            try await Task.delay(seconds: 3)
            toast = nil
            
            if toastQueue.hasToasts {
                try await Task.delay(milliseconds: 1000)
                consumeToast()
            }
        }
    }
    
    // MARK: - Withdrawals -
    
    func withdraw(exchangedFiat: ExchangedFiat, to destinationMetadata: DestinationMetadata) async throws {
        let rendezvous = PublicKey.generate()!
        do {
            try await self.client.withdraw(
                exchangedFiat: exchangedFiat,
                owner: owner,
                destinationMetadata: destinationMetadata,
            )
            
            historyController.sync()
            
            Analytics.withdrawal(
                exchangedFiat: exchangedFiat,
                successful: true,
                error: nil
            )
            
        } catch {
            
            ErrorReporting.capturePayment(
                error: error,
                rendezvous: rendezvous,
                exchangedFiat: exchangedFiat
            )
            
            Analytics.withdrawal(
                exchangedFiat: exchangedFiat,
                successful: false,
                error: error
            )
            
            throw error
        }
    }
    
    // MARK: - Cash -
    
    func receiveCash(_ payload: CashCode.Payload, completion: @escaping (ReceiveCashResult) -> Void) {
        print("Scanned: \(payload.fiat.formatted(suffix: nil)) \(payload.fiat.currencyCode)")
        
        guard scanOperation == nil else {
            return
        }
        
        let operation = ScanCashOperation(
            client: client,
            flipClient: flipClient,
            database: database,
            owner: owner,
            payload: payload
        )
        
        scanOperation = operation
        Task {
            defer {
                scanOperation = nil
            }
            
            do {
                let metadata = try await operation.start()
                
                updatePostTransaction()
                
                enqueue(toast: .init(
                    amount: metadata.exchangedFiat.converted,
                    isDeposit: true
                ))
                
                showCashBill(.init(
                    kind: .cash,
                    exchangedFiat: metadata.exchangedFiat,
                    received: true
                ))
                
                Analytics.transfer(
                    event: .grabBill,
                    exchangedFiat: metadata.exchangedFiat,
                    successful: true,
                    error: nil
                )
                completion(.success)
                
            } catch ScanCashOperation.Error.noOpenStreamForRendezvous {
//                showCashExpiredError()
                completion(.noStream)
                
            } catch {
                ErrorReporting.capturePayment(
                    error: error,
                    rendezvous: payload.rendezvous.publicKey,
                    fiat: payload.fiat
                )
                
                Analytics.transfer(
                    event: .grabBill,
                    fiat: payload.fiat,
                    successful: false,
                    error: error
                )
                completion(.failed)
            }
        }
    }
    
    func showCashBill(_ billDescription: BillDescription) {
        let operation = SendCashOperation(
            client: client,
            database: database,
            owner: owner,
            exchangedFiat: billDescription.exchangedFiat
        )
        
        let payload = operation.payload
        
        var primaryAction: BillState.PrimaryAction? = .init(asset: .airplane, title: "Send as a Link") { [weak self, weak operation] in
            if let operation, let self {
                // Disable scanning of the bill
                // while the share sheet is up
                operation.ignoresStream = true
                
                let payload       = operation.payload
                let exchangedFiat = billDescription.exchangedFiat
                
                do {
                    let giftCard = try await self.createCashLink(
                        payload: payload,
                        exchangedFiat: exchangedFiat
                    )
                    
                    self.showCashLinkShareSheet(
                        giftCard: giftCard,
                        exchangedFiat: exchangedFiat
                    )
                    
                } catch {
                    ErrorReporting.captureError(error)
                    showSomethingWentWrongError()
                }
            }
        }
        
        var secondaryAction: BillState.SecondaryAction? = .init(asset: .cancel, title: "Cancel") { [weak self] in
            self?.dismissCashBill(style: .slide)
        }
        
        if billDescription.received {
            Task {
                try await Task.delay(milliseconds: 750)
                valuation = BillValuation(
                    rendezvous: payload.rendezvous.publicKey,
                    exchangedFiat: billDescription.exchangedFiat,
                    mintMetadata: try database.getMintMetadata(mint: billDescription.exchangedFiat.mint)
                )
            }
            
            // Don't show actions for receives
            primaryAction   = nil
            secondaryAction = nil
        }
        
        sendOperation     = operation
        presentationState = .visible(billDescription.received ? .pop : .slide)
        billState         = .init(
            bill: .cash(payload),
            primaryAction: primaryAction,
            secondaryAction: secondaryAction,
        )
        
        operation.start { [weak self] result in
            switch result {
            case .success:
                self?.enqueue(toast: .init(
                    amount: billDescription.exchangedFiat.converted,
                    isDeposit: false
                ))
                
                self?.updatePostTransaction()
                
                self?.dismissCashBill(style: .pop)
                
                Analytics.transfer(
                    event: .giveBill,
                    exchangedFiat: billDescription.exchangedFiat,
                    successful: true,
                    error: nil
                )
                
            case .failure(let error):
                self?.dismissCashBill(style: .slide)
                
                ErrorReporting.capturePayment(
                    error: error,
                    rendezvous: payload.rendezvous.publicKey,
                    exchangedFiat: billDescription.exchangedFiat
                )
                
                Analytics.transfer(
                    event: .giveBill,
                    exchangedFiat: billDescription.exchangedFiat,
                    successful: false,
                    error: error
                )
            }
        }
    }
    
    private func showCashLinkShareSheet(giftCard: GiftCardCluster, exchangedFiat: ExchangedFiat) {
        UIApplication.isInterfaceResetDisabled = true
        
        let item = ShareCashLinkItem(giftCard: giftCard, exchangedFiat: exchangedFiat)
        ShareSheet.present(activityItem: item) { [weak self] didShare in
            guard let self = self else { return }
            
            let hideBillActions = {
                self.billState.primaryAction = nil
                self.billState.secondaryAction = nil
            }
            
            let cancelSend = {
                self.dismissCashBill(style: .slide)
                Task {
                    do {
                        try await self.cancelCashLink(giftCardVault: giftCard.cluster.vaultPublicKey)
                        self.updatePostTransaction()
                    } catch {
                        ErrorReporting.captureError(error)
                    }
                }
            }
            
            let completeSend = {
                _ = Task {
                    try await Task.delay(milliseconds: 250)
                    
                    self.enqueue(toast: .init(
                        amount: exchangedFiat.converted,
                        isDeposit: false
                    ))
                    
                    self.dismissCashBill(style: .pop)
                    self.updatePostTransaction()
                }
            }
            
            var confirmationDialog: DialogItem?
            
            confirmationDialog = .init(
                style: .success,
                title: "Did you send the link?",
                subtitle: "Any cash that isn't collected within 7 days will be automatically returned to your balance",
                dismissable: false,
            ) {
                .standard("Yes") {
                    hideBillActions()
                    completeSend()
                };
                
                .subtle("No, Cancel Send") {
                    self.dialogItem = .init(
                        style: .destructive,
                        title: "Are You Sure?",
                        subtitle: "Anyone you sent the link to won't be able to collect the cash",
                        dismissable: false,
                    ) {
                        .destructive("Yes") {
                            hideBillActions()
                            cancelSend()
                        };
                        
                        .subtle("Nevermind") {
                            self.dialogItem = confirmationDialog
                        }
                    }
                }
            }
            
            self.dialogItem = confirmationDialog
        }
    }
    
    func dismissCashBill(style: PresentationState.Style) {
        consumeToast()
        
        sendOperation = nil
        presentationState = .hidden(style)
        billState = .default()
        valuation = nil
        
        UIApplication.isInterfaceResetDisabled = false
    }
    
    // MARK: - Cash Links -
    
    private func createCashLink(payload: CashCode.Payload, exchangedFiat: ExchangedFiat) async throws -> GiftCardCluster {
        do {
            var vmAuthority = PublicKey.usdcAuthority
            var owner = owner
            
            // Ensure that our outgoing (source) account mint
            // matches the mint of the funds being sent
            if owner.timelock.mint != exchangedFiat.mint {
                guard let authority = try? database.getVMAuthority(mint: exchangedFiat.mint) else {
                    throw Error.vmMetadataMissing
                }
                
                vmAuthority = authority
                owner = owner.use(
                    mint: exchangedFiat.mint,
                    timeAuthority: authority
                )
            }
            
            let giftCard = GiftCardCluster(
                mint: exchangedFiat.mint,
                timeAuthority: vmAuthority
            )
            
            try await client.sendCashLink(
                exchangedFiat: exchangedFiat,
                ownerCluster: owner,
                giftCard: giftCard,
                rendezvous: payload.rendezvous.publicKey
            )
            
            Analytics.transfer(
                event: .sendCashLink,
                exchangedFiat: exchangedFiat,
                successful: true,
                error: nil
            )
            
            return giftCard
            
        } catch {
            ErrorReporting.captureError(error)
            
            Analytics.transfer(
                event: .sendCashLink,
                exchangedFiat: exchangedFiat,
                successful: false,
                error: error
            )
            
            // TODO: Show error
            
            throw error
        }
    }
    
    func cancelCashLink(giftCardVault: PublicKey) async throws {
        try await client.voidCashLink(giftCardVault: giftCardVault, owner: ownerKeyPair)
        
        updatePostTransaction()
    }
    
    func receiveCashLink(mnemonic: MnemonicPhrase) {
        let giftCardKeyPair = DerivedKey.derive(using: .solana, mnemonic: mnemonic).keyPair
        Task {
            do {
                let giftCardAccountInfo = try await client.fetchAccountInfo(
                    type: .giftCard,
                    owner: giftCardKeyPair
                )
                
                // For now, we need use(mint:) because exchangeData is returning USDC for mint
                guard let exchangedFiat = giftCardAccountInfo.exchangedFiat?.use(mint: giftCardAccountInfo.mint) else {
                    trace(.failure, components: "Gift card account info is missing ExchangeFiat.")
                    return
                }
                
                guard giftCardAccountInfo.claimState != .claimed && giftCardAccountInfo.claimState != .expired else {
                    showCashLinkNotAvailable()
                    return
                }
                
                // Fetch the mint metadata. We'll need it to create
                // the account cluster. Authority, address and duration
                // can all be different across VMs
                let vmMint       = giftCardAccountInfo.mint
                let mintMetadata = try await fetchMintMetadata(mint: vmMint)
                let vmAuthority  = mintMetadata.vmAuthority
                
                guard let vmAuthority else {
                    throw Error.vmMetadataMissing
                }
                
                // Now that we have a mint from account infos,
                // we can create the account cluster
                let giftCard = GiftCardCluster(
                    mnemonic: mnemonic,
                    mint: vmMint,
                    timeAuthority: vmAuthority
                )
                
                let mintCurrencyCluster = AccountCluster(
                    authority: keyAccount.derivedKey,
                    mint: vmMint,
                    timeAuthority: vmAuthority
                )
                
                // We need to ensure the accounts for this mint
                // are created. This call is a no-op is the
                // account already exists
                try await client.createAccounts(
                    owner: ownerKeyPair,
                    mint: vmMint,
                    cluster: mintCurrencyCluster,
                    kind: .primary,
                    derivationIndex: 0
                )
                
                // Deposit the gift card
                try await client.receiveCashLink(
                    usdc: exchangedFiat.usdc,
                    ownerCluster: owner.use(
                        mint: vmMint,
                        timeAuthority: vmAuthority
                    ),
                    giftCard: giftCard
                )
                
                updatePostTransaction()
                
                enqueue(toast: .init(
                    amount: exchangedFiat.converted,
                    isDeposit: true
                ))
                
                showCashBill(
                    .init(
                        kind: .cash,
                        exchangedFiat: exchangedFiat,
                        received: true
                    )
                )
                
                Analytics.transfer(
                    event: .receiveCashLink,
                    exchangedFiat: exchangedFiat,
                    successful: true,
                    error: nil
                )
                
            } catch {
                ErrorReporting.captureError(error)
                
                Analytics.transfer(
                    event: .receiveCashLink,
                    exchangedFiat: nil,
                    successful: false,
                    error: error
                )
                
                showCashLinkNotAvailable()
                trace(.failure, components: "Failed to receive cash link for gift card: \(giftCardKeyPair.publicKey)")
            }
        }
    }
    
//    func showCashLinkBillWithShareSheet(exchangedFiat: ExchangedFiat) {
//        let operation = SendCashOperation(
//            client: client,
//            owner: owner,
//            exchangedFiat: exchangedFiat
//        )
//        
//        let payload = operation.payload
//        
//        let owner    = owner
//        let giftCard = GiftCardCluster()
//        let item     = ShareCashLinkItem(giftCard: giftCard, exchangedFiat: exchangedFiat)
//        
//        ShareSheet.present(activityItem: item) { [weak self] didShare in
//            guard let self = self else { return }
//            
//            if didShare {
//                self.enqueue(toast: .init(
//                    amount: exchangedFiat.converted,
//                    isDeposit: false
//                ))
//            }
//            
//            self.dismissCashBill(style: didShare ? .pop : .slide)
//            
//            if didShare {
//                Task {
//                    do {
//                        try await self.client.sendCashLink(
//                            exchangedFiat: exchangedFiat,
//                            ownerCluster: owner,
//                            giftCard: giftCard,
//                            rendezvous: payload.rendezvous.publicKey
//                        )
//                        
//                        self.updateBalance()
//                        
//                    } catch {
//                        
//                        ErrorReporting.captureError(error)
//                        
//                        Analytics.transfer(
//                            event: .sendCashLink,
//                            exchangedFiat: exchangedFiat,
//                            successful: false,
//                            error: error
//                        )
//                        
//                        // TODO: Show error
//                    }
//                }
//            }
//        }
//        
//        Task {
//            try await Task.delay(milliseconds: 350)
//            
//            sendOperation     = operation
//            presentationState = .visible(.slide)
//            billState         = .init(
//                bill: .cash(payload)
//            )
//        }
//    }
    
    // MARK: - Errors -
    
    private func showSomethingWentWrongError() {
        dialogItem = .init(
            style: .destructive,
            title: "Something Went Wrong",
            subtitle: "Please try again later",
            dismissable: true
        ) {
            .okay(kind: .destructive)
        }
    }
    
    private func showCashLinkNotAvailable() {
        dialogItem = .init(
            style: .destructive,
            title: "Cash Already Collected",
            subtitle: "This cash has already been collected, or was cancelled by the sender",
            dismissable: true
        ) {
            .okay(kind: .destructive)
        }
    }
}

// MARK: - Errors -

extension Session {
    enum Error: Swift.Error {
        case cashLinkCreationFailed
        case vmMetadataMissing
        case mintNotFound
    }
}

// MARK: - ReceiveCashResult -

extension Session {
    enum ReceiveCashResult {
        case success
        case noStream
        case failed
    }
}

// MARK: - BillDescription -

extension Session {
    struct BillDescription {
        enum Kind {
            case cash
        }
        
        let kind: Kind
        let exchangedFiat: ExchangedFiat
        let received: Bool
        
        init(kind: Kind, exchangedFiat: ExchangedFiat, received: Bool) {
            self.kind = kind
            self.exchangedFiat = exchangedFiat
            self.received = received
        }
    }
}

// MARK: - Mock -

extension Session {
    static let mock = Session(
        container: .mock,
        historyController: .mock,
        ratesController: .mock,
        database: .mock,
        keyAccount: .mock,
        owner: .init(
            authority: .derive(using: .primary(), mnemonic: .mock),
            mint: .mock,
            timeAuthority: .usdcAuthority
        ),
        userID: UUID()
    )
}
