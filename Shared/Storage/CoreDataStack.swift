import CoreData

final class CoreDataStack {
    // MARK: - Properties

    static let shared = CoreDataStack()

    let container: NSPersistentContainer

    var viewContext: NSManagedObjectContext {
        container.viewContext
    }

    // MARK: - Init

    init(
        inMemory: Bool = false,
        appGroupManager: AppGroupManaging = AppGroupManager.shared,
        fileManager: FileManager = .default
    ) {
        let modelName = Constants.Storage.coreDataModelName
        let model = CoreDataStack.makeManagedObjectModel(modelName: modelName)

        container = NSPersistentContainer(name: modelName, managedObjectModel: model)
        container.persistentStoreDescriptions = [CoreDataStack.makeStoreDescription(
            inMemory: inMemory,
            appGroupManager: appGroupManager,
            fileManager: fileManager
        )]

        container.loadPersistentStores { description, error in
            if let error {
                NSLog("[AIComplete] Persistent store load failed: \(error.localizedDescription)")
                // Fall back to in-memory store without deleting on-disk data.
                let fallback = NSPersistentStoreDescription()
                fallback.url = URL(fileURLWithPath: "/dev/null")
                self.container.persistentStoreDescriptions = [fallback]
                self.container.loadPersistentStores { _, retryError in
                    if retryError != nil {
                        // Last resort: continue without persistence.
                        // The app will work but data won't persist.
                    }
                }
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    // MARK: - Public

    func saveIfNeeded() throws {
        guard viewContext.hasChanges else {
            return
        }
        try viewContext.save()
    }

    func makeBackgroundContext() -> NSManagedObjectContext {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        context.automaticallyMergesChangesFromParent = true
        return context
    }

    // MARK: - Private

    private static func makeManagedObjectModel(modelName: String) -> NSManagedObjectModel {
        let candidateBundles = [Bundle.main, Bundle(for: CoreDataStack.self)] + Bundle.allBundles + Bundle.allFrameworks

        for bundle in candidateBundles {
            guard let modelURL = bundle.url(forResource: modelName, withExtension: "momd") else {
                continue
            }
            if let model = NSManagedObjectModel(contentsOf: modelURL) {
                return model
            }
        }

        if let mergedModel = NSManagedObjectModel.mergedModel(from: candidateBundles),
           !mergedModel.entities.isEmpty {
            return mergedModel
        }

        // Return empty model as last resort — app will function but without CoreData persistence
        return NSManagedObjectModel()
    }

    private static func makeStoreDescription(
        inMemory: Bool,
        appGroupManager: AppGroupManaging,
        fileManager: FileManager
    ) -> NSPersistentStoreDescription {
        let description = NSPersistentStoreDescription()

        if inMemory {
            description.url = URL(fileURLWithPath: "/dev/null")
        } else {
            description.url = (try? appGroupManager.persistentStoreURL(createParentIfMissing: true))
                ?? fallbackPersistentStoreURL(fileManager: fileManager)
        }

        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        return description
    }

    private static func fallbackPersistentStoreURL(fileManager: FileManager) -> URL {
        let fallbackDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return fallbackDirectory.appendingPathComponent(Constants.Storage.sqliteFileName, isDirectory: false)
    }
}
