import SwiftUI

struct ChatView: View {
    @EnvironmentObject private var appState: AppState
    @State private var messages: [ChatMessage] = []
    @State private var prompt = ""
    @State private var isSending = false
    @State private var errorText: String?
    @State private var lastResult: ChatCompletionResult?

    private var installedModels: [String] {
        appState.installedModelIDs.sorted()
    }

    private var selectedModelID: String? {
        appState.chatSelectedDownloadedModelID ?? appState.localServerModelID
    }

    private var adapterCandidates: [TrainingAdapter] {
        appState.chatAdapters(for: selectedModelID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Basic Chat")
                .font(.title2)
                .fontWeight(.semibold)

            HStack(spacing: 10) {
                TextField("Base URL", text: $appState.chatBaseURL)
                    .textFieldStyle(.roundedBorder)
                TextField("Model", text: $appState.chatModel)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 10) {
                Menu("Use Downloaded Model") {
                    if installedModels.isEmpty {
                        Button("No downloaded models yet") {}
                            .disabled(true)
                    } else {
                        ForEach(installedModels, id: \.self) { modelID in
                            Button(displayName(modelID)) {
                                appState.chatSelectedDownloadedModelID = modelID
                                Task { await appState.startLocalServerForModel(modelID) }
                            }
                        }
                    }
                }
                .menuStyle(.borderlessButton)

                Menu("Adapter") {
                    Button("Auto latest adapter") {
                        appState.chatAdapterSelection = AppState.chatAdapterAuto
                        Task { await appState.restartLocalServerWithCurrentSelection() }
                    }
                    Button("None") {
                        appState.chatAdapterSelection = AppState.chatAdapterNone
                        Task { await appState.restartLocalServerWithCurrentSelection() }
                    }
                    if !adapterCandidates.isEmpty {
                        Divider()
                    }
                    ForEach(adapterCandidates) { adapter in
                        Button(adapter.displayName) {
                            appState.chatAdapterSelection = adapter.path
                            Task { await appState.restartLocalServerWithCurrentSelection() }
                        }
                    }
                }
                .menuStyle(.borderlessButton)

                if appState.isStartingLocalServer {
                    ProgressView()
                        .controlSize(.small)
                }

                Text("Installed: \(installedModels.count)")
                    .foregroundStyle(.secondary)

                Text("Adapter: \(adapterSelectionLabel())")
                    .foregroundStyle(.secondary)

                if let modelID = appState.localServerModelID {
                    Text("Serving: \(displayName(modelID))")
                        .foregroundStyle(.secondary)
                }

                Button("Stop Local Server") {
                    appState.stopLocalServer()
                }
                .disabled(appState.localServerModelID == nil)

                Spacer()
            }

            HStack(spacing: 10) {
                Text("Local Server")
                    .foregroundStyle(.secondary)
                TextField("Host", text: $appState.localServerHost)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 180)
                TextField("Port", value: $appState.localServerPort, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 120)
                Text(appState.localServerStatus)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            SecureField("API Key (optional)", text: $appState.chatAPIKey)
                .textFieldStyle(.roundedBorder)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(messages) { message in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(message.role.capitalized)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(message.content)
                                .textSelection(.enabled)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(message.role == "user" ? Color.blue.opacity(0.10) : Color.gray.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(minHeight: 280)

            if let errorText {
                Text(errorText)
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            if let lastResult {
                HStack(spacing: 16) {
                    if let value = lastResult.generationTokensPerSecond {
                        Text("Generation speed (tokens/s): \(String(format: "%.1f", value))")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    if let value = lastResult.promptProcessingTokensPerSecond {
                        Text("Prompt processing speed (tokens/s): \(String(format: "%.1f", value))")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack(alignment: .bottom, spacing: 12) {
                TextEditor(text: $prompt)
                    .frame(minHeight: 90)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )

                Button {
                    Task { await sendPrompt() }
                } label: {
                    if isSending {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Send")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSending || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .onAppear {
            appState.refreshInstalledModels()
            Task { await appState.refreshTrainingAdapters() }
        }
    }

    @MainActor
    private func sendPrompt() async {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        errorText = nil
        prompt = ""
        let userMessage = ChatMessage(role: "user", content: text)
        messages.append(userMessage)
        isSending = true

        do {
            let result = try await ChatClient.send(
                baseURL: appState.chatBaseURL,
                model: appState.chatModel,
                messages: messages,
                apiKey: appState.chatAPIKey
            )
            messages.append(ChatMessage(role: "assistant", content: result.content))
            lastResult = result
        } catch {
            errorText = error.localizedDescription
        }

        isSending = false
    }

    private func displayName(_ modelID: String) -> String {
        if modelID.hasPrefix("mlx-community/") {
            return String(modelID.dropFirst("mlx-community/".count))
        }
        return modelID
    }

    private func adapterSelectionLabel() -> String {
        switch appState.chatAdapterSelection {
        case AppState.chatAdapterAuto:
            return "Auto"
        case AppState.chatAdapterNone:
            return "None"
        default:
            return URL(fileURLWithPath: appState.chatAdapterSelection).lastPathComponent
        }
    }
}
