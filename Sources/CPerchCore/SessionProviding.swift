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
}

public extension SessionProviding {
    /// Default: derive the dot state from the current sessions.
    var aggregate: AggregateState { AggregateState(sessions: sessions) }
}
