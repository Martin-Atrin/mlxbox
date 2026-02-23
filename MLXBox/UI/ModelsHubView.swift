import SwiftUI

struct ModelsHubView: View {
    @EnvironmentObject private var appState: AppState
    @State private var query = ""

    private var filteredModels: [RemoteModel] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty { return appState.remoteModels }
        return appState.remoteModels.filter { model in
            model.id.lowercased().contains(trimmed) ||
            (model.pipelineTag?.lowercased().contains(trimmed) ?? false) ||
            (model.libraryName?.lowercased().contains(trimmed) ?? false)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("MLX Community Models")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button {
                    Task { await appState.refreshRemoteModels() }
                } label: {
                    if appState.isLoadingRemoteModels {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Refresh")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(appState.isLoadingRemoteModels)
            }

            HStack(spacing: 10) {
                Link("Collections", destination: HuggingFaceModelService.collectionsURL)
                Text("•")
                    .foregroundStyle(.secondary)
                Link("API Endpoint", destination: HuggingFaceModelService.modelsAPIURL)
            }
            .font(.callout)

            TextField("Filter models", text: $query)
                .textFieldStyle(.roundedBorder)

            SecureField("Hugging Face Token (optional for private/gated)", text: $appState.huggingFaceToken)
                .textFieldStyle(.roundedBorder)

            if let remoteModelsError = appState.remoteModelsError {
                Text(remoteModelsError)
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            if let modelOperationError = appState.modelOperationError {
                Text(modelOperationError)
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            Table(filteredModels) {
                TableColumn("Model ID") { model in
                    Text(model.id)
                }
                TableColumn("Pipeline") { model in
                    Text(model.pipelineTag ?? "-")
                }
                TableColumn("Library") { model in
                    Text(model.libraryName ?? "-")
                }
                TableColumn("Downloads") { model in
                    Text("\(model.downloads)")
                }
                TableColumn("Likes") { model in
                    Text("\(model.likes)")
                }
                TableColumn("Installed") { model in
                    Label(
                        appState.isModelInstalled(model.id) ? "Yes" : "No",
                        systemImage: appState.isModelInstalled(model.id) ? "checkmark.circle.fill" : "circle"
                    )
                    .foregroundStyle(appState.isModelInstalled(model.id) ? .green : .secondary)
                }
                TableColumn("Action") { model in
                    if appState.activeModelOperations.contains(model.id) {
                        ProgressView()
                    } else if appState.isModelInstalled(model.id) {
                        Button("Delete") {
                            Task { await appState.deleteModel(model.id) }
                        }
                    } else {
                        Button("Install") {
                            Task { await appState.installModel(model.id) }
                        }
                    }
                }
            }
        }
        .padding(20)
        .onAppear {
            if appState.remoteModels.isEmpty {
                Task { await appState.refreshRemoteModels() }
            } else {
                appState.refreshInstalledModels()
            }
        }
    }
}
