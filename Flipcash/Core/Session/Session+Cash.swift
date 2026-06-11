//
//  Session+Cash.swift
//  Flipcash
//

import Foundation
import FlipcashUI
import FlipcashCore

private let logger = Logger(label: "flipcash.cash")

extension Session {

    /// Face-to-face cash-bill and cash-link choreography, namespaced off
    /// ``Session`` as `session.cash`. Owns the in-flight scan/send
    /// operations; bill presentation state stays on ``Session``.
    final class Cash {

        private unowned let session: Session
        private let client: Client
        private let flipClient: FlipClient
        private let database: Database
        private let ratesController: RatesController
        private let toastController: ToastController
        private let owner: AccountCluster
        private let keyAccount: KeyAccount

        private var scanOperation: ScanCashOperation?
        private var sendOperation: SendCashOperation?
        private var grabStarts: [PublicKey: Date] = [:]

        /// Whether a `ScanCashOperation` is currently in flight. Used by
        /// `ScanViewModel` to prevent new codes from being registered while
        /// a grab is being processed, avoiding orphaned entries in the
        /// scanned-rendezvous set.
        var isProcessingScan: Bool {
            scanOperation != nil
        }

        private var ownerKeyPair: KeyPair {
            owner.authority.keyPair
        }

        init(
            session: Session,
            client: Client,
            flipClient: FlipClient,
            database: Database,
            ratesController: RatesController,
            toastController: ToastController,
            owner: AccountCluster,
            keyAccount: KeyAccount
        ) {
            self.session = session
            self.client = client
            self.flipClient = flipClient
            self.database = database
            self.ratesController = ratesController
            self.toastController = toastController
            self.owner = owner
            self.keyAccount = keyAccount
        }

        // MARK: - Lifecycle -

        func didEnterBackground() {
            // If the sendOperation is ignoring stream, it's likely
            // presenting a share sheet or in some way mid-process
            // so we don't want to dismiss the bill from under it
            if let sendOperation, !sendOperation.ignoresStream {
                dismissBill(style: .slide)
            }
        }

        // MARK: - Cash -

        /// Completes a face-to-face bill grab after the camera scans a cash code.
        ///
        /// ## Device A (Sender)
        /// Displays a bill (`showBill` → `SendCashOperation`), encoding a
        /// rendezvous keypair and amount into a visual cash code.
        ///
        /// ## Device B (Receiver — this method)
        /// 1. **Scan** — Camera decodes the cash code payload (rendezvous + amount).
        /// 2. **Delegate to `ScanCashOperation`** — Handles the full grab handshake
        ///    (listen for mint, create accounts, grab, poll for settlement).
        /// 3. **Post-transaction** — Refresh balances and show a received-bill UI
        ///    via `showBill` with the `VerifiedState` from the sender's message.
        ///
        /// The received bill becomes a **live `SendCashOperation`** — other users
        /// can scan Device B's screen to continue the "quick give and grab" chain.
        func receive(_ payload: CashCode.Payload, completion: @escaping (ReceiveResult) -> Void) {
            // Record the start date of when
            // we first saw the bill and match
            // it to the rendezvous
            grabStarts[payload.rendezvous.publicKey] = .now

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
            Task { [session] in
                defer {
                    scanOperation = nil
                }

                do {
                    // Track grab initiation to measure the start-to-completion funnel
                    Analytics.transferStart(event: .grabBillStart)

                    let metadata = try await operation.start()

                    session.updatePostTransaction()

                    showBill(.init(
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
                    session.dialogItem = .error(title: "Something Went Wrong", subtitle: "Please try again later")
                    completion(.failed)
                }
            }
        }

        func showBill(_ billDescription: BillDescription) {
            // Only inbound bills enqueue a "+$" deposit toast; sent bills don't.
            if billDescription.received {
                toastController.enqueue(.init(
                    amount: billDescription.exchangedFiat.nativeAmount,
                    isDeposit: true
                ))
            }

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

                    // Outgoing bills always carry the pin from `GiveViewModel.prepareSubmission`.
                    // Re-fetching a fresh proof here would reintroduce the native-amount
                    // mismatch that pinning prevents, so this is structurally unreachable —
                    // crash debug builds and fail closed in release.
                    guard let verifiedState = billDescription.verifiedState else {
                        logger.error("Missing verifiedState for outgoing cash link", metadata: [
                            "rendezvous": "\(payload.rendezvous.publicKey.base58)",
                            "mint": "\(exchangedFiat.mint.base58)",
                        ])
                        assertionFailure("Outgoing BillDescription must carry a pinned VerifiedState")
                        self.session.dialogItem = .error(title: "Something Went Wrong", subtitle: "Please try again later")
                        return
                    }

                    do {
                        let giftCard = try await self.createLink(
                            payload: payload,
                            exchangedFiat: exchangedFiat,
                            verifiedState: verifiedState
                        )

                        guard self.session.isShowingBill && self.sendOperation === operation else {
                            // The bill was dismissed (e.g. operation failed) OR a
                            // new bill was pulled while this link was being created.
                            // Either way this gift card belongs to a bill the user
                            // has moved on from — void it to return the funds.
                            do {
                                try await self.cancelLink(
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
                            self.session.updatePostTransaction()
                            return
                        }

                        self.showLinkShareSheet(
                            giftCard: giftCard,
                            exchangedFiat: exchangedFiat
                        )

                    } catch {
                        ErrorReporting.captureError(error)
                        // Suppress late-arriving errors from stale/orphaned tasks
                        // (e.g. gRPC stream finally giving up minutes later) so they
                        // don't fire dialogs on unrelated bills the user has moved on to.
                        if self.session.isShowingBill && self.sendOperation === operation {
                            self.session.dialogItem = .error(title: "Something Went Wrong", subtitle: "Please try again later")
                        }
                    }
                }
            }

            var secondaryAction: BillState.SecondaryAction? = .init(asset: .cancel, title: nil) { [weak self] in
                self?.dismissBill(style: .slide)
            }

            let storedMintMetadata = try? database.getMintMetadata(mint: billDescription.exchangedFiat.mint)

            if billDescription.received {
                Task { [session] in
                    try await Task.delay(milliseconds: 750)
                    session.valuation = BillValuation(
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

            sendOperation             = operation
            session.presentationState = .visible(billDescription.received ? .pop : .slide)
            session.billState         = .init(
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
                    self?.toastController.enqueue(.init(
                        amount: billDescription.exchangedFiat.nativeAmount,
                        isDeposit: false
                    ))

                    self?.session.updatePostTransaction()

                    self?.dismissBill(style: .pop)

                    Analytics.transfer(
                        event: .giveBill,
                        exchangedFiat: billDescription.exchangedFiat,
                        grabTime: nil,
                        successful: true,
                        error: nil
                    )
                } catch is CancellationError {
                    // Cancelled by dismissBill — no error UI, no analytics.
                    return
                } catch {
                    // Diagnostics + ErrorReporting happen inside SendCashOperation.
                    self?.dismissBill(style: .slide)
                    self?.session.dialogItem = .error(title: "Something Went Wrong", subtitle: "The cash was returned to your wallet")

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

        private func showLinkShareSheet(giftCard: GiftCardCluster, exchangedFiat: ExchangedFiat) {
            let item = ShareCashLinkItem(giftCard: giftCard, exchangedFiat: exchangedFiat)
            ShareSheet.present(activityItem: item) { [weak self] didShare in
                guard let self = self else { return }

                let hideBillActions = {
                    self.session.billState.primaryAction = nil
                    self.session.billState.secondaryAction = nil
                }

                let cancelSend = {
                    self.dismissBill(style: .slide)
                    Task { [session = self.session] in
                        do {
                            try await self.cancelLink(giftCardVault: giftCard.cluster.vaultPublicKey)
                        } catch {
                            ErrorReporting.captureError(error)
                        }
                        // Keeps the session graph alive until cancelLink's
                        // unowned `session` deref completes.
                        withExtendedLifetime(session) {}
                    }
                }

                let completeSend = {
                    _ = Task { [session = self.session] in
                        try await Task.delay(milliseconds: 250)

                        // Toast: user confirmed sending a cash link (-amount)
                        self.toastController.enqueue(.init(
                            amount: exchangedFiat.nativeAmount,
                            isDeposit: false
                        ))

                        self.dismissBill(style: .pop)
                        session.updatePostTransaction()
                    }
                }

                var confirmationDialog: DialogItem?

                confirmationDialog = .success(
                    title: "Did You Send The Link?",
                    subtitle: "Any cash that isn't collected within 7 days will be automatically returned to your balance"
                ) {
                    .standard("Yes") {
                        hideBillActions()
                        completeSend()
                    };
                    .subtle("No, Cancel Send") {
                        self.session.dialogItem = .alert(
                            title: "Are You Sure?",
                            subtitle: "Anyone you sent the link to won't be able to collect the cash",
                            dismissable: false
                        ) {
                            .destructive("Yes") {
                                hideBillActions()
                                cancelSend()
                            };
                            .subtle("Nevermind") {
                                self.session.dialogItem = confirmationDialog
                            }
                        }
                    }
                }

                self.session.dialogItem = confirmationDialog
            }
        }

        func dismissBill(style: PresentationState.Style) {
            sendOperation?.cancel()
            sendOperation = nil
            session.presentationState = .hidden(style)
            session.billState = .default()
            session.valuation = nil

            // Consume toast after bill state is cleared
            // so isShowingBill returns false
            toastController.consume()
        }

        // MARK: - Cash Links -

        private func createLink(payload: CashCode.Payload, exchangedFiat: ExchangedFiat, verifiedState: VerifiedState) async throws -> GiftCardCluster {
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

                throw error
            }
        }

        func cancelLink(giftCardVault: PublicKey) async throws {
            try await client.voidCashLink(giftCardVault: giftCardVault, owner: ownerKeyPair)
            session.updatePostTransaction()
        }

        /// Receives a Cash Link (gift card) opened via deep link.
        ///
        /// ## Device A (Sender)
        /// 1. Created the gift card via `createLink`, which funded a gift-card
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
        func receiveLink(mnemonic: MnemonicPhrase, claimIfOwned: Bool = false) {
            let giftCardKeyPair = DerivedKey.derive(using: .solana, mnemonic: mnemonic).keyPair
            Task { [session] in
                do {
                    let giftCardAccountInfo = try await Task.retry(
                        maxAttempts: 3,
                        delay: .milliseconds(500),
                        shouldRetry: { error in
                            guard let e = error as? ErrorFetchBalance else { return false }
                            return e == .notFound || e == .unknown || e == .transportFailure
                        }
                    ) {
                        try await self.client.fetchAccountInfo(
                            type: .giftCard,
                            owner: giftCardKeyPair,
                            requestingOwner: self.ownerKeyPair
                        )
                    }

                    guard let exchangedFiat = giftCardAccountInfo.exchangedFiat else {
                        logger.error("Gift card account info is missing ExchangeFiat.")
                        return
                    }

                    guard giftCardAccountInfo.claimState != .claimed && giftCardAccountInfo.claimState != .expired else {
                        logger.info("Cash link not available", metadata: [
                            "claimState": "\(giftCardAccountInfo.claimState)",
                            "giftCardAuthority": "\(giftCardKeyPair.publicKey.base58)",
                        ])
                        session.dialogItem = .error(title: "Cash Already Collected", subtitle: "This cash has already been collected, or was cancelled by the sender")
                        return
                    }

                    if giftCardAccountInfo.isGiftCardIssuer && !claimIfOwned {
                        logger.info("Cash link self-claim detected", metadata: [
                            "giftCardAuthority": "\(giftCardKeyPair.publicKey.base58)",
                            "currency": "\(exchangedFiat.currencyRate.currency.rawValue)",
                        ])
                        let giftCardAuthority = giftCardKeyPair.publicKey
                        session.dialogItem = .alert(
                            title: "Collect Your Own Cash?",
                            subtitle: "You tapped to collect the cash you sent. Are you sure you want to collect it yourself?",
                            dismissable: false
                        ) {
                            .destructive("Collect") { [weak self] in
                                logger.info("Cash link self-claim confirmed", metadata: [
                                    "giftCardAuthority": "\(giftCardAuthority.base58)",
                                ])
                                self?.receiveLink(mnemonic: mnemonic, claimIfOwned: true)
                            };
                            .subtle("Don't Collect") {
                                logger.info("Cash link self-claim cancelled", metadata: [
                                    "giftCardAuthority": "\(giftCardAuthority.base58)",
                                ])
                            }
                        }
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
                        try? self.database.insert(mints: [inlineMint], date: .now)
                        vmAuthority = inlineMint.vmMetadata?.authority
                    } else {
                        let mintMetadata = try await session.fetchMintMetadata(mint: vmMint)
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
                        authority: self.keyAccount.derivedKey,
                        mint: vmMint,
                        timeAuthority: vmAuthority
                    )

                    // Subscribe to this mint's live data early so the stream
                    // has time to deliver verified state while we create
                    // accounts and deposit the gift card below.
                    self.ratesController.ensureMintSubscribed(vmMint)

                    // We need to ensure the accounts for this mint
                    // are created. This call is a no-op is the
                    // account already exists
                    try await self.client.createAccounts(
                        owner: self.ownerKeyPair,
                        mint: vmMint,
                        cluster: mintCurrencyCluster,
                        kind: .primary,
                        derivationIndex: 0
                    )

                    // Deposit the gift card
                    try await self.client.receiveCashLink(
                        usdf: exchangedFiat.onChainAmount,
                        ownerCluster: self.owner.use(
                            mint: vmMint,
                            timeAuthority: vmAuthority
                        ),
                        giftCard: giftCard
                    )

                    // Wait for verified state — the stream was subscribed
                    // above, so data should arrive during the blocking calls.
                    // Required for launchpad currencies in the quick-give-and-grab chain.
                    let verifiedState = await self.ratesController.awaitVerifiedState(
                        for: exchangedFiat.nativeAmount.currency,
                        mint: vmMint
                    )

                    session.updatePostTransaction()

                    showBill(
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

                } catch let ErrorSubmitIntent.staleState(reasons, kinds) where kinds.contains(.alreadyClaimed) {
                    // Server-side race: another device claimed first.
                    // Benign — surface the dialog without Bugsnag.
                    logger.info("Cash link already claimed (server race)", metadata: [
                        "giftCardAuthority": "\(giftCardKeyPair.publicKey.base58)",
                    ])
                    session.dialogItem = .error(title: "Cash Already Collected", subtitle: "This cash has already been collected, or was cancelled by the sender")
                    Analytics.transfer(
                        event: .receiveCashLink,
                        exchangedFiat: nil,
                        grabTime: nil,
                        successful: false,
                        error: ErrorSubmitIntent.staleState(reasons, kinds: kinds)
                    )

                } catch ErrorSubmitIntent.denied(let reasons, let messages) {
                    // Server-side guard refusal (spam, AML, rate/policy).
                    // Not a bug — surface the generic dialog without Bugsnag.
                    logger.info("Cash link denied by guard", metadata: [
                        "giftCardAuthority": "\(giftCardKeyPair.publicKey.base58)",
                    ])
                    session.dialogItem = .error(title: "Something Went Wrong", subtitle: "Please try again later")
                    Analytics.transfer(
                        event: .receiveCashLink,
                        exchangedFiat: nil,
                        grabTime: nil,
                        successful: false,
                        error: ErrorSubmitIntent.denied(reasons, messages: messages)
                    )

                } catch {
                    logger.error("Failed to receive cash link for gift card", metadata: [
                        "public_key": "\(giftCardKeyPair.publicKey)",
                    ])
                    ErrorReporting.captureError(error)

                    Analytics.transfer(
                        event: .receiveCashLink,
                        exchangedFiat: nil,
                        grabTime: nil,
                        successful: false,
                        error: error
                    )

                    if error is ErrorFetchBalance {
                        session.dialogItem = .error(title: "Unable to Find Cash", subtitle: "Please check your connection and try again")
                    } else {
                        session.dialogItem = .error(title: "Something Went Wrong", subtitle: "Please try again later")
                    }
                }
            }
        }
    }
}

// MARK: - ReceiveResult -

extension Session.Cash {
    enum ReceiveResult {
        case success
        case noStream
        case failed
    }
}

// MARK: - BillDescription -

extension Session.Cash {
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
