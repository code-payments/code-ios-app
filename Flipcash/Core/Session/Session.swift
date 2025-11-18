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
    @Published var isShowingBillEditor: Bool = false

    private var grabStarts: [PublicKey: Date] = [:]

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
//            underlying: totalUSDC,
//            rate: ratesController.rateForBalanceCurrency(),
//            mint: .usdc
//        )
//    }
//    
//    var exchangedEntryBalance: ExchangedFiat {
//        try! ExchangedFiat(
//            underlying: totalUSDC,
//            rate: ratesController.rateForEntryCurrency(),
//            mint: .usdc
//        )
//    }
    
    var nextTransactionLimit: Quarks? {
        nextTransactionLimit(currency: ratesController.rateForEntryCurrency().currency)
    }
    
    func nextTransactionLimit(currency: CurrencyCode) -> Quarks? {
        guard let limits else {
            return nil
        }
        
        guard let limit = limits.sendLimitFor(currency: currency) else {
            return nil
        }
        
        return limit.nextTransaction
    }
    
    var singleTransactionLimit: Quarks? {
        singleTransactionLimitFor(currency: ratesController.entryCurrency)
    }
    
    func singleTransactionLimitFor(currency: CurrencyCode) -> Quarks? {
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
    
    var totalBalance: ExchangedFiat {
        var usdBalance: Decimal = 0
        balances.forEach { balance in
            let exchanged = balance.computeExchangedValue(with: .oneToOne) // Compute USD value
            usdBalance += exchanged.converted.decimalValue
        }
        
        let balanceMint = PublicKey.usdc
        let totalUSD    = try! Quarks(
            fiatDecimal: usdBalance,
            currencyCode: .usd,
            decimals: balanceMint.mintDecimals
        )
        
        let exchanged = try! ExchangedFiat(
            underlying: totalUSD,
            rate: ratesController.rateForBalanceCurrency(),
            mint: .usdc
        )
        
        return exchanged
    }
    
    var balances: [StoredBalance] {
        updateableBalances.value.sorted { lhs, rhs in
            if lhs.usdcValue != rhs.usdcValue {
                return lhs.usdcValue > rhs.usdcValue
            } else {
                return lhs.name.lexicographicallyPrecedes(rhs.name)
            }
        }
    }
    
    func balances(for rate: Rate) -> [ExchangedBalance] {
        balances.compactMap { stored in
            let exchangedFiat = stored.computeExchangedValue(with: rate)

            // Filter out balances with zero fiat value after conversion
            guard exchangedFiat.hasDisplayableValue() else {
                return nil
            }

            return ExchangedBalance(
                stored: stored,
                exchangedFiat: exchangedFiat
            )
        }
    }
    
    func balance(for mint: PublicKey) -> StoredBalance? {
        balances.filter {
            $0.mint == mint
        }.first
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
        } didSet: { [weak self] in
            self?.objectWillChange.send()
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
        
        return exchangedFiat.converted <= nextTransactionLimit
    }
    
    func hasSufficientFunds(for exchangedFiat: ExchangedFiat) -> SufficientFundsResult {
        guard exchangedFiat.underlying.quarks > 0 else {
            return .insufficient(shortfall: nil)
        }

        guard let balance = balance(for: exchangedFiat.mint) else {
            return .insufficient(shortfall: nil)
        }

        let entryRate = ratesController.rateForEntryCurrency()
        let exchangedBalance = balance.computeExchangedValue(with: entryRate)

        if exchangedFiat.underlying <= exchangedBalance.underlying {
            // Sufficient funds - send the requested amount
            return .sufficient(amountToSend: exchangedFiat)
        } else {
            let deltaToBalanceInFiat = abs(exchangedBalance.converted.decimalValue - exchangedFiat.converted.decimalValue)

            // Calculate tolerance as half the smallest denomination for this currency
            // USD (2 decimals): 0.01 / 2 = 0.005 (half a penny)
            // JPY (0 decimals): 1.0 / 2 = 0.5 (half a yen)
            // BHD (3 decimals): 0.001 / 2 = 0.0005 (half a fils)
            let decimals = exchangedFiat.converted.currencyCode.maximumFractionDigits
            let smallestDenomination = pow(10.0, -Double(decimals))
            let tolerance = smallestDenomination / 2.0

            // If the amount being sent is within half the smallest denomination,
            // we'll consider it sufficient. Only applies to max sends.
            // Return the balance amount so the caller sends the
            // actual balance instead of the requested amount.
            if deltaToBalanceInFiat <= Decimal(tolerance) {
                print("Attempt max send, within error tolerance")
                return .sufficient(amountToSend: exchangedBalance)
            } else {
                let shortfall = try! exchangedFiat.subtracting(exchangedBalance)
                return .insufficient(shortfall: shortfall)
            }
        }
    }
    
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
//            trace(.note, components: "Showing toast: \(toast!.amount.formatted())")
            
            try await Task.delay(seconds: 3)
            toast = nil
            
            if toastQueue.hasToasts {
                try await Task.delay(milliseconds: 1000)
                consumeToast()
            }
        }
    }
    
    // MARK: - Withdrawals -
    
    func withdraw(exchangedFiat: ExchangedFiat, fee: Quarks, to destinationMetadata: DestinationMetadata) async throws {
        let rendezvous = PublicKey.generate()!
        let mint = exchangedFiat.mint
        do {
            guard let vmAuthority = try database.getVMAuthority(mint: mint) else {
                throw Error.vmMetadataMissing
            }
            
            try await self.client.withdraw(
                exchangedFiat: exchangedFiat,
                fee: fee,
                owner: owner.use(
                    mint: mint,
                    timeAuthority: vmAuthority
                ),
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
        // Record the start date of when
        // we first saw the bill and match
        // it to the rendezvous
        grabStarts[payload.rendezvous.publicKey] = .now
        
        print("Scanned: \(payload.fiat.formatted()) \(payload.fiat.currencyCode)")
        
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
                
                var grabTimeInSeconds: Double? = nil
                if let start = grabStarts[payload.rendezvous.publicKey] {
                    grabTimeInSeconds = Date.now.timeIntervalSince1970 - start.timeIntervalSince1970
                }
                
                Analytics.transfer(
                    event: .grabBill,
                    exchangedFiat: metadata.exchangedFiat,
                    grabTime: grabTimeInSeconds,
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
            bill: .cash(payload, mint: billDescription.exchangedFiat.mint),
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
                    grabTime: nil,
                    successful: true,
                    error: nil
                )
                
            case .failure(let error):
                self?.dismissCashBill(style: .slide)
                self?.showCashReturnedError()
                
                ErrorReporting.capturePayment(
                    error: error,
                    rendezvous: payload.rendezvous.publicKey,
                    exchangedFiat: billDescription.exchangedFiat
                )
                
                Analytics.transfer(
                    event: .giveBill,
                    exchangedFiat: billDescription.exchangedFiat,
                    grabTime: nil,
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
        sendOperation = nil
        presentationState = .hidden(style)
        billState = .default()
        valuation = nil

        UIApplication.isInterfaceResetDisabled = false

        // Consume toast after bill state is cleared
        // so isShowingBill returns false
        consumeToast()
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
                grabTime: nil,
                successful: true,
                error: nil
            )
            
            return giftCard
            
        } catch {
            ErrorReporting.captureError(error)
            
            Analytics.transfer(
                event: .sendCashLink,
                exchangedFiat: exchangedFiat,
                grabTime: nil,
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
                
                guard let exchangedFiat = giftCardAccountInfo.exchangedFiat else {
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
                    usdc: exchangedFiat.underlying,
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
                    grabTime: nil,
                    successful: true,
                    error: nil
                )
                
            } catch {
                ErrorReporting.captureError(error)
                
                Analytics.transfer(
                    event: .receiveCashLink,
                    exchangedFiat: nil,
                    grabTime: nil,
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
    
    private func showCashReturnedError() {
        dialogItem = .init(
            style: .destructive,
            title: "Something Went Wrong",
            subtitle: "The cash was returned to your wallet",
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

// MARK: - SufficientFundsResult -

extension Session {
    enum SufficientFundsResult {
        /// User has sufficient funds to send
        /// - Parameter amountToSend: The amount to actually send (may be adjusted from requested amount due to tolerance)
        case sufficient(amountToSend: ExchangedFiat)

        /// User does not have sufficient funds
        /// - Parameter shortfall: The amount the user is short by (nil if no balance exists)
        case insufficient(shortfall: ExchangedFiat?)
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
