//
//  WalletConnection.swift
//  Code
//
//  Created by Dima Bart on 2025-09-17.
//

import Foundation
import UIKit
import FlipcashUI
import FlipcashCore
import TweetNacl
import SolanaSwift

private let logger = Logger(label: "flipcash.wallet-connection")

@MainActor
@Observable
public final class WalletConnection {

    var isShowingAmountEntry: Bool = false

    var dialogItem: DialogItem?

    /// Single source of truth for external-wallet processing state. Invalid
    /// combinations — "cancelled flag set with no active context", "both
    /// buy-existing and launch contexts populated simultaneously" — are
    /// unrepresentable by construction.
    var state: WalletProcessingState = .idle

    /// Buy-existing context, exposed for `.fullScreenCover(item:)`. Writing
    /// `nil` (SwiftUI dismiss) transitions to `.idle` only if currently buying.
    var processing: ExternalSwapProcessing? {
        get {
            if case .buying(let p, _) = state { return p }
            return nil
        }
        set {
            if newValue == nil, case .buying = state {
                state = .idle
            }
        }
    }

    /// Launch context, exposed for `.fullScreenCover(item:)`. Writing `nil`
    /// (SwiftUI dismiss) transitions to `.idle` only if currently launching.
    var launchProcessing: ExternalLaunchProcessing? {
        get {
            if case .launching(let l, _) = state { return l }
            return nil
        }
        set {
            if newValue == nil, case .launching = state {
                state = .idle
            }
        }
    }

    /// True iff the current context is marked failed. `SwapProcessingScreen`
    /// observes this via `.onChange(of:)` to flip its display to cancelled.
    var isProcessingCancelled: Bool {
        switch state {
        case .idle: return false
        case .buying(_, let isFailed), .launching(_, let isFailed): return isFailed
        }
    }

    private(set) var session: ConnectedWalletSession?

    var publicKey: FlipcashCore.PublicKey {
        box.publicKey
    }

    private let box: Box
    private let owner: AccountCluster
    private let client: Client

    private let solanaClient = BlockchainClient(
        apiClient: JSONRPCAPIClient(
            endpoint: .init(
                address: "https://api.mainnet-beta.solana.com",
                network: .mainnetBeta
            )
        )
    )

    /// Pending swap info to use when Phantom returns with signed transaction
    private var pendingSwap: PendingSwap?

    /// Awaiting continuation for `connect()`. Resumed by `didConnect` on
    /// success or by the errorCode branch of `didReceiveURL` on failure.
    private var pendingConnect: CheckedContinuation<Void, Swift.Error>?

    /// What the signed-transaction handler should do after the user returns
    private struct PendingSwap {
        /// Funding-leg swap id (USDC→USDF) — used in the Phantom memo.
        let fundingSwapId: SwapId
        let amount: ExchangedFiat
        let displayName: String
        let onCompleted: @MainActor @Sendable (FlipcashCore.Signature, ExchangedFiat) async throws -> SignedSwapResult
    }

    /// Whether the user has previously linked a Phantom wallet via
    /// `connectToPhantom`. Once true it stays true for the lifetime of the
    /// keychain entry; users can clear by uninstalling Phantom or wiping app data.
    var isConnected: Bool {
        Keychain.connectedWalletSession != nil
    }

    // MARK: - Init -

    init(owner: AccountCluster, client: Client) {
        self.owner = owner
        self.client = client

        if let connectedWalletSession = Keychain.connectedWalletSession {
            self.session = connectedWalletSession
            self.box = try! Box(secretKey: connectedWalletSession.secretKey)
            logger.info("Restored encryption box", metadata: ["publicKey": "\(box.publicKey.base58)"])
        } else {
            self.box = try! Box()
            logger.info("New encryption box", metadata: ["publicKey": "\(box.publicKey.base58)"])
        }
    }
    
    // MARK: - Receive -

    func didReceiveURL(url: URL) {
        if let code = url.queryItemValue(for: "errorCode") {
            Analytics.track(event: Analytics.WalletEvent.cancel)
            pendingSwap = nil

            let isUserCancel = code == "4001"
            if !isUserCancel {
                logger.error("Wallet returned error", metadata: [
                    "code": "\(code)",
                    "url": "\(url.sanitizedForAnalytics)",
                ])
                // Non-cancel errors commonly mean the stored session is no
                // longer recognised by Phantom (uninstall, user-disconnect,
                // server revocation). Drop the keychain entry so the next
                // attempt forces a fresh connect instead of looping on a
                // dead session.
                Keychain.connectedWalletSession = nil
                session = nil
            }

            // If the error came from the connect deeplink and an async
            // awaiter is present, propagate the failure to them instead of
            // showing the transaction-oriented dialog. 4001 (user-cancel)
            // becomes a CancellationError so callers can silently abort;
            // every other code becomes `connectFailed` so callers can
            // surface an error.
            if url.pathComponents.last == "walletConnected", let continuation = pendingConnect {
                pendingConnect = nil
                if isUserCancel {
                    continuation.resume(throwing: CancellationError())
                } else {
                    continuation.resume(throwing: WalletConnectionError.connectFailed(code: code))
                }
                return
            }

            if case .idle = state {
                dialogItem = .init(
                    style: .destructive,
                    title: isUserCancel ? "Transaction Cancelled" : "Transaction Failed",
                    subtitle: isUserCancel
                        ? "The transaction was cancelled in your wallet"
                        : "Your wallet returned an error. Please try again.",
                    dismissable: true
                ) {
                    .okay(kind: .destructive)
                }
            } else {
                markCurrentStateFailed()
            }
            return
        }

        guard var encryptedResponse = try? EncryptedWalletResponse(url: url) else {
            logger.warning("Wallet callback URL did not contain an encrypted response", metadata: [
                "url": "\(url.sanitizedForAnalytics)",
            ])
            return
        }
        
        let component = url.pathComponents.last
        do {
            switch component {
            case "walletConnected":
                guard let encryptionPublicKey = encryptedResponse.encryptionPublicKey else {
                    return
                }
                
                let response = try box.decrypt(
                    type: WalletResponse.Connected.self,
                    encryptedWalletResponse: encryptedResponse
                )
                
                didConnect(
                    response: response,
                    encryptionPublicKey: encryptionPublicKey
                )
                
            case "transactionSigned":
                guard let session else {
                    logger.warning("Received signed transaction but no active session found.")
                    return
                }

                encryptedResponse.encryptionPublicKey = session.phantomEncryptionPublicKey

                let response = try box.decrypt(
                    type: WalletResponse.SignedTransaction.self,
                    encryptedWalletResponse: encryptedResponse
                )

                didSignTransaction(response.transaction)
                
            default:
                logger.warning("Deep link path did not match known routes", metadata: ["component": "\(component ?? "nil")"])
                return
            }
            
        } catch {
            logger.error("Failed to decrypt", metadata: ["error": "\(error)"])
            return
        }
    }
    
    private func didConnect(response: WalletResponse.Connected, encryptionPublicKey: Data) {
        if let walletSession = WalletSession(
            walletPublicKey: response.publicKey,
            sessionToken: response.session
        ) {
            logger.info("Connected to wallet")
            let session = ConnectedWalletSession(
                secretKey: box.secretKey,
                walletPublicKey: walletSession.walletPublicKey,
                sessionToken: walletSession.sessionToken,
                phantomEncryptionPublicKey: encryptionPublicKey
            )

            Keychain.connectedWalletSession = session
            self.session = session

            if let continuation = pendingConnect {
                pendingConnect = nil
                continuation.resume(returning: ())
            } else {
                // Legacy path — the connect was initiated from a non-async
                // caller (e.g. CurrencyInfoScreen's Phantom entry point),
                // which expects the amount-entry sheet to appear after
                // connect. Callers using `connect()` handle the follow-up
                // themselves.
                isShowingAmountEntry = true
            }
        }
    }
    
    private func didSignTransaction(_ signedTx: String) {
        Task { [solanaClient, weak self] in
            let pending = self?.pendingSwap
            self?.pendingSwap = nil

            guard let pending, let self else {
                logger.warning("Received signed transaction but no pending swap context")
                return
            }

            // Present the generic processing screen immediately. The server callback
            // below transitions to a launch context when the caller is launching a
            // new currency; early-exit failures transition back to `.idle` so no
            // cover presents for a swap the server never recorded.
            self.state = .buying(
                ExternalSwapProcessing(
                    swapId: pending.fundingSwapId,
                    currencyName: pending.displayName,
                    amount: pending.amount
                ),
                isFailed: false
            )

            let swapMetadata: [String: String] = [
                "swapId": pending.fundingSwapId.publicKey.base58,
                "amount": pending.amount.nativeAmount.formatted(),
                "name": pending.displayName,
            ]

            let rawData = Data(Base58.toBytes(signedTx))
            guard let tx = SolanaTransaction(data: rawData) else {
                logger.error("Failed to decode signed transaction")
                ErrorReporting.captureError(Error.invalidURL, reason: "Failed to decode signed transaction", metadata: swapMetadata)
                self.state = .idle
                return
            }

            // Notify server before submitting to chain — if the server rejects,
            // skip chain submission entirely so no USDC is spent without a swap state.
            do {
                let result = try await pending.onCompleted(tx.identifier, pending.amount)
                switch result {
                case .buyExisting(let swapId):
                    if swapId != pending.fundingSwapId {
                        self.state = .buying(
                            ExternalSwapProcessing(
                                swapId: swapId,
                                currencyName: pending.displayName,
                                amount: pending.amount
                            ),
                            isFailed: false
                        )
                    }
                case .launch(let swapId, let mint):
                    self.state = .launching(
                        ExternalLaunchProcessing(
                            swapId: swapId,
                            launchedMint: mint,
                            currencyName: pending.displayName,
                            amount: pending.amount
                        ),
                        isFailed: false
                    )
                }
                logger.info("Server notified of swap funding")
            } catch {
                logger.error("Server notification failed", metadata: ["error": "\(error)"])
                ErrorReporting.captureError(error, reason: "Server notification failed", metadata: swapMetadata)
                self.state = .idle
                return
            }

            // Server accepted — submit transaction to chain. The swap id is
            // server-recorded at this point, so on failure we keep the context
            // and flip `isFailed` so the processing screen surfaces the error.
            do {
                let txBase64 = rawData.base64EncodedString()
                let signature = try await solanaClient.apiClient.sendTransaction(
                    transaction: txBase64,
                    configs: .init(encoding: "base64")!
                )
                logger.info("Transaction sent", metadata: ["signature": "\(signature)"])
                Analytics.track(event: Analytics.WalletEvent.transactionsSubmitted)
            } catch {
                logger.error("Chain submission failed", metadata: ["error": "\(error)"])
                ErrorReporting.captureError(error, reason: "Chain submission failed", metadata: swapMetadata)
                self.markCurrentStateFailed()
            }
        }
    }
    
    /// Opens the external wallet via deep link.
    private func openExternalWallet(_ url: URL) {
        url.openWithApplication()
    }

    /// Requests an external swap to fund a buy of an existing launchpad currency.
    /// The processing screen is deferred until the user returns with a signed transaction.
    func requestSwap(usdc: Quarks, token: MintMetadata) async throws {
        let fundingSwapId = SwapId.generate()
        try await requestUsdcToUsdfSwap(
            fundingSwapId: fundingSwapId,
            usdc: usdc,
            displayName: token.name,
            onCompleted: { [client, owner] signature, amount in
                try await client.buyWithExternalFunding(
                    swapId: fundingSwapId,
                    amount: amount,
                    of: token,
                    owner: owner,
                    transactionSignature: signature
                )
                return .buyExisting(swapId: fundingSwapId)
            }
        )
        isShowingAmountEntry = false
    }

    /// Requests an external USDC→USDF swap for the currency-creation launch flow.
    /// `onCompleted` runs after Phantom signs and must execute
    /// `Session.launchCurrency` + `Session.buyNewCurrencyWithExternalFunding`,
    /// returning the swap id from the buy so the processing screen polls the
    /// right swap state (the funding swap id is unrelated).
    func requestSwapForLaunch(
        usdc: Quarks,
        displayName: String,
        onCompleted: @escaping @MainActor @Sendable (FlipcashCore.Signature, ExchangedFiat) async throws -> SignedSwapResult
    ) async throws {
        try await requestUsdcToUsdfSwap(
            fundingSwapId: SwapId.generate(),
            usdc: usdc,
            displayName: displayName,
            onCompleted: onCompleted
        )
    }

    /// Dismisses the processing screen and clears any pending wallet dialogs.
    func dismissProcessing() {
        dialogItem = nil
        state = .idle
    }

    /// Flips the current active context's `isFailed` flag. No-op for `.idle`.
    private func markCurrentStateFailed() {
        state = state.markedFailed()
    }

    // MARK: - Actions -

    /// Async wrapper around `connectToPhantom()`. Returns immediately if
    /// already connected. Otherwise opens Phantom and suspends until the
    /// connect deeplink arrives (success) or an errorCode callback does
    /// (throws `WalletConnectionError.connectFailed`). A second call while
    /// the first is in flight cancels the first waiter.
    func connect() async throws {
        guard !isConnected else { return }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Swift.Error>) in
            pendingConnect?.resume(throwing: CancellationError())
            pendingConnect = continuation
            connectToPhantom()
        }
    }

    func connectToPhantom() {
        let nonce = UUID().uuidString

        var c = URLComponents(string: "https://phantom.app/ul/v1/connect")!
        c.queryItems = [
            URLQueryItem(name: "app_url",                    value: "https://app.flipcash.com"),
            URLQueryItem(name: "dapp_encryption_public_key", value: publicKey.base58),
            URLQueryItem(name: "cluster",                    value: "mainnet-beta"), // or "devnet"
            URLQueryItem(name: "redirect_link",              value: "https://app.flipcash.com/wallet/walletConnected"),
            URLQueryItem(name: "nonce",                      value: nonce)
        ]

        Analytics.track(event: Analytics.WalletEvent.connect)
        openExternalWallet(c.url!)
    }

    /// Builds + sends a USDC→USDF transaction to Phantom for signing. Stashes
    /// the supplied `onCompleted` closure so `didSignTransaction` can run it
    /// once the signed transaction comes back via deeplink.
    private func requestUsdcToUsdfSwap(
        fundingSwapId: SwapId,
        usdc: Quarks,
        displayName: String,
        onCompleted: @escaping @MainActor @Sendable (FlipcashCore.Signature, ExchangedFiat) async throws -> SignedSwapResult
    ) async throws {
        guard let connectedSession = Keychain.connectedWalletSession else {
            throw Error.noSession
        }

        let amount = ExchangedFiat.compute(
            onChainAmount: TokenAmount(quarks: usdc.quarks, mint: .usdf),
            rate: .oneToOne,
            supplyQuarks: nil
        )

        let externalWallet = try FlipcashCore.PublicKey(base58: connectedSession.walletPublicKey.base58)
        let flipcashOwner = owner.authorityPublicKey

        let instructions = SwapInstructionBuilder.buildUsdcToUsdfSwapInstructions(
            sender: externalWallet,
            owner: flipcashOwner,
            amount: usdc.quarks,
            pool: .usdf,
            swapId: fundingSwapId.publicKey
        )

        let instructionsConverted = try instructions.map { instruction in
            TransactionInstruction(
                keys: try instruction.accounts.map { meta in
                    SolanaSwift.AccountMeta(
                        publicKey: try SolanaSwift.PublicKey(string: meta.publicKey.base58),
                        isSigner: meta.isSigner,
                        isWritable: meta.isWritable
                    )
                },
                programId: try SolanaSwift.PublicKey(string: instruction.program.base58),
                data: [UInt8](instruction.data)
            )
        }

        let recentBlockhash = try await solanaClient.apiClient.getLatestBlockhash(commitment: "finalized")

        var transaction = Transaction(
            instructions: instructionsConverted,
            recentBlockhash: recentBlockhash,
            feePayer: try SolanaSwift.PublicKey(string: externalWallet.base58)
        )

        pendingSwap = PendingSwap(
            fundingSwapId: fundingSwapId,
            amount: amount,
            displayName: displayName,
            onCompleted: onCompleted
        )

        let txEncoded = Base58.fromBytes(Array(try transaction.serialize()))

        let payload: [String: Any] = [
            "transaction": txEncoded,
            "session": connectedSession.sessionToken
        ]
        let payloadData = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (nonce, payloadEncrypted) = try box.encryptForPhantom(
            payload: payloadData,
            encryptionPublicKey: connectedSession.phantomEncryptionPublicKey
        )

        var c = URLComponents(string: "https://phantom.app/ul/v1/signTransaction")!
        c.queryItems = [
            URLQueryItem(name: "dapp_encryption_public_key", value: publicKey.base58),
            URLQueryItem(name: "nonce",                      value: nonce),
            URLQueryItem(name: "redirect_link",              value: "https://app.flipcash.com/wallet/transactionSigned"),
            URLQueryItem(name: "payload",                    value: payloadEncrypted)
        ]

        guard let url = c.url else {
            pendingSwap = nil
            logger.error("Failed to construct signTransaction URL")
            throw Error.invalidURL
        }

        Analytics.walletRequestAmount(amount: Quarks(
            quarks: amount.onChainAmount.quarks,
            currencyCode: .usd,
            decimals: PublicKey.usdf.mintDecimals
        ))
        openExternalWallet(url)
        logger.info("Requested USDC→USDF swap", metadata: [
            "amount": "\(amount.usdfValue.formatted())",
            "swapId": "\(fundingSwapId.publicKey.base58)",
            "name": "\(displayName)",
        ])
    }
}

/// NaCl “box” with an ephemeral X25519 keypair for one Phantom session.
extension WalletConnection {
    public struct Box {
        
        public let publicKey: FlipcashCore.PublicKey // 32 bytes – send as `dapp_encryption_public_key`
        public let secretKey: Seed32   // 32 bytes – keep private for session lifetime
        
        private let decoder = JSONDecoder()

        /// Generate a fresh ephemeral keypair.
        public init(secretKey: Seed32? = nil) throws {
            let keyPair: (publicKey: Data, secretKey: Data)?
            if let secretKey {
                keyPair = try? NaclBox.keyPair(fromSecretKey: secretKey.data)
            } else {
                keyPair = try? NaclBox.keyPair()
            }
            
            guard let keyPair else {
                throw WalletConnectionError.keypairGenerationFailed
            }
            
            self.publicKey = try! PublicKey(keyPair.publicKey)
            self.secretKey = try! Seed32(keyPair.secretKey)
        }

        // MARK: - Decrypt -
        
        /// Decrypts wallet's payload using X25519 public key (bytes) and returns the typed response
        public func decrypt<T>(
            type: T.Type,
            encryptedWalletResponse: EncryptedWalletResponse
        ) throws -> T where T: Decodable {
            guard let encryptionPublicKey = encryptedWalletResponse.encryptionPublicKey else {
                throw WalletConnectionError.decryptionFailed
            }
            
            return try decrypt(
                type: type,
                sealed: .init(
                    data: encryptedWalletResponse.data,
                    nonce: encryptedWalletResponse.nonce
                ),
                encryptionPublicKey: encryptionPublicKey
            )
        }
        
        /// Decrypts wallet's payload using X25519 public key (bytes) and returns the typed response
        public func decrypt<T>(
            type: T.Type,
            sealed: SealedData,
            encryptionPublicKey: Data
        ) throws -> T where T: Decodable {
            let decrypted = try decrypt(
                sealed: sealed,
                encryptionPublicKey: encryptionPublicKey
            )
            
            do {
                return try decoder.decode(T.self, from: decrypted)
            } catch {
                throw WalletConnectionError.jsonDecodingFailed(underlying: error)
            }
        }

        /// Decrypts wallet's payload using X25519 public key (bytes) and returns the decrypted data
        public func decrypt(
            sealed: SealedData,
            encryptionPublicKey: Data
        ) throws -> Data {
            // 1. Precompute shared key via X25519
            let sharedKey = try NaclBox.before(
                publicKey: encryptionPublicKey,
                secretKey: secretKey.data
            )
            
            // 2. XSalsa20-Poly1305 open (NaCl secretbox)
            let decrypted = try NaclSecretBox.open(
                box: sealed.data,
                nonce: sealed.nonce,
                key: sharedKey
            )
            
            return decrypted
        }
        
        // MARK: - Encrypt -
        
        /// Encrypts a JSON payload for Phantom using XSalsa20-Poly1305 with the shared secret derived from
        /// our Box.secretKey and Phantom's `phantom_encryption_public_key`.
        public func encryptForPhantom(
            payload: Data,
            encryptionPublicKey: Data
        ) throws -> (String, String) {
            let sharedKey = try NaclBox.before(
                publicKey: encryptionPublicKey,
                secretKey: secretKey.data
            )
            
            let nonce         = try Data.secRandom(24)
            let boxed         = try NaclSecretBox.secretBox(message: payload, nonce: nonce, key: sharedKey)
            let nonceString   = Base58.fromBytes(Array(nonce))
            let payloadString = Base58.fromBytes(Array(boxed))
            
            return (nonceString, payloadString)
        }
    }
}

// MARK: - Error -

public enum WalletConnectionError: Error, LocalizedError {
    case keypairGenerationFailed
    case decryptionFailed
    case jsonDecodingFailed(underlying: Error)
    case noSession
    case connectFailed(code: String)

    public var errorDescription: String? {
        switch self {
        case .keypairGenerationFailed:   return "Failed to generate X25519 keypair."
        case .decryptionFailed:          return "Failed to decrypt payload (MAC check failed)."
        case .jsonDecodingFailed(let e): return "Failed to decode JSON: \(e.localizedDescription)"
        case .noSession:                 return "No connected wallet session."
        case .connectFailed(let code):   return "Wallet connection failed (code: \(code))."
        }
    }
}

extension WalletConnection {
    enum Error: Swift.Error {
        case noSession
        case missingVerifiedState
        case invalidURL
    }
}

/// External-wallet processing state. Variants differ by flow (buy-existing vs
/// currency launch) and each carries an `isFailed` flag that drives the
/// processing screen's "cancelled" display without requiring a separate flag
/// that could drift out of sync with the active context.
enum WalletProcessingState: Hashable {
    case idle
    case buying(ExternalSwapProcessing, isFailed: Bool)
    case launching(ExternalLaunchProcessing, isFailed: Bool)

    /// Returns the state with the active context's `isFailed` flipped to true.
    /// `.idle` is a fixed point. Idempotent on already-failed states.
    func markedFailed() -> WalletProcessingState {
        switch self {
        case .idle:
            return .idle
        case .buying(let context, _):
            return .buying(context, isFailed: true)
        case .launching(let context, _):
            return .launching(context, isFailed: true)
        }
    }
}

// MARK: - SealedData -

public struct SealedData {
    
    public let data: Data
    public let nonce: Data
    
    public init(data: Data, nonce: Data) {
        self.data = data
        self.nonce = nonce
    }
}

// MARK: - WalletSession -

public struct WalletSession: Codable {
    
    public let walletPublicKey: FlipcashCore.PublicKey
    public let sessionToken: String
    
    init?(walletPublicKey: String, sessionToken: String) {
        guard let publicKey = try? PublicKey(base58: walletPublicKey) else {
            return nil
        }
        
        self.walletPublicKey = publicKey
        self.sessionToken = sessionToken
    }
    
    init(walletPublicKey: FlipcashCore.PublicKey, sessionToken: String) {
        self.walletPublicKey = walletPublicKey
        self.sessionToken = sessionToken
    }
}

// MARK: - ConnectedWalletSession -

struct ConnectedWalletSession: Codable {
    public let secretKey: Seed32
    public let walletPublicKey: FlipcashCore.PublicKey
    public let sessionToken: String
    public let phantomEncryptionPublicKey: Data
}

@MainActor
private extension FlipcashCore.Keychain {
    @SecureCodable(.connectedWalletSession)
    static var connectedWalletSession: ConnectedWalletSession?
}

// MARK: - Mock -

extension WalletConnection {
    static let mock = WalletConnection(owner: .mock, client: .mock)
}
