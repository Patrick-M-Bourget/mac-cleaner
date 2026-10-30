import Foundation
import Observation
import CacheDropCore
import SwiftUI

/// Whether the first-run welcome is showing (#158). Decided once at launch, right after Still's state is copied;
/// the Help menu opens it again.
@MainActor @Observable final class WelcomeModel {
    static let shared = WelcomeModel()
    var isShowing = false

    /// Called from `CacheDropApp.init`, before anything writes CacheDrop's state.
    func decideAtLaunch(migration: LegacyStillMigration.Outcome?, stateExisted: Bool) {
        #if DEBUG
        // Disposable UI test runs treat the welcome as seen, so it never covers a journey, unless a test asks for it.
        // Then "seen" is a file in the test's own state root, never the user's defaults.
        if LocalStateLocation.isDisposableTest {
            isShowing = ProcessInfo.processInfo.environment["CACHEDROP_TEST_SHOW_WELCOME"] == "1" && !Self.testMarkerExists
            return
        }
        #endif
        isShowing = FirstRunWelcome(preferences: UserDefaults.standard).shouldShow(migration: migration, stateExisted: stateExisted)
    }

    /// Skip and the last step both end it for good.
    func finish() {
        isShowing = false
        #if DEBUG
        if LocalStateLocation.isDisposableTest {
            if let marker = Self.testMarker { try? Data().write(to: marker) }
            return
        }
        #endif
        FirstRunWelcome(preferences: UserDefaults.standard).markSeen()
    }

    #if DEBUG
    private static var testMarker: URL? { try? LocalStateLocation.root(create: false).appendingPathComponent("welcome-seen") }
    private static var testMarkerExists: Bool { testMarker.map { FileManager.default.fileExists(atPath: $0.path) } ?? false }
    #endif
}

/// The calm three-step welcome (Decision 25): few words, one primary action per step, Skip on every step. The launch scan
/// runs behind it from the start, so the last step shows its progress and ends with Done (#310).
struct FirstRunWelcomeView: View {
    let model: WelcomeModel
    let catalog: CatalogCleanupModel
    @State private var step = 0
    @State private var access = FullDiskAccessModel()

    var body: some View {
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.lg) {
            switch step {
            case 0:
                PageHeader(title: "Welcome to CacheDrop", subtitle: "CacheDrop finds space you can safely get back, and cleans only what you choose.")
                StatusRow(text: "It never touches your files without asking, your logins, or Photos, Mail and Messages data.",
                          symbol: "hand.raised", identifier: "welcomeNeverTouches")
            case 1:
                PageHeader(title: FullDiskAccessGuide.title, subtitle: FullDiskAccessGuide.summary)
                FullDiskAccessLink(title: "Learn more", model: access)
            default:
                PageHeader(title: catalog.isScanning ? "Your first scan is running" : "Your first scan is done",
                           subtitle: "Scans only read. Nothing is cleaned until you review it.")
                if catalog.isScanning {
                    ProgressView(catalog.scanProgressText).controlSize(.small).accessibilityIdentifier("welcomeScanProgress")
                }
            }
            Divider()
            SheetFooter {
                Text("\(step + 1) of 3").font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
            } actions: {
                Button("Skip") { model.finish() }.accessibilityIdentifier("welcomeSkip")
                if step < 2 {
                    Button("Continue") { step += 1 }.keyboardShortcut(.defaultAction).accessibilityIdentifier("welcomeContinue")
                } else {
                    Button("Done") { model.finish() }.keyboardShortcut(.defaultAction).accessibilityIdentifier("welcomeDone")
                }
            }
        }
        .padding(CacheDropDesign.Space.xl).frame(width: CacheDropDesign.Size.sheetNarrow).background(CacheDropDesign.reading).cacheDropButtonRule()
    }
}
