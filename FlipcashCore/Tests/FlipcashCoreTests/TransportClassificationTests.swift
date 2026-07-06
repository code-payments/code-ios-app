//
//  TransportClassificationTests.swift
//  FlipcashCoreTests
//

import Foundation
import Testing
import GRPCCore
import GRPCInProcessTransport
@testable import FlipcashCore

@Suite("Transport classification — classifiable errors route transient gRPC failures to a non-reportable case")
struct TransportClassificationTests {

    /// Generic contract check, reused by one `@Test` per conformer below. Using
    /// a generic over the concrete type (not a list of erased closures) keeps
    /// arguments `Sendable`-free and the call type-safe.
    private func assertClassifies<E: TransportClassifiableError>(_ type: E.Type) {
        #expect(E.from(transportError: RPCError(code: .deadlineExceeded, message: "")).reportingLevel == .suppressed)
        #expect(E.from(transportError: RPCError(code: .unavailable, message: "")).reportingLevel == .suppressed)
        // Regression 6a1b80a: app/user-initiated teardown lands on `.cancelled` at
        // `.info`, never collapsed into `.unknown`/`.error`.
        #expect(E.from(transportError: RPCError(code: .cancelled, message: "")).reportingLevel == .info)
        #expect(E.from(transportError: RPCError(code: .internalError, message: "")).reportingLevel == .error)
    }

    // MARK: - Registry (one line per TransportClassifiableError conformer) -

    @Test func errorFetchBalance() { assertClassifies(ErrorFetchBalance.self) }

    @Test func errorRegisterAccount() { assertClassifies(ErrorRegisterAccount.self) }
    @Test func errorLoginAccount() { assertClassifies(ErrorLoginAccount.self) }
    @Test func errorFetchUserFlags() { assertClassifies(ErrorFetchUserFlags.self) }
    @Test func errorFetchUnauthenticatedUserFlags() { assertClassifies(ErrorFetchUnauthenticatedUserFlags.self) }
    @Test func errorFetchTransactionHistory() { assertClassifies(ErrorFetchTransactionHistory.self) }
    @Test func errorFetchTransactionHistoryItemsByID() { assertClassifies(ErrorFetchTransactionHistoryItemsByID.self) }
    @Test func errorAddToken() { assertClassifies(ErrorAddToken.self) }
    @Test func errorDeleteToken() { assertClassifies(ErrorDeleteToken.self) }
    @Test func errorUpdateSettings() { assertClassifies(ErrorUpdateSettings.self) }
    @Test func errorFetchJWT() { assertClassifies(ErrorFetchJWT.self) }
    @Test func errorSendEmailCode() { assertClassifies(ErrorSendEmailCode.self) }
    @Test func errorCheckEmailCode() { assertClassifies(ErrorCheckEmailCode.self) }
    @Test func errorUnlinkEmail() { assertClassifies(ErrorUnlinkEmail.self) }
    @Test func errorFetchProfile() { assertClassifies(ErrorFetchProfile.self) }
    @Test func errorRateHistory() { assertClassifies(ErrorRateHistory.self) }
    @Test func errorGetSwap() { assertClassifies(ErrorGetSwap.self) }
    @Test func errorVoidGiftCard() { assertClassifies(ErrorVoidGiftCard.self) }
    @Test func errorFetchLimits() { assertClassifies(ErrorFetchLimits.self) }
    @Test func errorFetchIntentMetadata() { assertClassifies(ErrorFetchIntentMetadata.self) }
    @Test func errorSendVerificationCode() { assertClassifies(ErrorSendVerificationCode.self) }
    @Test func errorCheckVerificationCode() { assertClassifies(ErrorCheckVerificationCode.self) }
    @Test func errorUnlinkPhone() { assertClassifies(ErrorUnlinkPhone.self) }
    @Test func errorLinkForPayment() { assertClassifies(ErrorLinkForPayment.self) }
    @Test func errorContactSync() { assertClassifies(ErrorContactSync.self) }
    @Test func errorResolve() { assertClassifies(ErrorResolve.self) }
    @Test func errorGetMessages() { assertClassifies(ErrorGetMessages.self) }
    @Test func errorSendMessage() { assertClassifies(ErrorSendMessage.self) }
    @Test func errorAdvancePointer() { assertClassifies(ErrorAdvancePointer.self) }
    @Test func errorNotifyIsTyping() { assertClassifies(ErrorNotifyIsTyping.self) }
    @Test func errorGetDmChatFeed() { assertClassifies(ErrorGetDmChatFeed.self) }
    @Test func errorGetChat() { assertClassifies(ErrorGetChat.self) }

    // MARK: - Tier 2: associated-value errors that capture the transport error -
    // These don't conform to TransportClassifiableError (they carry the error in a
    // case rather than mapping to a dedicated one), so their `reportingLevel` is
    // asserted directly.

    @Test("ErrorModeration.network is reportable only for non-transient errors")
    func errorModerationNetwork() {
        #expect(ErrorModeration.network(RPCError(code: .deadlineExceeded, message: "")).reportingLevel == .suppressed)
        #expect(ErrorModeration.network(RPCError(code: .internalError, message: "")).reportingLevel == .error)
        #expect(ErrorModeration.unknown.reportingLevel == .error)
    }

    @Test("ErrorLaunchCurrency.network is reportable only for non-transient errors")
    func errorLaunchCurrencyNetwork() {
        #expect(ErrorLaunchCurrency.network(RPCError(code: .deadlineExceeded, message: "")).reportingLevel == .suppressed)
        #expect(ErrorLaunchCurrency.network(RPCError(code: .internalError, message: "")).reportingLevel == .error)
        #expect(ErrorLaunchCurrency.unknown.reportingLevel == .error)
    }

    @Test("ErrorSwap classifies grpcStatus by transience; grpcError always reports")
    func errorSwapClassification() {
        #expect(ErrorSwap.grpcStatus(RPCError(code: .deadlineExceeded, message: "")).reportingLevel == .suppressed)
        #expect(ErrorSwap.grpcStatus(RPCError(code: .internalError, message: "")).reportingLevel == .error)
        // .grpcError is the un-typed failure — deliberately reported even for a
        // transient-looking code, unlike the typed .grpcStatus case.
        #expect(ErrorSwap.grpcError(RPCError(code: .unavailable, message: "")).reportingLevel == .error)
        #expect(ErrorSwap.unknown.reportingLevel == .error)
    }

    @Test("ErrorStatelessSwap classifies grpcStatus by transience; grpcError always reports")
    func errorStatelessSwapClassification() {
        #expect(ErrorStatelessSwap.grpcStatus(RPCError(code: .deadlineExceeded, message: "")).reportingLevel == .suppressed)
        #expect(ErrorStatelessSwap.grpcStatus(RPCError(code: .internalError, message: "")).reportingLevel == .error)
        #expect(ErrorStatelessSwap.grpcError(RPCError(code: .unavailable, message: "")).reportingLevel == .error)
        #expect(ErrorStatelessSwap.unknown.reportingLevel == .error)
    }

    // MARK: - Raw RPCError self-classification -
    // Unary RPCs whose failure type is the existential `Error` ship the RPCError
    // directly; its `ServerError` conformance classifies transient transport
    // failures as non-reportable without a dedicated error enum.

    @Test("RPCError suppresses transient codes, softens cancellation, errors the rest")
    func rpcErrorReportability() {
        #expect(RPCError(code: .deadlineExceeded, message: "").reportingLevel == .suppressed)
        #expect(RPCError(code: .unavailable, message: "").reportingLevel == .suppressed)
        #expect(RPCError(code: .internalError, message: "").reportingLevel == .error)
        // App/user-initiated teardown — visible, but not a defect.
        #expect(RPCError(code: .cancelled, message: "").reportingLevel == .info)
    }

    // MARK: - Real transport errors -

    /// End-to-end proof that a REAL deadline expiry in the v2 stack — not a
    /// hand-built RPCError — surfaces as `.deadlineExceeded` and stays
    /// non-reportable. Runs hermetically over the in-process transport against
    /// a handler that outlives the call's timeout.
    @Test("A real deadline expiry surfaces as RPCError.deadlineExceeded and stays non-reportable")
    func realDeadlineExpiryClassifiesAsNonReportable() async throws {
        let method = MethodDescriptor(fullyQualifiedService: "test.Slow", method: "Sleep")
        let transport = InProcessTransport()
        var router = RPCRouter<InProcessTransport.Server>()
        router.registerHandler(forMethod: method, deserializer: UTF8Codec(), serializer: UTF8Codec()) { _, _ in
            try await Task.sleep(for: .seconds(60))
            return StreamingServerResponse(single: ServerResponse(message: "too late"))
        }
        let server = GRPCServer(transport: transport.server, router: router)
        let client = GRPCClient(transport: transport.client)

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await server.serve() }
            group.addTask { try await client.runConnections() }

            var options = CallOptions.defaults
            options.timeout = .milliseconds(100)

            var caught: RPCError?
            do {
                _ = try await client.unary(
                    request: ClientRequest(message: "ping"),
                    descriptor: method,
                    serializer: UTF8Codec(),
                    deserializer: UTF8Codec(),
                    options: options
                ) { try $0.message }
            } catch let error as RPCError {
                caught = error
            }

            let rpcError = try #require(caught)
            #expect(rpcError.code == .deadlineExceeded)
            #expect(rpcError.reportingLevel == .suppressed)

            client.beginGracefulShutdown()
            server.beginGracefulShutdown()
            group.cancelAll()
        }
    }
}

private struct UTF8Codec: MessageSerializer, MessageDeserializer {
    func serialize<Bytes: GRPCContiguousBytes>(_ message: String) throws -> Bytes {
        Bytes(Array(message.utf8))
    }

    func deserialize<Bytes: GRPCContiguousBytes>(_ serializedMessageBytes: Bytes) throws -> String {
        serializedMessageBytes.withUnsafeBytes { String(decoding: $0, as: UTF8.self) }
    }
}
