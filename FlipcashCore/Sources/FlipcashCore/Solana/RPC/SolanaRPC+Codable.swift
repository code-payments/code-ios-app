//
//  SolanaRPC+Codable.swift
//  FlipcashCore
//
//  Created by Raul Riera on 2026-05-07.
//

import Foundation

// MARK: - SolanaCommitment -

/// Solana commitment level. The wire form is the lowercase enum name.
public enum SolanaCommitment: String, Codable, Sendable {
    case processed
    case confirmed
    case finalized
}

// MARK: - SolanaTransactionEncoding -

/// Wire encoding for transaction bytes in `sendTransaction` /
/// `simulateTransaction` params. Flipcash always submits base64.
public enum SolanaTransactionEncoding: String, Codable, Sendable {
    case base64
    case base58
}

// MARK: - SolanaSendTransactionConfig -

public struct SolanaSendTransactionConfig: Encodable, Sendable {

    public let encoding: SolanaTransactionEncoding

    public init(encoding: SolanaTransactionEncoding = .base64) {
        self.encoding = encoding
    }
}

// MARK: - SolanaSimulateTransactionConfig -

public struct SolanaSimulateTransactionConfig: Encodable, Sendable {

    public let commitment: SolanaCommitment
    public let encoding: SolanaTransactionEncoding
    public let replaceRecentBlockhash: Bool

    public init(
        commitment: SolanaCommitment = .confirmed,
        encoding: SolanaTransactionEncoding = .base64,
        replaceRecentBlockhash: Bool = false
    ) {
        self.commitment = commitment
        self.encoding = encoding
        self.replaceRecentBlockhash = replaceRecentBlockhash
    }
}

// MARK: - SolanaSimulationResult -

/// Decoded `value` from a `simulateTransaction` response. `err` is intentionally
/// kept opaque (`AnyCodable`-shaped via `JSONValue`) — Solana's simulation
/// errors are a discriminated grab-bag (`InstructionError`, `BlockhashNotFound`,
/// strings, nested arrays). The client only branches on null vs non-null and
/// surfaces `logs` to callers.
public struct SolanaSimulationResult: Decodable, Sendable {

    public let err: JSONValue?
    public let logs: [String]?

    public init(err: JSONValue? = nil, logs: [String]? = nil) {
        self.err = err
        self.logs = logs
    }
}

// MARK: - SolanaRPCError -

public enum SolanaRPCError: Error, Sendable {

    /// The simulation request was accepted by the network but the simulation
    /// itself reported an `err` payload. `logs` are forwarded as-is.
    case transactionSimulationError(logs: [String])

    /// The JSON-RPC envelope returned `error: { code, message, data }`.
    case responseError(SolanaRPCResponseError)

    /// HTTP layer error (timeout, DNS failure, lost connection).
    case transport(URLError)

    /// HTTP returned a non-2xx response without a JSON-RPC error envelope.
    case invalidHTTPStatus(code: Int)

    /// JSON-RPC envelope decoded without `result` or `error`. Unexpected.
    case missingResult

    /// Failed to encode the outgoing request body.
    case encoding(Error)

    /// Failed to decode the response body.
    case decoding(Error)
}

// MARK: - SolanaRPCResponseError -

public struct SolanaRPCResponseError: Decodable, Sendable, Error {

    public let code: Int?
    public let message: String?
    public let data: Payload?

    public init(code: Int?, message: String?, data: Payload?) {
        self.code = code
        self.message = message
        self.data = data
    }

    public struct Payload: Decodable, Sendable {
        public let logs: [String]?

        public init(logs: [String]?) {
            self.logs = logs
        }
    }
}

// MARK: - JSONValue -

/// Minimal JSON value sum type used to round-trip opaque payloads (e.g. the
/// `err` field on a simulation result) without committing to a schema we
/// don't read.
public enum JSONValue: Decodable, Sendable, Equatable {

    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.typeMismatch(
                JSONValue.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unsupported JSON value"
                )
            )
        }
    }
}
