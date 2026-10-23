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
