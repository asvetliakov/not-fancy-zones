import Foundation

/// Shared between the UI thread and the AX worker. Invalidating never waits for the worker.
public final class WorkToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    public init() {}
    public var isValid: Bool { lock.lock(); defer { lock.unlock() }; return !cancelled }
    public func cancel() { lock.lock(); cancelled = true; lock.unlock() }
}
