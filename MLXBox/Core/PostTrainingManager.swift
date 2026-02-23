import Foundation

struct DatasetScaffoldResult: Sendable {
    let datasetDirectory: URL
    let trainFile: URL
    let readmeFile: URL
}

struct TrainingRunResult: Sendable {
    let exitCode: Int32
    let log: String
    let adapterPath: URL
}

actor PostTrainingManager {
    private var process: Process?

    func createDatasetScaffold(name: String, format: TrainingDatasetFormat) throws -> DatasetScaffoldResult {
        let root = try RuntimePaths.appSupportRoot().appendingPathComponent("training-datasets", isDirectory: true)
        if !FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }

        let folder = root.appendingPathComponent(TrainingSupport.sanitizedDatasetFolderName(name), isDirectory: true)
        if !FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }

        let train = folder.appendingPathComponent(format.filename)
        if !FileManager.default.fileExists(atPath: train.path) {
            let seed = [format.sampleLine, format.sampleLine].joined(separator: "\n") + "\n"
            try seed.data(using: .utf8)?.write(to: train, options: [.atomic])
        }

        let readme = folder.appendingPathComponent("README.txt")
        let readmeText = """
        MLXBox post-training dataset scaffold

        Format: \(format.rawValue)
        File: \(format.filename)

        Required for training:
        1. Keep each sample on a single line in JSONL.
        2. Ensure all lines in train.jsonl share the same schema.
        3. Add validation samples to valid.jsonl (optional but recommended).
        4. Use UTF-8 and avoid trailing commas in JSON.
        """
        try readmeText.data(using: .utf8)?.write(to: readme, options: [.atomic])

        return DatasetScaffoldResult(datasetDirectory: folder, trainFile: train, readmeFile: readme)
    }

    func runLoRATraining(
        modelID: String,
        modelPath: String,
        datasetPath: String,
        iterations: Int,
        learningRate: String,
        batchSize: Int
    ) async throws -> TrainingRunResult {
        guard process == nil else {
            throw NSError(
                domain: "MLXBox.PostTraining",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "A training process is already running."]
            )
        }

        let executable = try RuntimePaths.venvBinary("mlx_lm.lora")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw NSError(
                domain: "MLXBox.PostTraining",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "mlx_lm.lora not found. Run runtime install/repair first."]
            )
        }

        let runRoot = try RuntimePaths.appSupportRoot().appendingPathComponent("training-runs", isDirectory: true)
        if !FileManager.default.fileExists(atPath: runRoot.path) {
            try FileManager.default.createDirectory(at: runRoot, withIntermediateDirectories: true)
        }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let adapters = runRoot.appendingPathComponent("adapters-\(stamp)", isDirectory: true)
        if !FileManager.default.fileExists(atPath: adapters.path) {
            try FileManager.default.createDirectory(at: adapters, withIntermediateDirectories: true)
        }
        try AdapterRegistry.writeMetadata(adapterDirectory: adapters, modelID: modelID)

        let run = Process()
        run.executableURL = executable
        run.arguments = [
            "--model", modelPath,
            "--train",
            "--data", datasetPath,
            "--iters", "\(max(1, iterations))",
            "--batch-size", "\(max(1, batchSize))",
            "--learning-rate", learningRate,
            "--adapter-path", adapters.path
        ]

        let stdout = Pipe()
        let stderr = Pipe()
        run.standardOutput = stdout
        run.standardError = stderr

        try run.run()
        process = run

        run.waitUntilExit()
        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
        process = nil

        let combined = (String(data: outputData, encoding: .utf8) ?? "")
            + "\n"
            + (String(data: errorData, encoding: .utf8) ?? "")

        return TrainingRunResult(exitCode: run.terminationStatus, log: combined, adapterPath: adapters)
    }

    func stopTraining() {
        guard let process else { return }
        if process.isRunning {
            process.terminate()
        }
    }
}
