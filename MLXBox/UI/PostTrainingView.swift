import SwiftUI

struct PostTrainingView: View {
    @EnvironmentObject private var appState: AppState

    private var trainableInstalledModels: [String] {
        let trainable = Set(
            appState.remoteModels
                .filter(\.trainableWithMLXLM)
                .map(\.id)
        )
        return appState.installedModelIDs
            .filter { trainable.contains($0) }
            .sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MLX-LM Post-Training")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Create dataset scaffolds and run LoRA/QLoRA fine-tuning with mlx_lm.lora.")
                .foregroundStyle(.secondary)

            GroupBox("Training Setup") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Base model", selection: Binding(
                        get: { appState.selectedTrainingModelID ?? "" },
                        set: { appState.selectedTrainingModelID = $0.isEmpty ? nil : $0 }
                    )) {
                        if trainableInstalledModels.isEmpty {
                            Text("No trainable installed models").tag("")
                        } else {
                            ForEach(trainableInstalledModels, id: \.self) { id in
                                Text(displayName(id)).tag(id)
                            }
                        }
                    }
                    .pickerStyle(.menu)

                    HStack(spacing: 10) {
                        TextField("Dataset name", text: $appState.trainingDatasetName)
                            .textFieldStyle(.roundedBorder)

                        Picker("Format", selection: $appState.trainingDatasetFormat) {
                            ForEach(TrainingDatasetFormat.allCases) { format in
                                Text(format.rawValue).tag(format)
                            }
                        }
                        .pickerStyle(.menu)

                        Button("Create Dataset Scaffold") {
                            Task { await appState.createTrainingDatasetScaffold() }
                        }
                    }

                    HStack(spacing: 10) {
                        TextField("Dataset directory", text: $appState.trainingDatasetDirectory)
                            .textFieldStyle(.roundedBorder)
                        Stepper("Iters: \(appState.trainingIterations)", value: $appState.trainingIterations, in: 1...50_000)
                        Stepper("Batch: \(appState.trainingBatchSize)", value: $appState.trainingBatchSize, in: 1...64)
                        TextField("Learning rate", text: $appState.trainingLearningRate)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 120)
                    }

                    HStack(spacing: 10) {
                        Button {
                            Task { await appState.startPostTraining() }
                        } label: {
                            if appState.isTraining {
                                ProgressView().controlSize(.small)
                            } else {
                                Text("Start Training")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(appState.isTraining || appState.selectedTrainingModelID == nil)

                        Button("Stop") {
                            appState.stopPostTraining()
                        }
                        .disabled(!appState.isTraining)

                        Text(appState.trainingStatus)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            GroupBox("Dataset Example") {
                ScrollView {
                    Text(appState.trainingDatasetFormat.sampleLine)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                }
                .frame(minHeight: 100)
            }

            GroupBox("Supported Families (MLX-LM LoRA)") {
                Text(TrainingSupport.supportedModelFamilies.joined(separator: ", "))
                    .foregroundStyle(.secondary)
            }

            GroupBox("Training Log") {
                ScrollView {
                    Text(appState.trainingLog.isEmpty ? "No logs yet." : appState.trainingLog)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 200)
            }
        }
        .padding(20)
        .onAppear {
            appState.refreshInstalledModels()
        }
    }

    private func displayName(_ modelID: String) -> String {
        if modelID.hasPrefix("mlx-community/") {
            return String(modelID.dropFirst("mlx-community/".count))
        }
        return modelID
    }
}
