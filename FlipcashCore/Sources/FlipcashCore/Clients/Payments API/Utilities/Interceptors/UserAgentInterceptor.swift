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

class UserAgentInterceptor<Request, Response>: ClientInterceptor<Request, Response>, @unchecked Sendable {
    override func send(_ part: GRPCClientRequestPart<Request>, promise: EventLoopPromise<Void>?, context: ClientInterceptorContext<Request, Response>) {
        var modifiedPart = part
        switch modifiedPart {
        case .metadata(var headers):
            headers.add(.userAgent, value: "Flipcash/iOS/\(AppMeta.version)")
            modifiedPart = .metadata(headers)
        default:
            break
        }
        context.send(modifiedPart, promise: promise)
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
