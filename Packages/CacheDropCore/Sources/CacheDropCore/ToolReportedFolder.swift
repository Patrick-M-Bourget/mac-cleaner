import Foundation

/// A tool that says where it keeps its data (`uv cache dir`, Decision 44), so CacheDrop never guesses the folder.
extension Catalog {
    /// The folder the tool prints for `query`: one absolute path with no `.` or `..` parts. Anything else is a failure,
    /// and so is a tool that fails or doesn't answer within `timeout`. Run like the cleanup command, with the tool's folder on PATH.
    static func reportedFolder(by tool: URL, query: [String], timeout: TimeInterval) -> Result<URL, ToolPreviewError> {
        var environment = BoundedTool.defaultEnvironment
        environment["PATH"] = tool.deletingLastPathComponent().path + ":" + (environment["PATH"] ?? "")
        let output: String
        do { output = try BoundedTool.run(executable: tool, arguments: query, timeout: timeout, outputLimit: 4096, environment: environment) }
        catch let error as ToolPreviewError { return .failure(error) }
        catch { return .failure(.failed) }
        let path = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard path.hasPrefix("/"), path != "/", !path.contains("\n"),
              path.dropFirst().split(separator: "/", omittingEmptySubsequences: false).allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { return .failure(.invalidOutput) }
        return .success(URL(fileURLWithPath: path))
    }

    /// Why a rule whose tool names its folder offers nothing: the tool didn't say where it is. Never a size of 0.
    static func locationQueryNotice(_ tool: ToolCommand, query: [String]) -> String {
        let name = tool.executables.first.map { URL(fileURLWithPath: $0).lastPathComponent } ?? ""
        return "\(name) didn’t say where its cache is (`\(([name] + query).joined(separator: " "))`), so it isn’t offered."
    }
}
