import Foundation

struct WhisperStatus: Sendable {
    let available: Bool
    let executable: String?
    let hint: String

    static let unavailable = WhisperStatus(
        available: false,
        executable: nil,
        hint: "Install whisper.cpp to enable local speech-to-text workflows."
    )
}

enum WhisperBridge {
    static func detect() async -> WhisperStatus {
        await Task.detached(priority: .utility) {
            for executable in ["whisper-server", "whisper-cli"] {
                if run(arguments: [executable, "--help"]) {
                    return WhisperStatus(
                        available: true,
                        executable: executable,
                        hint: "\(executable) found. You can wire transcription endpoints in the next iteration."
                    )
                }
            }
            return WhisperStatus.unavailable
        }.value
    }

    private static func run(arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
