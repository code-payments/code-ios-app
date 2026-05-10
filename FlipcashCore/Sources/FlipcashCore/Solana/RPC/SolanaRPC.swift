//
//  SolanaRPC.swift
//  FlipcashCore
//
//  Created by Raul Riera on 2026-05-07.
//

import Foundation
import Logging

private let logger = Logger(label: "flipcash.solana-rpc")

// MARK: - SolanaRPC -

/// The narrow Solana JSON-RPC surface the app consumes today: fetch the
/// latest blockhash, simulate a signed transaction before submitting it, and
/// submit a signed transaction. Designed for use from any isolation context;
/// callers are expected to hop to `@MainActor` themselves for UI updates.
public protocol SolanaRPC: Sendable {

    func getLatestBlockhash(commitment: SolanaCommitment) async throws -> Hash

    func sendTransaction(
        _ base64Transaction: String,
        configuration: SolanaSendTransactionConfig
    ) async throws -> Signature

    /// Throws `SolanaRPCError.transactionSimulationError(logs:)` when the
    /// network accepts the request but the simulation itself reports an
    /// `err` payload — propagating the failure through the type system so
    /// callers cannot accidentally treat a failed simulation as a green-light.
    func simulateTransaction(
        _ base64Transaction: String,
        configuration: SolanaSimulateTransactionConfig
    ) async throws -> SolanaSimulationResult
}

// MARK: - SolanaJSONRPCClient -

/// Default `SolanaRPC` implementation backed by `URLSession`. Stateless: each
/// call builds a fresh `URLRequest`, performs the round trip, and decodes the
/// envelope. Safe to share across actors.
public struct SolanaJSONRPCClient: SolanaRPC {

    public static let mainnetBetaURL = URL(string: "https://api.mainnet-beta.solana.com")!

    private let endpoint: URL
    private let urlSession: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(
        endpoint: URL = SolanaJSONRPCClient.mainnetBetaURL,
        urlSession: URLSession = .shared
    ) {
        self.endpoint = endpoint
        self.urlSession = urlSession
    }

    // MARK: - SolanaRPC -

    public func getLatestBlockhash(commitment: SolanaCommitment) async throws -> Hash {
        let response: RPCContextValue<GetLatestBlockhashValue> = try await call(
            method: "getLatestBlockhash",
            params: GetLatestBlockhashParams(commitment: commitment)
        )
        return try Hash(base58: response.value.blockhash)
    }

    public func sendTransaction(
        _ base64Transaction: String,
        configuration: SolanaSendTransactionConfig
    ) async throws -> Signature {
        let signatureString: String = try await call(
            method: "sendTransaction",
            params: SendTransactionParams(
                transaction: base64Transaction,
                configuration: configuration
            )
        )
        return try Signature(base58: signatureString)
    }

    public func simulateTransaction(
        _ base64Transaction: String,
        configuration: SolanaSimulateTransactionConfig
    ) async throws -> SolanaSimulationResult {
        let response: RPCContextValue<SolanaSimulationResult> = try await call(
            method: "simulateTransaction",
            params: SimulateTransactionParams(
                transaction: base64Transaction,
                configuration: configuration
            )
        )
        let result = response.value
        if result.err != nil {
            throw SolanaRPCError.transactionSimulationError(logs: result.logs ?? [])
        }
        return result
    }

    // MARK: - Transport -

    private func call<Params: Encodable & Sendable, Result: Decodable & Sendable>(
        method: String,
        params: Params
    ) async throws -> Result {
        let request = try makeRequest(method: method, params: params)

        let (data, urlResponse): (Data, URLResponse)
        do {
            (data, urlResponse) = try await urlSession.data(for: request)
        } catch let error as URLError {
            throw SolanaRPCError.transport(error)
        }

        if let http = urlResponse as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw SolanaRPCError.invalidHTTPStatus(code: http.statusCode)
        }

        let envelope: JSONRPCEnvelope<Result>
        do {
            envelope = try decoder.decode(JSONRPCEnvelope<Result>.self, from: data)
        } catch {
            throw SolanaRPCError.decoding(error)
        }

        if let envelopeError = envelope.error {
            throw SolanaRPCError.responseError(envelopeError)
        }

        guard let result = envelope.result else {
            throw SolanaRPCError.missingResult
        }

        return result
    }

    private func makeRequest<Params: Encodable & Sendable>(
        method: String,
        params: Params
    ) throws -> URLRequest {
        let body = JSONRPCRequest(method: method, params: params)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            request.httpBody = try encoder.encode(body)
        } catch {
            throw SolanaRPCError.encoding(error)
        }
        return request
    }
}

// MARK: - JSON-RPC envelopes -

/// Outgoing JSON-RPC 2.0 request. `id` is fixed because Solana RPC nodes do
/// not pipeline requests over a single HTTP POST — we issue one POST per call.
private struct JSONRPCRequest<Params: Encodable & Sendable>: Encodable, Sendable {
    let jsonrpc = "2.0"
    let id = 1
    let method: String
    let params: Params
}

private struct JSONRPCEnvelope<Result: Decodable & Sendable>: Decodable, Sendable {
    let result: Result?
    let error: SolanaRPCResponseError?
}

/// Solana wraps "stateful" RPC results in a `{ context, value }` shape so the
/// caller can correlate to the slot the response was computed against.
private struct RPCContextValue<Value: Decodable & Sendable>: Decodable, Sendable {
    let value: Value
}

// MARK: - getLatestBlockhash -

private struct GetLatestBlockhashParams: Encodable, Sendable {
    let commitment: SolanaCommitment

    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(CommitmentObject(commitment: commitment))
    }

    private struct CommitmentObject: Encodable, Sendable {
        let commitment: SolanaCommitment
    }
}

private struct GetLatestBlockhashValue: Decodable, Sendable {
    let blockhash: String
}

// MARK: - sendTransaction -

private struct SendTransactionParams: Encodable, Sendable {
    let transaction: String
    let configuration: SolanaSendTransactionConfig

    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(transaction)
        try container.encode(configuration)
    }
}

// MARK: - simulateTransaction -

private struct SimulateTransactionParams: Encodable, Sendable {
    let transaction: String
    let configuration: SolanaSimulateTransactionConfig

    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(transaction)
        try container.encode(configuration)
    }
}
