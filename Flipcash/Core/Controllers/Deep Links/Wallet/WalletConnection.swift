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

@MainActor
@Observable
public final class WalletConnection {

    var isShowingAmountEntry: Bool = false

    var dialogItem: DialogItem?

    /// Current swap processing context. When set, the processing screen should be shown.
    var processing: ExternalSwapProcessing?

    /// Set when the user cancels in the external wallet. The processing screen
    /// observes this to switch to the failed display state.
    var isProcessingCancelled = false

    private(set) var session: ConnectedWalletSession?

    var publicKey: FlipcashCore.PublicKey {
        box.publicKey
    }

    private let box: Box
    private let owner: AccountCluster
    private let client: Client
    private let ratesController: RatesController

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

    private struct PendingSwap {
        let swapId: SwapId
        let amount: ExchangedFiat
        let token: MintMetadata
    }

    // MARK: - Init -

    init(owner: AccountCluster, client: Client, ratesController: RatesController) {
        self.owner = owner
        self.client = client
        self.ratesController = ratesController

        if let connectedWalletSession = Keychain.connectedWalletSession {
            self.session = connectedWalletSession
            self.box = try! Box(secretKey: connectedWalletSession.secretKey)
            print("[WalletConnection] Restored encryption box, public key: \(box.publicKey.base58)")
        } else {
            self.box = try! Box()
            print("[WalletConnection] New encryption box, public key: \(box.publicKey.base58)")
        }
    }
    
    // MARK: - Receive -

    func didReceiveURL(url: URL) {
        // The user has returned from the external wallet — re-enable interface reset
        // regardless of outcome (success, cancel, error).
        UIApplication.isInterfaceResetDisabled = false

        if let code = url.queryItemValue(for: "errorCode") {
            if code == "4001" {
                Analytics.walletCancel()
                pendingSwap = nil

                if processing != nil {
                    isProcessingCancelled = true
                } else {
                    dialogItem = .init(
                        style: .destructive,
                        title: "Transaction Cancelled",
                        subtitle: "The transaction was cancelled in your wallet",
                        dismissable: true
                    ) {
                        .okay(kind: .destructive)
                    }
                }
            }
            return
        }
        
        guard var encryptedResponse = try? EncryptedWalletResponse(url: url) else {
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
                    print("[WalletConnection] Received signed transactions but no active session found.")
                    return
                }
                
                encryptedResponse.encryptionPublicKey = session.phantomEncryptionPublicKey
                
                let response = try box.decrypt(
                    type: WalletResponse.SignedTransactions.self,
                    encryptedWalletResponse: encryptedResponse
                )
                
                didSignTransactions(response.transactions)
                
            default:
                print("[WalletConnection] Deep link path did not match known routes: \(component ?? "nil")")
                return
            }
            
        } catch {
            print("[WalletConnection] Failed to decrypt: \(error)")
            return
        }
    }
    
    private func didConnect(response: WalletResponse.Connected, encryptionPublicKey: Data) {
        if let walletSession = WalletSession(
            walletPublicKey: response.publicKey,
            sessionToken: response.session
        ) {
            print("[WalletConnection] Connected to: \(response.publicKey), Session: \(response.session)")
            let session = ConnectedWalletSession(
                secretKey: box.secretKey,
                walletPublicKey: walletSession.walletPublicKey,
                sessionToken: walletSession.sessionToken,
                phantomEncryptionPublicKey: encryptionPublicKey
            )
            
            Keychain.connectedWalletSession = session
            self.session = session

            isShowingAmountEntry = true
        }
    }
    
    private func didSignTransactions(_ transactions: [String]) {
        Task { [solanaClient, client, weak self] in
            // Capture pending swap before processing
            let pending = self?.pendingSwap
            self?.pendingSwap = nil

            // Submit transactions in parallel and collect results
            let results = await withTaskGroup(of: (index: Int, signature: String?).self) { group in
                for (index, txBase58) in transactions.enumerated() {
                    group.addTask {
                        do {
                            // Decode base58 -> bytes -> Data
                            let rawBytes = Base58.toBytes(txBase58)
                            let rawData  = Data(rawBytes)
                            let txBase64 = rawData.base64EncodedString()

                            let signature = try await solanaClient.apiClient.sendTransaction(
                                transaction: txBase64,
                                configs: .init(encoding: "base64")!
                            )

                            print("[WalletConnection] Transaction sent: \(signature)")
                            return (index, signature)

                        } catch {
                            ErrorReporting.captureError(error, reason: "Failed to send Solana transaction")
                            print("[WalletConnection] Transaction failed to send: \(error)")
                            return (index, nil)
                        }
                    }
                }

                var collected: [(index: Int, signature: String?)] = []
                for await result in group {
                    collected.append(result)
                }
                return collected.sorted { $0.index < $1.index }
            }

            let submittedSignatures = results.compactMap(\.signature)
            let errorCount = results.count - submittedSignatures.count

            if errorCount == 0 {
                Analytics.walletTransactionsSubmitted()

                // If this was a swap transaction, notify server via buy()
                if let pending, let firstSignature = submittedSignatures.first, let self {
                    do {
                        let signatureKey = try Signature(base58: firstSignature)
                        let fundingSource = FundingSource.externalWallet(transactionSignature: signatureKey)

                        // Get verified state for intent construction
                        guard let verifiedState = await self.ratesController.getVerifiedState(
                            for: pending.amount.converted.currencyCode,
                            mint: pending.amount.mint
                        ) else {
                            throw Error.missingVerifiedState
                        }

                        // Call buy() with externalWallet funding (Phase 1 only, no IntentFundSwap)
                        try await client.buy(
                            swapId: pending.swapId,
                            amount: pending.amount,
                            verifiedState: verifiedState,
                            of: pending.token,
                            owner: self.owner,
                            fundingSource: fundingSource
                        )

                        print("[WalletConnection] Server notified of swap funding via buy()")
                    } catch {
                        ErrorReporting.captureError(error, reason: "Failed to notify server of swap funding")
                        print("[WalletConnection] Failed to notify server: \(error)")
                    }
                } else {
                    // Regular transfer (not a swap)
                    await MainActor.run {
                        self?.showSuccessDialog(tokenName: "Funds")
                    }
                }
            } else {
                Analytics.walletTransactionsFailed()
                await MainActor.run {
                    self?.showSomethingWentWrongDialog()
                }
            }
        }
    }
    
    /// Opens the external wallet via deep link and disables interface reset while the user is away.
    /// The flag is cleared in `didReceiveURL` when Phantom redirects back.
    private func openExternalWallet(_ url: URL) {
        UIApplication.isInterfaceResetDisabled = true
        url.openWithApplication()
    }

    /// Requests an external swap: builds the transaction, opens Phantom,
    /// and shows the processing screen.
    func requestSwap(usdc: Quarks, mint: FlipcashCore.PublicKey, token: MintMetadata) async throws {
        let result = try await requestUsdcToUsdfSwap(usdc: usdc, token: token)
        processing = ExternalSwapProcessing(
            swapId: result.swapId,
            mint: mint,
            amount: result.amount
        )
        isShowingAmountEntry = false
    }

    /// Dismisses the processing screen and clears any pending wallet dialogs.
    func dismissProcessing() {
        dialogItem = nil
        isProcessingCancelled = false
        processing = nil
    }

    // MARK: - Actions -

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

        Analytics.walletConnect()
        openExternalWallet(c.url!)
    }

    /// Initiates USDC→USDF swap via Phantom wallet
    /// 1. Generate swapId and build transaction (with swapId in memo)
    /// 2. Send to Phantom for signing
    /// 3. After signing: submit TX to chain, then call buy() with externalWallet funding
    ///
    /// - Parameters:
    ///   - usdc: Amount of USDC to swap (in quarks)
    ///   - token: The token to buy with the swapped USDF
    func requestUsdcToUsdfSwap(usdc: Quarks, token: MintMetadata) async throws -> (swapId: SwapId, amount: ExchangedFiat) {
        guard let connectedSession = Keychain.connectedWalletSession else {
            throw Error.noSession
        }

        // 1. Generate swapId (will be used in memo AND in buy() call)
        let swapId = SwapId.generate()

        // Create ExchangedFiat for the buy() call (USDC/USDF are 1:1)
        let amount = ExchangedFiat(underlying: usdc, converted: usdc, mint: token.address)

        // 2. Build transaction with swapId in memo
        let externalWallet = try FlipcashCore.PublicKey(base58: connectedSession.walletPublicKey.base58)
        let flipcashOwner = owner.authorityPublicKey

        let instructions = SwapInstructionBuilder.buildUsdcToUsdfSwapInstructions(
            sender: externalWallet,
            owner: flipcashOwner,
            amount: usdc.quarks,
            pool: .usdf,
            swapId: swapId.publicKey
        )

        // Convert FlipcashCore instructions to SolanaSwift
        let instructionsConverted = instructions.map { instruction in
            TransactionInstruction(
                keys: instruction.accounts.map { meta in
                    SolanaSwift.AccountMeta(
                        publicKey: try! SolanaSwift.PublicKey(string: meta.publicKey.base58),
                        isSigner: meta.isSigner,
                        isWritable: meta.isWritable
                    )
                },
                programId: try! SolanaSwift.PublicKey(string: instruction.program.base58),
                data: [UInt8](instruction.data)
            )
        }

        let recentBlockhash = try await solanaClient.apiClient.getLatestBlockhash(commitment: "finalized")

        var transaction = Transaction(
            instructions: instructionsConverted,
            recentBlockhash: recentBlockhash,
            feePayer: try SolanaSwift.PublicKey(string: externalWallet.base58)
        )

        // 3. Store pending swap info (to use when Phantom returns)
        pendingSwap = PendingSwap(swapId: swapId, amount: amount, token: token)

        // 4. Serialize and send to Phantom
        let txEncoded = Base58.fromBytes(Array(try transaction.serialize()))

        let payload: [String: Any] = [
            "transactions": [txEncoded],
            "session": connectedSession.sessionToken
        ]
        let payloadData = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (nonce, payloadEncrypted) = try box.encryptForPhantom(
            payload: payloadData,
            encryptionPublicKey: connectedSession.phantomEncryptionPublicKey
        )

        var c = URLComponents(string: "https://phantom.app/ul/v1/signAllTransactions")!
        c.queryItems = [
            URLQueryItem(name: "dapp_encryption_public_key", value: publicKey.base58),
            URLQueryItem(name: "nonce",                      value: nonce),
            URLQueryItem(name: "redirect_link",              value: "https://app.flipcash.com/wallet/transactionSigned"),
            URLQueryItem(name: "payload",                    value: payloadEncrypted)
        ]

        guard let url = c.url else {
            pendingSwap = nil
            print("[WalletConnection] Failed to construct signAllTransactions URL")
            throw Error.invalidURL
        }

        Analytics.walletRequestAmount(amount: amount.underlying)
        openExternalWallet(url)
        print("[WalletConnection] Requested USDC→USDF swap of \(amount.underlying) for \(token.symbol), swapId: \(swapId.publicKey.base58)")

        return (swapId: swapId, amount: amount)
    }

    // MARK: - Dialogs -
    
    private func showSuccessDialog(tokenName: String) {
        Task {
            let status = await PushController.fetchStatus()
            
            dialogItem = .init(
                style: .success,
                title: "Your \(tokenName) Will Be Available Soon",
                subtitle: "It should be available in a few minutes. If you have any issues please contact support@flipcash.com",
                dismissable: true,
            ) {
                if status == .notDetermined {
                    .standard("Notify Me") {
                        Task {
                            do {
                                try await PushController.authorizeAndRegister()
                            } catch {}
                        }
                    };
                    .dismiss(kind: .subtle)
                } else {
                    .okay(kind: .standard)
                }
            }
        }
    }
    
    private func showSomethingWentWrongDialog() {
        dialogItem = .init(
            style: .destructive,
            title: "Something Went Wrong",
            subtitle: "Please try again later",
            dismissable: true,
        ) {
            .okay(kind: .destructive)
        }
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

    public var errorDescription: String? {
        switch self {
        case .keypairGenerationFailed:   return "Failed to generate X25519 keypair."
        case .decryptionFailed:          return "Failed to decrypt payload (MAC check failed)."
        case .jsonDecodingFailed(let e): return "Failed to decode JSON: \(e.localizedDescription)"
        case .noSession:                 return "No connected wallet session."
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
    static let mock = WalletConnection(owner: .mock, client: .mock, ratesController: .mock)
}
