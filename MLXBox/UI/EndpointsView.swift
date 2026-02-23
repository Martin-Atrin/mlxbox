import SwiftUI

struct EndpointsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Local Endpoint Scanner")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button {
                    Task { await appState.scanEndpoints() }
                } label: {
                    if appState.isScanningEndpoints {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Scan")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(appState.isScanningEndpoints)
            }

            Text("Scans common localhost ports for OpenAI-compatible or local model server endpoints.")
                .foregroundStyle(.secondary)

            if appState.endpoints.isEmpty {
                ContentUnavailableView("No local endpoints detected", systemImage: "antenna.radiowaves.left.and.right", description: Text("Start your MLX or llama.cpp server and scan again."))
            } else {
                Table(appState.endpoints) {
                    TableColumn("Base URL") { endpoint in
                        Text(endpoint.baseURL)
                    }
                    TableColumn("Probe") { endpoint in
                        Text(endpoint.probePath)
                    }
                    TableColumn("Status") { endpoint in
                        Text("\(endpoint.statusCode)")
                    }
                    TableColumn("Type") { endpoint in
                        Text(endpoint.signature)
                    }
                    TableColumn("Action") { endpoint in
                        Button("Use in Chat") {
                            appState.useEndpointForChat(endpoint)
                        }
                    }
                }
            }
        }
        .padding(20)
    }
}
