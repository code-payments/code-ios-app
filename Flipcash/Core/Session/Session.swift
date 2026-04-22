//
//  Session.swift
//  Code
//
//  Created by Dima Bart on 2025-04-15.
//

import UIKit
import FlipcashUI
import FlipcashCore

private let logger = Logger(label: "flipcash.session")

@MainActor
protocol SessionDelegate: AnyObject {
    func didDetectUnlockedAccount()
}

/// Central state object for an authenticated user session.
///
/// Holds balances, transaction limits, user profile, and UI presentation
/// state (bill display, toasts, dialogs). Balances and limits auto-refresh
/// from the local database via ``Updateable`` whenever `.databaseDidChange`
/// is posted.
///
/// Inject via `@Environment(Session.self)`. Use `@Bindable` when bindings
/// are needed (e.g. `$session.dialogItem` for sheets).
@MainActor @Observable
class Session {

    // MARK: - Database-Driven State -

    /// Current transaction limits, auto-refreshed from the database.
    var limits: Limits? {
        updateableLimits.value
    }

    // MARK: - UI Presentation State -

    /// The bill currently being displayed on the scan screen.
    var billState: BillState = .default()

    /// Controls bill slide-in/out animation.
    var presentationState: PresentationState = .hidden(.slide)

    /// Post-transaction amount display, shown as a sheet.
    var valuation: BillValuation? = nil

    /// The currently visible balance-change toast, or `nil` when none is shown.
    /// Set by ``consumeToast()`` and cleared after a 3-second display window.
    var toast: Toast? = nil

    /// App-wide modal dialog (confirmations, errors). Presented by
    /// ``DialogWindow`` in a separate `UIWindow` above all sheets.
    var dialogItem: DialogItem?

    // MARK: - User State -

    /// Server-fetched user profile.
    var profile: Profile?

    /// Feature flags for the current user.
    var userFlags: UserFlags?

    /// Active Coinbase onramp order, if any.
    var coinbaseOrder: OnrampOrderResponse?

    /// Navigation trigger for deep-linking to a currency info screen.
    var pendingCurrencyInfoMint: PublicKey? = nil

    @ObservationIgnored private var grabStarts: [PublicKey: Date] = [:]

    @ObservationIgnored let keyAccount: KeyAccount
    @ObservationIgnored let owner: AccountCluster
    @ObservationIgnored let userID: UserID
    
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
    
    /// Returns the server-provided send limit for the given currency, or `nil` if limits
    /// haven't been fetched yet. Callers pick the field appropriate for their flow:
    /// - Give: `nextTransaction` (remaining daily allowance, capped at `maxPerTransaction`)
    /// - Buy / WalletConnect / Onramp: `maxPerDay` (reused as per-transaction buy cap)
    func sendLimitFor(currency: CurrencyCode) -> SendLimit? {
        limits?.sendLimitFor(currency: currency)
    }
    
    var isShowingBill: Bool {
        billState.bill != nil
    }

    /// Whether a `ScanCashOperation` is currently in flight. Used by
    /// `ScanViewModel` to prevent new codes from being registered while
    /// a grab is being processed, avoiding orphaned entries in the
    /// scanned-rendezvous set.
    var isProcessingScan: Bool {
        scanOperation != nil
    }
    
    var hasCoinbaseOnramp: Bool {
        BetaFlags.shared.hasEnabled(.enableCoinbase) || userFlags?.hasCoinbase == true
    }
    
    var hasPreferredOnrampProvider: Bool {
        userFlags?.hasPreferredOnrampProvider == true
    }
    
    var totalBalance: ExchangedFiat {
        let rate = ratesController.rateForBalanceCurrency()

        return balances
            .map { $0.computeExchangedValue(with: rate) }
            .total(rate: rate)
    }
    
    var balances: [StoredBalance] {
        updateableBalances.value.sorted { lhs, rhs in
            if lhs.usdf != rhs.usdf {
                return lhs.usdf > rhs.usdf
            } else {
                return lhs.name.lexicographicallyPrecedes(rhs.name)
            }
        }
    }
    
    func balances(for rate: Rate) -> [ExchangedBalance] {
        balances.compactMap { stored in
            let exchangedFiat = stored.computeExchangedValue(with: rate)

            // Filter out balances with zero fiat value after conversion (except for USDC)
            guard stored.mint == .usdf || exchangedFiat.hasDisplayableValue() else {
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
    
    @ObservationIgnored private let container: Container
    @ObservationIgnored private let client: Client
    @ObservationIgnored private let flipClient: FlipClient
    @ObservationIgnored private let ratesController: RatesController
    @ObservationIgnored private let historyController: HistoryController
    @ObservationIgnored private let database: Database

    @ObservationIgnored private var poller: Poller!

    @ObservationIgnored private var scanOperation: ScanCashOperation?
    @ObservationIgnored private var sendOperation: SendCashOperation?

    /// Buffered toasts waiting to be displayed. Observation is ignored because
    /// the queue is an internal detail — only the published ``toast`` property
    /// drives UI updates.
    @ObservationIgnored private var toastQueue = ToastQueue()

    private var updateableBalances: Updateable<[StoredBalance]>!
    private var updateableLimits: Updateable<Limits?>!

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

        self.updateableBalances = Updateable { [weak self] in
            (try? self?.database.getBalances()) ?? []
        } didSet: { [weak self] in
            self?.ensureValidTokenSelection()
            self?.updateStreamingMints()
        }

        self.updateableLimits = Updateable { [weak self] in
            try? self?.database.getLimits()
        }

        // Ensure we have a valid token selected on initialization
        ensureValidTokenSelection()

        registerPoller()
        startStreaming()

        Task {
            try await updateProfile()
            try await updateUserFlags()
        }

        Task {
            await syncUserPreferences()
        }

        observeBalanceCurrencyChanges()
    }

    /// Start streaming live mint data for exchange rates
    private func startStreaming() {
        let mints = balances.filter { $0.quarks > 0 }.map { $0.mint }
        ratesController.startStreaming(mints: mints)
    }
    
    func prepareForLogout() {
        ratesController.prepareForLogout()
    }
    
    // MARK: - Token Selection -
    
    /// Ensures that a valid token is selected in the TokenController
    /// If the currently selected token doesn't exist in balances or is nil,
    /// it will automatically select the highest balance token
    private func ensureValidTokenSelection() {
        let currentBalances = balances

        // If no balances, nothing to select
        guard !currentBalances.isEmpty else {
            return
        }

        // Check if current selection is valid
        if let selectedTokenMint = ratesController.selectedTokenMint {
            let isValid = currentBalances.contains { $0.mint == selectedTokenMint }
            if isValid {
                return // Current selection is valid
            }
        }

        // No valid selection, default to highest balance (first in sorted list)
        if let highestBalance = currentBalances.first {
            ratesController.selectToken(highestBalance.mint)
        }
    }

    /// Updates the streaming subscription with the current balance mints
    private func updateStreamingMints() {
        let mints = balances.filter { $0.quarks > 0 }.map { $0.mint }
        ratesController.updateSubscribedMints(mints)
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

    // MARK: - Settings Sync -

    /// Syncs user locale and region preferences to the server.
    /// Fire-and-forget — best-effort server hints.
    func syncUserPreferences() async {
        try? await flipClient.updateSettings(
            locale: Locale.current.identifier(.bcp47),
            region: ratesController.balanceCurrency.rawValue,
            owner: ownerKeyPair
        )
    }

    /// Observes `balanceCurrency` changes on `RatesController` and
    /// syncs the updated region to the server. Re-registers after
    /// each change since `withObservationTracking` is one-shot.
    private func observeBalanceCurrencyChanges() {
        withObservationTracking {
            _ = ratesController.balanceCurrency
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                await self?.syncUserPreferences()
                self?.observeBalanceCurrencyChanges()
            }
        }
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
    
    func didBecomeActive() {
        ratesController.ensureStreamConnected()
    }

    func didEnterBackground() {
        // If the sendOperation is ignoring stream, it's likely
        // presenting a share sheet or in some way mid-process
        // so we don't want to dismiss the bill from under it
        if let sendOperation, !sendOperation.ignoresStream {
            dismissCashBill(style: .slide)
        }
    }
    
    // MARK: - Balance -
    
    
    func hasSufficientFunds(for exchangedFiat: ExchangedFiat) -> SufficientFundsResult {
        guard exchangedFiat.onChainAmount.quarks > 0 else {
            return .insufficient(shortfall: nil)
        }

        guard let balance = balance(for: exchangedFiat.mint) else {
            return .insufficient(shortfall: nil)
        }

        let entryRate = ratesController.rateForEntryCurrency()
        let exchangedBalance = balance.computeExchangedValue(with: entryRate)

        if exchangedFiat.onChainAmount <= exchangedBalance.onChainAmount {
            // Sufficient funds - send the requested amount
            return .sufficient(amountToSend: exchangedFiat)
        } else {
            let deltaToBalanceInFiat = abs(exchangedBalance.nativeAmount.value - exchangedFiat.nativeAmount.value)

            // Calculate tolerance as half the smallest denomination for this currency
            // USD (2 decimals): 0.01 / 2 = 0.005 (half a penny)
            // JPY (0 decimals): 1.0 / 2 = 0.5 (half a yen)
            // BHD (3 decimals): 0.001 / 2 = 0.0005 (half a fils)
            let decimals = exchangedFiat.nativeAmount.currency.maximumFractionDigits
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
                return .insufficient(shortfall: exchangedFiat.subtracting(exchangedBalance))
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
    
    private var didAttemptBuy = false
    private func poll() async throws {
        // Limits failure must not block balance fetch
        try? await fetchLimitsIfNeeded()
        try await fetchBalance()
    }
    
    // MARK: - Limits -
    
    private func fetchLimitsIfNeeded() async throws {
        if limits == nil || limits?.isStale == true {
            if limits != nil {
                logger.info("Limits stale, refreshing")
            }
            try await fetchLimits()
        }
    }
    
    private func fetchLimits() async throws {
        let fetchedLimits = try await client.fetchTransactionLimits(
            owner: ownerKeyPair,
            since: .todayAtMidnight()
        )

        database.transaction { database in
            try? database.insertLimits(fetchedLimits)
        }

        if let usdLimit = fetchedLimits.sendLimitFor(currency: .usd) {
            logger.info("Limits updated", metadata: [
                "usd_max_per_tx": "\(usdLimit.maxPerTransaction.value)",
                "usd_next_tx": "\(usdLimit.nextTransaction.value)",
                "usd_max_per_day": "\(usdLimit.maxPerDay.value)",
            ])
        }
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
                    costBasis: account.usdCostBasis,
                    date: now
                )
            }
        }
    }
    
    func updateBalance() {
        Task {
            do {
                try await fetchBalance()
            } catch {
                logger.error("Balance fetch failed", metadata: ["error": "\(error)"])
            }
        }
    }

    func updatePostTransaction() {
        logger.info("Post-transaction update triggered")
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

    /// Enqueues a toast and kicks off consumption if no toast is currently visible.
    private func show(toast: Toast) {
        enqueue(toast: toast)
        if self.toast == nil {
            consumeToast()
        }
    }

    /// Adds a toast to the queue without triggering consumption.
    ///
    /// Preferred over ``show(toast:)`` when consumption will be triggered
    /// externally (e.g. after a bill is dismissed via ``dismissCashBill``).
    private func enqueue(toast: Toast) {
        toastQueue.insert(toast)
    }

    /// Pops the next toast from the queue and displays it for 3 seconds.
    ///
    /// Consumption is deferred while a bill is on screen — ``dismissCashBill``
    /// calls this method once the bill is cleared so queued toasts resume.
    /// After each toast, a 1-second gap separates consecutive notifications.
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
                logger.debug("Bill showing, waiting for toasts to resume...")
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
    
    // MARK: - Swaps -

    @discardableResult
    func buy(amount: ExchangedFiat, of mint: PublicKey) async throws -> SwapId {
        let token = try await fetchMintMetadata(mint: mint)

        // Get verified state for intent construction
        guard let verifiedState = await ratesController.getVerifiedState(
            for: amount.nativeAmount.currency,
            mint: amount.mint
        ) else {
            throw Error.missingVerifiedState
        }

        logger.info("buying", metadata: ["amount": "\(amount.nativeAmount.formatted())", "symbol": "\(token.symbol)"])

        return try await client.buy(amount: amount, verifiedState: verifiedState, of: token.metadata, owner: owner)
    }

    @discardableResult
    func buyWithExternalFunding(
        amount: ExchangedFiat,
        of mint: PublicKey,
        transactionSignature: Signature
    ) async throws -> SwapId {
        let token = try await fetchMintMetadata(mint: mint)
        let swapId = SwapId.generate()

        return try await client.buyWithExternalFunding(
            swapId: swapId,
            amount: amount,
            of: token.metadata,
            owner: owner,
            transactionSignature: transactionSignature
        )
    }

    @discardableResult
    func launchCurrency(
        name: String,
        description: String,
        billColors: [String],
        icon: Data,
        nameAttestation: ModerationAttestation,
        descriptionAttestation: ModerationAttestation,
        iconAttestation: ModerationAttestation
    ) async throws -> PublicKey {
        logger.info("Launching currency")

        let mint = try await client.launch(
            name: name,
            description: description,
            billColors: billColors,
            icon: icon,
            nameAttestation: nameAttestation,
            descriptionAttestation: descriptionAttestation,
            iconAttestation: iconAttestation,
            owner: ownerKeyPair
        )

        logger.info("Currency launched", metadata: ["mint": "\(mint.base58)"])
        return mint
    }

    @discardableResult
    func buyNewCurrency(
        amount: ExchangedFiat,
        feeAmount: ExchangedFiat,
        mint: PublicKey,
        swapId: SwapId = .generate()
    ) async throws -> SwapId {
        logger.info("Buying new currency", metadata: [
            "amount": "\(amount.nativeAmount.formatted())",
            "feeAmount": "\(feeAmount.nativeAmount.formatted())",
            "mint": "\(mint.base58)",
            "swapId": "\(swapId.publicKey.base58)"
        ])

        // Phase 2 funding (IntentFundSwap) requires a verified state for the
        // source mint — USDF for a reserves-funded launch.
        guard let verifiedState = await ratesController.getVerifiedState(
            for: amount.nativeAmount.currency,
            mint: amount.mint
        ) else {
            throw Error.missingVerifiedState
        }

        // Intentionally no fetchMintMetadata: a freshly-launched currency isn't
        // yet in the local DB, and in dry-run mode the server doesn't surface it
        // via fetchMints either. The new-currency swap path in SwapService skips
        // VM/launchpad metadata validation, and SwapInstructionBuilder derives
        // every account from the ReserveNewCurrencyServerParameter, so the mint
        // PublicKey is all we need.
        let metadata = try await client.buyNewCurrency(
            swapId: swapId,
            amount: amount,
            feeAmount: feeAmount,
            verifiedState: verifiedState,
            mint: mint,
            owner: owner
        )

        logger.info("New currency buy completed", metadata: [
            "swapId": "\(metadata.swapId.publicKey.base58)",
            "state": "\(metadata.state)"
        ])

        updatePostTransaction()
        return metadata.swapId
    }

    @discardableResult
    func buyNewCurrencyWithExternalFunding(
        amount: ExchangedFiat,
        feeAmount: ExchangedFiat,
        mint: PublicKey,
        transactionSignature: Signature
    ) async throws -> SwapId {
        logger.info("Buying new currency (external funding)", metadata: [
            "amount": "\(amount.nativeAmount.formatted())",
            "feeAmount": "\(feeAmount.nativeAmount.formatted())",
            "mint": "\(mint.base58)"
        ])

        let swapId = SwapId.generate()
        let metadata = try await client.buyNewCurrencyWithExternalFunding(
            swapId: swapId,
            amount: amount,
            feeAmount: feeAmount,
            mint: mint,
            owner: ownerKeyPair,
            transactionSignature: transactionSignature
        )

        logger.info("New currency buy (external) completed", metadata: [
            "swapId": "\(metadata.swapId.publicKey.base58)",
            "state": "\(metadata.state)"
        ])

        updatePostTransaction()
        return metadata.swapId
    }

    @discardableResult
    func sell(amount: ExchangedFiat, in mint: PublicKey) async throws -> SwapId {
        let token = try await fetchMintMetadata(mint: mint)

        // Get verified state for intent construction
        guard let verifiedState = await ratesController.getVerifiedState(
            for: amount.nativeAmount.currency,
            mint: amount.mint
        ) else {
            throw Error.missingVerifiedState
        }

        guard let supply = verifiedState.supplyFromBonding else {
            throw Error.missingSupply
        }

        // Cap to the on-chain balance when rounding pushed quarks above it.
        // compute(fromEntered:) already round-trips through compute(onChainAmount:)
        // for server consistency, so we only need to recompute when capping.
        let amountForIntent: ExchangedFiat
        if let balance = balance(for: mint),
           amount.onChainAmount.quarks > balance.quarks,
           mint != .usdf {
            amountForIntent = ExchangedFiat.compute(
                onChainAmount: TokenAmount(quarks: balance.quarks, mint: mint),
                rate: ratesController.rateForEntryCurrency(),
                supplyQuarks: supply
            )
        } else {
            amountForIntent = amount
        }

        logger.info("selling", metadata: ["amount": "\(amountForIntent.nativeAmount.formatted())", "symbol": "\(token.symbol)"])

        return try await client.sell(amount: amountForIntent, verifiedState: verifiedState, in: token.metadata, owner: owner)
    }
    
    // MARK: - Withdrawals -
    
    func withdraw(exchangedFiat: ExchangedFiat, fee: TokenAmount, to destinationMetadata: DestinationMetadata) async throws {
        let rendezvous = PublicKey.generate()!
        let mint = exchangedFiat.mint
        do {
            guard let vmAuthority = try database.getVMAuthority(mint: mint) else {
                throw Error.vmMetadataMissing
            }

            // Get verified state for intent construction
            guard let verifiedState = await ratesController.getVerifiedState(
                for: exchangedFiat.nativeAmount.currency,
                mint: mint
            ) else {
                throw Error.missingVerifiedState
            }

            try await self.client.withdraw(
                exchangedFiat: exchangedFiat,
                verifiedState: verifiedState,
                fee: fee,
                owner: owner.use(
                    mint: mint,
                    timeAuthority: vmAuthority
                ),
                destinationMetadata: destinationMetadata
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
    
    /// Completes a face-to-face bill grab after the camera scans a cash code.
    ///
    /// ## Device A (Sender)
    /// Displays a bill (`showCashBill` → `SendCashOperation`), encoding a
    /// rendezvous keypair and amount into a visual cash code.
    ///
    /// ## Device B (Receiver — this method)
    /// 1. **Scan** — Camera decodes the cash code payload (rendezvous + amount).
    /// 2. **Delegate to `ScanCashOperation`** — Handles the full grab handshake
    ///    (listen for mint, create accounts, grab, poll for settlement).
    /// 3. **Post-transaction** — Refresh balances and show a received-bill UI
    ///    via `showCashBill` with the `VerifiedState` from the sender's message.
    ///
    /// The received bill becomes a **live `SendCashOperation`** — other users
    /// can scan Device B's screen to continue the "quick give and grab" chain.
    func receiveCash(_ payload: CashCode.Payload, completion: @escaping (ReceiveCashResult) -> Void) {
        // Record the start date of when
        // we first saw the bill and match
        // it to the rendezvous
        grabStarts[payload.rendezvous.publicKey] = .now
        
        print("Scanned: \(payload.fiat.formatted()) \(payload.fiat.currency)")
        
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
                // Track grab initiation to measure the start-to-completion funnel
                Analytics.transferStart(event: .grabBillStart)

                let metadata = try await operation.start()

                updatePostTransaction()

                // Toast: user grabbed cash by scanning a bill (+amount)
                enqueue(toast: .init(
                    amount: metadata.exchangedFiat.nativeAmount,
                    isDeposit: true
                ))

                showCashBill(.init(
                    kind: .cash,
                    exchangedFiat: metadata.exchangedFiat,
                    received: true,
                    verifiedState: metadata.verifiedState
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
                // The sender's stream is no longer open, so the
                // bill has expired or was dismissed.
                completion(.noStream)

            } catch ClientError.denied {
                // Another device grabbed this bill first. Stop polling
                // and silently reset so the scanner can pick up new codes.
                logger.warning("Scan denied (concurrent grab)", metadata: ["rendezvous": "\(payload.rendezvous.publicKey.base58)"])
                completion(.failed)

            } catch ClientError.pollLimitReached {
                // The intent was never fulfilled for this receiver.
                // The transfer didn't complete in time. Silently reset
                // so the user can retry by scanning again.
                completion(.failed)

            } catch MessagingWaitError.timedOut {
                // No advertisement arrived on the rendezvous stream within
                // the wait window — the bill is stale or the sender is gone.
                // Silently reset so the user can retry by scanning again.
                completion(.failed)

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
                showSomethingWentWrongError()
                completion(.failed)
            }
        }
    }
    
    func showCashBill(_ billDescription: BillDescription) {
        // Clear pending navigation so deep link triggers don't
        // re-present sheets after the bill dismisses them.
        pendingCurrencyInfoMint = nil

        let operation = SendCashOperation(
            client: client,
            database: database,
            ratesController: ratesController,
            owner: owner,
            exchangedFiat: billDescription.exchangedFiat,
            verifiedState: billDescription.verifiedState
        )
        
        let payload = operation.payload
        
        var primaryAction: BillState.PrimaryAction? = .init(asset: .airplane, title: "Send as a Link") { [weak self, weak operation] in
            if let operation, let self {
                // Suppress grab-request processing on the rendezvous stream
                // while the share sheet is up (keeps the bill alive underneath).
                operation.ignoresStream = true
                
                let payload       = operation.payload
                let exchangedFiat = billDescription.exchangedFiat
                
                do {
                    let giftCard = try await self.createCashLink(
                        payload: payload,
                        exchangedFiat: exchangedFiat
                    )

                    guard self.isShowingBill && self.sendOperation === operation else {
                        // The bill was dismissed (e.g. operation failed) OR a
                        // new bill was pulled while this link was being created.
                        // Either way this gift card belongs to a bill the user
                        // has moved on from — void it to return the funds.
                        do {
                            try await self.cancelCashLink(
                                giftCardVault: giftCard.cluster.vaultPublicKey
                            )
                        } catch {
                            ErrorReporting.capturePayment(
                                error: error,
                                rendezvous: payload.rendezvous.publicKey,
                                exchangedFiat: exchangedFiat,
                                reason: "Failed to void gift card after bill dismissed during cash link creation"
                            )
                        }
                        self.updatePostTransaction()
                        return
                    }

                    self.showCashLinkShareSheet(
                        giftCard: giftCard,
                        exchangedFiat: exchangedFiat
                    )

                } catch {
                    ErrorReporting.captureError(error)
                    // Suppress late-arriving errors from stale/orphaned tasks
                    // (e.g. gRPC stream finally giving up minutes later) so they
                    // don't fire dialogs on unrelated bills the user has moved on to.
                    if self.isShowingBill && self.sendOperation === operation {
                        self.showSomethingWentWrongError()
                    }
                }
            }
        }

        var secondaryAction: BillState.SecondaryAction? = .init(asset: .cancel, title: nil) { [weak self] in
            self?.dismissCashBill(style: .slide)
        }
        
        let storedMintMetadata = try? database.getMintMetadata(mint: billDescription.exchangedFiat.mint)

        if billDescription.received {
            Task {
                try await Task.delay(milliseconds: 750)
                valuation = BillValuation(
                    rendezvous: payload.rendezvous.publicKey,
                    exchangedFiat: billDescription.exchangedFiat,
                    mintMetadata: storedMintMetadata
                )
            }

            // Don't show actions for receives
            primaryAction   = nil
            secondaryAction = nil
        }

        let billColors = storedMintMetadata?.metadata.billColors ?? []

        sendOperation     = operation
        presentationState = .visible(billDescription.received ? .pop : .slide)
        billState         = .init(
            bill: .cash(payload, mint: billDescription.exchangedFiat.mint, billColors: billColors),
            primaryAction: primaryAction,
            secondaryAction: secondaryAction,
        )
        
        // Track give initiation to measure the start-to-completion funnel.
        // Only for outgoing bills — received bills are displayed after a
        // successful grab and don't represent a new give action.
        if !billDescription.received {
            Analytics.transferStart(event: .giveBillStart)
        }

        Task { [weak self] in
            do {
                try await operation.start()

                // Toast: someone grabbed the user's bill (-amount)
                self?.enqueue(toast: .init(
                    amount: billDescription.exchangedFiat.nativeAmount,
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
            } catch is CancellationError {
                // Cancelled by dismissCashBill — no error UI, no analytics.
                return
            } catch {
                // Diagnostics + ErrorReporting happen inside SendCashOperation.
                self?.dismissCashBill(style: .slide)
                self?.showCashReturnedError()

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
                    } catch {
                        ErrorReporting.captureError(error)
                    }
                }
            }
            
            let completeSend = {
                _ = Task {
                    try await Task.delay(milliseconds: 250)

                    // Toast: user confirmed sending a cash link (-amount)
                    self.enqueue(toast: .init(
                        amount: exchangedFiat.nativeAmount,
                        isDeposit: false
                    ))
                    
                    self.dismissCashBill(style: .pop)
                    self.updatePostTransaction()
                }
            }
            
            var confirmationDialog: DialogItem?
            
            confirmationDialog = .init(
                style: .success,
                title: "Did You Send The Link?",
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
        sendOperation?.cancel()
        sendOperation = nil
        presentationState = .hidden(style)
        billState = .default()
        valuation = nil

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

            // Wait for verified state. The in-memory cache is empty on cold
            // launch until the live mint stream delivers the first batch, so
            // polling matches the receive path's behavior at `receiveCashLink`
            // below and avoids a spurious error when the user taps Send within
            // the first few seconds of relaunching the app.
            guard let verifiedState = await ratesController.awaitVerifiedState(
                for: exchangedFiat.nativeAmount.currency,
                mint: exchangedFiat.mint
            ) else {
                throw Error.missingVerifiedState
            }

            try await client.sendCashLink(
                exchangedFiat: exchangedFiat,
                verifiedState: verifiedState,
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
    
    /// Receives a Cash Link (gift card) opened via deep link.
    ///
    /// ## Device A (Sender)
    /// 1. Created the gift card via `createCashLink`, which funded a gift-card
    ///    account on-chain and generated a mnemonic-backed deep link URL.
    /// 2. Shared the link externally (iMessage, WhatsApp, etc.).
    ///
    /// ## Device B (Receiver — this method)
    /// 1. **Derive keys** — Reconstruct the gift card keypair from the mnemonic
    ///    embedded in the deep link.
    /// 2. **Fetch gift card info** — Query the server for the gift card account's
    ///    balance (`ExchangedFiat`), claim state, and mint.
    /// 3. **Fetch mint metadata** — Obtain the VM authority for the gift card's
    ///    mint so we can derive the correct account cluster.
    /// 4. **Subscribe to mint** — Add the mint to the live stream early so
    ///    verified state arrives while the blocking calls below execute.
    /// 5. **Create accounts** — Ensure Device B has token accounts for this mint
    ///    (no-op if they already exist).
    /// 6. **Deposit** — Call `receiveCashLink` to move funds from the gift card
    ///    vault into Device B's vault.
    /// 7. **Await verified state** — Wait for the exchange-rate and reserve-state
    ///    proofs to arrive from the stream. Required for launchpad currencies.
    /// 8. **Show bill** — Display the received bill with a `SendCashOperation`
    ///    so others can scan it from Device B's screen.
    func receiveCashLink(mnemonic: MnemonicPhrase, claimIfOwned: Bool = false) {
        let giftCardKeyPair = DerivedKey.derive(using: .solana, mnemonic: mnemonic).keyPair
        Task {
            do {
                let giftCardAccountInfo = try await fetchAccountInfoWithRetry(
                    type: .giftCard,
                    owner: giftCardKeyPair
                )

                guard let exchangedFiat = giftCardAccountInfo.exchangedFiat else {
                    logger.error("Gift card account info is missing ExchangeFiat.")
                    return
                }

                guard giftCardAccountInfo.claimState != .claimed && giftCardAccountInfo.claimState != .expired else {
                    logger.info("Cash link not available", metadata: [
                        "claimState": "\(giftCardAccountInfo.claimState)",
                        "giftCardAuthority": "\(giftCardKeyPair.publicKey.base58)",
                    ])
                    showCashLinkNotAvailable()
                    return
                }

                if giftCardAccountInfo.isGiftCardIssuer && !claimIfOwned {
                    logger.info("Cash link self-claim detected", metadata: [
                        "giftCardAuthority": "\(giftCardKeyPair.publicKey.base58)",
                        "currency": "\(exchangedFiat.currencyRate.currency.rawValue)",
                    ])
                    showCollectOwnCashConfirmation(
                        mnemonic: mnemonic,
                        giftCardAuthority: giftCardKeyPair.publicKey
                    )
                    return
                }

                // Resolve the mint metadata. We'll need it to create
                // the account cluster. Authority, address and duration
                // can all be different across VMs.
                // Prefer inline metadata from the account info response
                // to avoid an extra network round-trip.
                let vmMint = giftCardAccountInfo.mint
                let vmAuthority: PublicKey?
                if let inlineMint = giftCardAccountInfo.mintMetadata {
                    // Persist so SendCashOperation can find it
                    // for the quick give-and-grab chain.
                    try? database.insert(mints: [inlineMint], date: .now)
                    vmAuthority = inlineMint.vmMetadata?.authority
                } else {
                    let mintMetadata = try await fetchMintMetadata(mint: vmMint)
                    vmAuthority = mintMetadata.vmAuthority
                }
                
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
                
                // Subscribe to this mint's live data early so the stream
                // has time to deliver verified state while we create
                // accounts and deposit the gift card below.
                ratesController.ensureMintSubscribed(vmMint)

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
                    usdf: exchangedFiat.onChainAmount,
                    ownerCluster: owner.use(
                        mint: vmMint,
                        timeAuthority: vmAuthority
                    ),
                    giftCard: giftCard
                )

                // Wait for verified state — the stream was subscribed
                // above, so data should arrive during the blocking calls.
                // Required for launchpad currencies in the quick-give-and-grab chain.
                let verifiedState = await ratesController.awaitVerifiedState(
                    for: exchangedFiat.nativeAmount.currency,
                    mint: vmMint
                )

                updatePostTransaction()

                // Toast: user redeemed a cash link (+amount)
                enqueue(toast: .init(
                    amount: exchangedFiat.nativeAmount,
                    isDeposit: true
                ))

                showCashBill(
                    .init(
                        kind: .cash,
                        exchangedFiat: exchangedFiat,
                        received: true,
                        verifiedState: verifiedState
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
                logger.error("Failed to receive cash link for gift card", metadata: ["public_key": "\(giftCardKeyPair.publicKey)"])
                ErrorReporting.captureError(error)

                Analytics.transfer(
                    event: .receiveCashLink,
                    exchangedFiat: nil,
                    grabTime: nil,
                    successful: false,
                    error: error
                )

                if error is ErrorFetchBalance {
                    showCashLinkConnectionError()
                } else {
                    showSomethingWentWrongError()
                }
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

    private func showCashLinkConnectionError() {
        dialogItem = .init(
            style: .destructive,
            title: "Unable to Find Cash",
            subtitle: "Please check your connection and try again",
            dismissable: true
        ) {
            .okay(kind: .destructive)
        }
    }

    private func showCollectOwnCashConfirmation(
        mnemonic: MnemonicPhrase,
        giftCardAuthority: PublicKey
    ) {
        dialogItem = .init(
            style: .destructive,
            title: "Collect Your Own Cash?",
            subtitle: "You tapped to collect the cash you sent. Are you sure you want to collect it yourself?",
            dismissable: false,
        ) {
            .destructive("Collect") { [weak self] in
                guard let self else { return }
                logger.info("Cash link self-claim confirmed", metadata: [
                    "giftCardAuthority": "\(giftCardAuthority.base58)",
                ])
                self.receiveCashLink(mnemonic: mnemonic, claimIfOwned: true)
            };

            .subtle("Don't Collect") {
                logger.info("Cash link self-claim cancelled", metadata: [
                    "giftCardAuthority": "\(giftCardAuthority.base58)",
                ])
            }
        }
    }

    // MARK: - Helpers -

    private func fetchAccountInfoWithRetry(type: AccountInfoType, owner: KeyPair) async throws -> AccountInfo {
        let maxAttempts = 3

        for i in 0..<maxAttempts {
            do {
                return try await client.fetchAccountInfo(type: type, owner: owner, requestingOwner: ownerKeyPair)
            } catch let error as ErrorFetchBalance {
                switch error {
                case .notFound, .unknown:
                    if i < maxAttempts - 1 {
                        logger.warning("fetchAccountInfo failed, retrying", metadata: ["error": "\(error)", "attempt": "\(i + 1)/\(maxAttempts)"])
                        try await Task.delay(milliseconds: 500)
                    } else {
                        throw error
                    }
                case .accountNotInList, .parseFailed, .ok:
                    throw error
                }
            }
        }

        // Unreachable: the loop always returns or throws on the last attempt
        throw ErrorFetchBalance.unknown
    }
}

// MARK: - Errors -

extension Session {
    enum Error: Swift.Error {
        case cashLinkCreationFailed
        case vmMetadataMissing
        case mintNotFound
        case insufficientBalance
        case missingVerifiedState
        case missingSupply
        case unableToConvertToFiat
        
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
        let verifiedState: VerifiedState?

        init(kind: Kind, exchangedFiat: ExchangedFiat, received: Bool, verifiedState: VerifiedState? = nil) {
            self.kind = kind
            self.exchangedFiat = exchangedFiat
            self.received = received
            self.verifiedState = verifiedState
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
