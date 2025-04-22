//
//  UnaryCall+Extensions.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import GRPC

extension UnaryCall {
    func handle(on queue: DispatchQueue, function: String = #function, success: @Sendable @escaping (ResponsePayload) -> Void, failure: @Sendable @escaping (GRPC.GRPCStatus) -> Void) {
        response.whenSuccessBlocking(onto: queue, success)
        response.whenFailureBlocking(onto: queue) { error in
            if let typedError = error as? GRPC.GRPCStatus {
                let message = typedError.message ?? "'no-message'"
                let code = typedError.code.description
                trace(.failure, components: [code, message], function: function)
                failure(typedError)
            } else {
                trace(.failure, components: "Failed to type GRPC response error as `GRPC.GRPCStatus`: \(error)", function: function)
                failure(.processingError)
            }
        }
    }
}
