import Foundation

protocol LlamaRuntimeBackend: AnyObject {
    var isLoaded: Bool { get }
    var memoryUsage: Int { get }

    func loadModel(path: String, contextSize: Int) throws
    func unloadModel()
    func generate(prompt: String, maxTokens: Int, seed: Int) async throws -> String
}
