import Foundation
import SQLite3

enum LexiconStoreError: LocalizedError {
    case openFailed(String)
    case prepareFailed(String)
    case executionFailed(String)

    var errorDescription: String? {
        switch self {
        case let .openFailed(message):
            return "Failed to open lexicon DB: \(message)"
        case let .prepareFailed(message):
            return "Failed to prepare SQL statement: \(message)"
        case let .executionFailed(message):
            return "Failed to execute SQL statement: \(message)"
        }
    }
}

actor LexiconStore {
    // MARK: - Properties

    private let appGroupManager: AppGroupManaging
    private let fileManager: FileManager
    private var database: OpaquePointer?

    // MARK: - Init

    init(
        appGroupManager: AppGroupManaging = AppGroupManager.shared,
        fileManager: FileManager = .default
    ) {
        self.appGroupManager = appGroupManager
        self.fileManager = fileManager
    }

    deinit {
        if let database {
            sqlite3_close(database)
        }
    }

    // MARK: - Public API

    func recordWords(_ terms: [String], lang: String, at date: Date = Date()) throws {
        guard !terms.isEmpty else {
            return
        }

        try ensureDatabaseReady()

        for term in terms {
            try upsert(term: term, lang: lang, into: "words", date: date)
        }
    }

    func recordPhrases(_ phrases: [String], lang: String, at date: Date = Date()) throws {
        guard !phrases.isEmpty else {
            return
        }

        try ensureDatabaseReady()

        for phrase in phrases {
            try upsert(term: phrase, lang: lang, into: "phrases", date: date)
        }
    }

    func topWords(lang: String, limit: Int, now: Date = Date()) throws -> [LexiconRankedItem] {
        try rankedItems(
            table: "words",
            lang: lang,
            limit: limit,
            minCount: 1,
            now: now
        )
    }

    func topPhrases(lang: String, limit: Int, minCount: Int = 3, now: Date = Date()) throws -> [LexiconRankedItem] {
        try rankedItems(
            table: "phrases",
            lang: lang,
            limit: limit,
            minCount: minCount,
            now: now
        )
    }

    func clearAll() throws {
        try ensureDatabaseReady()
        try execute(sql: "DELETE FROM words;")
        try execute(sql: "DELETE FROM phrases;")
    }

    // MARK: - Private

    private func ensureDatabaseReady() throws {
        if database != nil {
            return
        }

        let url = try AppGroupPaths.lexiconDatabaseURL(
            appGroupManager: appGroupManager,
            fileManager: fileManager
        )

        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        var handle: OpaquePointer?

        if sqlite3_open_v2(url.path, &handle, flags, nil) != SQLITE_OK {
            let message = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            sqlite3_close(handle)
            throw LexiconStoreError.openFailed(message)
        }

        database = handle
        try createSchemaIfNeeded()
    }

    private func createSchemaIfNeeded() throws {
        try execute(sql: """
        CREATE TABLE IF NOT EXISTS words (
            term TEXT PRIMARY KEY,
            count INTEGER NOT NULL,
            lastSeen REAL NOT NULL,
            lang TEXT NOT NULL
        );
        """)

        try execute(sql: """
        CREATE TABLE IF NOT EXISTS phrases (
            term TEXT PRIMARY KEY,
            count INTEGER NOT NULL,
            lastSeen REAL NOT NULL,
            lang TEXT NOT NULL
        );
        """)

        try execute(sql: "CREATE INDEX IF NOT EXISTS idx_words_lang ON words(lang);")
        try execute(sql: "CREATE INDEX IF NOT EXISTS idx_phrases_lang ON phrases(lang);")
    }

    private func upsert(term: String, lang: String, into table: String, date: Date) throws {
        guard let database else {
            return
        }

        let sql = """
        INSERT INTO \(table) (term, count, lastSeen, lang)
        VALUES (?, 1, ?, ?)
        ON CONFLICT(term) DO UPDATE SET
            count = \(table).count + 1,
            lastSeen = excluded.lastSeen,
            lang = excluded.lang;
        """

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw LexiconStoreError.prepareFailed(errorMessage(for: database))
        }

        sqlite3_bind_text(statement, 1, term, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(statement, 2, date.timeIntervalSince1970)
        sqlite3_bind_text(statement, 3, lang, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw LexiconStoreError.executionFailed(errorMessage(for: database))
        }
    }

    private func rankedItems(
        table: String,
        lang: String,
        limit: Int,
        minCount: Int,
        now: Date
    ) throws -> [LexiconRankedItem] {
        guard limit > 0 else {
            return []
        }

        try ensureDatabaseReady()
        guard let database else {
            return []
        }

        let fetchLimit = max(limit * 5, 50)
        let sql = """
        SELECT term, count, lastSeen
        FROM \(table)
        WHERE lang = ? AND count >= ?
        ORDER BY count DESC, lastSeen DESC
        LIMIT ?;
        """

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw LexiconStoreError.prepareFailed(errorMessage(for: database))
        }

        sqlite3_bind_text(statement, 1, lang, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(statement, 2, Int32(minCount))
        sqlite3_bind_int(statement, 3, Int32(fetchLimit))

        var items: [LexiconRankedItem] = []

        while sqlite3_step(statement) == SQLITE_ROW {
            guard let termPointer = sqlite3_column_text(statement, 0) else {
                continue
            }

            let term = String(cString: termPointer)
            let count = Int(sqlite3_column_int(statement, 1))
            let timestamp = sqlite3_column_double(statement, 2)
            let lastSeen = Date(timeIntervalSince1970: timestamp)
            let score = rankScore(count: count, lastSeen: lastSeen, now: now)

            items.append(
                LexiconRankedItem(
                    term: term,
                    count: count,
                    lastSeen: lastSeen,
                    score: score
                )
            )
        }

        return items
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.count > rhs.count
                }
                return lhs.score > rhs.score
            }
            .prefix(limit)
            .map { $0 }
    }

    private func rankScore(count: Int, lastSeen: Date, now: Date) -> Double {
        let days = max(0, now.timeIntervalSince(lastSeen) / (24 * 60 * 60))
        let recencyBoost = Foundation.exp(-days / 14)
        return (Double(count) * 0.7) + (recencyBoost * 0.3)
    }

    private func execute(sql: String) throws {
        guard let database else {
            return
        }

        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw LexiconStoreError.executionFailed(errorMessage(for: database))
        }
    }

    private func errorMessage(for database: OpaquePointer) -> String {
        String(cString: sqlite3_errmsg(database))
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
