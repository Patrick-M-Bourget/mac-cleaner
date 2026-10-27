import AppKit
import Darwin
import Observation
import CacheDropCore
import SwiftUI

@MainActor @Observable final class CleanupRecoveryModel {
    private(set) var snapshot: CleanupRecoverySnapshot?
    private(set) var error: String?
    private(set) var loaded = false
    var requiresReview: Bool { error != nil || snapshot?.interruptedBatches.isEmpty == false }
    func refresh() async { loaded = false; error = nil; _ = await loadOnce() }
    /// Runs once per process; opening another window is not a second recovery session.
    func loadOnce() async -> Bool {
        guard !loaded else { return false }
        loaded = true
        do {
            snapshot = try await Task.detached(priority: .utility) {
                guard let reader = try CleanupJournalLocation.existingReader() else { return nil as CleanupRecoverySnapshot? }
                return try CleanupRecoverySnapshot(journal: reader)
            }.value
        } catch {
            self.error = "The local cleanup journal could not be read. Outcomes cannot be confirmed. Nothing will resume automatically."
        }
        return requiresReview
    }
}

struct CleanupRecoveryView: View {
    @Bindable var model: CleanupRecoveryModel
    var body: some View {
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.xl) {
            PageHeader(title: "Review interrupted cleanup", subtitle: "Recorded facts from a previous session. Nothing will resume or repeat automatically.")
            if let error = model.error {
                StatusRow(text: error, symbol: "exclamationmark.triangle", role: .failure)
                Text("Keep the journal for recovery. Reopening CacheDrop may help; do not clear or reset unresolved records.").font(.callout).foregroundStyle(.secondary)
            } else if let snapshot = model.snapshot, !snapshot.interruptedBatches.isEmpty {
                SummarySurface {
                    VStack(alignment: .leading, spacing: CacheDropDesign.Space.sm) {
                        Text("\(snapshot.unresolvedCount) unresolved · \(snapshot.pendingCount) not started").font(CacheDropDesign.TypeStyle.section)
                        Text("\(snapshot.knownResultCount) recorded results in these batches").font(.callout).foregroundStyle(.secondary)
                    }
                }
                StatusRow(text: snapshot.unresolvedNotice, symbol: "info.circle", role: .caution)
                ForEach(snapshot.interruptedBatches) { batch in
                    Text("Approved " + (batch.records.first?.approvedAt.formatted(date: .abbreviated, time: .shortened) ?? "Unknown date")).font(CacheDropDesign.TypeStyle.section)
                    LazyVStack(alignment: .leading, spacing: CacheDropDesign.Space.lg) {
                        ForEach(batch.records) { record in
                            SettingsRow(title: record.originalURL.lastPathComponent, detail: record.originalURL.path) {
                                StatusRow(text: record.recoveryStateText, symbol: record.state == .succeeded ? "checkmark.circle" : "info.circle", role: record.state == .succeeded ? .success : .neutral)
                                    .accessibilityIdentifier("recoveryState-" + record.originalURL.lastPathComponent)
                                Text(record.message).font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
                                if let returned = record.trashURL {
                                    Text("Recorded resulting location: " + returned.path).font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary).textSelection(.enabled)
                                    Text("Location has not been verified in this session.").font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
                                    if record.state == .succeeded, returned.isFileURL {
                                        Button("Reveal recorded location") { Finder.reveal([returned]) }
                                            .accessibilityLabel("Reveal recorded location for " + record.originalURL.lastPathComponent)
                                    }
                                }
                                DisclosureGroup("Recorded details") {
                                    VStack(alignment: .leading, spacing: CacheDropDesign.Space.sm) {
                                        Text("Scope: " + record.scopeURL.path)
                                        Text("Action: " + record.actionTitle + (record.previewOnly == true ? " · Dry run" : "") + " · Policy \(record.policyVersion)")
                                        Text("Resource identity at approval: " + record.resourceID)
                                    }.font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary).textSelection(.enabled)
                                }
                            }
                            Divider()
                        }
                    }
                }
                StatusRow(text: "For another cleanup, start a new plan from a fresh scan. These records do not restore a plan or grant file access.", symbol: "arrow.clockwise")
            } else {
                EmptyState(title: "No interrupted cleanup recorded", detail: "A new cleanup still requires a manual scan and approval.", symbol: "checkmark.circle")
            }
        }
    }
}
