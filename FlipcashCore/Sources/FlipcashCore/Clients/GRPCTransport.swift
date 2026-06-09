//
//  GRPCTransport.swift
//  FlipcashCore
//

import GRPCCore
import GRPCNIOTransportHTTP2

/// The app's gRPC v2 client transport type (Network.framework on iOS).
public typealias AppTransport = HTTP2ClientTransport.TransportServices

extension CallOptions {
    /// Unary RPCs get a 15s deadline (ported from the v1 `CallOptions.default`),
    /// so they fail fast on a dead connection instead of waiting for the OS TCP
    /// timeout. Streaming RPCs deliberately use `.defaults` (no deadline) so
    /// long-lived streams aren't killed at the 15s mark.
    static var unaryDefault: CallOptions {
        var options = CallOptions.defaults
        options.timeout = .seconds(15)
        return options
    }
}

/// Builds the gRPC v2 client transport. iOS uses `TransportServices`
/// (Network.framework) so the connection respects the system network stack,
/// VPN, and proxy — matching what the v1 `ClientConnection` used under the hood.
enum GRPCTransport {

    /// Keepalive ported from the v1 connection (30s interval / 10s timeout,
    /// permitted without active calls) so long-lived bidirectional streams
    /// survive idle periods. TLS uses the system trust store.
    static func makeTransportServices(host: String, port: Int) throws -> HTTP2ClientTransport.TransportServices {
        var config = HTTP2ClientTransport.TransportServices.Config.defaults
        config.connection.keepalive = .init(
            time: .seconds(30),
            timeout: .seconds(10),
            allowWithoutCalls: true
        )
        return try HTTP2ClientTransport.TransportServices(
            target: .dns(host: host, port: port),
            transportSecurity: .tls,
            config: config
        )
    }
}
