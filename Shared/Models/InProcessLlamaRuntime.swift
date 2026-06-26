import Foundation

final class InProcessLlamaRuntime: @unchecked Sendable, LlamaRuntimeBackend {
    private let errorBufferLength = 2048
    private var handle: UnsafeMutableRawPointer?

    private(set) var isLoaded = false
    private(set) var memoryUsage = 0
    private(set) var loadedModelPath: String?
    private(set) var loadedContextSize = 4096

    static var isAvailable: Bool {
        AILlamaInProcessRuntimeIsAvailable()
    }

    deinit {
        if let handle {
            AILlamaRuntimeDestroy(handle)
        }
    }

    func loadModel(path: String, contextSize: Int) throws {
        guard FileManager.default.fileExists(atPath: path) else {
            throw LlamaBridgeError.modelFileMissing(path)
        }

        let runtimeHandle = try ensureHandle()
        var errorBuffer = Array(repeating: CChar(0), count: errorBufferLength)
        let resolvedContextSize = max(512, contextSize)
        let threadCount = max(1, ProcessInfo.processInfo.activeProcessorCount - 1)

        let loaded = path.withCString { modelPathPointer in
            AILlamaRuntimeLoadModel(
                runtimeHandle,
                modelPathPointer,
                Int32(resolvedContextSize),
                Int32(threadCount),
                &errorBuffer,
                errorBuffer.count
            )
        }

        guard loaded else {
            throw LlamaBridgeError.processFailed(stringFromErrorBuffer(errorBuffer))
        }

        loadedModelPath = path
        loadedContextSize = resolvedContextSize
        isLoaded = true
        memoryUsage = Int(AILlamaRuntimeMemoryUsage(runtimeHandle))
    }

    func unloadModel() {
        if let handle {
            AILlamaRuntimeUnloadModel(handle)
        }
        loadedModelPath = nil
        loadedContextSize = 4096
        isLoaded = false
        memoryUsage = 0
    }

    func generate(prompt: String, maxTokens: Int, seed: Int) async throws -> String {
        guard isLoaded else {
            throw LlamaBridgeError.modelNotLoaded
        }

        let runtimeHandle = try ensureHandle()
        var errorBuffer = Array(repeating: CChar(0), count: errorBufferLength)

        let resultPointer: UnsafeMutablePointer<CChar>? = prompt.withCString { promptPointer in
            AILlamaRuntimeGenerate(
                runtimeHandle,
                promptPointer,
                Int32(max(1, maxTokens)),
                UInt32(bitPattern: Int32(seed)),
                0.2,
                0.9,
                &errorBuffer,
                errorBuffer.count
            )
        }

        guard let resultPointer else {
            throw LlamaBridgeError.processFailed(stringFromErrorBuffer(errorBuffer))
        }

        defer {
            AILlamaStringFree(resultPointer)
        }

        memoryUsage = Int(AILlamaRuntimeMemoryUsage(runtimeHandle))
        return String(cString: resultPointer)
    }

    private func ensureHandle() throws -> UnsafeMutableRawPointer {
        if let handle {
            return handle
        }

        var errorBuffer = Array(repeating: CChar(0), count: errorBufferLength)
        guard let handle = AILlamaRuntimeCreate(&errorBuffer, errorBuffer.count) else {
            let message = stringFromErrorBuffer(errorBuffer)
            if message.isEmpty {
                throw LlamaBridgeError.runtimeUnavailable
            }
            throw LlamaBridgeError.processFailed(message)
        }

        self.handle = handle
        return handle
    }

    private func stringFromErrorBuffer(_ errorBuffer: [CChar]) -> String {
        let message = String(cString: errorBuffer)
        return message.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
