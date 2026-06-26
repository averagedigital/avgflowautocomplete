import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum LoginItemDefaultsKey {
        static let hasRegistered = "hasRegisteredLoginItem"
        static let registeredBundlePath = "registeredLoginItemBundlePath"
    }

    private var menuBarController: MenuBarController?
    private var overlayManager: OverlayCompletionManager?
    let permissionsManager = PermissionsManager()
    private var permissionObserver: NSObjectProtocol?
    private var appActivationObserver: NSObjectProtocol?
    private var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Force dark appearance for the entire app
        NSApp.appearance = NSAppearance(named: .darkAqua)

        NSLog("[AIComplete] App launched — bundle: \(Bundle.main.bundleIdentifier ?? "nil")")

        if isRunningTests {
            NSLog("[AIComplete] Test mode detected — skipping overlay, menu bar, permissions, and login item setup")
            return
        }

        if reconcileDuplicateInstancesIfNeeded() {
            NSLog("[AIComplete] Duplicate instance detected — aborting bootstrap for this process")
            return
        }

        PerformanceMetricsCollector.shared.start()

        menuBarController = MenuBarController()

        // Always listen for permission changes
        permissionObserver = NotificationCenter.default.addObserver(
            forName: .accessibilityPermissionGranted,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            NSLog("[AIComplete] Accessibility granted via polling — starting overlay")
            Task { @MainActor [weak self] in
                self?.ensureOverlayManager().start()
            }
        }
        appActivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.permissionsManager.checkAccessibility() {
                    NSLog("[AIComplete] Accessibility granted on app activation — starting overlay")
                    self.ensureOverlayManager().start()
                } else {
                    self.permissionsManager.startPolling(forceRestart: true)
                }
            }
        }

        // Check accessibility permission
        let accessibilityGranted = permissionsManager.checkAccessibility()
        if accessibilityGranted {
            NSLog("[AIComplete] Accessibility already granted — starting overlay")
            ensureOverlayManager().start()
        } else {
            NSLog("[AIComplete] Accessibility NOT granted — waiting for manual grant in Settings")
            permissionsManager.requestAccessibility()
            permissionsManager.startPolling(forceRestart: true)
        }

        // Menu bar actions
        menuBarController?.onSettingsClicked = {
            NSLog("[AIComplete] Settings requested")
            self.showSettingsWindow()
        }

        menuBarController?.onToggleClicked = { [weak self] enabled in
            NSLog("[AIComplete] Toggle: \(enabled)")
            Task { @MainActor [weak self] in
                if enabled {
                    // Re-check permission before starting
                    if self?.permissionsManager.checkAccessibility() == true {
                        self?.ensureOverlayManager().start()
                    } else {
                        NSLog("[AIComplete] Accessibility still not granted — open System Settings to grant")
                        self?.showSettingsWindow()
                    }
                } else {
                    self?.overlayManager?.stop()
                }
            }
        }

        // Register as login item (auto-launch)
        registerLoginItemIfNeeded()

        // Only surface settings immediately when user action is required.
        if !accessibilityGranted {
            showSettingsWindow()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let permissionObserver {
            NotificationCenter.default.removeObserver(permissionObserver)
            self.permissionObserver = nil
        }
        if let appActivationObserver {
            NotificationCenter.default.removeObserver(appActivationObserver)
            self.appActivationObserver = nil
        }
        permissionsManager.stopPolling()
        PerformanceMetricsCollector.shared.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showSettingsWindow()
        }
        return true
    }

    // MARK: - Settings Window

    private func showSettingsWindow() {
        // Defers window activation to the next run loop tick to avoid layout recursion.
        DispatchQueue.main.async {
            if let window = NSApp.windows.first(where: {
                $0.title.contains("AIComplete") || $0.identifier?.rawValue.contains("settings") == true
            }), !(window is SuggestionPanel) {
                // Make the entire window vibrancy-transparent
                Self.applyVibrancy(to: window)
                window.makeKeyAndOrderFront(nil)
            }
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    static func applyVibrancy(to window: NSWindow) {
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
    }

    // MARK: - Login Item

    private func registerLoginItemIfNeeded() {
        let defaults = UserDefaults.standard
        let currentBundlePath = Bundle.main.bundleURL.resolvingSymlinksInPath().standardizedFileURL.path
        let hasRegistered = defaults.bool(forKey: LoginItemDefaultsKey.hasRegistered)
        let lastRegisteredPath = defaults.string(forKey: LoginItemDefaultsKey.registeredBundlePath)

        guard isPreferredInstallLocation(Bundle.main.bundleURL) else {
            NSLog("[AIComplete] Skipping login item registration for non-installed bundle path: \(currentBundlePath)")
            return
        }

        if hasRegistered, lastRegisteredPath == currentBundlePath {
            return
        }

        if #available(macOS 13.0, *) {
            do {
                if let lastRegisteredPath,
                   lastRegisteredPath != currentBundlePath {
                    do {
                        try SMAppService.mainApp.unregister()
                        NSLog("[AIComplete] Removed stale login item registration for path: \(lastRegisteredPath)")
                    } catch {
                        NSLog("[AIComplete] Login item unregister before refresh failed: \(error)")
                    }
                }

                try SMAppService.mainApp.register()
                defaults.set(true, forKey: LoginItemDefaultsKey.hasRegistered)
                defaults.set(currentBundlePath, forKey: LoginItemDefaultsKey.registeredBundlePath)
                NSLog("[AIComplete] Login item registered for path: \(currentBundlePath)")
            } catch {
                NSLog("[AIComplete] Login item registration failed: \(error)")
            }
        }
    }

    private func reconcileDuplicateInstancesIfNeeded() -> Bool {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            return false
        }

        let currentApp = NSRunningApplication.current
        let currentPID = currentApp.processIdentifier
        let currentBundleURL = Bundle.main.bundleURL.resolvingSymlinksInPath().standardizedFileURL
        let currentIsPreferred = isPreferredInstallLocation(currentBundleURL)

        let peers = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter { $0.processIdentifier != currentPID && !$0.isTerminated }

        guard !peers.isEmpty else {
            return false
        }

        let preferredPeers = peers.filter { peer in
            guard let bundleURL = peer.bundleURL else { return false }
            return isPreferredInstallLocation(bundleURL)
        }

        if !currentIsPreferred {
            let winner = preferredPeers.sorted(by: launchOrder).first ?? peers.sorted(by: launchOrder).first
            if let winner {
                NSLog(
                    "[AIComplete] Yielding to existing instance pid=\(winner.processIdentifier) path=\(winner.bundleURL?.path ?? "unknown")"
                )
                NSApp.terminate(nil)
                return true
            }
            return false
        }

        for peer in peers {
            guard let peerBundleURL = peer.bundleURL else { continue }
            guard !isPreferredInstallLocation(peerBundleURL) else { continue }
            NSLog(
                "[AIComplete] Terminating duplicate non-installed instance pid=\(peer.processIdentifier) path=\(peerBundleURL.path)"
            )
            _ = peer.forceTerminate()
        }

        return false
    }

    private func isPreferredInstallLocation(_ bundleURL: URL) -> Bool {
        let resolvedPath = bundleURL.resolvingSymlinksInPath().standardizedFileURL.path
        let applicationRoots = [
            FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask).first,
            FileManager.default.urls(for: .applicationDirectory, in: .userDomainMask).first
        ]
        .compactMap { $0?.resolvingSymlinksInPath().standardizedFileURL.path }

        return applicationRoots.contains { root in
            resolvedPath == root || resolvedPath.hasPrefix(root + "/")
        }
    }

    private func launchOrder(_ lhs: NSRunningApplication, _ rhs: NSRunningApplication) -> Bool {
        let lhsDate = lhs.launchDate ?? .distantFuture
        let rhsDate = rhs.launchDate ?? .distantFuture
        if lhsDate != rhsDate {
            return lhsDate < rhsDate
        }
        return lhs.processIdentifier < rhs.processIdentifier
    }

    private func ensureOverlayManager() -> OverlayCompletionManager {
        if let overlayManager {
            return overlayManager
        }
        let manager = OverlayCompletionManager(permissionsManager: permissionsManager)
        overlayManager = manager
        return manager
    }
}
