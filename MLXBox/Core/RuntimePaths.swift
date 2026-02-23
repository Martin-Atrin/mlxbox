import Foundation

enum RuntimePaths {
    static func appSupportRoot() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let root = base.appendingPathComponent("MLXBox", isDirectory: true)
        if !FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }
        return root
    }

    static func runtimeRoot() throws -> URL {
        let root = try appSupportRoot().appendingPathComponent("runtime", isDirectory: true)
        if !FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }
        return root
    }

    static func venvRoot() throws -> URL {
        try runtimeRoot().appendingPathComponent("venv", isDirectory: true)
    }

    static func venvBinary(_ name: String) throws -> URL {
        try venvRoot().appendingPathComponent("bin/\(name)")
    }

    static func bootstrapStateFile() throws -> URL {
        try runtimeRoot().appendingPathComponent("bootstrap-state.json")
    }
}
