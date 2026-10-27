import Foundation
import Observation

public enum AppearanceChoice: String, CaseIterable, Sendable {
    case automatic = "Automatic", light = "Light", dark = "Dark"
}

/// The app's local appearance preference only; no cleanup or OS setting authority.
@MainActor public protocol AppearancePreferenceStore: AnyObject {
    func read() throws -> String?
    func write(_ value: String) throws
    func remove() throws
}

@MainActor @Observable public final class AppearancePreferenceController {
    public enum Notice: Sendable { case invalidSavedValue, unreadable, saveFailed }
    public private(set) var choice = AppearanceChoice.automatic
    public private(set) var notice: Notice?
    @ObservationIgnored private let store: any AppearancePreferenceStore
    public init(store: any AppearancePreferenceStore) {
        self.store = store
        do {
            if let value = try store.read() {
                if let saved = AppearanceChoice(rawValue: value) { choice = saved }
                else { notice = .invalidSavedValue }
            }
        } catch { notice = .unreadable }
    }
    public func reset() throws {
        try store.remove()
        choice = .automatic; notice = nil
    }
    public func retrySaving() { choose(choice) }
    public func choose(_ choice: AppearanceChoice) {
        self.choice = choice
        do { try store.write(choice.rawValue); notice = nil }
        catch { notice = .saveFailed }
    }
}
