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

protocol SessionDelegate: AnyObject {
    func didDetectUnlockedAccount()
}

/// Central state object for an authenticated user session.
///
/// Holds balances, transaction limits, user profile, and UI presentation
/// state (bill display, dialogs). Balances and limits auto-refresh
/// from the local database via ``Updateable`` whenever `.databaseDidChange`
/// is posted.
///
/// Inject via `@Environment(Session.self)`. Use `@Bindable` when bindings
/// are needed (e.g. `$session.dialogItem` for sheets).
@Observable
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

    /// App-wide modal dialog (confirmations, errors). Presented by
    /// ``DialogWindow`` in a separate `UIWindow` above all sheets.
    var dialogItem: DialogItem?

    /// Whether the standalone Bill Designer overlay is presented over
    /// the scan screen. Toggled by the Settings → Advanced Features row.
    var isShowingBillDesigner: Bool = false

    // MARK: - User State -

    /// Server-fetched user profile.
    var profile: Profile?

    /// Feature flags for the current user.
    var userFlags: UserFlags?

    @ObservationIgnored let keyAccount: KeyAccount
    @ObservationIgnored let owner: AccountCluster
    @ObservationIgnored let userID: UserID
    
    var ownerKeyPair: KeyPair {
        owner.authority.keyPair
    }
    
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
        // Avoid the display-ordered sort in `balances` — this is called per
        // SwiftUI body re-eval from amount-entry computed props.
        updateableBalances.value.first { $0.mint == mint }
    }

    /// True when the user has at least one non-USDF balance with a displayable
    /// fiat value. Skips the sort + allocate that `balances(for:)` does, so
    /// callers gating a presentation pay only the early-exit predicate cost.
    func hasGiveableBalance(for rate: Rate) -> Bool {
        updateableBalances.value.contains { stored in
            stored.mint != .usdf && stored.computeExchangedValue(with: rate).hasDisplayableValue()
        }
    }
    
    @ObservationIgnored private let container: Container
    @ObservationIgnored private let client: Client
    @ObservationIgnored private let flipClient: FlipClient
    @ObservationIgnored private let ratesController: RatesController
    @ObservationIgnored private let historyController: HistoryController
    @ObservationIgnored private let database: Database

    @ObservationIgnored private var poller: Poller!

    /// Buy/sell/launch RPC choreography, namespaced off the session.
    @ObservationIgnored private(set) var purchases: Purchases!

    /// Cash-bill and cash-link choreography, namespaced off the session.
    @ObservationIgnored private(set) var cash: Cash!

    private var updateableBalances: Updateable<[StoredBalance]>!
    private var updateableLimits: Updateable<Limits?>!

    // MARK: - Init -

    init(container: Container, historyController: HistoryController, ratesController: RatesController, toastController: ToastController, database: Database, keyAccount: KeyAccount, owner: AccountCluster, userID: UserID) {
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

        self.purchases = Purchases(session: self, client: client, owner: owner)
        self.cash = Cash(
            session: self,
            client: client,
            flipClient: flipClient,
            database: database,
            ratesController: ratesController,
            toastController: toastController,
            owner: owner,
            keyAccount: keyAccount
        )

        toastController.isSuppressed = { [weak self] in
            self?.isShowingBill ?? false
        }

        ensureValidTokenSelection()

        registerPoller()
        startStreaming()

        profile   = try? database.getProfile()
        userFlags = try? database.getUserFlags()

        // Independent so a profile failure doesn't starve the user-flags fetch.
        // userFlags carries server-pinned withdrawal/launch fees; without it,
        // those flows submit fee=0 and the server denies the intent.
        Task {
            do { try await updateProfile() }
            catch { logger.error("Failed to fetch profile", metadata: ["error": "\(error)"]) }
        }

        Task {
            do { try await updateUserFlags() }
            catch { logger.error("Failed to fetch user flags", metadata: ["error": "\(error)"]) }
        }

        Task {
            await syncUserPreferences()
        }

        observeBalanceCurrencyChanges()
    }

    /// Skipped under unit tests so seeded `VerifiedProtoService` data isn't
    /// raced by a live stream delivery.
    private func startStreaming() {
        guard !Container.isRunningUnitTests else { return }
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
        let fetched = try await Task.retry(
            maxAttempts: 3,
            delay: .milliseconds(500),
            shouldRetry: { (error: any Swift.Error) in (error as? ErrorFetchProfile) == .unknown }
        ) {
            try await flipClient.fetchProfile(userID: userID, owner: ownerKeyPair)
        }

        profile = fetched
        try? database.insertProfile(fetched)
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
        let fetched = try await Task.retry(
            maxAttempts: 3,
            delay: .milliseconds(500),
            shouldRetry: { (error: any Swift.Error) in (error as? ErrorFetchUserFlags) == .unknown }
        ) {
            try await flipClient.fetchUserFlags(userID: userID, owner: ownerKeyPair)
        }

        userFlags = fetched
        try? database.insertUserFlags(fetched)
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
        dialogItem = .alert(
            title: "Log In?",
            subtitle: "You're already logged into an account. Please ensure you have saved your Access Key before proceeding. Would you like to logout and login with a new account?"
        ) {
            .destructive("Log Out & Log In") {
                Task {
                    try await completion()
                }
            };
            .cancel()
        }
    }
    
    // MARK: - Lifecycle -
    
    func didBecomeActive() {
        ratesController.ensureStreamConnected()
    }

    func didEnterBackground() {
        cash.didEnterBackground()
    }
    
    // MARK: - Balance -
    
    
    func hasSufficientFunds(for exchangedFiat: ExchangedFiat) -> SufficientFundsResult {
        guard exchangedFiat.onChainAmount.quarks > 0 else {
            return .insufficient(shortfall: nil)
        }

        guard let balance = balance(for: exchangedFiat.mint) else {
            return .insufficient(shortfall: nil)
        }

        let rate = ratesController.rateForBalanceCurrency()
        let exchangedBalance = balance.computeExchangedValue(with: rate)

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
                logger.info("Attempt max send, within error tolerance")
                return .sufficient(amountToSend: exchangedBalance)
            } else {
                return .insufficient(shortfall: exchangedFiat.subtracting(exchangedBalance))
            }
        }
    }
    
    // MARK: - Poller -

    private func registerPoller() {
        poller = Poller(seconds: 10, fireImmediately: true) { [weak self] in
            // Limits failure must not block balance fetch
            try? await self?.fetchLimitsIfNeeded()
            try? await self?.fetchBalance()
        }
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

    // MARK: - Withdrawals -
    
    func withdraw(exchangedFiat: ExchangedFiat, verifiedState: VerifiedState, fee: TokenAmount, to destinationMetadata: DestinationMetadata) async throws {
        try assertFresh(verifiedState, operation: "withdraw", currency: exchangedFiat.nativeAmount.currency, mint: exchangedFiat.mint)

        let rendezvous = PublicKey.generate()!
        let mint = exchangedFiat.mint
        do {
            guard let vmAuthority = try database.getVMAuthority(mint: mint) else {
                throw Error.vmMetadataMissing
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
    
    // MARK: - Helpers -

    /// Throws `Error.verifiedStateStale` if the proof is past `clientMaxAge`.
    /// Logs at `.warning` because the canPerformAction gate in the VM should
    /// have prevented this — reaching here means the gate has a hole.
    func assertFresh(
        _ verifiedState: VerifiedState,
        operation: String,
        currency: CurrencyCode,
        mint: PublicKey
    ) throws {
        guard verifiedState.isStale else { return }
        logger.warning("Rejected stale verifiedState", metadata: [
            "operation": "\(operation)",
            "currency": "\(currency.rawValue)",
            "mint": "\(mint.base58)",
            "ageSeconds": "\(verifiedState.age)",
            "clientMaxAge": "\(VerifiedState.clientMaxAge)"
        ])
        throw Error.verifiedStateStale
    }
}

// MARK: - Errors -

extension Session {
    enum Error: Swift.Error {
        case vmMetadataMissing
        case mintNotFound
        case insufficientBalance
        case missingSupply
        case verifiedStateStale
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
