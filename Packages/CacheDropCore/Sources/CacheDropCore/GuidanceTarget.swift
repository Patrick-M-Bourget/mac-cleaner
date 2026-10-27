import Foundation

/// What "Open …" opens for a finding.
public enum GuidanceTarget: Sendable, Equatable {
    case folder(URL), app(bundleID: String), url(URL)
}
