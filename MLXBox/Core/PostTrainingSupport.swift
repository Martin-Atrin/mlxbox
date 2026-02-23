import Foundation

enum TrainingDatasetFormat: String, CaseIterable, Identifiable, Sendable {
    case chat = "Chat"
    case completions = "Completions"
    case text = "Text"
    case tools = "Tools"

    var id: String { rawValue }

    var filename: String { "train.jsonl" }

    var sampleLine: String {
        switch self {
        case .chat:
            return #"{"messages":[{"role":"system","content":"You are a concise assistant."},{"role":"user","content":"Write a SQL query for the total orders by month."},{"role":"assistant","content":"SELECT DATE_TRUNC('month', order_date) AS month, COUNT(*) AS total_orders FROM orders GROUP BY 1 ORDER BY 1;"}]}"#
        case .completions:
            return #"{"prompt":"Summarize: MLX is optimized for Apple silicon.","completion":"MLX is a framework optimized for machine learning on Apple silicon."}"#
        case .text:
            return #"{"text":"This is a standalone training text sample for language modeling."}"#
        case .tools:
            return #"{"messages":[{"role":"user","content":"What is the weather in San Francisco?"},{"role":"assistant","tool_calls":[{"id":"call_1","type":"function","function":{"name":"get_current_weather","arguments":"{\"location\":\"San Francisco, USA\",\"format\":\"celsius\"}"}}]}],"tools":[{"type":"function","function":{"name":"get_current_weather","description":"Get the current weather","parameters":{"type":"object","properties":{"location":{"type":"string"},"format":{"type":"string","enum":["celsius","fahrenheit"]}},"required":["location","format"]}}}]}"#
        }
    }
}

enum TrainingSupport {
    static let supportedModelFamilies: [String] = [
        "Llama",
        "Mistral",
        "Mixtral",
        "Phi",
        "Qwen",
        "Gemma",
        "OLMo",
        "MiniCPM",
        "InternLM"
    ]

    static func inferTrainable(modelID: String, tags: [String]) -> Bool {
        let lowerID = modelID.lowercased()
        let lowerTags = tags.map { $0.lowercased() }

        let familySignals = [
            "llama", "mistral", "mixtral", "phi", "qwen", "gemma", "olmo", "minicpm", "internlm"
        ]
        if familySignals.contains(where: { lowerID.contains($0) }) {
            return true
        }
        if lowerTags.contains(where: { tag in
            familySignals.contains(where: { tag.contains($0) })
        }) {
            return true
        }
        return false
    }

    static func sanitizedDatasetFolderName(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let mapped = name.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let candidate = String(mapped).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return candidate.isEmpty ? "dataset" : candidate
    }
}
