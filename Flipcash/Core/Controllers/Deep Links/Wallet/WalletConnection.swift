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

private let logger = Logger(label: "flipcash.wallet-connection")

@Observable
public final class WalletConnection {

    /// General wallet-related dialogs (connect failures, key restoration).
    /// Swap-flow dialogs are owned by `PhantomDepositOperation`.
    var dialogItem: DialogItem?

    private(set) var session: ConnectedWalletSession?

    var publicKey: FlipcashCore.PublicKey {
        box.publicKey
    }

    /// Stream of deeplink events from Phantom — signed transactions and
    /// errors. Consumed by the in-flight `PhantomDepositOperation`; the
    /// stream finishes in `deinit` so the consumer Task exits cleanly.
    let deeplinkEvents: AsyncStream<DeeplinkEvent>
    private let deeplinkContinuation: AsyncStream<DeeplinkEvent>.Continuation

    /// Event yielded onto `deeplinkEvents` for each deeplink return.
    enum DeeplinkEvent: Sendable {
        /// Phantom returned with a signed transaction (base58-encoded).
        case signed(String)
        /// Phantom returned with code 4001 (user-cancel).
        case userCancelled
        /// Phantom returned with a non-cancel error code.
        case failed(code: String)
    }

    private let box: Box
    let owner: AccountCluster
    private let rpc: any SolanaRPC

    /// Awaiting continuation for `connect()` / `handshake()`. Resumed by
    /// `didConnect` on success or by the errorCode branch of `didReceiveURL`
    /// on failure.
    private var pendingConnect: CheckedContinuation<Void, Swift.Error>?

    /// Whether the user has previously linked a Phantom wallet via
    /// `connectToPhantom`. Once true it stays true for the lifetime of the
    /// keychain entry; users can clear by uninstalling Phantom or wiping app data.
    var isConnected: Bool {
        Keychain.connectedWalletSession != nil
    }

    // MARK: - Init -

    init(owner: AccountCluster, rpc: any SolanaRPC = SolanaJSONRPCClient()) {
        self.owner = owner
        self.rpc = rpc

        var continuation: AsyncStream<DeeplinkEvent>.Continuation!
        self.deeplinkEvents = AsyncStream { continuation = $0 }
        self.deeplinkContinuation = continuation

        if let connectedWalletSession = Keychain.connectedWalletSession {
            self.session = connectedWalletSession
            self.box = try! Box(secretKey: connectedWalletSession.secretKey)
            logger.info("Restored encryption box", metadata: ["publicKey": "\(box.publicKey.base58)"])
        } else {
            self.box = try! Box()
            logger.info("New encryption box", metadata: ["publicKey": "\(box.publicKey.base58)"])
        }
    }

    deinit {
        // Closing the stream lets the coordinator's consumer Task exit cleanly
        // when the SessionContainer (and thus this connection) tears down.
        deeplinkContinuation.finish()
    }
    
    // MARK: - Receive -

    func didReceiveURL(url: URL) {
        if let code = url.queryItemValue(for: "errorCode") {
            Analytics.track(event: Analytics.WalletEvent.cancel)

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
            // yielding a swap event. 4001 (user-cancel) becomes a
            // CancellationError so callers can silently abort; every other
            // code becomes `connectFailed` so callers can surface an error.
            if url.pathComponents.last == "walletConnected", let continuation = pendingConnect {
                pendingConnect = nil
                if isUserCancel {
                    // Distinct from CancellationError so the coordinator can
                    // surface a "Connection Cancelled" dialog. CancellationError
                    // would route through the silent local-cancel path.
                    continuation.resume(throwing: WalletConnectionError.userCancelledConnect)
                } else {
                    continuation.resume(throwing: WalletConnectionError.connectFailed(code: code))
                }
                return
            }

            // Swap-flow error. Forward to the coordinator via the stream;
            // the coordinator decides whether to mark the active context
            // failed or surface a dialog (e.g., user tapped Phantom but
            // pending state had cleared).
            deeplinkContinuation.yield(isUserCancel ? .userCancelled : .failed(code: code))
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
            }
        }
    }
    
    /// Yields the signed transaction to the deeplink stream. The in-flight
    /// `PhantomDepositOperation` consumes the stream and runs simulation +
    /// server-notify + chain submission for the operation.
    private func didSignTransaction(_ signedTx: String) {
        deeplinkContinuation.yield(.signed(signedTx))
    }

    /// Opens the external wallet via deep link.
    private func openExternalWallet(_ url: URL) {
        url.openWithApplication()
    }

    // MARK: - Actions -

    /// Async wrapper around `connectToPhantom()`. Returns immediately if
    /// already connected. Otherwise opens Phantom and suspends until the
    /// connect deeplink arrives (success) or an errorCode callback does
    /// (throws `WalletConnectionError.connectFailed`). A second call while
    /// the first is in flight cancels the first waiter.
    ///
    /// Task cancellation is propagated through `withTaskCancellationHandler`
    /// so callers that abandon the connect (e.g. the Phantom flow screen
    /// being popped) don't leak the underlying `CheckedContinuation`.
    func connect() async throws {
        guard !isConnected else { return }
        try await openConnectDeeplink()
    }

    /// Always deeplinks Phantom for connect, even when a Keychain session
    /// already exists. Used by `PhantomDepositOperation` to verify the
    /// session is live before requesting a signature — Phantom auto-approves
    /// when it still trusts our `dapp_encryption_public_key` (~sub-second
    /// round-trip), and shows the connect prompt when it doesn't.
    ///
    /// Skipping this verification leaves us vulnerable to "first transaction
    /// silently fails" when the user revoked us in Phantom between flows.
    func handshake() async throws {
        try await openConnectDeeplink()
    }

    /// Shared deeplink-and-await primitive. Suspends until `didConnect` or an
    /// errorCode callback resolves the continuation. Cancellation propagates
    /// through `withTaskCancellationHandler`.
    private func openConnectDeeplink() async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Swift.Error>) in
                pendingConnect?.resume(throwing: CancellationError())
                pendingConnect = continuation
                connectToPhantom()
            }
        } onCancel: { [weak self] in
            Task { @MainActor [weak self] in
                self?.cancelPendingConnect()
            }
        }
    }

    /// Resumes any in-flight `pendingConnect` with a CancellationError and
    /// clears the slot. Safe to call when nothing is pending.
    private func cancelPendingConnect() {
        guard let continuation = pendingConnect else { return }
        pendingConnect = nil
        continuation.resume(throwing: CancellationError())
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

    /// Builds + sends a USDC→USDF transaction to Phantom for signing. The
    /// signed transaction comes back via `didReceiveURL` → `deeplinkEvents`,
    /// where the in-flight `PhantomDepositOperation` consumes it. This method
    /// has no pending-state side effects of its own — it's a pure "send sign
    /// request" service.
    func sendUsdcToUsdfSignRequest(
        usdc: FlipcashCore.TokenAmount,
        fundingSwapId: SwapId,
        displayName: String
    ) async throws {
        guard let connectedSession = Keychain.connectedWalletSession else {
            throw Error.noSession
        }

        let amount = ExchangedFiat.compute(
            onChainAmount: usdc,
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

        let recentBlockhash = try await rpc.getLatestBlockhash(commitment: .finalized)

        let transaction = SolanaTransaction(
            payer: externalWallet,
            recentBlockhash: recentBlockhash,
            instructions: instructions
        )

        let txEncoded = Base58.fromBytes(Array(transaction.encode()))

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
            logger.error("Failed to construct signTransaction URL")
            throw Error.invalidURL
        }

        Analytics.walletRequestAmount(amount: amount.nativeAmount)
        openExternalWallet(url)
        logger.info("Requested USDC→USDF swap", metadata: [
            "amount": "\(amount.nativeAmount.formatted())",
            "swapId": "\(fundingSwapId.publicKey.base58)",
            "name": "\(displayName)",
        ])
    }

    /// Deposit-flavoured sibling of `sendUsdcToUsdfSignRequest`. The signed
    /// swap's USDF output is transferred to the user's USDF VM deposit ATA
    /// instead of the swap PDA, so Geyser credits the balance with no
    /// server-side buy intent. `destination` is the operation-derived deposit
    /// ATA — the builder re-derives the same account from `.vmDeposit`.
    func sendUsdcToUsdfDepositSignRequest(
        usdc: FlipcashCore.TokenAmount,
        destination: FlipcashCore.PublicKey,
        fundingSwapId: SwapId,
        displayName: String
    ) async throws {
        guard let connectedSession = Keychain.connectedWalletSession else {
            throw Error.noSession
        }

        let amount = ExchangedFiat.compute(
            onChainAmount: usdc,
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
            swapId: fundingSwapId.publicKey,
            destination: .vmDeposit
        )

        let recentBlockhash = try await rpc.getLatestBlockhash(commitment: .finalized)

        let transaction = SolanaTransaction(
            payer: externalWallet,
            recentBlockhash: recentBlockhash,
            instructions: instructions
        )

        let txEncoded = Base58.fromBytes(Array(transaction.encode()))

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
            logger.error("Failed to construct deposit signTransaction URL")
            throw Error.invalidURL
        }

        Analytics.walletRequestAmount(amount: amount.nativeAmount)
        openExternalWallet(url)
        logger.info("Requested USDC→USDF deposit swap", metadata: [
            "amount": "\(amount.nativeAmount.formatted())",
            "swapId": "\(fundingSwapId.publicKey.base58)",
            "destination": "\(destination.base58)",
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
    /// User cancelled the connect prompt in Phantom (Phantom code 4001 on the
    /// `walletConnected` deeplink). Distinct from `CancellationError`, which
    /// signals a local Task cancellation (view dismissed, coordinator reset).
    case userCancelledConnect

    public var errorDescription: String? {
        switch self {
        case .keypairGenerationFailed:   return "Failed to generate X25519 keypair."
        case .decryptionFailed:          return "Failed to decrypt payload (MAC check failed)."
        case .jsonDecodingFailed(let e): return "Failed to decode JSON: \(e.localizedDescription)"
        case .noSession:                 return "No connected wallet session."
        case .connectFailed(let code):   return "Wallet connection failed (code: \(code))."
        case .userCancelledConnect:      return "You cancelled the connection in your wallet."
        }
    }
}

extension WalletConnection {
    enum Error: Swift.Error {
        case noSession
        case invalidURL
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

private extension FlipcashCore.Keychain {
    @SecureCodable(.connectedWalletSession)
    static var connectedWalletSession: ConnectedWalletSession?
}

// MARK: - Mock -

extension WalletConnection {
    static let mock = WalletConnection(owner: .mock)
}
