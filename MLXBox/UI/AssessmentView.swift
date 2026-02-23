import SwiftUI

struct AssessmentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Machine Assessment")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button {
                    Task { await appState.refreshAssessment() }
                } label: {
                    if appState.isRefreshingAssessment {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Refresh")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(appState.isRefreshingAssessment)
            }

            GroupBox("Hardware") {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                    row("Mac", appState.assessment.modelIdentifier)
                    row("Chip", appState.assessment.chipName)
                    row("CPU Cores", "\(appState.assessment.cpuCoreCount) total (\(appState.assessment.performanceCoreCount)P+\(appState.assessment.efficiencyCoreCount)E)")
                    row("Unified Memory", "\(format(appState.assessment.totalMemoryGB)) GB")
                    row("Available Now", "\(format(appState.assessment.availableMemoryGB)) GB")
                    row("Memory Bandwidth (est.)", "\(format(appState.assessment.memoryBandwidthGBs)) GB/s")
                }
            }

            GroupBox("LLM Fit Integration") {
                VStack(alignment: .leading, spacing: 8) {
                    if appState.llmfitSnapshot.available {
                        Text("Status: connected")
                        if let version = appState.llmfitSnapshot.version {
                            Text("Version: \(version)")
                                .foregroundStyle(.secondary)
                        }
                        if let summary = appState.llmfitSnapshot.systemSummary {
                            Text("System: \(summary)")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                        if let recommendation = appState.llmfitSnapshot.recommendationSummary {
                            Text("Recommendations: \(recommendation)")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                    } else {
                        Text("Status: unavailable")
                        Text("Install `llmfit` to enable direct recommendation sync. Fallback estimations are active.")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            GroupBox("Whisper.cpp Harness") {
                if appState.whisperStatus.available {
                    Text("Status: ready (\(appState.whisperStatus.executable ?? "unknown executable"))")
                    Text(appState.whisperStatus.hint)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Status: unavailable")
                    Text(appState.whisperStatus.hint)
                        .foregroundStyle(.secondary)
                }
            }

            GroupBox("Runtime Bootstrap") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Auto-install/repair dependencies on launch", isOn: $appState.autoBootstrapRuntimeOnLaunch)

                    HStack {
                        Button {
                            Task { await appState.bootstrapRuntime(repair: true) }
                        } label: {
                            if appState.isBootstrappingRuntime {
                                ProgressView().controlSize(.small)
                            } else {
                                Text("Install/Repair Runtime")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(appState.isBootstrappingRuntime)

                        Spacer()
                    }

                    if !appState.runtimeBootstrapReport.results.isEmpty {
                        ForEach(appState.runtimeBootstrapReport.results) { row in
                            Text("\(row.name): \(row.state.rawValue) - \(row.detail)")
                                .font(.callout)
                                .foregroundStyle(row.state == .failed ? .red : .secondary)
                        }
                    } else {
                        Text("No runtime bootstrap run yet.")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            GroupBox("Guidance") {
                Text("MLXBox targets no-swap inference. A model is marked as safe when at least 2 GB remains after loading weights.")
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(20)
    }

    @ViewBuilder
    private func row(_ key: String, _ value: String) -> some View {
        GridRow {
            Text(key)
                .fontWeight(.medium)
            Text(value)
                .foregroundStyle(.secondary)
        }
    }

    private func format(_ number: Double) -> String {
        String(format: "%.1f", number)
    }
}
