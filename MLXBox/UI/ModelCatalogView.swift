import SwiftUI

struct ModelCatalogView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Model Fit Matrix")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Picker("Quantization", selection: $appState.selectedQuantization) {
                    ForEach(Quantization.allCases) { quantization in
                        Text(quantization.rawValue).tag(quantization)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)
                .onChange(of: appState.selectedQuantization) {
                    appState.recalculateEvaluations()
                }
            }

            Text("Estimates are conservative and designed to avoid swap pressure.")
                .foregroundStyle(.secondary)

            Table(appState.evaluations) {
                TableColumn("Model") { item in
                    Text(item.model.id)
                }
                TableColumn("Family") { item in
                    Text(item.model.family)
                }
                TableColumn("Params (B)") { item in
                    Text(String(format: "%.1f", item.model.parameterCountB))
                }
                TableColumn("RAM Needed") { item in
                    Text(String(format: "%.1f GB", item.requiredMemoryGB))
                }
                TableColumn("RAM Left") { item in
                    Text(String(format: "%.1f GB", item.availableRAMAfterLoadGB))
                        .foregroundStyle(item.availableRAMAfterLoadGB > 0 ? Color.secondary : Color.red)
                }
                TableColumn("Tokens/s (est.)") { item in
                    Text(String(format: "%.1f", item.estimatedTokensPerSecond))
                }
                TableColumn("No Swap") { item in
                    Label(item.fitsWithoutSwap ? "Yes" : "No", systemImage: item.fitsWithoutSwap ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(item.fitsWithoutSwap ? .green : .red)
                }
            }
        }
        .padding(20)
        .onAppear {
            appState.recalculateEvaluations()
        }
    }
}
