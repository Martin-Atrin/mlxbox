import Foundation

struct EndpointCandidate: Identifiable, Hashable, Sendable {
    let baseURL: String
    let probePath: String
    let statusCode: Int
    let signature: String
    let modelHint: String?

    var id: String { "\(baseURL)\(probePath)" }
}

enum EndpointScanner {
    private static let ports = [8080, 11434, 8000, 5000, 1234, 3000]
    private static let paths = ["/v1/models", "/models", "/health", "/"]

    static func scanLocalhost() async -> [EndpointCandidate] {
        await withTaskGroup(of: EndpointCandidate?.self, returning: [EndpointCandidate].self) { group in
            for port in ports {
                for path in paths {
                    group.addTask {
                        await probe(port: port, path: path)
                    }
                }
            }

            var found: [EndpointCandidate] = []
            for await result in group {
                if let result {
                    found.append(result)
                }
            }

            let deduped = Dictionary(grouping: found, by: \.id)
                .compactMap { $0.value.first }
                .sorted { lhs, rhs in
                    if lhs.baseURL == rhs.baseURL { return lhs.probePath < rhs.probePath }
                    return lhs.baseURL < rhs.baseURL
                }
            return deduped
        }
    }

    private static func probe(port: Int, path: String) async -> EndpointCandidate? {
        guard let url = URL(string: "http://127.0.0.1:\(port)\(path)") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 0.8
        request.httpMethod = "GET"

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return nil }
            guard (200...499).contains(http.statusCode) else { return nil }

            let body = String(data: data, encoding: .utf8) ?? ""
            let signature = detectSignature(from: body)
            let modelHint = detectModelHint(from: body)

            return EndpointCandidate(
                baseURL: "http://127.0.0.1:\(port)",
                probePath: path,
                statusCode: http.statusCode,
                signature: signature,
                modelHint: modelHint
            )
        } catch {
            return nil
        }
    }

    private static func detectSignature(from body: String) -> String {
        let lower = body.lowercased()
        if lower.contains("llama.cpp") { return "llama.cpp server" }
        if lower.contains("ollama") { return "ollama" }
        if lower.contains("openai") || lower.contains("chat.completions") { return "OpenAI-compatible" }
        if lower.contains("mlx") { return "MLX runtime" }
        if lower.isEmpty { return "reachable" }
        return "custom local service"
    }

    private static func detectModelHint(from body: String) -> String? {
        let lower = body.lowercased()
        if lower.contains("llama-3.2") { return "mlx-community/Llama-3.2-3B-Instruct-4bit" }
        if lower.contains("mistral") { return "mlx-community/Mistral-7B-Instruct-v0.3-4bit" }
        if lower.contains("qwen") { return "mlx-community/Qwen2.5-7B-Instruct-4bit" }
        return nil
    }
}
