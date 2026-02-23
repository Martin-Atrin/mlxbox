import Foundation

actor LocalModelServerController {
    private var process: Process?
    private var currentModelPath: String?
    private var currentHost: String?
    private var currentPort: Int?

    func start(modelPath: String, host: String, port: Int, adapterPath: String?) async throws {
        if let process, process.isRunning,
           currentModelPath == modelPath,
           currentHost == host,
           currentPort == port {
            return
        }

        stop()

        let executable = try RuntimePaths.venvBinary("mlx_lm.server")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw NSError(
                domain: "MLXBox.LocalServer",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "mlx_lm.server is not installed in runtime venv."]
            )
        }

        let newProcess = Process()
        newProcess.executableURL = executable
        var arguments = [
            "--model", modelPath,
            "--host", host,
            "--port", "\(port)"
        ]
        if let adapterPath, !adapterPath.isEmpty {
            arguments += ["--adapter-path", adapterPath]
        }
        newProcess.arguments = arguments
        newProcess.standardOutput = FileHandle.nullDevice
        newProcess.standardError = FileHandle.nullDevice

        try newProcess.run()
        process = newProcess
        currentModelPath = modelPath
        currentHost = host
        currentPort = port

        try await waitUntilReady(host: host, port: port, timeoutSeconds: 30)
    }

    func stop() {
        guard let process else { return }
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        self.process = nil
        currentModelPath = nil
        currentHost = nil
        currentPort = nil
    }

    func isRunning() -> Bool {
        process?.isRunning == true
    }

    private func waitUntilReady(host: String, port: Int, timeoutSeconds: Double) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if await isEndpointReady(host: host, port: port) {
                return
            }
            try await Task.sleep(nanoseconds: 300_000_000)
        }

        throw NSError(
            domain: "MLXBox.LocalServer",
            code: -2,
            userInfo: [NSLocalizedDescriptionKey: "Local MLX server did not become ready in time."]
        )
    }

    private func isEndpointReady(host: String, port: Int) async -> Bool {
        guard let url = URL(string: "http://\(host):\(port)/v1/models") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 0.8

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200...299).contains(http.statusCode)
        } catch {
            return false
        }
    }
}
