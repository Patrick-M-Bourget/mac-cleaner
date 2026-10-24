public enum SafariCapability {
    public enum Access: Sendable { case granted, denied, unknown }
    public enum Grouping: Sendable { case profile, shared, unknown }
    public struct Evidence: Sendable {
        public var safariVersion: String
        public var osVersion: String
        public var access: Access
        public var grouping: Grouping
        public var ownerInactive: Bool?
        public init(safariVersion: String, osVersion: String, access: Access, grouping: Grouping, ownerInactive: Bool?) {
            self.safariVersion = safariVersion; self.osVersion = osVersion; self.access = access
            self.grouping = grouping; self.ownerInactive = ownerInactive
        }
    }
    public struct Result: Equatable, Sendable {
        public let canMutate: Bool
        public let reasons: [String]
        public let groupLabel: String
    }
    public static func assess(_ evidence: Evidence) -> Result {
        Result(canMutate: false, reasons: (evidence.access == .granted ? [] : ["Access unavailable"]) + (evidence.ownerInactive == true ? [] : ["Safari or helper may be writing"]) + ["No validated Safari asset-only mapping", "Exclusive Safari/helper ownership unproven"], groupLabel: "Safari cache boundary unknown")
    }
}
