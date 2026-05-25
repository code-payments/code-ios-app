//
//  UnaryCall+Extensions.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import GRPC

private let logger = Logger(label: "flipcash.grpc")

extension UnaryCall {
    func handle(on queue: DispatchQueue, function: String = #function, success: @Sendable @escaping (ResponsePayload) -> Void, failure: @Sendable @escaping (GRPC.GRPCStatus) -> Void) {
        response.whenSuccessBlocking(onto: queue, success)
        response.whenFailureBlocking(onto: queue) { error in
            // Route through GRPCStatusTransformable when available so NIO and
            // gRPC transport errors carry the correct code (timeouts →
            // .deadlineExceeded, closed channels → .unavailable, etc.).
            // GRPCStatus itself conforms and returns self, so typed-status
            // errors flow through the same path. Only truly unrelated error
            // types fall back to .processingError.
            if let transformable = error as? GRPCStatusTransformable {
                let status = transformable.makeGRPCStatus()
                logger.error("gRPC call failed", metadata: [
                    "function": "\(function)",
                    "code": "\(status.code.description)",
                    "message": "\(status.message ?? "'no-message'")"
                ])
                failure(status)
            } else {
                logger.error("gRPC call failed with unexpected error type", metadata: [
                    "function": "\(function)",
                    "error": "\(error)"
                ])
                failure(.processingError)
            }
        }
    }
}
