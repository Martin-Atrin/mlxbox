import SwiftUI

struct ModelFitHubView: View {
    @EnvironmentObject private var appState: AppState
    @State private var query = ""

    private var filteredRows: [UnifiedModelFitRow] {
        let scoped = appState.blendedRows.filter { row in
            if row.status == .recommended {
                return true
            }
            switch appState.selectedUseCase {
            case .general:
                return true
            case .chat:
                return row.model.category == .chat || row.model.category == .multimodal
            case .coding:
                return row.model.category == .coding
            case .reasoning:
                return row.model.category == .reasoning || row.model.category == .chat
            case .embedding:
                return row.model.category == .embedding
            case .multimodal:
                return row.model.category == .multimodal || row.model.category == .vision
            }
        }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty { return scoped }
        return scoped.filter { row in
            row.model.id.lowercased().contains(trimmed)
                || row.model.category.rawValue.lowercased().contains(trimmed)
                || (row.model.pipelineTag?.lowercased().contains(trimmed) ?? false)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Models")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button {
                    Task {
                        await appState.refreshRemoteModels()
                        await appState.refreshLLMFitRecommendations()
                    }
                } label: {
                    if appState.isLoadingRemoteModels || appState.isLoadingLLMFitRecommendations {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Refresh")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(appState.isLoadingRemoteModels || appState.isLoadingLLMFitRecommendations)
            }

            HStack(spacing: 10) {
                Text("Scenario")
                    .foregroundStyle(.secondary)
                Picker("Scenario", selection: $appState.selectedUseCase) {
                    ForEach(LLMFitUseCase.allCases) { useCase in
                        Text(useCase.title).tag(useCase)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: appState.selectedUseCase) { _, newValue in
                    Task { await appState.setUseCase(newValue) }
                }
            }

            HStack(spacing: 10) {
                Link("MLX Community", destination: HuggingFaceModelService.collectionsURL)
                Text("•")
                    .foregroundStyle(.secondary)
                if appState.llmfitSnapshot.available {
                    Text("llmfit \(appState.llmfitSnapshot.version ?? "")").foregroundStyle(.secondary)
                } else {
                    Text("llmfit unavailable").foregroundStyle(.orange)
                }
            }
            .font(.callout)

            if let top = appState.llmfitRecommendations.first {
                Text("Top \(appState.selectedUseCase.title) recommendation: \(top.name) (\(top.fitLevel), score \(String(format: "%.1f", top.score)))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            let uncategorizedCount = appState.remoteModels.filter { $0.category == .uncategorized }.count
            if uncategorizedCount > 0 {
                Text("Uncategorized models remaining: \(uncategorizedCount)")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            TextField("Filter models", text: $query)
                .textFieldStyle(.roundedBorder)

            SecureField("Hugging Face Token (optional for private/gated)", text: $appState.huggingFaceToken)
                .textFieldStyle(.roundedBorder)

            if let remoteError = appState.remoteModelsError {
                Text(remoteError)
                    .foregroundStyle(.red)
                    .font(.callout)
            }
            if let llmfitError = appState.llmfitRecommendationsError {
                Text(llmfitError)
                    .foregroundStyle(.orange)
                    .font(.callout)
            }
            if let operationError = appState.modelOperationError {
                Text(operationError)
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            Table(filteredRows) {
                TableColumn("Model") { row in
                    Text(row.model.displayName)
                }
                TableColumn("Category") { row in
                    Text(row.model.category.rawValue)
                }
                TableColumn("Trainable") { row in
                    Label(
                        row.model.trainableWithMLXLM ? "Yes" : "No",
                        systemImage: row.model.trainableWithMLXLM ? "wrench.and.screwdriver.fill" : "nosign"
                    )
                    .foregroundStyle(row.model.trainableWithMLXLM ? .green : .secondary)
                }
                TableColumn("Status") { row in
                    statusView(row.status)
                }
                TableColumn("RAM Needed") { row in
                    Text(formatGB(row.estimatedMemoryRequiredGB))
                }
                TableColumn("RAM Left") { row in
                    let value = row.estimatedRAMLeftGB
                    Text(formatGB(value))
                        .foregroundStyle((value ?? 0) >= 2.0 ? Color.secondary : Color.red)
                }
                TableColumn("Installed") { row in
                    Label(
                        appState.isModelInstalled(row.model.id) ? "Yes" : "No",
                        systemImage: appState.isModelInstalled(row.model.id) ? "checkmark.circle.fill" : "circle"
                    )
                    .foregroundStyle(appState.isModelInstalled(row.model.id) ? .green : .secondary)
                }
                TableColumn("Action") { row in
                    actionButton(for: row)
                }
            }
        }
        .padding(20)
        .onAppear {
            if appState.remoteModels.isEmpty || appState.blendedRows.isEmpty {
                Task {
                    await appState.refreshRemoteModels()
                    await appState.refreshLLMFitRecommendations()
                }
            } else {
                appState.refreshBlendedRows()
            }
        }
    }

    @ViewBuilder
    private func statusView(_ status: UnifiedFitStatus) -> some View {
        switch status {
        case .recommended:
            Label("Recommended", systemImage: "star.fill").foregroundStyle(.yellow)
        case .fits:
            Label("Fits", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .notFit:
            Label("Not Fit", systemImage: "xmark.circle.fill").foregroundStyle(.red)
        case .unknown:
            Label("Unknown", systemImage: "questionmark.circle").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func actionButton(for row: UnifiedModelFitRow) -> some View {
        if appState.activeModelOperations.contains(row.model.id) {
            ProgressView()
        } else if appState.isModelInstalled(row.model.id) {
            Button("Delete") {
                Task { await appState.deleteModel(row.model.id) }
            }
        } else {
            Button("Install") {
                Task { await appState.installModel(row.model.id) }
            }
            .disabled(row.status == .notFit)
        }
    }

    private func formatGB(_ value: Double?) -> String {
        guard let value else { return "-" }
        return String(format: "%.1f GB", value)
    }
}
