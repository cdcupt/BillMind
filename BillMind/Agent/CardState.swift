import Foundation

/// Lifecycle of a single bill card inside a recording session.
///
/// The agent advances a card through these stages. Two invariants matter:
/// `recorded` is the only state in which the host writes a `BillRecord`, and
/// `failed` is a first-class, retryable state — extraction errors are never
/// swallowed into a silent partial card.
enum CardState: String, Sendable, Equatable, CaseIterable {
    /// Input accepted (consent + journal gates passed, image downscaled).
    case intake
    /// A single structured-output extraction call is in flight.
    case extracting
    /// Deterministic, AI-free validation is running.
    case validating
    /// One or more clarifying questions are open, awaiting chip answers.
    case clarifying
    /// Complete enough to confirm; awaiting the user's Save.
    case review
    /// Confirmed and persisted — the terminal success state.
    case recorded
    /// Extraction threw (timeout / non-JSON / HTTP error). Retryable.
    case failed
    /// Dropped by the user; never persisted.
    case discarded

    /// Whether a card in this state may transition into `recorded`.
    var isConfirmable: Bool { self == .review }

    /// Terminal states the session no longer acts on.
    var isTerminal: Bool { self == .recorded || self == .discarded }
}
