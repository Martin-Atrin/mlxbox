import Foundation

enum ModelSource: String, Sendable {
    case mlxCommunity = "mlx-community"
    case embeddingDiscovery = "embedding-discovery"
}

enum ModelCategory: String, CaseIterable, Sendable {
    case chat = "Chat"
    case coding = "Coding"
    case reasoning = "Reasoning"
    case embedding = "Embedding"
    case multimodal = "Multimodal"
    case speechToText = "Speech-to-Text"
    case textToSpeech = "Text-to-Speech"
    case vision = "Vision"
    case audio = "Audio"
    case tooling = "Tooling"
    case uncategorized = "Uncategorized"
}

struct RemoteModel: Identifiable, Hashable, Sendable {
    let id: String
    let downloads: Int
    let likes: Int
    let pipelineTag: String?
    let libraryName: String?
    let createdAt: Date?
    let tags: [String]
    let category: ModelCategory
    let source: ModelSource
    let trainableWithMLXLM: Bool

    var displayName: String {
        if id.hasPrefix("mlx-community/") {
            return String(id.dropFirst("mlx-community/".count))
        }
        return id
    }
}

enum HuggingFaceModelService {
    static let collectionsURL = URL(string: "https://huggingface.co/mlx-community/collections")!
    static let modelsAPIURL = URL(string: "https://huggingface.co/api/models?author=mlx-community&limit=200&sort=downloads&direction=-1")!
    static let embeddingAPIURL = URL(string: "https://huggingface.co/api/models?pipeline_tag=feature-extraction&limit=500&sort=downloads&direction=-1")!

    static func fetchMLXCommunityModels() async throws -> [RemoteModel] {
        async let primaryRaw = fetchModels(url: modelsAPIURL)
        async let embeddingRaw = fetchModels(url: embeddingAPIURL)

        let primary = try await primaryRaw.map { dto in
            mapToRemote(dto, source: .mlxCommunity)
        }

        let secondaryEmbeddings = try await embeddingRaw
            .filter { dto in isSecondaryEmbeddingCandidate(dto) }
            .map { dto in mapToRemote(dto, source: .embeddingDiscovery, forcedCategory: .embedding) }

        var mergedByID: [String: RemoteModel] = [:]
        for model in primary + secondaryEmbeddings {
            guard model.id != "unknown" else { continue }
            if let existing = mergedByID[model.id] {
                // Prefer mlx-community source, then higher downloads.
                if existing.source == .mlxCommunity && model.source != .mlxCommunity {
                    continue
                }
                if model.source == .mlxCommunity && existing.source != .mlxCommunity {
                    mergedByID[model.id] = model
                    continue
                }
                if model.downloads > existing.downloads {
                    mergedByID[model.id] = model
                }
            } else {
                mergedByID[model.id] = model
            }
        }

        return mergedByID.values.sorted { lhs, rhs in
            if lhs.downloads == rhs.downloads {
                return lhs.likes > rhs.likes
            }
            return lhs.downloads > rhs.downloads
        }
    }

    private static func fetchModels(url: URL) async throws -> [HFModelDTO] {
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "MLXBox.HF", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response from Hugging Face"])
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "No body"
            throw NSError(
                domain: "MLXBox.HF",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Hugging Face returned \(http.statusCode): \(body)"]
            )
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([HFModelDTO].self, from: data)
    }

    private static func mapToRemote(_ item: HFModelDTO, source: ModelSource, forcedCategory: ModelCategory? = nil) -> RemoteModel {
        let id = item.id ?? item.modelId ?? "unknown"
        let tags = item.tags ?? []
        let category = forcedCategory ?? inferCategory(
            id: id,
            pipelineTag: item.pipelineTag,
            tags: tags,
            libraryName: item.libraryName
        )

        return RemoteModel(
            id: id,
            downloads: item.downloads ?? 0,
            likes: item.likes ?? 0,
            pipelineTag: item.pipelineTag,
            libraryName: item.libraryName,
            createdAt: item.createdAt,
            tags: tags,
            category: category,
            source: source,
            trainableWithMLXLM: TrainingSupport.inferTrainable(modelID: id, tags: tags)
        )
    }

    private static func isSecondaryEmbeddingCandidate(_ item: HFModelDTO) -> Bool {
        let id = (item.id ?? item.modelId ?? "").lowercased()
        let tags = (item.tags ?? []).map { $0.lowercased() }
        let pipeline = (item.pipelineTag ?? "").lowercased()
        let library = (item.libraryName ?? "").lowercased()

        let embeddingSignal =
            pipeline == "feature-extraction" ||
            pipeline == "sentence-similarity" ||
            tags.contains("feature-extraction") ||
            tags.contains("sentence-similarity") ||
            tags.contains("embedding") ||
            tags.contains("text-embeddings-inference") ||
            id.contains("embedding")

        let mlxSignal =
            id.hasPrefix("mlx-community/") ||
            id.contains("-mlx") ||
            library.contains("mlx") ||
            tags.contains("mlx") ||
            tags.contains("mlx-lm") ||
            tags.contains(where: { $0.contains("mlx") })

        return embeddingSignal && mlxSignal
    }

    private static func inferCategory(id: String, pipelineTag: String?, tags: [String], libraryName: String?) -> ModelCategory {
        let lowerID = id.lowercased()
        let lowerPipeline = (pipelineTag ?? "").lowercased()
        let lowerTags = tags.map { $0.lowercased() }
        let lowerLibrary = (libraryName ?? "").lowercased()

        if matchesAny(lowerPipeline, ["feature-extraction", "sentence-similarity"]) ||
            containsAny(lowerTags, ["feature-extraction", "sentence-similarity", "embedding", "text-embeddings-inference"]) ||
            lowerID.contains("embedding") {
            return .embedding
        }

        if lowerPipeline == "automatic-speech-recognition" ||
            containsAny(lowerTags, ["automatic-speech-recognition", "asr"]) ||
            containsAny([lowerID], ["whisper", "asr", "transcribe"]) {
            return .speechToText
        }

        if lowerPipeline == "text-to-speech" ||
            containsAny(lowerTags, ["text-to-speech", "tts", "speech generation", "voice cloning"]) {
            return .textToSpeech
        }

        if matchesAny(lowerPipeline, ["image-text-to-text", "video-text-to-text"]) ||
            containsAny(lowerTags, ["multimodal", "image-text-to-text", "video-text-to-text"]) ||
            containsAny([lowerID], ["-vl-", "vision-language", "multimodal"]) {
            return .multimodal
        }

        if lowerPipeline == "image-to-text" ||
            containsAny(lowerTags, ["image-to-text", "vision"]) ||
            containsAny([lowerID], ["siglip", "clip", "vision"]) {
            return .vision
        }

        if containsAny([lowerID], ["coder", "code", "devstral"]) ||
            containsAny(lowerTags, ["code", "coding"]) {
            return .coding
        }

        if containsAny([lowerID], ["reason", "r1", "deepseek-r1"]) ||
            containsAny(lowerTags, ["reasoning"]) {
            return .reasoning
        }

        if lowerPipeline == "text-generation" ||
            containsAny([lowerID], ["instruct", "chat"]) {
            return .chat
        }

        if containsAny(lowerTags, ["audio", "speech"]) ||
            containsAny([lowerID], ["snac", "audio"]) {
            return .audio
        }

        if containsAny([lowerID], ["tokenizer", "processor"]) ||
            containsAny(lowerTags, ["tokenizer"]) ||
            lowerLibrary.contains("tokenizer") {
            return .tooling
        }

        return .uncategorized
    }

    private static func matchesAny(_ value: String, _ exact: [String]) -> Bool {
        exact.contains(value)
    }

    private static func containsAny(_ values: [String], _ fragments: [String]) -> Bool {
        values.contains { value in
            fragments.contains { fragment in
                value.contains(fragment)
            }
        }
    }
}

private struct HFModelDTO: Decodable {
    let id: String?
    let modelId: String?
    let downloads: Int?
    let likes: Int?
    let pipelineTag: String?
    let libraryName: String?
    let createdAt: Date?
    let tags: [String]?

    enum CodingKeys: String, CodingKey {
        case id
        case modelId
        case downloads
        case likes
        case pipelineTag = "pipeline_tag"
        case libraryName = "library_name"
        case createdAt
        case tags
    }
}
