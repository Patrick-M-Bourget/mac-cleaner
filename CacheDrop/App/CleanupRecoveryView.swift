import AppKit
import Darwin
import Observation
import CacheDropCore
import SwiftUI

@MainActor @Observable final class CleanupRecoveryModel {
    private(set) var snapshot: CleanupRecoverySnapshot?
    private(set) var error: String?
    private(set) var loaded = false
    /// What checking each interrupted batch against disk found (#309), by batch; nil until checked.
    private(set) var findings: [UUID: [CleanupRecoveryItem]]?
    /// The outcome of the last Mark as reviewed.
    private(set) var message: String?
    private(set) var markFailed = false
    private(set) var busy = false
    var requiresReview: Bool { error != nil || snapshot?.interruptedBatches.isEmpty == false }
    /// Opening Recovery is reading the journal again and checking against disk; its page shows skeleton rows meanwhile (#308).
    private(set) var reading = false
    /// Opening Recovery reads the journal again and checks each unresolved item against disk, read-only.
    func refresh() async {
        reading = true; defer { reading = false }
        loaded = false; error = nil; findings = nil; message = nil; _ = await loadOnce(); await check()
    }
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
            self.error = "CacheDrop couldn’t read its cleanup history, so it can’t tell what happened to these items. Nothing restarts by itself."
        }
        return requiresReview
    }
    private func check() async {
        guard let batches = snapshot?.interruptedBatches, !batches.isEmpty else { return }
        findings = await Self.check(batches)
    }
    private static func check(_ batches: [CleanupRecoveryBatch]) async -> [UUID: [CleanupRecoveryItem]] {
        let trashFolder = Self.trashFolder
        return await Task.detached(priority: .utility) {
            let review = CleanupRecoveryReview(trashFolder: trashFolder)
            return Dictionary(uniqueKeysWithValues: batches.map { ($0.id, review.check($0)) })
        }.value
    }
    /// The Trash an item would be in. A debug test run uses its fixture home's `.Trash`, never the user's.
    private static var trashFolder: @Sendable (URL) -> URL? {
        #if DEBUG
        if LocalStateLocation.isDisposableTest {
            let folder = CatalogCleanupModel.home.map(TrashSpace.folder)
            return { _ in folder }
        }
        #endif
        return CleanupRecoveryReview.finderTrashFolder
    }

    /// Records the findings shown, after checking again that disk still says the same; otherwise shows the new findings.
    func markReviewed() async {
        let lifecycle = AppLifecycleController.shared
        guard !busy, let shown = findings, let batches = snapshot?.interruptedBatches else { return }
        guard !lifecycle.operationInProgress, !lifecycle.maintenanceInProgress else {
            markFailed = true; message = "Wait for the current cleanup to finish."; return
        }
        busy = true; defer { busy = false }
        let fresh = await Self.check(batches)
        guard fresh.mapValues({ $0.map(\.finding) }) == shown.mapValues({ $0.map(\.finding) }) else {
            findings = fresh; markFailed = true
            message = "Something changed since the check. Review what was found now, then mark as reviewed."
            return
        }
        let trashFolder = Self.trashFolder
        do {
            try await Task.detached {
                let journal = try CleanupJournalLocation.writer()
                let review = CleanupRecoveryReview(trashFolder: trashFolder)
                try review.markReviewed(batches.flatMap { fresh[$0.id] ?? [] }, in: journal)
            }.value
            loaded = false; findings = nil
            _ = await loadOnce()
            markFailed = false
            message = "Marked as reviewed. History shows what was found."
        } catch {
            markFailed = true
            message = "Couldn’t record the review. Nothing was changed."
        }
    }
}

struct CleanupRecoveryView: View {
    @Bindable var model: CleanupRecoveryModel
    /// The back button above the title, from the page that opened this one.
    var back: BackButton? = nil
    /// Opens History, where a reviewed run shows its findings and offers Put back.
    var viewHistory: () -> Void = {}
    var body: some View {
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.xl) {
            PageHeader(title: "Review interrupted cleanup", subtitle: "CacheDrop checked where each unfinished item is now. Nothing restarts by itself.", back: back)
            if let message = model.message {
                StatusRow(text: message, symbol: model.markFailed ? "exclamationmark.triangle" : "checkmark.circle", role: model.markFailed ? .caution : .success, identifier: "recoveryMessage",
                          action: model.markFailed ? nil : StatusAction(title: "View History", identifier: "recoveryViewHistory", action: viewHistory))
            }
            if model.reading && model.findings == nil {
                // Nothing known yet: skeleton rows, never last time's answer (#308).
                SkeletonRows(.line, identifier: "recoverySkeleton")
            } else if let error = model.error {
                StatusRow(text: error, symbol: "exclamationmark.triangle", role: .failure)
                Text("Reopening CacheDrop may help. Don’t clear history or reset CacheDrop until this is reviewed.").font(.callout).foregroundStyle(.secondary)
            } else if let snapshot = model.snapshot, !snapshot.interruptedBatches.isEmpty {
                if let findings = model.findings {
                    let items = snapshot.interruptedBatches.flatMap { findings[$0.id] ?? [] }
                    ForEach(snapshot.interruptedBatches) { batch in
                        Text("Started " + (batch.records.first?.approvedAt.formatted(date: .abbreviated, time: .shortened) ?? "Unknown date")).font(CacheDropDesign.TypeStyle.section)
                        LazyVStack(alignment: .leading, spacing: CacheDropDesign.Space.lg) {
                            ForEach(findings[batch.id] ?? []) { item in
                                row(item)
                                Divider()
                            }
                        }
                    }
                    let unknown = items.filter(\.needsConfirmation).count
                    if unknown > 0 {
                        StatusRow(text: (unknown == 1 ? "1 item stays unknown." : "\(unknown) items stay unknown.") + " Check it in Finder first: marking as reviewed confirms it as it is.",
                                  symbol: "exclamationmark.circle", role: .caution)
                    }
                    Button("Mark as reviewed") { Task { await model.markReviewed() } }
                        .buttonStyle(.borderedProminent).disabled(model.busy).accessibilityIdentifier("recoveryMarkReviewed")
                } else {
                    SkeletonRows(.line, identifier: "recoverySkeleton")
                }
            } else if model.message == nil {
                EmptyState(title: "Nothing to review", detail: "No cleanup was interrupted.", symbol: "checkmark.circle", identifier: "recoveryEmpty")
            }
        }
    }

    private func row(_ item: CleanupRecoveryItem) -> some View {
        let record = item.record
        return SettingsRow(title: record.itemName ?? record.originalURL.lastPathComponent, detail: record.originalURL.path) {
            StatusRow(text: item.title + " · " + item.detail, symbol: item.needsConfirmation ? "exclamationmark.circle" : "checkmark.circle",
                      role: item.needsConfirmation ? .caution : .neutral, identifier: "recoveryState-" + record.originalURL.lastPathComponent)
            if let found = item.foundURL {
                Button("Show in Finder") { Finder.reveal([found]) }.buttonStyle(.link).help(found.path)
                    .accessibilityLabel("Show " + record.originalURL.lastPathComponent + " in Finder")
            }
            DisclosureGroup("Recorded details") {
                VStack(alignment: .leading, spacing: CacheDropDesign.Space.sm) {
                    Text(record.recoveryStateText + " · " + record.message)
                    Text("Scope: " + record.scopeURL.path)
                    Text("Action: " + record.actionTitle + (record.previewOnly == true ? " · Dry run" : "") + " · Policy \(record.policyVersion)")
                    Text("Resource identity at approval: " + record.resourceID)
                }.font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
    }
}
