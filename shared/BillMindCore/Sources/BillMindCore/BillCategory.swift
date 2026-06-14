import Foundation

/// The canonical expense category. Lives in the shared core so the server's
/// `BillValidator` and both clients agree on one set of raw values — the
/// validator's `knownCategoryRaws` are exactly `BillCategory.allCases` raw values.
///
/// Foundation-only by design: presentation concerns (SwiftUI `Color`, asset
/// names) belong in the client and are layered on via extensions there.
enum BillCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case food
    case transport
    case accommodation
    case shopping
    case entertainment
    case utilities
    case medical
    case education
    case subscription
    case misc

    var id: String { rawValue }

    var displayName: String { englishName }

    var englishName: String {
        switch self {
        case .food: return "Food"
        case .transport: return "Transport"
        case .accommodation: return "Hotel"
        case .shopping: return "Shopping"
        case .entertainment: return "Fun"
        case .utilities: return "Utilities"
        case .medical: return "Medical"
        case .education: return "Education"
        case .subscription: return "Subscription"
        case .misc: return "Other"
        }
    }

    /// The SF Symbol name a client can use; kept here as a plain string so the
    /// core stays platform-independent (no `Image`/`UIImage` dependency).
    var sfSymbol: String {
        switch self {
        case .food: return "fork.knife"
        case .transport: return "car.fill"
        case .accommodation: return "bed.double.fill"
        case .shopping: return "bag.fill"
        case .entertainment: return "sparkles"
        case .utilities: return "bolt.fill"
        case .medical: return "cross.case.fill"
        case .education: return "book.fill"
        case .subscription: return "arrow.triangle.2.circlepath"
        case .misc: return "square.grid.2x2.fill"
        }
    }
}
