import AppKit
import Foundation
import Observation
import CacheDropCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor @Observable final class DiagnosticsModel {
    private(set) var export: DiagnosticsExport?
    private(set) var isSaving = false
    private(set) var unavailable = false
    private var stateProtectionAvailable = false
    func review(selection: SessionPlan, inspection: FolderInspection, recovery: CleanupRecoveryModel) {
        guard !isSaving else { return }
        var codes = Set<DiagnosticsCode>()
        let scan: DiagnosticsScanStatus = inspection.isScanning ? .scanning : inspection.result.map { $0.isComplete ? .complete : .partial } ?? .notInspected
        if scan == .partial { codes.insert(.scanIncomplete) }
        let result = selection.catalog.result
        let unknown = selection.requiresRecoveryReview
        let cleanup: DiagnosticsCleanupStatus = selection.workspaceRunning ? .running : unknown ? .unknown : result.map { $0.records.contains { $0.state != .succeeded && !$0.wasPreviewed } ? .partial : .complete } ?? .idle
        if unknown { codes.insert(.outcomeUnknown) }
        if recovery.error != nil { codes.insert(.journalUnavailable) }
        let recoveryStatus: DiagnosticsRecoveryStatus = recovery.error != nil ? .unavailable : !recovery.loaded ? .notLoaded : recovery.requiresReview ? .requiresReview : .clear
        #if arch(arm64)
        let architecture = DiagnosticsArchitecture.arm64
        #elseif arch(x86_64)
        let architecture = DiagnosticsArchitecture.x86_64
        #else
        let architecture = DiagnosticsArchitecture.unknown
        #endif
        do {
            let snapshot = try DiagnosticsReview(appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                                                 build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
                                                 system: ProcessInfo.processInfo.operatingSystemVersion, architecture: architecture,
                                                 scopeCount: selection.scans.count, observedCount: inspection.result?.observations.count ?? 0,
                                                 selectedCount: selection.workspaceSelectedCount, scan: scan, cleanup: cleanup, recovery: recoveryStatus, errors: codes)
            let protectedRoot = try? LocalStateLocation.root(create: false)
            stateProtectionAvailable = protectedRoot != nil
            export = DiagnosticsExport(review: snapshot, protectedDirectory: protectedRoot); unavailable = false
        } catch { unavailable = true }
    }
    func save() async {
        guard !isSaving, let reviewed = export else { return }
        isSaving = true
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "CacheDrop-diagnostics.json"
        panel.message = "Save exactly the redacted payload you reviewed. Nothing is uploaded."
        let destination = panel.runModal() == .OK ? panel.url : nil
        let saved = await Task.detached(priority: .utility) { var copy = reviewed; copy.save(to: destination); return copy }.value
        export = saved; isSaving = false
    }
    var status: String {
        if unavailable { return "Diagnostics could not be prepared. Your existing preview is retained." }
        if isSaving { return "Saving the reviewed payload…" }
        switch export?.outcome {
        case .saved: return "Saved the exact reviewed payload locally. Nothing was uploaded."
        case .cancelled: return "Save cancelled. The reviewed payload is unchanged."
        case .failed where !stateProtectionAvailable: return "Could not verify local state protection. The reviewed payload is unchanged; reopen CacheDrop before saving."
        case .failed: return "Could not save there. The reviewed payload is unchanged; choose a destination again."
        case .notSaved, nil: return "Review the exact payload before choosing Save. Nothing is uploaded."
        }
    }
}

struct DiagnosticsView: View {
    @Bindable var model: DiagnosticsModel
    var body: some View {
        VStack(alignment: .leading, spacing: CacheDropDesign.Space.xl) {
            PageHeader(title: "Review diagnostics", subtitle: "A local snapshot with only allowlisted versions, counts, status and error codes.")
            SettingsRow(title: "Included", detail: "App/build and system versions, CPU architecture, session scope count, latest scan entry count, selected count and fixed status/error codes.") { EmptyView() }
            SettingsRow(title: "Excluded", detail: "File paths and names, resource/batch/account identities, raw errors, file or browser contents, credentials, cloud metadata and recovery records.") { EmptyView() }
            if let export = model.export {
                SettingsRow(title: "Exact payload", detail: "This preview stays frozen while you review or save it. It is not a live log.") {
                    SummarySurface {
                        Text(export.review.text).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier("diagnosticsPayload")
                    }
                }
            }
            StatusRow(text: model.status, symbol: "doc.text", role: model.export?.outcome == .failed || model.unavailable ? .caution : .neutral, identifier: "diagnosticsStatus")
            Text("Saving diagnostics does not clear history, resolve interrupted work or grant permission to retry cleanup.").font(CacheDropDesign.TypeStyle.caption).foregroundStyle(.secondary)
        }
    }
}
