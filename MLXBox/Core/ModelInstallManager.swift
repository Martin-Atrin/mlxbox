import Foundation

enum ModelInstallManager {
    static func modelsRoot() throws -> URL {
        let root = try RuntimePaths.appSupportRoot().appendingPathComponent("Models", isDirectory: true)
        if !FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }
        return root
    }

    static func localPath(for modelID: String) throws -> URL {
        try modelsRoot().appendingPathComponent(folderName(for: modelID), isDirectory: true)
    }

    static func installedModelIDs() throws -> Set<String> {
        let root = try modelsRoot()
        let entries = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        let ids = entries
            .filter { $0.hasDirectoryPath }
            .map { folderNameToModelID($0.lastPathComponent) }
        return Set(ids)
    }

    static func isInstalled(modelID: String) throws -> Bool {
        let path = try localPath(for: modelID)
        return FileManager.default.fileExists(atPath: path.path)
    }

    static func install(modelID: String, token: String?) async throws {
        let destination = try localPath(for: modelID)
        if FileManager.default.fileExists(atPath: destination.path) {
            return
        }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        do {
            if try await runHuggingFaceCLIDownload(modelID: modelID, destination: destination, token: token) == false {
                throw NSError(
                    domain: "MLXBox.Install",
                    code: -3,
                    userInfo: [NSLocalizedDescriptionKey: "Hugging Face CLI is not installed. Install `huggingface_hub` (`pip install -U huggingface_hub[cli]`) or `hf` CLI."]
                )
            }
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    static func delete(modelID: String) throws {
        let target = try localPath(for: modelID)
        guard FileManager.default.fileExists(atPath: target.path) else { return }
        try FileManager.default.removeItem(at: target)
    }

    private static func runHuggingFaceCLIDownload(modelID: String, destination: URL, token: String?) async throws -> Bool {
        if let huggingfaceCLI = try resolveExecutable("huggingface-cli") {
            var arguments = [huggingfaceCLI, "download", modelID, "--local-dir", destination.path]
            // Keep copied files instead of symlinks to make deletion behavior predictable.
            arguments += ["--local-dir-use-symlinks", "False"]
            if let token, !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                arguments += ["--token", token]
            }
            try await runEnvCommand(arguments)
            return true
        }

        if let hfCLI = try resolveExecutable("hf") {
            var arguments = [hfCLI, "download", modelID, "--repo-type", "model", "--local-dir", destination.path]
            if let token, !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                arguments += ["--token", token]
            }
            try await runEnvCommand(arguments)
            return true
        }

        return false
    }

    private static func resolveExecutable(_ binary: String) throws -> String? {
        if let embedded = try embeddedRuntimeExecutable(named: binary) {
            return embedded
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [binary]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let path = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let path, !path.isEmpty else { return nil }
        return path
    }

    private static func embeddedRuntimeExecutable(named binary: String) throws -> String? {
        let candidate = try RuntimePaths.venvBinary(binary)
        if FileManager.default.isExecutableFile(atPath: candidate.path) {
            return candidate.path
        }
        return nil
    }

    private static func runEnvCommand(_ arguments: [String]) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let stderrData = (process.standardError as? Pipe)?.fileHandleForReading.readDataToEndOfFile() ?? Data()
            let stderr = String(data: stderrData, encoding: .utf8) ?? "Unknown process error"
            throw NSError(
                domain: "MLXBox.Install",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: stderr]
            )
        }
    }

    private static func folderName(for modelID: String) -> String {
        modelID.replacingOccurrences(of: "/", with: "__")
    }

    private static func folderNameToModelID(_ folderName: String) -> String {
        folderName.replacingOccurrences(of: "__", with: "/")
    }
}
