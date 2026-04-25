//
//  StreamReference.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import Combine
import GRPC

class StreamReference<Request, Response>: Cancellable {
    
    var stream: ServerStreamingCall<Request, Response>?
    
    init() {}
    
    init(stream: ServerStreamingCall<Request, Response>) {
        self.stream = stream
    }
    
    deinit {}
    
    func cancel() {
        stream?.cancel(promise: nil)
    }
}

public class BidirectionalStreamReference<Request, Response>: Cancellable, @unchecked Sendable {

    var stream: BidirectionalStreamingCall<Request, Response>?

    private var closure: (() -> Void)?

    // MARK: - Init -

    init() {}

    init(stream: BidirectionalStreamingCall<Request, Response>) {
        self.stream = stream
    }

    deinit {}

    // MARK: - Cancel -

    public func destroy() {
        cancel()
        release()
    }

    public func cancel() {
        stream?.cancel(promise: nil)
    }

    // MARK: - Memory -

    func retain() {
        closure = { _ = self }
    }

    func release() {
        closure = nil
    }
}
