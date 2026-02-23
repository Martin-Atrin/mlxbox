import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            AssessmentView()
                .tabItem {
                    Label("Assessment", systemImage: "gauge.with.needle")
                }

            ModelFitHubView()
                .tabItem {
                    Label("Models", systemImage: "shippingbox")
                }

            PostTrainingView()
                .tabItem {
                    Label("Post-Training", systemImage: "hammer")
                }

            EndpointsView()
                .tabItem {
                    Label("Endpoints", systemImage: "dot.radiowaves.left.and.right")
                }

            ChatView()
                .tabItem {
                    Label("Chat", systemImage: "message")
                }
        }
    }
}
