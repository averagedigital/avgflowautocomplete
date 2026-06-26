import ApplicationServices
import AppKit
import Foundation
import Security

@MainActor
final class PermissionsManager: ObservableObject {
    @Published private(set) var isAccessibilityGranted: Bool = false

    private var pollingTimer: Timer?
    private var hasLoggedBundleDiagnostics = false
    private var hasRequestedAccessibilityPrompt = false
    private var lastLoggedAccessibilityState: Bool?

    var currentBundlePath: String {
        Bundle.main.bundleURL.path
    }

    var currentBundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "unknown"
    }

    var isLikelyRunningFromXcode: Bool {
        currentBundlePath.contains("/DerivedData/")
    }

    var accessibilityResetCommand: String {
        "tccutil reset Accessibility \(currentBundleIdentifier)"
    }

    var codeSigningTeamIdentifier: String? {
        let url = Bundle.main.bundleURL as CFURL
        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(url, SecCSFlags(), &staticCode)
        guard createStatus == errSecSuccess, let staticCode else {
            return nil
        }

        var signingInfo: CFDictionary?
        let infoStatus = SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &signingInfo
        )
        guard infoStatus == errSecSuccess,
              let signingInfo = signingInfo as? [String: Any]
        else {
            return nil
        }
        return signingInfo[kSecCodeInfoTeamIdentifier as String] as? String
    }

    var isLikelyAdHocSigned: Bool {
        codeSigningTeamIdentifier == nil
    }

    func checkAccessibility() -> Bool {
        let options: CFDictionary = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false
        ] as CFDictionary
        let trustedWithOptions = AXIsProcessTrustedWithOptions(options)
        let trustedLegacy = AXIsProcessTrusted()
        let trusted = trustedWithOptions || trustedLegacy
        if isAccessibilityGranted != trusted {
            isAccessibilityGranted = trusted
        }

        if !hasLoggedBundleDiagnostics {
            hasLoggedBundleDiagnostics = true
            NSLog(
                "[AIComplete] bundle path: \(currentBundlePath) (xcodeRun=\(isLikelyRunningFromXcode))"
            )
        }

        if lastLoggedAccessibilityState != trusted {
            lastLoggedAccessibilityState = trusted
            NSLog(
                "[AIComplete] AX trust check: options=\(trustedWithOptions) legacy=\(trustedLegacy) result=\(trusted) (bundle: \(Bundle.main.bundleIdentifier ?? "nil"))"
            )
        }
        return trusted
    }

    func requestAccessibility(force: Bool = false) {
        if hasRequestedAccessibilityPrompt && !force {
            return
        }
        hasRequestedAccessibilityPrompt = true
        NSLog("[AIComplete] Requesting Accessibility permission prompt")
        let options: CFDictionary = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func startPolling(forceRestart: Bool = false) {
        if pollingTimer != nil && !forceRestart {
            return
        }
        stopPolling()
        if checkAccessibility() {
            NotificationCenter.default.post(name: .accessibilityPermissionGranted, object: nil)
            return
        }

        NSLog("[AIComplete] Starting accessibility polling (every 1.5s)")
        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] timer in
            Task { @MainActor [weak self] in
                guard let self else {
                    timer.invalidate()
                    return
                }
                if self.checkAccessibility() {
                    NSLog("[AIComplete] Accessibility permission detected via polling!")
                    timer.invalidate()
                    self.pollingTimer = nil
                    NotificationCenter.default.post(
                        name: .accessibilityPermissionGranted,
                        object: nil
                    )
                }
            }
        }
        pollingTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }
}

extension Notification.Name {
    static let accessibilityPermissionGranted = Notification.Name("accessibilityPermissionGranted")
}
