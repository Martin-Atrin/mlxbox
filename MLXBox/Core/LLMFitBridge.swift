import Foundation

enum LLMFitUseCase: String, CaseIterable, Identifiable, Sendable {
    case general
    case coding
    case reasoning
    case chat
    case multimodal
    case embedding

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .coding: return "Coding"
        case .reasoning: return "Reasoning"
        case .chat: return "Chat"
        case .multimodal: return "Multimodal"
        case .embedding: return "Embedding"
        }
    }
}

struct LLMFitRecommendation: Identifiable, Sendable {
    let name: String
    let fitLevel: String
    let score: Double
    let bestQuant: String?
    let estimatedTPS: Double?
    let memoryRequiredGB: Double?
    let memoryAvailableGB: Double?
    let useCase: String?
    let paramsB: Double?

    var id: String { name.lowercased() }
}

struct LLMFitSnapshot: Sendable {
    let available: Bool
    let version: String?
    let systemSummary: String?
    let recommendationSummary: String?
    let errorDescription: String?

    static let unavailable = LLMFitSnapshot(
        available: false,
        version: nil,
        systemSummary: nil,
        recommendationSummary: nil,
        errorDescription: "llmfit not found in PATH"
    )
}

enum LLMFitBridge {
    static func loadSnapshot() async -> LLMFitSnapshot {
        await Task.detached(priority: .utility) {
            guard let versionResult = runLLMFit(arguments: ["--version"]),
                  versionResult.status == 0 else {
                return LLMFitSnapshot.unavailable
            }

            let version = versionResult.stdout
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: "\n")
                .last
                .map(String.init)

            let system = runLLMFit(arguments: ["system", "--json"])
            let recommendation = runLLMFit(arguments: ["recommend", "--json"])

            return LLMFitSnapshot(
                available: true,
                version: version,
                systemSummary: summarize(jsonPayload: system?.status == 0 ? system?.stdout : nil),
                recommendationSummary: summarize(jsonPayload: recommendation?.status == 0 ? recommendation?.stdout : nil),
                errorDescription: nil
            )
        }.value
    }

    static func fetchRecommendations(useCase: LLMFitUseCase, limit: Int = 25) async -> [LLMFitRecommendation] {
        await Task.detached(priority: .utility) {
            guard let result = runLLMFit(arguments: ["recommend", "--json", "--limit", "\(limit)", "--use-case", useCase.rawValue]),
                  result.status == 0,
                  let data = result.stdout.data(using: .utf8) else {
                return []
            }

            let decoder = JSONDecoder()
            do {
                let payload = try decoder.decode(LLMFitRecommendationsPayload.self, from: data)
                return payload.models.map {
                    LLMFitRecommendation(
                        name: $0.name,
                        fitLevel: $0.fitLevel,
                        score: $0.score,
                        bestQuant: $0.bestQuant,
                        estimatedTPS: $0.estimatedTPS,
                        memoryRequiredGB: $0.memoryRequiredGB,
                        memoryAvailableGB: $0.memoryAvailableGB,
                        useCase: $0.useCase,
                        paramsB: $0.paramsB
                    )
                }
            } catch {
                return []
            }
        }.value
    }

    private static func summarize(jsonPayload: String?) -> String? {
        guard let payload = jsonPayload, !payload.isEmpty else { return nil }
        guard let data = payload.data(using: .utf8) else { return nil }

        if let object = try? JSONSerialization.jsonObject(with: data) {
            if let dictionary = object as? [String: Any] {
                let pairs = dictionary
                    .prefix(6)
                    .map { element in "\(element.key): \(element.value)" }
                return pairs.joined(separator: " | ")
            }
            if let array = object as? [Any] {
                let preview = array.prefix(4).map { String(describing: $0) }
                return preview.joined(separator: " | ")
            }
        }

        return payload
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\n")
            .prefix(3)
            .joined(separator: " ")
    }

    private static func runLLMFit(arguments: [String]) -> ProcessResult? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["llmfit"] + arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            return ProcessResult(
                status: process.terminationStatus,
                stdout: stdout,
                stderr: stderr
            )
        }
        return ProcessResult(status: process.terminationStatus, stdout: stdout, stderr: stderr)
    }
}

private struct ProcessResult {
    let status: Int32
    let stdout: String
    let stderr: String
}

private struct LLMFitRecommendationsPayload: Decodable {
    let models: [LLMFitRecommendationDTO]
}

private struct LLMFitRecommendationDTO: Decodable {
    let name: String
    let fitLevel: String
    let score: Double
    let bestQuant: String?
    let estimatedTPS: Double?
    let memoryRequiredGB: Double?
    let memoryAvailableGB: Double?
    let useCase: String?
    let paramsB: Double?

    enum CodingKeys: String, CodingKey {
        case name
        case fitLevel = "fit_level"
        case score
        case bestQuant = "best_quant"
        case estimatedTPS = "estimated_tps"
        case memoryRequiredGB = "memory_required_gb"
        case memoryAvailableGB = "memory_available_gb"
        case useCase = "use_case"
        case paramsB = "params_b"
    }
}
