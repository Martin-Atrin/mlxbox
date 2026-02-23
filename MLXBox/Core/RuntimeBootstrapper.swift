import Foundation

enum RuntimeStepState: String, Sendable {
    case ok
    case installed
    case failed
    case skipped
}

struct RuntimeStepResult: Identifiable, Sendable {
    let id = UUID()
    let name: String
    let state: RuntimeStepState
    let detail: String
}

struct RuntimeBootstrapReport: Sendable {
    let startedAt: Date
    let finishedAt: Date
    let results: [RuntimeStepResult]

    static let idle = RuntimeBootstrapReport(startedAt: .distantPast, finishedAt: .distantPast, results: [])
}

enum RuntimeBootstrapper {
    private static let stateVersion = 1

    static func bootstrap(repair: Bool = false) async -> RuntimeBootstrapReport {
        await Task.detached(priority: .userInitiated) {
            let started = Date()
            var results: [RuntimeStepResult] = []

            do {
                if !repair, try runtimeLooksHealthy() {
                    results.append(
                        RuntimeStepResult(
                            name: "Bootstrap",
                            state: .skipped,
                            detail: "Runtime already healthy; skipped reinstall."
                        )
                    )
                    return RuntimeBootstrapReport(
                        startedAt: started,
                        finishedAt: Date(),
                        results: results
                    )
                }

                let brew = try resolveExecutable("brew")
                results.append(contentsOf: try ensureLLMFit(brewExecutable: brew))
                results.append(contentsOf: try ensureWhisperCPP(brewExecutable: brew))
                results.append(contentsOf: try ensurePythonRuntime(forceRepair: repair))
                try writeBootstrapState()
            } catch {
                results.append(
                    RuntimeStepResult(
                        name: "Bootstrap",
                        state: .failed,
                        detail: error.localizedDescription
                    )
                )
            }

            return RuntimeBootstrapReport(
                startedAt: started,
                finishedAt: Date(),
                results: results
            )
        }.value
    }

    private static func ensureLLMFit(brewExecutable: String?) throws -> [RuntimeStepResult] {
        if let llmfit = try resolveExecutable("llmfit"), runQuickCheck(executable: llmfit, arguments: ["--version"]) {
            return [RuntimeStepResult(name: "llmfit", state: .ok, detail: "Already installed.")]
        }

        guard let brewExecutable else {
            return [RuntimeStepResult(name: "llmfit", state: .failed, detail: "Homebrew not found; cannot auto-install llmfit.")]
        }

        try runCommand(executable: brewExecutable, arguments: ["tap", "AlexsJones/llmfit"])
        try runCommand(executable: brewExecutable, arguments: ["install", "llmfit"])
        return [RuntimeStepResult(name: "llmfit", state: .installed, detail: "Installed with Homebrew.")]
    }

    private static func ensureWhisperCPP(brewExecutable: String?) throws -> [RuntimeStepResult] {
        for binary in ["whisper-server", "whisper-cli"] {
            if let executable = try resolveExecutable(binary), runQuickCheck(executable: executable, arguments: ["--help"]) {
                return [RuntimeStepResult(name: "whisper.cpp", state: .ok, detail: "\(binary) is already available.")]
            }
        }

        guard let brewExecutable else {
            return [RuntimeStepResult(name: "whisper.cpp", state: .failed, detail: "Homebrew not found; cannot auto-install whisper-cpp.")]
        }

        try runCommand(executable: brewExecutable, arguments: ["install", "whisper-cpp"])
        return [RuntimeStepResult(name: "whisper.cpp", state: .installed, detail: "Installed with Homebrew.")]
    }

    private static func ensurePythonRuntime(forceRepair: Bool) throws -> [RuntimeStepResult] {
        guard let python3 = try resolveExecutable("python3") else {
            return [RuntimeStepResult(name: "Python runtime", state: .failed, detail: "python3 not found.")]
        }

        var results: [RuntimeStepResult] = []
        let venvRoot = try RuntimePaths.venvRoot()
        let venvPython = try RuntimePaths.venvBinary("python3")
        let venvPip = try RuntimePaths.venvBinary("pip")

        if !FileManager.default.fileExists(atPath: venvPython.path) {
            try runCommand(executable: python3, arguments: ["-m", "venv", venvRoot.path])
            results.append(RuntimeStepResult(name: "Python venv", state: .installed, detail: "Created runtime virtual environment."))
        } else {
            results.append(RuntimeStepResult(name: "Python venv", state: .ok, detail: "Virtual environment already exists."))
        }

        if forceRepair || !pythonPackagesHealthy() {
            try runCommand(executable: venvPython.path, arguments: ["-m", "pip", "install", "--upgrade", "pip"])
            try runCommand(
                executable: venvPip.path,
                arguments: ["install", "--upgrade", "mlx", "mlx-lm[train]", "huggingface_hub[cli]"]
            )
            results.append(RuntimeStepResult(name: "MLX runtime", state: .installed, detail: "Installed/updated mlx, mlx-lm[train], and huggingface CLI."))
        } else {
            results.append(RuntimeStepResult(name: "MLX runtime", state: .ok, detail: "Python packages already available."))
        }

        return results
    }

    private static func runtimeLooksHealthy() throws -> Bool {
        guard let llmfit = try resolveExecutable("llmfit"),
              runQuickCheck(executable: llmfit, arguments: ["--version"]) else {
            return false
        }

        let hasWhisperServer = try resolveExecutable("whisper-server") != nil
        let hasWhisperCLI = try resolveExecutable("whisper-cli") != nil
        let whisperOK = hasWhisperServer || hasWhisperCLI
        guard whisperOK else { return false }

        let venvPython = try RuntimePaths.venvBinary("python3").path
        let venvPip = try RuntimePaths.venvBinary("pip").path
        let venvHF = try RuntimePaths.venvBinary("hf").path
        guard FileManager.default.isExecutableFile(atPath: venvPython),
              FileManager.default.isExecutableFile(atPath: venvPip),
              FileManager.default.isExecutableFile(atPath: venvHF) else {
            return false
        }

        let stateURL = try RuntimePaths.bootstrapStateFile()
        guard let data = try? Data(contentsOf: stateURL),
              let state = try? JSONDecoder().decode(BootstrapState.self, from: data),
              state.version == stateVersion else {
            return false
        }
        return true
    }

    private static func pythonPackagesHealthy() -> Bool {
        do {
            let hf = try RuntimePaths.venvBinary("hf").path
            let mlxLM = try RuntimePaths.venvBinary("mlx_lm").path
            let mlxLMLoRA = try RuntimePaths.venvBinary("mlx_lm.lora").path
            return FileManager.default.isExecutableFile(atPath: hf)
                && FileManager.default.isExecutableFile(atPath: mlxLM)
                && FileManager.default.isExecutableFile(atPath: mlxLMLoRA)
        } catch {
            return false
        }
    }

    private static func writeBootstrapState() throws {
        let fileURL = try RuntimePaths.bootstrapStateFile()
        let state = BootstrapState(version: stateVersion, updatedAt: Date())
        let data = try JSONEncoder().encode(state)
        try data.write(to: fileURL, options: [.atomic])
    }

    private static func runQuickCheck(executable: String, arguments: [String]) -> Bool {
        do {
            try runCommand(executable: executable, arguments: arguments)
            return true
        } catch {
            return false
        }
    }

    private static func resolveExecutable(_ binary: String) throws -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [binary]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let outputData = (process.standardOutput as? Pipe)?.fileHandleForReading.readDataToEndOfFile() ?? Data()
        let output = String(data: outputData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let output, !output.isEmpty else { return nil }
        return output
    }

    private static func runCommand(executable: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorData = error.fileHandleForReading.readDataToEndOfFile()
            let errorText = String(data: errorData, encoding: .utf8) ?? "Process failed with status \(process.terminationStatus)."
            throw NSError(
                domain: "MLXBox.Runtime",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: errorText]
            )
        }
    }
}

private struct BootstrapState: Codable {
    let version: Int
    let updatedAt: Date
}
