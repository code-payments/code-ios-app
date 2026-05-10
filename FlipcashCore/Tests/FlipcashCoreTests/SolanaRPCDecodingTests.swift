//
//  SolanaRPCDecodingTests.swift
//  FlipcashCoreTests
//

import Foundation
import os
import Testing
@testable import FlipcashCore

@Suite("SolanaJSONRPCClient JSON-RPC decoding", .serialized)
struct SolanaRPCDecodingTests {

    // MARK: - Fixtures

    private static let endpoint = URL(string: "https://example-solana.test/rpc")!
    private static let blockhashB58 = "EBDRoayCDDUvDgCimta45ajQeXbexv7aKqJubruqpyvu"
    private static let signatureB58 = "5WuSx6eLmz26LxLzeaAKabtQ9xTpFjjEo8v2rCWHsAcxnGxmLuSav5rgb1JfWqXP2SaqtjLPUNBEXYTfGYdufjmt"
    private static let unsignedTx = "AQ=="

    private static func client(serving body: String) -> SolanaJSONRPCClient {
        StubURLProtocol.body.withLock { $0 = body }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return SolanaJSONRPCClient(
            endpoint: endpoint,
            urlSession: URLSession(configuration: configuration)
        )
    }

    // MARK: - getLatestBlockhash

    @Test("getLatestBlockhash decodes value.blockhash into a Hash")
    func getLatestBlockhash_decodesBlockhash() async throws {
        let body = """
        {
          "jsonrpc": "2.0",
          "result": {
            "context": { "slot": 1 },
            "value": {
              "blockhash": "\(Self.blockhashB58)",
              "lastValidBlockHeight": 1234
            }
          },
          "id": 1
        }
        """
        let hash = try await Self.client(serving: body).getLatestBlockhash(commitment: .finalized)
        #expect(hash.base58 == Self.blockhashB58)
    }

    // MARK: - sendTransaction

    @Test("sendTransaction decodes the result string into a Signature")
    func sendTransaction_decodesSignature() async throws {
        let body = """
        {
          "jsonrpc": "2.0",
          "result": "\(Self.signatureB58)",
          "id": 1
        }
        """
        let signature = try await Self.client(serving: body)
            .sendTransaction(Self.unsignedTx, configuration: .init())
        #expect(signature.base58 == Self.signatureB58)
    }

    // MARK: - simulateTransaction — success

    @Test("simulateTransaction returns logs when err is null")
    func simulateTransaction_decodesLogs_whenErrIsNull() async throws {
        let body = """
        {
          "jsonrpc": "2.0",
          "result": {
            "context": { "slot": 1 },
            "value": {
              "err": null,
              "logs": ["Program A invoke [1]", "Program A success"]
            }
          },
          "id": 1
        }
        """
        let result = try await Self.client(serving: body)
            .simulateTransaction(Self.unsignedTx, configuration: .init())
        #expect(result.err == nil)
        #expect(result.logs == ["Program A invoke [1]", "Program A success"])
    }

    // MARK: - simulateTransaction — err present → throws transactionSimulationError

    @Test("simulateTransaction throws transactionSimulationError carrying logs when err is non-null")
    func simulateTransaction_throwsSimulationError_whenErrPresent() async throws {
        let body = """
        {
          "jsonrpc": "2.0",
          "result": {
            "context": { "slot": 1 },
            "value": {
              "err": { "InstructionError": [0, "InsufficientFunds"] },
              "logs": ["Program A invoke [1]", "Program A failed: insufficient funds"]
            }
          },
          "id": 1
        }
        """
        do {
            _ = try await Self.client(serving: body)
                .simulateTransaction(Self.unsignedTx, configuration: .init())
            Issue.record("simulateTransaction should have thrown")
        } catch let SolanaRPCError.transactionSimulationError(logs) {
            #expect(logs == ["Program A invoke [1]", "Program A failed: insufficient funds"])
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    // MARK: - JSON-RPC envelope error → throws responseError

    @Test("Envelope-level error is surfaced as SolanaRPCError.responseError with code, message, and logs")
    func envelopeError_surfacesAsResponseError() async throws {
        let body = """
        {
          "jsonrpc": "2.0",
          "error": {
            "code": -32602,
            "message": "Invalid params: bad encoding",
            "data": { "logs": ["preflight: invalid base64"] }
          },
          "id": 1
        }
        """
        do {
            _ = try await Self.client(serving: body).getLatestBlockhash(commitment: .finalized)
            Issue.record("Expected SolanaRPCError.responseError")
        } catch let SolanaRPCError.responseError(payload) {
            #expect(payload.code == -32602)
            #expect(payload.message == "Invalid params: bad encoding")
            #expect(payload.data?.logs == ["preflight: invalid base64"])
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}

// MARK: - URLProtocol stub

/// `URLProtocol`-based stub so the suite runs hermetically — no live network,
/// CI-compatible. Body is shared via static state because `URLSession`
/// instantiates `URLProtocol` subclasses itself, leaving no constructor seam
/// for per-instance state. The suite is `.serialized` so the set-body →
/// request → read-body sequence stays atomic across test methods; the lock
/// keeps individual access Swift-6-clean and tolerates future per-test
/// parallelism if the stub is reworked to key by request URL.
private final class StubURLProtocol: URLProtocol {

    static let body = OSAllocatedUnfairLock(initialState: "")

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        let payload = Self.body.withLock { $0 }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(payload.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
