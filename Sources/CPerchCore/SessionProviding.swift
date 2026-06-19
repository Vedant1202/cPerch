import Foundation

/// What CPerchApp consumes. CPerchCore implements it — `StubSessionStore` now (P0),
/// the real `SessionStore` in Phase 2. Freezing this lets the UI (P1-D) be built in
/// parallel against the stub. (FROZEN v0 CONTRACT.)
public protocol SessionProviding: AnyObject {
    /// Current sessions, sorted needs-you-first by the implementation.
    var sessions: [Session] { get }
    /// Aggregate state for the menu-bar dot.
    var aggregate: AggregateState { get }
    /// Invoked on the main queue whenever `sessions` changes.
    var onChange: (() -> Void)? { get set }
    func start()
    func stop()
    /// Change how long concluded sessions are retained (seconds) and re-evaluate. Optional:
    /// the default is a no-op so non-configurable stores (e.g. the stub) need not implement it.
    func setRetentionWindow(_ seconds: TimeInterval)
}

public extension SessionProviding {
    /// Default: derive the dot state from the current sessions.
    var aggregate: AggregateState { AggregateState(sessions: sessions) }
    /// Default no-op — only the real `SessionStore` honors a runtime retention change.
    func setRetentionWindow(_ seconds: TimeInterval) {}
}
