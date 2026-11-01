import Foundation

/// Decimal sizes shared by every page and report. Unknown stays distinct from zero.
public enum SizeFormatter {
    /// Partial measurements are lower bounds; estimates and upper bounds keep one qualifier, never two.
    public static func text(_ value: Int64?, complete: Bool = true, upperBound: Bool = false, estimate: Bool = false) -> String {
        guard let value else { return "Unknown" }
        let size: SizeEstimate = !complete ? (value > 0 ? .atLeast(value) : .unknown) : estimate ? .about(value) : .measured(value)
        return text(size, upperBound: upperBound)
    }

    public static func text(_ estimate: SizeEstimate, upperBound: Bool = false) -> String {
        switch estimate {
        // Nothing to free is never hedged (#568).
        case .measured(let value): (upperBound && value > 0 ? "Up to " : "") + bytes(value)
        case .about(let value): "About " + bytes(value)
        case .atLeast(let value): value > 0 ? "At least " + bytes(value) : "Unknown"
        case .unknown: "Unknown"
        }
    }

    private static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .decimal)
    }
}

extension SizeEstimate {
    public var text: String { SizeFormatter.text(self) }
    /// Copies sharing disk blocks are an upper bound; estimated and incomplete sizes retain their own qualifier.
    public func text(upperBound: Bool) -> String { SizeFormatter.text(self, upperBound: upperBound) }
}
