import Foundation

enum UnifiedFitStatus: String, Sendable {
    case recommended = "Recommended"
    case fits = "Fits"
    case notFit = "Not Fit"
    case unknown = "Unknown"
}

struct UnifiedModelFitRow: Identifiable, Sendable {
    let model: RemoteModel
    let estimatedParamsB: Double?
    let estimatedMemoryRequiredGB: Double?
    let estimatedRAMLeftGB: Double?
    let estimatedTPS: Double?
    let inferredQuantization: Quantization
    let llmfitMatch: LLMFitRecommendation?
    let status: UnifiedFitStatus

    var id: String { model.id }
}

enum UnifiedModelFitBuilder {
    static func buildRows(
        remoteModels: [RemoteModel],
        recommendations: [LLMFitRecommendation],
        assessment: MachineAssessment
    ) -> [UnifiedModelFitRow] {
        let rows = remoteModels.map { model -> UnifiedModelFitRow in
            let quant = inferQuantization(from: model)
            let paramsB = inferParamsB(from: model)

            let requiredGB = paramsB.map { estimateRequiredMemoryGB(paramsB: $0, quantization: quant) }
            let ramLeftGB = requiredGB.map { assessment.availableMemoryGB - $0 }
            let tps = paramsB.map { estimateTPS(paramsB: $0, quantization: quant, assessment: assessment) }
            let recMatch = bestRecommendationMatch(for: model.id, remoteParamsB: paramsB, in: recommendations)

            let llmfitRunnable = recMatch.map { isRunnableFitLevel($0.fitLevel) } ?? false
            let llmfitMemoryFits = recMatch.map { recommendationMemoryFits($0, availableMemoryGB: assessment.availableMemoryGB) } ?? false
            let heuristicFits = ramLeftGB.map { $0 >= 2.0 } ?? false

            let status: UnifiedFitStatus
            if recMatch != nil && llmfitRunnable && (heuristicFits || llmfitMemoryFits) {
                status = .recommended
            } else if heuristicFits || llmfitMemoryFits {
                status = .fits
            } else if ramLeftGB != nil || recMatch != nil {
                status = .notFit
            } else {
                status = .unknown
            }

            return UnifiedModelFitRow(
                model: model,
                estimatedParamsB: paramsB,
                estimatedMemoryRequiredGB: requiredGB,
                estimatedRAMLeftGB: ramLeftGB,
                estimatedTPS: tps,
                inferredQuantization: quant,
                llmfitMatch: recMatch,
                status: status
            )
        }

        return rows.sorted { lhs, rhs in
            let lhsScore = statusRank(lhs.status)
            let rhsScore = statusRank(rhs.status)
            if lhsScore != rhsScore {
                return lhsScore < rhsScore
            }
            if lhs.model.downloads != rhs.model.downloads {
                return lhs.model.downloads > rhs.model.downloads
            }
            return lhs.model.likes > rhs.model.likes
        }
    }

    private static func statusRank(_ status: UnifiedFitStatus) -> Int {
        switch status {
        case .recommended: return 0
        case .fits: return 1
        case .notFit: return 2
        case .unknown: return 3
        }
    }

    private static func estimateRequiredMemoryGB(paramsB: Double, quantization: Quantization) -> Double {
        let params = paramsB * 1_000_000_000
        let rawWeights = params * quantization.bytesPerParameter
        let runtimeOverhead = 1.2
        return (rawWeights * runtimeOverhead) / 1_073_741_824
    }

    private static func estimateTPS(paramsB: Double, quantization: Quantization, assessment: MachineAssessment) -> Double {
        let bandwidthContribution = (assessment.memoryBandwidthGBs / max(paramsB, 1.0)) * 1.5
        let coreBoost = 1.0 + (Double(assessment.performanceCoreCount) * 0.03)
        return max(0.5, bandwidthContribution * quantization.throughputMultiplier * coreBoost)
    }

    private static func inferQuantization(from model: RemoteModel) -> Quantization {
        let id = model.id.lowercased()
        let tags = model.tags.map { $0.lowercased() }

        if id.contains("8bit") || tags.contains(where: { $0.contains("8-bit") || $0 == "8bit" }) {
            return .q8
        }
        if id.contains("6bit") || tags.contains(where: { $0.contains("6-bit") || $0 == "6bit" }) {
            return .q6
        }
        return .q4
    }

    private static func inferParamsB(from model: RemoteModel) -> Double? {
        let text = (model.id + " " + model.tags.joined(separator: " ")).lowercased()

        let regex = try? NSRegularExpression(pattern: #"([0-9]+(?:\.[0-9]+)?)\s*([bm])\b"#)
        guard let regex else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let valueRange = Range(match.range(at: 1), in: text),
              let unitRange = Range(match.range(at: 2), in: text) else {
            return nil
        }

        guard let value = Double(text[valueRange]) else { return nil }
        let unit = text[unitRange]
        if unit == "b" { return value }
        return value / 1000.0
    }

    private static func bestRecommendationMatch(for modelID: String, remoteParamsB: Double?, in recommendations: [LLMFitRecommendation]) -> LLMFitRecommendation? {
        let remoteCanonical = canonicalModelName(modelID)

        return recommendations.first { rec in
            let recCanonical = canonicalModelName(rec.name)
            guard parameterSizesCompatible(remoteParamsB: remoteParamsB, recommendedParamsB: rec.paramsB, remoteID: modelID, recommendedName: rec.name) else {
                return false
            }
            if remoteCanonical == recCanonical { return true }
            if remoteCanonical.contains(recCanonical) || recCanonical.contains(remoteCanonical) { return true }

            let remoteTokens = significantTokens(from: remoteCanonical)
            let recTokens = significantTokens(from: recCanonical)
            let overlap = remoteTokens.intersection(recTokens)
            return overlap.count >= 3
        }
    }

    private static func canonicalModelName(_ raw: String) -> String {
        var value = raw.lowercased()
        if value.hasPrefix("mlx-community/") {
            value = String(value.dropFirst("mlx-community/".count))
        }
        if let slash = value.firstIndex(of: "/") {
            value = String(value[value.index(after: slash)...])
        }
        value = value.replacingOccurrences(of: "-4bit", with: "")
        value = value.replacingOccurrences(of: "-6bit", with: "")
        value = value.replacingOccurrences(of: "-8bit", with: "")
        value = value.replacingOccurrences(of: "_4bit", with: "")
        value = value.replacingOccurrences(of: "_6bit", with: "")
        value = value.replacingOccurrences(of: "_8bit", with: "")
        value = value.replacingOccurrences(of: " ", with: "-")
        return value
    }

    private static func significantTokens(from value: String) -> Set<String> {
        let cleanedSlash = value.replacingOccurrences(of: "/", with: "-")
        let cleaned = cleanedSlash.replacingOccurrences(of: "_", with: "-")
        let rawTokens = cleaned.split(separator: "-").map(String.init)
        let filtered = rawTokens.filter { token in
            token.count > 2 &&
            token != "instruct" &&
            token != "chat" &&
            token != "model" &&
            token != "quantized"
        }
        return Set(filtered)
    }

    private static func parameterSizesCompatible(
        remoteParamsB: Double?,
        recommendedParamsB: Double?,
        remoteID: String,
        recommendedName: String
    ) -> Bool {
        let remote = remoteParamsB ?? fallbackParamsB(from: remoteID)
        let recommended = recommendedParamsB ?? fallbackParamsB(from: recommendedName)
        guard let remote, let recommended else { return true }
        let ratio = remote / max(recommended, 0.001)
        return ratio >= 0.60 && ratio <= 1.60
    }

    private static func fallbackParamsB(from text: String) -> Double? {
        let lower = text.lowercased()
        let regex = try? NSRegularExpression(pattern: #"([0-9]+(?:\.[0-9]+)?)\s*([bm])\b"#)
        guard let regex else { return nil }
        let range = NSRange(lower.startIndex..<lower.endIndex, in: lower)
        guard let match = regex.firstMatch(in: lower, options: [], range: range),
              let valueRange = Range(match.range(at: 1), in: lower),
              let unitRange = Range(match.range(at: 2), in: lower),
              let value = Double(lower[valueRange]) else {
            return nil
        }
        return lower[unitRange] == "b" ? value : value / 1000.0
    }

    private static func isRunnableFitLevel(_ fitLevel: String) -> Bool {
        let normalized = fitLevel.lowercased()
        return normalized == "perfect" || normalized == "good" || normalized == "marginal"
    }

    private static func recommendationMemoryFits(_ rec: LLMFitRecommendation, availableMemoryGB: Double) -> Bool {
        if let required = rec.memoryRequiredGB, let available = rec.memoryAvailableGB {
            return required <= available
        }
        if let required = rec.memoryRequiredGB {
            return required <= availableMemoryGB
        }
        return isRunnableFitLevel(rec.fitLevel)
    }
}
