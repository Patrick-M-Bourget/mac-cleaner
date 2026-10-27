import Foundation
import Observation
import StillCore
import SwiftUI

/// Whether the first-run welcome is showing (#158). Decided once at launch, right after Still's state is copied;
/// the Help menu opens it again.
@MainActor @Observable final class WelcomeModel {
    static let shared = WelcomeModel()
    var isShowing = false

    /// Called from `StillApp.init`, before anything writes CacheDrop's state.
    func decideAtLaunch(migration: LegacyStillMigration.Outcome?, stateExisted: Bool) {
        #if DEBUG
        // Disposable UI test runs treat the welcome as seen, so it never covers a journey, unless a test asks for it.
        // Then "seen" is a file in the test's own state root, never the user's defaults.
        if LocalStateLocation.isDisposableTest {
            isShowing = ProcessInfo.processInfo.environment["STILL_TEST_SHOW_WELCOME"] == "1" && !Self.testMarkerExists
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

/// The calm three-step welcome (Decision 25): few words, one primary action per step, Skip on every step.
struct FirstRunWelcomeView: View {
    let model: WelcomeModel
    let startScan: () -> Void
    @State private var step = 0
    @State private var access = FullDiskAccessModel()

    var body: some View {
        VStack(alignment: .leading, spacing: StillDesign.Space.lg) {
            switch step {
            case 0:
                PageHeader(title: "Welcome to CacheDrop", subtitle: "CacheDrop finds space you can safely get back, and cleans only what you choose.")
                StatusRow(text: "It never touches your files without asking, your logins, or Photos, Mail and Messages data.",
                          symbol: "hand.raised", identifier: "welcomeNeverTouches")
            case 1:
                PageHeader(title: FullDiskAccessGuide.title, subtitle: FullDiskAccessGuide.summary)
                FullDiskAccessLink(title: "Learn more", model: access, symbol: nil)
            default:
                PageHeader(title: "Start your first scan", subtitle: "Scans only read. Nothing is cleaned until you review it.")
            }
            Divider()
            HStack {
                Text("\(step + 1) of 3").font(StillDesign.TypeStyle.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Skip") { model.finish() }.accessibilityIdentifier("welcomeSkip")
                if step < 2 {
                    Button("Continue") { step += 1 }.keyboardShortcut(.defaultAction).accessibilityIdentifier("welcomeContinue")
                } else {
                    Button("Start scan") { model.finish(); startScan() }.keyboardShortcut(.defaultAction).accessibilityIdentifier("welcomeStartScan")
                }
            }
        }
        .padding(StillDesign.Space.xl).frame(width: StillDesign.Size.sheetNarrow).background(StillDesign.reading)
    }
}
