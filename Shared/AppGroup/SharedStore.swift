import Foundation

enum SharedStore {
    static func makeLexiconStore(appGroupManager: AppGroupManaging = AppGroupManager.shared) -> LexiconStore {
        LexiconStore(appGroupManager: appGroupManager)
    }

    static func makePersonalLexicon(appGroupManager: AppGroupManaging = AppGroupManager.shared) -> PersonalLexicon {
        PersonalLexicon(
            store: makeLexiconStore(appGroupManager: appGroupManager),
            appGroupManager: appGroupManager
        )
    }
}
