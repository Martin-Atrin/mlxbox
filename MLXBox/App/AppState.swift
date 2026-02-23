import Foundation

@MainActor
final class AppState: ObservableObject {
    private let localServerController = LocalModelServerController()
    private let postTrainingManager = PostTrainingManager()
    static let chatAdapterAuto = "__auto__"
    static let chatAdapterNone = "__none__"

    @Published var assessment = MachineAssessment.placeholder
    @Published var selectedQuantization: Quantization = .q4
    @Published var evaluations: [ModelEvaluation] = []
    @Published var selectedUseCase: LLMFitUseCase = .chat
    @Published var llmfitRecommendations: [LLMFitRecommendation] = []
    @Published var blendedRows: [UnifiedModelFitRow] = []
    @Published var isLoadingLLMFitRecommendations = false
    @Published var llmfitRecommendationsError: String?
    @Published var endpoints: [EndpointCandidate] = []
    @Published var llmfitSnapshot = LLMFitSnapshot.unavailable
    @Published var whisperStatus = WhisperStatus.unavailable
    @Published var remoteModels: [RemoteModel] = []
    @Published var installedModelIDs: Set<String> = []
    @Published var isLoadingRemoteModels = false
    @Published var remoteModelsError: String?
    @Published var modelOperationError: String?
    @Published var activeModelOperations: Set<String> = []
    @Published var huggingFaceToken = ""
    @Published var runtimeBootstrapReport: RuntimeBootstrapReport = .idle
    @Published var isBootstrappingRuntime = false
    @Published var isRefreshingAssessment = false
    @Published var isScanningEndpoints = false
    @Published var chatBaseURL = "http://127.0.0.1:8080"
    @Published var chatModel = "mlx-community/Llama-3.2-3B-Instruct-4bit"
    @Published var chatAPIKey = ""
    @Published var localServerHost = "127.0.0.1"
    @Published var localServerPort = 8098
    @Published var localServerStatus = "Idle"
    @Published var isStartingLocalServer = false
    @Published var localServerModelID: String?
    @Published var autoBootstrapRuntimeOnLaunch = true
    @Published var selectedTrainingModelID: String?
    @Published var trainingDatasetName = "my-dataset"
    @Published var trainingDatasetFormat: TrainingDatasetFormat = .chat
    @Published var trainingDatasetDirectory = ""
    @Published var trainingIterations = 600
    @Published var trainingBatchSize = 1
    @Published var trainingLearningRate = "1e-5"
    @Published var isTraining = false
    @Published var trainingStatus = "Idle"
    @Published var trainingLog = ""
    @Published var trainingAdapters: [TrainingAdapter] = []
    @Published var chatSelectedDownloadedModelID: String?
    @Published var chatAdapterSelection = AppState.chatAdapterAuto

    func bootstrap() async {
        async let assessmentRefresh: Void = refreshAssessment()
        async let endpointsScan: Void = scanEndpoints()
        async let modelRefresh: Void = refreshRemoteModels()
        async let recommendationRefresh: Void = refreshLLMFitRecommendations()
        async let adapterRefresh: Void = refreshTrainingAdapters()

        _ = await (assessmentRefresh, endpointsScan, modelRefresh, recommendationRefresh, adapterRefresh)

        if autoBootstrapRuntimeOnLaunch {
            await bootstrapRuntime(repair: false)
        }
    }

    func refreshAssessment() async {
        isRefreshingAssessment = true
        defer { isRefreshingAssessment = false }

        async let machine = SystemAssessment.collect()
        async let llmfit = LLMFitBridge.loadSnapshot()
        async let whisper = WhisperBridge.detect()

        assessment = await machine
        llmfitSnapshot = await llmfit
        whisperStatus = await whisper
        recalculateEvaluations()
        refreshBlendedRows()
    }

    func recalculateEvaluations() {
        evaluations = ModelCatalog.defaultModels
            .map { $0.evaluate(on: assessment, quantization: selectedQuantization) }
            .sorted { lhs, rhs in
                if lhs.fitsWithoutSwap != rhs.fitsWithoutSwap {
                    return lhs.fitsWithoutSwap && !rhs.fitsWithoutSwap
                }
                return lhs.availableRAMAfterLoadGB > rhs.availableRAMAfterLoadGB
            }
    }

    func scanEndpoints() async {
        isScanningEndpoints = true
        defer { isScanningEndpoints = false }
        endpoints = await EndpointScanner.scanLocalhost()
        if let first = endpoints.first {
            chatBaseURL = first.baseURL
            if let modelHint = first.modelHint, !modelHint.isEmpty {
                chatModel = modelHint
            }
        }
    }

    func useEndpointForChat(_ endpoint: EndpointCandidate) {
        chatBaseURL = endpoint.baseURL
        if let hint = endpoint.modelHint, !hint.isEmpty {
            chatModel = hint
        }
    }

    func refreshRemoteModels() async {
        isLoadingRemoteModels = true
        defer { isLoadingRemoteModels = false }

        do {
            remoteModels = try await HuggingFaceModelService.fetchMLXCommunityModels()
            remoteModelsError = nil
        } catch {
            remoteModelsError = error.localizedDescription
        }

        refreshInstalledModels()
        refreshBlendedRows()
    }

    func refreshLLMFitRecommendations() async {
        isLoadingLLMFitRecommendations = true
        defer { isLoadingLLMFitRecommendations = false }

        let recs = await LLMFitBridge.fetchRecommendations(useCase: selectedUseCase, limit: 40)
        llmfitRecommendations = recs
        if llmfitSnapshot.available && recs.isEmpty {
            llmfitRecommendationsError = "No llmfit recommendations returned for \(selectedUseCase.title)."
        } else {
            llmfitRecommendationsError = nil
        }
        refreshBlendedRows()
    }

    func refreshInstalledModels() {
        do {
            installedModelIDs = try ModelInstallManager.installedModelIDs()
            if chatSelectedDownloadedModelID == nil || !installedModelIDs.contains(chatSelectedDownloadedModelID ?? "") {
                chatSelectedDownloadedModelID = installedModelIDs.sorted().first
            }
            if selectedTrainingModelID == nil || !(installedModelIDs.contains(selectedTrainingModelID!)) {
                selectedTrainingModelID = installedModelIDs.sorted().first
            }
        } catch {
            modelOperationError = error.localizedDescription
        }
    }

    func refreshTrainingAdapters() async {
        do {
            trainingAdapters = try AdapterRegistry.scan()
        } catch {
            modelOperationError = "Adapter scan failed: \(error.localizedDescription)"
        }
    }

    func chatAdapters(for modelID: String?) -> [TrainingAdapter] {
        guard let modelID else { return [] }
        let exact = trainingAdapters.filter { $0.modelIDHint == modelID }
        let fallback = trainingAdapters.filter { $0.modelIDHint == nil }
        return exact + fallback
    }

    func isModelInstalled(_ modelID: String) -> Bool {
        installedModelIDs.contains(modelID)
    }

    func installModel(_ modelID: String) async {
        activeModelOperations.insert(modelID)
        defer { activeModelOperations.remove(modelID) }

        do {
            try await ModelInstallManager.install(modelID: modelID, token: huggingFaceToken)
            refreshInstalledModels()
            modelOperationError = nil
        } catch {
            modelOperationError = error.localizedDescription
        }
    }

    func deleteModel(_ modelID: String) async {
        activeModelOperations.insert(modelID)
        defer { activeModelOperations.remove(modelID) }

        do {
            try ModelInstallManager.delete(modelID: modelID)
            refreshInstalledModels()
            modelOperationError = nil
        } catch {
            modelOperationError = error.localizedDescription
        }
    }

    func bootstrapRuntime(repair: Bool = true) async {
        isBootstrappingRuntime = true
        defer { isBootstrappingRuntime = false }
        runtimeBootstrapReport = await RuntimeBootstrapper.bootstrap(repair: repair)
        await refreshAssessment()
        await refreshLLMFitRecommendations()
        refreshInstalledModels()
    }

    func setUseCase(_ useCase: LLMFitUseCase) async {
        selectedUseCase = useCase
        await refreshLLMFitRecommendations()
    }

    func refreshBlendedRows() {
        blendedRows = UnifiedModelFitBuilder.buildRows(
            remoteModels: remoteModels,
            recommendations: llmfitRecommendations,
            assessment: assessment
        )
    }

    func startLocalServerForModel(_ modelID: String) async {
        isStartingLocalServer = true
        defer { isStartingLocalServer = false }

        do {
            let localPath = try ModelInstallManager.localPath(for: modelID).path
            let adapterPath = resolveChatAdapterPath(for: modelID)
            try await localServerController.start(
                modelPath: localPath,
                host: localServerHost,
                port: localServerPort,
                adapterPath: adapterPath
            )

            localServerModelID = modelID
            chatSelectedDownloadedModelID = modelID
            chatBaseURL = "http://\(localServerHost):\(localServerPort)"

            do {
                let models = try await ChatClient.listModels(baseURL: chatBaseURL, apiKey: chatAPIKey)
                if let first = models.first {
                    chatModel = first
                } else {
                    chatModel = modelID
                }
            } catch {
                chatModel = modelID
            }

            if let adapterPath {
                localServerStatus = "Running \(modelID) + adapter \(URL(fileURLWithPath: adapterPath).lastPathComponent)"
            } else {
                localServerStatus = "Running \(modelID) on \(chatBaseURL)"
            }
            modelOperationError = nil
        } catch {
            localServerStatus = "Failed"
            modelOperationError = "Local server start failed: \(error.localizedDescription)"
        }
    }

    func stopLocalServer() {
        Task {
            await localServerController.stop()
            await MainActor.run {
                localServerModelID = nil
                localServerStatus = "Stopped"
            }
        }
    }

    func createTrainingDatasetScaffold() async {
        do {
            let result = try await postTrainingManager.createDatasetScaffold(
                name: trainingDatasetName,
                format: trainingDatasetFormat
            )
            trainingDatasetDirectory = result.datasetDirectory.path
            trainingStatus = "Dataset scaffold ready"
            modelOperationError = nil
        } catch {
            modelOperationError = "Dataset scaffold failed: \(error.localizedDescription)"
        }
    }

    func startPostTraining() async {
        guard let modelID = selectedTrainingModelID else {
            trainingStatus = "No model selected"
            return
        }

        isTraining = true
        trainingStatus = "Running"
        trainingLog = ""
        defer { isTraining = false }

        do {
            let datasetDir: String
            if trainingDatasetDirectory.isEmpty {
                let scaffold = try await postTrainingManager.createDatasetScaffold(
                    name: trainingDatasetName,
                    format: trainingDatasetFormat
                )
                datasetDir = scaffold.datasetDirectory.path
                trainingDatasetDirectory = datasetDir
            } else {
                datasetDir = trainingDatasetDirectory
            }

            let modelPath = try ModelInstallManager.localPath(for: modelID).path
            let result = try await postTrainingManager.runLoRATraining(
                modelID: modelID,
                modelPath: modelPath,
                datasetPath: datasetDir,
                iterations: trainingIterations,
                learningRate: trainingLearningRate,
                batchSize: trainingBatchSize
            )
            trainingLog = result.log
            trainingStatus = result.exitCode == 0
                ? "Completed. Adapters: \(result.adapterPath.path)"
                : "Failed (exit \(result.exitCode)). Check logs."
            await refreshTrainingAdapters()
        } catch {
            trainingStatus = "Failed"
            trainingLog += "\n\(error.localizedDescription)"
        }
    }

    func stopPostTraining() {
        Task {
            await postTrainingManager.stopTraining()
            await MainActor.run {
                trainingStatus = "Stopping..."
            }
        }
    }

    func restartLocalServerWithCurrentSelection() async {
        guard let modelID = chatSelectedDownloadedModelID else { return }
        await startLocalServerForModel(modelID)
    }

    private func resolveChatAdapterPath(for modelID: String) -> String? {
        switch chatAdapterSelection {
        case AppState.chatAdapterNone:
            return nil
        case AppState.chatAdapterAuto:
            return chatAdapters(for: modelID).first?.path
        default:
            return trainingAdapters.first(where: { $0.path == chatAdapterSelection })?.path
        }
    }
}
