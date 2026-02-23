import Foundation

enum Quantization: String, CaseIterable, Identifiable {
    case q4 = "Q4"
    case q6 = "Q6"
    case q8 = "Q8"

    var id: String { rawValue }

    var bytesPerParameter: Double {
        switch self {
        case .q4: return 0.5
        case .q6: return 0.75
        case .q8: return 1.0
        }
    }

    var throughputMultiplier: Double {
        switch self {
        case .q4: return 1.0
        case .q6: return 0.8
        case .q8: return 0.65
        }
    }
}

struct ModelProfile: Identifiable, Hashable, Sendable {
    let id: String
    let family: String
    let parameterCountB: Double
    let maxContext: Int
    let capabilities: [String]

    func evaluate(on machine: MachineAssessment, quantization: Quantization) -> ModelEvaluation {
        let requiredMemoryGB = estimateRequiredMemoryGB(quantization: quantization)
        let availableAfterLoad = machine.availableMemoryGB - requiredMemoryGB
        let fitsWithoutSwap = availableAfterLoad >= 2.0
        let estimatedTPS = estimateTokensPerSecond(machine: machine, quantization: quantization)

        return ModelEvaluation(
            model: self,
            quantization: quantization,
            requiredMemoryGB: requiredMemoryGB,
            availableRAMAfterLoadGB: availableAfterLoad,
            fitsWithoutSwap: fitsWithoutSwap,
            estimatedTokensPerSecond: estimatedTPS
        )
    }

    private func estimateRequiredMemoryGB(quantization: Quantization) -> Double {
        let params = parameterCountB * 1_000_000_000
        let rawWeights = params * quantization.bytesPerParameter
        let runtimeOverheadMultiplier = 1.20
        let memoryBytes = rawWeights * runtimeOverheadMultiplier
        return memoryBytes / 1_073_741_824
    }

    private func estimateTokensPerSecond(machine: MachineAssessment, quantization: Quantization) -> Double {
        let bandwidthContribution = (machine.memoryBandwidthGBs / max(parameterCountB, 1.0)) * 1.5
        let coreBoost = 1.0 + (Double(machine.performanceCoreCount) * 0.03)
        return max(0.5, bandwidthContribution * quantization.throughputMultiplier * coreBoost)
    }
}

struct ModelEvaluation: Identifiable, Sendable {
    let model: ModelProfile
    let quantization: Quantization
    let requiredMemoryGB: Double
    let availableRAMAfterLoadGB: Double
    let fitsWithoutSwap: Bool
    let estimatedTokensPerSecond: Double

    var id: String { model.id + quantization.rawValue }
}

enum ModelCatalog {
    static let defaultModels: [ModelProfile] = [
        ModelProfile(
            id: "llama-3.2-1b",
            family: "Llama 3.2",
            parameterCountB: 1.0,
            maxContext: 8_192,
            capabilities: ["Chat", "Reasoning"]
        ),
        ModelProfile(
            id: "llama-3.2-3b",
            family: "Llama 3.2",
            parameterCountB: 3.0,
            maxContext: 8_192,
            capabilities: ["Chat", "Reasoning"]
        ),
        ModelProfile(
            id: "qwen-2.5-7b",
            family: "Qwen 2.5",
            parameterCountB: 7.0,
            maxContext: 32_768,
            capabilities: ["Chat", "Coding"]
        ),
        ModelProfile(
            id: "mistral-7b-instruct",
            family: "Mistral",
            parameterCountB: 7.0,
            maxContext: 32_768,
            capabilities: ["Chat", "Coding"]
        ),
        ModelProfile(
            id: "llama-3.1-8b",
            family: "Llama 3.1",
            parameterCountB: 8.0,
            maxContext: 32_768,
            capabilities: ["Chat", "Reasoning"]
        ),
        ModelProfile(
            id: "deepseek-r1-distill-14b",
            family: "DeepSeek Distill",
            parameterCountB: 14.0,
            maxContext: 32_768,
            capabilities: ["Reasoning", "Coding"]
        ),
        ModelProfile(
            id: "qwen-2.5-32b",
            family: "Qwen 2.5",
            parameterCountB: 32.0,
            maxContext: 32_768,
            capabilities: ["Reasoning", "Coding"]
        ),
        ModelProfile(
            id: "llama-3.1-70b",
            family: "Llama 3.1",
            parameterCountB: 70.0,
            maxContext: 8_192,
            capabilities: ["Reasoning", "Advanced Chat"]
        )
    ]
}
