public protocol LogMiddleware: Sendable {
    /// Process a log entry before it reaches handlers.
    /// Return `false` to drop the entry entirely.
    func process(_ entry: inout LogEntry) -> Bool
}
