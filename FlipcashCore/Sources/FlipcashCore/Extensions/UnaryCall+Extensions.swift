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
            if let typedError = error as? GRPC.GRPCStatus {
                let message = typedError.message ?? "'no-message'"
                let code = typedError.code.description
                logger.error("gRPC call failed", metadata: [
                    "function": "\(function)",
                    "code": "\(code)",
                    "message": "\(message)"
                ])
                failure(typedError)
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
