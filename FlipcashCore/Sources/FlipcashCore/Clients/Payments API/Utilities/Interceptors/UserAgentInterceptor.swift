//
//  UserAgentInterceptor.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import GRPC
import NIO
import NIOHPACK

/// Attaches a `User-Agent` header to every outgoing gRPC request.
///
/// The product name is derived from the RPC method path so that each
/// backend receives the user agent it expects:
///   - OCP server  (`/ocp.*`)       → `OpenCodeProtocol/iOS/{version}`
///   - Flipcash server              → `Flipcash/iOS/{version}`
class UserAgentInterceptor<Request, Response>: ClientInterceptor<Request, Response>, @unchecked Sendable {
    override func send(_ part: GRPCClientRequestPart<Request>, promise: EventLoopPromise<Void>?, context: ClientInterceptorContext<Request, Response>) {
        var modifiedPart = part
        switch modifiedPart {
        case .metadata(var headers):
            let product = Self.productName(for: context.path)
            headers.add(.userAgent, value: "\(product)/iOS/\(AppMeta.version)")
            modifiedPart = .metadata(headers)
        default:
            break
        }
        context.send(modifiedPart, promise: promise)
    }

    /// Returns the product name for the `User-Agent` header based on
    /// the gRPC method path (e.g. `/ocp.transaction.v1.Transaction/SubmitIntent`).
    private static func productName(for path: String) -> String {
        if path.hasPrefix("/ocp.") {
            return "OpenCodeProtocol"
        }
        return "Flipcash"
    }
}

// MARK: - App -

public enum AppMeta {
    public static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String
    }
    
    public static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as! String
    }
}

// MARK: - Headers -

private enum Headers: String {
    case userAgent = "User-Agent"
}

// MARK: - HPACKHeaders -

private extension HPACKHeaders {
    mutating func add(_ header: Headers, value: String) {
        add(name: header.rawValue, value: value)
    }
}
