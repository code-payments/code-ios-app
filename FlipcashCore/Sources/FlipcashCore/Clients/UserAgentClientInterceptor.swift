//
//  UserAgentClientInterceptor.swift
//  FlipcashCore
//

import GRPCCore

/// Attaches a `user-agent` header to every outgoing gRPC request (v2 interceptor,
/// registered on the `GRPCClient`). The product name is derived from the method's
/// service so each backend receives the user agent it expects:
///   - OCP server  (`ocp.*`) → `OpenCodeProtocol/iOS/{version}`
///   - Flipcash server        → `Flipcash/iOS/{version}`
///
/// v2 enforces lowercase metadata keys, so the header is `user-agent`.
struct UserAgentClientInterceptor: ClientInterceptor {
    func intercept<Input: Sendable, Output: Sendable>(
        request: StreamingClientRequest<Input>,
        context: ClientContext,
        next: (StreamingClientRequest<Input>, ClientContext) async throws -> StreamingClientResponse<Output>
    ) async throws -> StreamingClientResponse<Output> {
        var request = request
        let product = context.descriptor.service.fullyQualifiedService.hasPrefix("ocp.")
            ? "OpenCodeProtocol"
            : "Flipcash"
        request.metadata.replaceOrAddString("\(product)/iOS/\(AppMeta.version)", forKey: "user-agent")
        return try await next(request, context)
    }
}
