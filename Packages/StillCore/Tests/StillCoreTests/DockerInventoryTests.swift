import Foundation
import Testing
@testable import StillCore

@Test func dockerFixtureKeepsPersistentVolumesAndDaemonEstimatesDistinct() throws {
    let report = try DockerInventory.parseFixture(version: "fixture-only-1", output: "{\"Type\":\"Local Volumes\",\"TotalCount\":\"2\",\"Active\":\"1\",\"Size\":\"12GB\",\"Reclaimable\":\"6GB (50%)\"}\n")
    #expect(report.categories.first?.persistentData == true)
    #expect(report.categories.first?.daemonSize == "12GB")
    #expect(report.hostAllocatedBytes == nil)
    #expect(!report.runtimeQualified)
}

@Test func unknownDockerLayoutAndVersionDoNotBecomeRecognizedInventory() {
    #expect(throws: (any Error).self) { try DockerInventory.parseFixture(version: "999.0", output: "{}") }
    #expect(throws: (any Error).self) { try DockerInventory.parseFixture(version: "fixture-only-1", output: "{\"Type\":\"Mystery\",\"TotalCount\":\"1\",\"Active\":\"0\",\"Size\":\"1GB\",\"Reclaimable\":\"1GB\"}") }
}

@Test func unavailableDaemonMetricRemainsUnknown() throws {
    let report = try DockerInventory.parseFixture(version: "fixture-only-1", output: "{\"Type\":\"Build Cache\",\"TotalCount\":\"0\",\"Active\":\"0\",\"Size\":\"N/A\",\"Reclaimable\":\"N/A\"}")
    #expect(report.categories.first?.daemonSize == nil)
    #expect(report.categories.first?.daemonReclaimable == nil)
}

@Test func sparseDiskImageLengthIsNotInferredVirtualCapacity() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillDockerProbe-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("disposable.raw")
    try Data("disposable".utf8).write(to: file)
    let handle = try FileHandle(forWritingTo: file)
    try handle.truncate(atOffset: 64 * 1024 * 1024)
    try handle.close()
    let before = try file.resourceValues(forKeys: [.contentModificationDateKey])
    let measurement = try DockerDiskImage.readSelected(file)
    #expect(measurement.logicalBytes == 67_108_864)
    #expect(measurement.virtualCapacityBytes == nil)
    #expect(!measurement.ownershipVerified)
    #expect(try file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate == before.contentModificationDate)
}

@Test func disposableDockerHelperAcceptsOnlyReadOnlyCommandsAndPreservesVolumeSentinel() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillDockerProbe-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    let sentinel = root.appendingPathComponent("persistent-volume-data")
    try Data("protected-data".utf8).write(to: sentinel)
    let tool = root.appendingPathComponent("docker")
    let script = """
    #!/bin/sh
    if test "$#" = 1 && test "$1" = --version; then
      printf 'Docker version fixture-only-1\\n'
    elif test "$#" = 6 && test "$1" = --host && test "$2" = "unix://${0%/*}/daemon.sock" && test "$3" = system && test "$4" = df && test "$5" = --format && test "$6" = json; then
      printf '%s\\n' '{"Type":"Local Volumes","TotalCount":"1","Active":"1","Size":"12GB","Reclaimable":"0B (0%)"}'
    else
      exit 7
    fi
    """
    try Data(script.utf8).write(to: tool)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: tool.path)
    let inventory = try DockerInspector.inspectFixture(executable: tool)
    #expect(inventory.categories.first?.persistentData == true)
    #expect(!inventory.runtimeQualified)
    #expect(try Data(contentsOf: sentinel) == Data("protected-data".utf8))
}

@Test func selectedDockerRunsNothingWithoutAnExplicitLocalSocket() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillDockerProbe-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    let executable = root.appendingPathComponent("docker")
    try Data("#!/bin/sh\ntouch \"${0%/*}/executed\"\n".utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    let result = DockerInspector.inspectSelected(executable: executable, socket: root.appendingPathComponent("daemon.sock"))
    #expect(result.state == .invalidEndpoint)
    #expect(result.inventory == nil)
    #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("executed").path))
}

@Test func dockerRuntimeAcceptsAnyVersionAndKeepsHostAllocationUnknown() throws {
    let report = try DockerInventory.parseRuntime(clientVersion: "29.1.0", serverVersion: "27.3.1", output: completeDockerReport)
    #expect(report.version == "CLI 29.1.0 / Engine 27.3.1")
    #expect(report.categories.first?.persistentData == true)
    #expect(report.hostAllocatedBytes == nil)
    #expect(!report.runtimeQualified)
    #expect(throws: (any Error).self) { try DockerInventory.parseRuntime(clientVersion: "29.1.0", serverVersion: "29.1.0", output: "{}") }
}

private let completeDockerReport = """
{"Type":"Local Volumes","TotalCount":"2","Active":"1","Size":"12GB","Reclaimable":"6GB (50%)"}
{"Type":"Images","TotalCount":"0","Active":"0","Size":"0B","Reclaimable":"0B"}
{"Type":"Containers","TotalCount":"0","Active":"0","Size":"0B","Reclaimable":"0B"}
{"Type":"Build Cache","TotalCount":"0","Active":"0","Size":"0B","Reclaimable":"0B"}
"""
@Test func dockerRuntimeRejectsTruncatedAndControlCharacterReports() {
    #expect(throws: (any Error).self) { try DockerInventory.parseRuntime(clientVersion: "28.5.1", serverVersion: "28.5.1", output: completeDockerReport.components(separatedBy: "\n")[0]) }
    #expect(throws: (any Error).self) { try DockerInventory.parseRuntime(clientVersion: "28.5.1", serverVersion: "28.5.1", output: completeDockerReport.replacingOccurrences(of: "12GB", with: String(repeating: "x", count: 1000))) }
}

@Test func dockerRuntimeTransportUsesOnlyExplicitEndpointAndReadOnlyCommands() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("StillDockerProbe-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    let tool = root.appendingPathComponent("docker")
    let sentinel = root.appendingPathComponent("persistent-volume-data")
    try Data("protected-data".utf8).write(to: sentinel)
    let script = """
    #!/bin/sh
    test "$1" = --config && test "$2" = "\(root.path)/config" && test "$3" = --host && test "$4" = "unix://\(root.path)/daemon.sock" || exit 7
    test "$HOME" = "\(root.path)" && test -z "$DOCKER_HOST" && test -z "$DOCKER_CONTEXT" || exit 8
    if test "$#" = 7 && test "$5" = version && test "$6" = --format && test "$7" = '{{json .}}'; then
      printf '%s\\n' '{"Client":{"Version":"29.1.0"},"Server":{"Version":"29.1.0"}}'
    elif test "$#" = 8 && test "$5" = system && test "$6" = df && test "$7" = --format && test "$8" = json; then
      cat '\(root.appendingPathComponent("report.json").path)'
    else exit 9
    fi
    """
    try Data(completeDockerReport.utf8).write(to: root.appendingPathComponent("report.json"))
    try Data(script.utf8).write(to: tool)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: tool.path)
    let report = try DockerInspector.inspectRuntime(executable: tool, socket: root.appendingPathComponent("daemon.sock"), workspace: root)
    #expect(report.state == .observed)
    #expect(report.inventory?.categories.count == 4)
    #expect(report.inventory?.runtimeQualified == false)
    #expect(try Data(contentsOf: sentinel) == Data("protected-data".utf8))
}
