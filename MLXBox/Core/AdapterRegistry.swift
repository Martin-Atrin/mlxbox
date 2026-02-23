import Foundation

struct TrainingAdapter: Identifiable, Hashable, Sendable {
    let path: String
    let modelIDHint: String?
    let createdAt: Date

    var id: String { path }

    var displayName: String {
        URL(fileURLWithPath: path).lastPathComponent
    }
}

enum AdapterRegistry {
    static func scan() throws -> [TrainingAdapter] {
        let root = try RuntimePaths.appSupportRoot().appendingPathComponent("training-runs", isDirectory: true)
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }

        let entries = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles])
        var adapters: [TrainingAdapter] = []

        for url in entries where url.hasDirectoryPath {
            let configExists = FileManager.default.fileExists(atPath: url.appendingPathComponent("adapter_config.json").path)
            let weightsExists = FileManager.default.fileExists(atPath: url.appendingPathComponent("adapters.safetensors").path)
            guard configExists || weightsExists else { continue }

            let metadata = readMetadata(from: url.appendingPathComponent("mlxbox_adapter.json"))
            let created: Date = metadata?.createdAt
                ?? (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate)
                ?? Date.distantPast

            adapters.append(
                TrainingAdapter(
                    path: url.path,
                    modelIDHint: metadata?.modelID,
                    createdAt: created
                )
            )
        }

        return adapters.sorted { lhs, rhs in lhs.createdAt > rhs.createdAt }
    }

    static func writeMetadata(adapterDirectory: URL, modelID: String) throws {
        let metadata = AdapterMetadata(modelID: modelID, createdAt: Date())
        let data = try JSONEncoder().encode(metadata)
        try data.write(to: adapterDirectory.appendingPathComponent("mlxbox_adapter.json"), options: [.atomic])
    }

    private static func readMetadata(from fileURL: URL) -> AdapterMetadata? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(AdapterMetadata.self, from: data)
    }
}

private struct AdapterMetadata: Codable {
    let modelID: String
    let createdAt: Date
}
