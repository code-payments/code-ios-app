//
//  UserAgentClientInterceptorTests.swift
//  FlipcashCoreTests
//

import Foundation
import Testing
import GRPCCore
@testable import FlipcashCore

@Suite("UserAgentClientInterceptor — per-backend user-agent injection")
struct UserAgentClientInterceptorTests {

    private func interceptedUserAgent(forService service: String) async throws -> [String] {
        let interceptor = UserAgentClientInterceptor()
        let request = StreamingClientRequest<String>(metadata: [:]) { _ in }
        let context = ClientContext(
            descriptor: MethodDescriptor(fullyQualifiedService: service, method: "Test"),
            remotePeer: "test",
            localPeer: "test"
        )

        var captured: Metadata?
        _ = try await interceptor.intercept(request: request, context: context) { request, _ in
            captured = request.metadata
            return StreamingClientResponse<String>(of: String.self, error: RPCError(code: .cancelled, message: ""))
        }

        let metadata = try #require(captured)
        return Array(metadata[stringValues: "user-agent"])
    }

    @Test("OCP services get the OpenCodeProtocol user agent, lowercase key, exactly once")
    func ocpServiceUserAgent() async throws {
        let values = try await interceptedUserAgent(forService: "ocp.currency.v1.Currency")
        #expect(values.count == 1)
        #expect(values.first == "OpenCodeProtocol/iOS/\(AppMeta.version)")
    }

    @Test("Flipcash services get the Flipcash user agent, lowercase key, exactly once")
    func flipcashServiceUserAgent() async throws {
        let values = try await interceptedUserAgent(forService: "flipcash.account.v1.Account")
        #expect(values.count == 1)
        #expect(values.first == "Flipcash/iOS/\(AppMeta.version)")
    }
}
