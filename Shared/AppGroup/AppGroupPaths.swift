import Foundation

enum AppGroupPaths {
    private static func sharedDocumentsURL(
        appGroupManager: AppGroupManaging,
        fileManager: FileManager
    ) throws -> URL {
        let rootURL: URL
        if let container = appGroupManager.sharedContainerURL() {
            rootURL = container
        } else {
            let fallback = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fileManager.temporaryDirectory
            rootURL = fallback.appendingPathComponent(Constants.AppGroup.sharedRootDirectoryName, isDirectory: true)
        }

        let documentsURL = rootURL.appendingPathComponent(Constants.AppGroup.documentsDirectoryName, isDirectory: true)
        try fileManager.createDirectory(at: documentsURL, withIntermediateDirectories: true)
        return documentsURL
    }

    static func lexiconDatabaseURL(
        appGroupManager: AppGroupManaging = AppGroupManager.shared,
        fileManager: FileManager = .default
    ) throws -> URL {
        let documentsURL = try sharedDocumentsURL(
            appGroupManager: appGroupManager,
            fileManager: fileManager
        )
        return documentsURL.appendingPathComponent(Constants.Storage.lexiconSQLiteFileName, isDirectory: false)
    }

    static func tinyStyleWeightsURL(
        appGroupManager: AppGroupManaging = AppGroupManager.shared,
        fileManager: FileManager = .default
    ) throws -> URL {
        let documentsURL = try sharedDocumentsURL(
            appGroupManager: appGroupManager,
            fileManager: fileManager
        )
        return documentsURL.appendingPathComponent(Constants.Storage.tinyStyleWeightsFileName, isDirectory: false)
    }

    static func tinyStyleReplayBufferURL(
        appGroupManager: AppGroupManaging = AppGroupManager.shared,
        fileManager: FileManager = .default
    ) throws -> URL {
        let documentsURL = try sharedDocumentsURL(
            appGroupManager: appGroupManager,
            fileManager: fileManager
        )
        return documentsURL.appendingPathComponent(Constants.Storage.tinyStyleReplayBufferFileName, isDirectory: false)
    }

    static func tinyStyleEventsURL(
        appGroupManager: AppGroupManaging = AppGroupManager.shared,
        fileManager: FileManager = .default
    ) throws -> URL {
        let documentsURL = try sharedDocumentsURL(
            appGroupManager: appGroupManager,
            fileManager: fileManager
        )
        return documentsURL.appendingPathComponent(Constants.Storage.tinyStyleEventsFileName, isDirectory: false)
    }
}
