import Foundation

actor TinyStyleReplayBuffer {
    // MARK: - Properties

    private let appGroupManager: AppGroupManaging
    private let fileManager: FileManager
    private let maxCapacity: Int
    private var examples: [TinyStyleExample] = []

    // MARK: - Init

    init(
        appGroupManager: AppGroupManaging = AppGroupManager.shared,
        fileManager: FileManager = .default,
        maxCapacity: Int = 2000
    ) {
        self.appGroupManager = appGroupManager
        self.fileManager = fileManager
        self.maxCapacity = max(1, maxCapacity)
    }

    // MARK: - API

    func add(_ example: TinyStyleExample) {
        examples.append(example)
        trimIfNeeded()
    }

    func add(_ batch: [TinyStyleExample]) {
        guard !batch.isEmpty else {
            return
        }
        examples.append(contentsOf: batch)
        trimIfNeeded()
    }

    func sampleMixed(batchSize: Int = 16) -> [TinyStyleExample] {
        guard !examples.isEmpty else {
            return []
        }

        let safeBatchSize = max(1, batchSize)
        let recentPool = Array(examples.suffix(min(100, examples.count)))

        let recentCount = min(recentPool.count, safeBatchSize / 2)
        let randomCount = min(examples.count, safeBatchSize - recentCount)

        let recentSample = Array(recentPool.suffix(recentCount))

        var randomSample: [TinyStyleExample] = []
        if randomCount > 0 {
            let shuffled = examples.shuffled()
            randomSample = Array(shuffled.prefix(randomCount))
        }

        let mixed = recentSample + randomSample
        return Array(mixed.prefix(safeBatchSize))
    }

    func count() -> Int {
        examples.count
    }

    func save() throws {
        let url = try AppGroupPaths.tinyStyleReplayBufferURL(
            appGroupManager: appGroupManager,
            fileManager: fileManager
        )
        let payload = try JSONEncoder().encode(examples)
        try payload.write(to: url, options: [.atomic])
    }

    func load() throws {
        let url = try AppGroupPaths.tinyStyleReplayBufferURL(
            appGroupManager: appGroupManager,
            fileManager: fileManager
        )
        guard fileManager.fileExists(atPath: url.path) else {
            examples = []
            return
        }

        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode([TinyStyleExample].self, from: data)
        examples = Array(decoded.suffix(maxCapacity))
    }

    // MARK: - Private

    private func trimIfNeeded() {
        guard examples.count > maxCapacity else {
            return
        }
        examples = Array(examples.suffix(maxCapacity))
    }
}
