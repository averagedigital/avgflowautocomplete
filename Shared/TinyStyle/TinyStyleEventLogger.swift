import Foundation

actor TinyStyleEventLogger {
    // MARK: - Properties

    private let appGroupManager: AppGroupManaging
    private let fileManager: FileManager

    // MARK: - Init

    init(
        appGroupManager: AppGroupManaging = AppGroupManager.shared,
        fileManager: FileManager = .default
    ) {
        self.appGroupManager = appGroupManager
        self.fileManager = fileManager
    }

    // MARK: - API

    func append(event: TinyStyleEvent) throws {
        let url = try eventsURL()
        let encoder = JSONEncoder()
        var line = try encoder.encode(event)
        line.append(0x0A) // newline

        if !fileManager.fileExists(atPath: url.path) {
            try line.write(to: url, options: [.atomic])
            return
        }

        let handle = try FileHandle(forWritingTo: url)
        defer {
            try? handle.close()
        }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)

        // Compact periodically to keep bounded growth.
        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if fileSize > 8 * 1024 * 1024 {
            var events = try loadEvents()
            if events.count > 5000 {
                events = Array(events.suffix(5000))
            }
            try saveEvents(events)
        }
    }

    func drainEvents(limit: Int = 500) throws -> [TinyStyleEvent] {
        guard limit > 0 else {
            return []
        }

        var events = try loadEvents()
        guard !events.isEmpty else {
            return []
        }

        let output = Array(events.prefix(limit))
        events.removeFirst(output.count)
        try saveEvents(events)
        return output
    }

    // MARK: - Private

    private func eventsURL() throws -> URL {
        try AppGroupPaths.tinyStyleEventsURL(
            appGroupManager: appGroupManager,
            fileManager: fileManager
        )
    }

    private func loadEvents() throws -> [TinyStyleEvent] {
        let url = try eventsURL()
        guard fileManager.fileExists(atPath: url.path) else {
            return []
        }

        let data = try Data(contentsOf: url)
        guard !data.isEmpty else {
            return []
        }

        // Backward-compatible read: support legacy JSON array and JSONL.
        if let legacy = try? JSONDecoder().decode([TinyStyleEvent].self, from: data) {
            return legacy
        }

        let lines = data.split(separator: 0x0A)
        var output: [TinyStyleEvent] = []
        let decoder = JSONDecoder()
        output.reserveCapacity(lines.count)

        for line in lines {
            guard !line.isEmpty else { continue }
            if let event = try? decoder.decode(TinyStyleEvent.self, from: Data(line)) {
                output.append(event)
            }
        }
        return output
    }

    private func saveEvents(_ events: [TinyStyleEvent]) throws {
        let url = try eventsURL()
        let encoder = JSONEncoder()
        var data = Data()
        data.reserveCapacity(events.count * 120)
        for event in events {
            data.append(try encoder.encode(event))
            data.append(0x0A)
        }
        try data.write(to: url, options: [.atomic])
    }
}
