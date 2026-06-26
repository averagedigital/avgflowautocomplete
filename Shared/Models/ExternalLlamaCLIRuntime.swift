import Foundation

final class ExternalLlamaCLIRuntime: @unchecked Sendable, LlamaRuntimeBackend {
    private static let executableNames = ["llama-cli", "llama"]
    private static let fixedExecutableCandidates = [
        "/opt/homebrew/bin/llama-cli",
        "/usr/local/bin/llama-cli",
        "/usr/bin/llama-cli"
    ]

    private(set) var isLoaded = false
    private(set) var memoryUsage: Int = 0
    private var executablePath: String?
    private var loadedModelPath: String?
    private var loadedContextSize: Int = 4096

    init() {
        executablePath = Self.resolveExecutablePath()
    }

    static var isAvailable: Bool {
        resolveExecutablePath() != nil
    }

    func loadModel(path: String, contextSize: Int) throws {
        guard let executable = executablePath ?? Self.resolveExecutablePath() else {
            throw LlamaBridgeError.runtimeUnavailable
        }
        guard FileManager.default.fileExists(atPath: path) else {
            throw LlamaBridgeError.modelFileMissing(path)
        }

        executablePath = executable
        loadedModelPath = path
        loadedContextSize = max(512, contextSize)
        isLoaded = true

        if let fileSize = (try? FileManager.default.attributesOfItem(atPath: path)[.size]) as? NSNumber {
            memoryUsage = fileSize.intValue
        } else {
            memoryUsage = 0
        }
    }

    func unloadModel() {
        loadedModelPath = nil
        loadedContextSize = 4096
        isLoaded = false
        memoryUsage = 0
    }

    func generate(prompt: String, maxTokens: Int, seed: Int) async throws -> String {
        guard isLoaded else {
            throw LlamaBridgeError.modelNotLoaded
        }
        guard let executablePath, let modelPath = loadedModelPath else {
            throw LlamaBridgeError.runtimeUnavailable
        }

        return try await runCLI(
            executablePath: executablePath,
            modelPath: modelPath,
            prompt: prompt,
            maxTokens: maxTokens,
            contextSize: loadedContextSize,
            seed: seed
        )
    }

    private static func resolveExecutablePath() -> String? {
        let fileManager = FileManager.default
        let env = ProcessInfo.processInfo.environment

        let envCandidates = [
            env["AICOMPLETE_LLAMA_CLI"],
            env["LLAMA_CPP_CLI"]
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for candidate in envCandidates where fileManager.isExecutableFile(atPath: candidate) {
            return candidate
        }

        for candidate in fixedExecutableCandidates where fileManager.isExecutableFile(atPath: candidate) {
            return candidate
        }

        if let path = env["PATH"] {
            let searchDirectories = path.split(separator: ":").map(String.init)
            for directory in searchDirectories {
                for executable in executableNames {
                    let candidate = URL(fileURLWithPath: directory).appendingPathComponent(executable).path
                    if fileManager.isExecutableFile(atPath: candidate) {
                        return candidate
                    }
                }
            }
        }

        return nil
    }

    private func runCLI(
        executablePath: String,
        modelPath: String,
        prompt: String,
        maxTokens: Int,
        contextSize: Int,
        seed: Int
    ) async throws -> String {
        try Task.checkCancellation()
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = [
                "-m", modelPath,
                "-c", "\(contextSize)",
                "-n", "\(max(1, maxTokens))",
                "--temp", "0.2",
                "--top-p", "0.9",
                "--seed", "\(seed)",
                "-p", prompt
            ]

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            process.terminationHandler = { process in
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                let stderr = String(data: stderrData, encoding: .utf8) ?? ""

                if process.terminationStatus == 0 {
                    continuation.resume(returning: stdout)
                } else {
                    let reason = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(throwing: LlamaBridgeError.processFailed(reason.isEmpty ? "llama-cli exited with \(process.terminationStatus)" : reason))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
