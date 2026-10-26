import Foundation

/// Detects Full Disk Access. The app uses `FullDiskAccessProbe`; tests and previews pass a fake.
public protocol FullDiskAccessDetecting: Sendable {
    func status() -> FullDiskAccessStatus
}
