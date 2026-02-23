import Foundation

struct ChatMessage: Identifiable, Hashable, Sendable {
    let id = UUID()
    let role: String
    let content: String
}

struct ChatCompletionResult: Sendable {
    let content: String
    let promptTokens: Int?
    let completionTokens: Int?
    let totalTokens: Int?
    let elapsedSeconds: Double

    var generationTokensPerSecond: Double? {
        guard let completionTokens, elapsedSeconds > 0 else { return nil }
        return Double(completionTokens) / elapsedSeconds
    }

    var promptProcessingTokensPerSecond: Double? {
        guard let promptTokens, elapsedSeconds > 0 else { return nil }
        return Double(promptTokens) / elapsedSeconds
    }
}

enum ChatClient {
    static func send(
        baseURL: String,
        model: String,
        messages: [ChatMessage],
        apiKey: String
    ) async throws -> ChatCompletionResult {
        let endpoint = try chatCompletionURL(from: baseURL)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let payload = ChatCompletionsRequest(
            model: model,
            messages: messages.map { .init(role: $0.role, content: $0.content) }
        )
        request.httpBody = try JSONEncoder().encode(payload)

        let start = Date()
        let (data, response) = try await URLSession.shared.data(for: request)
        let elapsed = max(0.001, Date().timeIntervalSince(start))
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "MLXBox.ChatClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP response"])
        }
        guard (200...299).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? "No body"
            throw NSError(
                domain: "MLXBox.ChatClient",
                code: Int(http.statusCode),
                userInfo: [NSLocalizedDescriptionKey: "Server returned \(http.statusCode): \(text)"]
            )
        }

        let decoded = try JSONDecoder().decode(ChatCompletionsResponse.self, from: data)
        let content = decoded.choices.first?.message?.content
            ?? decoded.choices.first?.text
            ?? "(No response content)"

        return ChatCompletionResult(
            content: content,
            promptTokens: decoded.usage?.promptTokens,
            completionTokens: decoded.usage?.completionTokens,
            totalTokens: decoded.usage?.totalTokens,
            elapsedSeconds: elapsed
        )
    }

    static func listModels(baseURL: String, apiKey: String = "") async throws -> [String] {
        let endpoint = try modelsURL(from: baseURL)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        if !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "MLXBox.ChatClient", code: -3, userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP response"])
        }
        guard (200...299).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? "No body"
            throw NSError(
                domain: "MLXBox.ChatClient",
                code: Int(http.statusCode),
                userInfo: [NSLocalizedDescriptionKey: "Model listing failed \(http.statusCode): \(text)"]
            )
        }

        let payload = try JSONDecoder().decode(ModelListResponse.self, from: data)
        return payload.data.map(\.id).filter { !$0.isEmpty }
    }

    private static func chatCompletionURL(from baseURL: String) throws -> URL {
        try endpointURL(from: baseURL, leaf: "chat/completions")
    }

    private static func modelsURL(from baseURL: String) throws -> URL {
        try endpointURL(from: baseURL, leaf: "models")
    }

    private static func endpointURL(from baseURL: String, leaf: String) throws -> URL {
        guard var url = URL(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw NSError(domain: "MLXBox.ChatClient", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid endpoint URL"])
        }

        if url.path.hasSuffix("/v1/\(leaf)") {
            return url
        }

        let normalizedPath = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if normalizedPath.isEmpty {
            url.append(path: "v1/\(leaf)")
            return url
        }

        if normalizedPath.hasSuffix("v1") {
            url.append(path: leaf)
            return url
        }

        url.append(path: "v1/\(leaf)")
        return url
    }
}

private struct ChatCompletionsRequest: Encodable {
    let model: String
    let messages: [ChatMessageDTO]
    let temperature = 0.4
    let stream = false
}

private struct ChatMessageDTO: Encodable {
    let role: String
    let content: String
}

private struct ChatCompletionsResponse: Decodable {
    let choices: [ChatChoice]
    let usage: ChatUsage?
}

private struct ChatChoice: Decodable {
    let message: ChatChoiceMessage?
    let text: String?
}

private struct ChatChoiceMessage: Decodable {
    let role: String?
    let content: String?
}

private struct ChatUsage: Decodable {
    let promptTokens: Int?
    let completionTokens: Int?
    let totalTokens: Int?

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}

private struct ModelListResponse: Decodable {
    let data: [ModelListItem]
}

private struct ModelListItem: Decodable {
    let id: String
}
