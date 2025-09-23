//
//  WalletConnection.swift
//  Code
//
//  Created by Dima Bart on 2025-09-17.
//

import Foundation
import FlipcashCore
import TweetNacl
import SolanaSwift

@MainActor
public final class WalletConnection: ObservableObject {
    
    @Published private var session: ConnectedWalletSession?
    
    var publicKey: FlipcashCore.PublicKey {
        box.publicKey
    }
    
    private let box: Box
    private let owner: AccountCluster
    
    private let solanaClient = BlockchainClient(
        apiClient: JSONRPCAPIClient(
            endpoint: .init(
                address: "https://api.mainnet-beta.solana.com",
                network: .mainnetBeta
            )
        )
    )
    
    // MARK: - Init -
    
    init(owner: AccountCluster) {
        self.owner = owner
        
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
        if let response = try? WalletResponseConnect(url: url) {
            didConnect(response: response)
        }
    }
    
    private func didConnect(response: WalletResponseConnect) {
        do {
            let result = try box.decrypt(
                sealed: .init(
                    data: response.data,
                    nonce: response.nonce
                ),
                encryptionPublicKey: response.encryptionPublicKey
            )
            
            if let walletSession = WalletSession(
                walletPublicKey: result.publicKey,
                sessionToken: result.session
            ) {
                print("[WalletConnection] Connected to: \(result.publicKey), Session: \(result.session)")
                let session = ConnectedWalletSession(
                    secretKey: box.secretKey,
                    walletPublicKey: walletSession.walletPublicKey,
                    sessionToken: walletSession.sessionToken,
                    phantomEncryptionPublicKey: response.encryptionPublicKey
                )
                
                Keychain.connectedWalletSession = session
                self.session = session
                
                Task {
                    try await Task.delay(seconds: 1)
                    await requestTransfer(usdc: 1)
                }
            }
            
        } catch {
            print("[WalletConnection] Did Connect (Error): \(error)")
        }
    }
    
    // MARK: - Actions -
    
    func connectToPhantom() {
        let nonce = UUID().uuidString
        
        #warning("Fix /verify endpoint")
        var c = URLComponents(string: "https://phantom.app/ul/v1/connect")!
        c.queryItems = [
            URLQueryItem(name: "app_url",                    value: "https://flipcash.com"),
            URLQueryItem(name: "dapp_encryption_public_key", value: publicKey.base58),
            URLQueryItem(name: "cluster",                    value: "mainnet-beta"), // or "devnet"
            URLQueryItem(name: "redirect_link",              value: "https://app.flipcash.com/verify/walletConnected"),
            URLQueryItem(name: "nonce",                      value: nonce)
        ]
        
        c.url!.openWithApplication()
    }
    
    /// Uses Phantom `signAllTransactions` (replaces deprecated `signAndSendTransaction`) to sign a single
    /// TokenProgram.transferChecked for a USDC (SPL Token) transfer. Phantom returns signed tx; your backend/client should broadcast it.
    func requestTransfer(usdc: Decimal) async {
        guard let connectedSession = Keychain.connectedWalletSession else {
            print("[WalletConnection] Error: no connected session")
            return
        }
        
        let depositAddress = owner.depositPublicKey
        
        do {
            // 1. Build USDC transfer with ATA handling
            let walletOwner    = try PublicKey(string: connectedSession.walletPublicKey.base58)
            let depositAddress = try PublicKey(string: depositAddress.base58)
            
            let destinationExists = try await solanaClient.apiClient.checkIfAssociatedTokenAccountExists(
                owner: depositAddress,
                mint: PublicKey.usdcMint.base58EncodedString,
                tokenProgramId: PublicKey.tokenProgram
            )
            
            let recentBlockhash = try await solanaClient.apiClient.getLatestBlockhash()
            
            var transaction = try TransactionBuilder.usdcTransfer(
                fromOwner: walletOwner,
                toOwner: depositAddress,
                amount: usdc,
                shouldCreateTokenAccount: !destinationExists,
                recentBlockhash: recentBlockhash
            )
            
            let txEncoded = Base58.fromBytes(Array(try transaction.serialize()))

            // Build the encrypted JSON
            let payload: [String: Any] = [
                "transactions": [txEncoded],
                "session": connectedSession.sessionToken
            ]
            let payloadData = try JSONSerialization.data(withJSONObject: payload, options: [])

            // Encrypt using our Box + Phantom's encryption public key from the saved session
            let (nonce, payloadEncrypted) = try box.encryptForPhantom(
                payload: payloadData,
                encryptionPublicKey: connectedSession.phantomEncryptionPublicKey
            )

            // Docs: https://docs.phantom.com/phantom-deeplinks/provider-methods/signalltransactions
            // Build Phantom signAllTransactions deeplink
            var c = URLComponents(string: "https://phantom.app/ul/v1/signAllTransactions")!
            #warning("Fix /verify endpoint")
            c.queryItems = [
                URLQueryItem(name: "dapp_encryption_public_key", value: publicKey.base58),
                URLQueryItem(name: "nonce",                      value: nonce),
                URLQueryItem(name: "redirect_link",              value: "https://app.flipcash.com/verify/transferComplete"),
                URLQueryItem(name: "payload",                    value: payloadEncrypted)
            ]

            guard let url = c.url else {
                print("[WalletConnection] Failed to construct signAllTransactions URL")
                return
            }

            url.openWithApplication()
            print("[WalletConnection] Requested transfer of \(usdc) USDC to \(depositAddress.base58EncodedString)")
            
        } catch {
            print("[WalletConnection] requestTransfer error: \(error)")
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
            
            self.publicKey = PublicKey(keyPair.publicKey)!
            self.secretKey = Seed32(keyPair.secretKey)!
        }

        // MARK: - Decrypt -

        /// Decrypts wallet's payload using X25519 public key (bytes) and returns the typed response.
        public func decrypt(
            sealed: SealedData,
            encryptionPublicKey: Data
        ) throws -> WalletConnectionResponse {
            // 1) Precompute shared key via X25519
            let sharedKey = try NaclBox.before(
                publicKey: encryptionPublicKey,
                secretKey: secretKey.data
            )
            
            // 2) XSalsa20-Poly1305 open (NaCl secretbox)
            let plaintext = try NaclSecretBox.open(
                box: sealed.data,
                nonce: sealed.nonce,
                key: sharedKey
            )
            
            // 3) Decode JSON → WalletConnectionResponse
            do {
                return try decoder.decode(WalletConnectionResponse.self, from: plaintext)
            } catch {
                throw WalletConnectionError.jsonDecodingFailed(underlying: error)
            }
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

    public var errorDescription: String? {
        switch self {
        case .keypairGenerationFailed:   return "Failed to generate X25519 keypair."
        case .decryptionFailed:          return "Failed to decrypt payload (MAC check failed)."
        case .jsonDecodingFailed(let e): return "Failed to decode JSON: \(e.localizedDescription)"
        }
    }
}

// MARK: - WalletConnectionResponse -

public struct WalletConnectionResponse: Decodable {
    public let publicKey: String
    public let session: String
    
    enum CodingKeys: String, CodingKey {
        case publicKey = "public_key"
        case session
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
        guard let publicKey = FlipcashCore.PublicKey(base58: walletPublicKey) else {
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

private struct ConnectedWalletSession: Codable {
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
    static let mock = WalletConnection(owner: .mock)
}
