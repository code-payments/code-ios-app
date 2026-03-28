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
    
    var stream: BidirectionalStreamingCall<Request, Response>? {
        didSet {
            if stream != nil {
                postponeTimeout()
            } else {
                cancelTimeout()
            }
        }
    }
    
    var timeoutHandler: (() -> Void)?
    
    var lastPing: Date?
    private(set) var pingTimeout: Int = 15 // seconds
    
    private var closure: (() -> Void)?
    
    private var timeoutTask: Task<Void, Error>?
    
    // MARK: - Init -
    
    init() {}
    
    init(stream: BidirectionalStreamingCall<Request, Response>) {
        self.stream = stream
    }
    
    deinit {}
    
    // MARK: - Ping -
    
    func receivedPing(updatedTimeout: Int? = nil) {
        lastPing = .now
        
        // If the server provides a timeout, 
        // we'll update our local timeout
        // accordingly.
        if let updatedTimeout {
            // Double the server-provided timeout
            let newTimeout = updatedTimeout * 2
            if pingTimeout != newTimeout {
                pingTimeout = newTimeout
            }
        }
        
        postponeTimeout()
    }
    
    func cancelTimeout() {
        timeoutTask?.cancel()
        timeoutTask = nil
    }
    
    func postponeTimeout() {
        cancelTimeout()
        
        timeoutTask = Task { [weak self] in
            guard let self else {
                return
            }
            
            guard !Task.isCancelled else {
                return
            }
            
            try await Task.delay(seconds: self.pingTimeout)
            
            if !Task.isCancelled {
                self.timeoutHandler?()
            }
        }
    }
    
    // MARK: - Health -

    /// Whether a ping was received recently enough to consider the stream alive.
    /// The existing `postponeTimeout` timer cannot be relied on here because
    /// `Task.sleep` does not fire promptly when the app resumes from suspension.
    var hasRecentPing: Bool {
        guard let lastPing else { return false }
        return Date.now.timeIntervalSince(lastPing) < TimeInterval(pingTimeout)
    }

    /// Whether the stream is likely alive based on recent ping activity.
    /// After backgrounding, the OS kills the socket but the stream object
    /// persists in memory. This catches that case by checking ping staleness.
    var isLikelyHealthy: Bool {
        stream != nil && hasRecentPing
    }

    // MARK: - Cancel -
    
    public func destroy() {
        timeoutHandler = nil
        cancel()
        release()
    }
    
    public func cancel() {
        cancelTimeout()
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
