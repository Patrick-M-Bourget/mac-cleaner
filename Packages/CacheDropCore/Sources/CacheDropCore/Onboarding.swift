import Foundation

/// Onboarding's first scan (#783, #784; Decision 174): the categories its badges show.
public enum Onboarding {
    /// The categories Welcome shows as badges, in two rows of five.
    public static let categories: [CatalogCategory] = [.developer, .browser, .system, .downloads, .audio,
                                                       .photoVideo, .models, .updaters, .logs, .leftovers]
}
