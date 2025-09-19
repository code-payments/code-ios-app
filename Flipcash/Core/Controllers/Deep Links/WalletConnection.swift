//
//  WalletConnection.swift
//  Code
//
//  Created by Dima Bart on 2025-09-17.
//

import Foundation
import FlipcashCore
import TweetNacl

@MainActor
public final class WalletConnection: ObservableObject {
    
    @Published private var session: WalletSession?
    
    var publicKey: PublicKey {
        box.publicKey
    }
    
    private let box: Box
    
    // MARK: - Init -
    
    init() {
        if let connectedWalletSession = Keychain.connectedWalletSession {
            self.box = try! Box(secretKey: connectedWalletSession.secretKey)
            print("[WalletConnection] Restored encryption box, public key: \(publicKey.base58)")
        } else {
            self.box = try! Box()
            print("[WalletConnection] New encryption box, public key: \(publicKey.base58)")
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
                Keychain.connectedWalletSession = .init(
                    secretKey: box.secretKey,
                    walletPublicKey: walletSession.walletPublicKey,
                    sessionToken: walletSession.sessionToken
                )
            }
            
        } catch {
            print("[WalletConnection] Did Connect (Error): \(error)")
        }
    }
    
    // MARK: - Actions -
    
    func connectToPhantom() {
        let nonce = UUID().uuidString
        
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
}

/// NaCl “box” with an ephemeral X25519 keypair for one Phantom session.
extension WalletConnection {
    public struct Box {
        
        public let publicKey: PublicKey // 32 bytes – send as `dapp_encryption_public_key`
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
    
    public let walletPublicKey: PublicKey
    public let sessionToken: String
    
    init?(walletPublicKey: String, sessionToken: String) {
        guard let publicKey = PublicKey(base58: walletPublicKey) else {
            return nil
        }
        
        self.walletPublicKey = publicKey
        self.sessionToken = sessionToken
    }
    
    init(walletPublicKey: PublicKey, sessionToken: String) {
        self.walletPublicKey = walletPublicKey
        self.sessionToken = sessionToken
    }
}

// MARK: - ConnectedWalletSession -

private struct ConnectedWalletSession: Codable {
    public let secretKey: Seed32
    public let walletPublicKey: PublicKey
    public let sessionToken: String
}

@MainActor
private extension Keychain {
    @SecureCodable(.connectedWalletSession)
    static var connectedWalletSession: ConnectedWalletSession?
}

// MARK: - Mock -

extension WalletConnection {
    static let mock = WalletConnection()
}
