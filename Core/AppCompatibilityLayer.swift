import ApplicationServices
import Foundation

enum TargetAppClass: String {
    case appKitNative
    case webKit
    case chromiumElectron
    case codeEditor
    case terminalLike
    case secure
    case unknown
}

struct GeometryFallbackPolicy: Equatable {
    let allowsSyntheticCaret: Bool
    let allowsInputFallback: Bool
    let allowsMouseFallback: Bool
}

final class AppCompatibilityLayer {
    func classifyTargetAppClass(
        for element: AXUIElement,
        appBundleID: String?,
        textReader: AccessibilityTextReader
    ) -> TargetAppClass {
        let traits = textReader.elementTraits(for: element)
        if traits.isSecure {
            return .secure
        }

        let bundleID = (appBundleID ?? "").lowercased()
        if bundleID == "com.apple.terminal" || bundleID == "com.googlecode.iterm2" || bundleID.contains("warp") {
            return .terminalLike
        }

        if bundleID.contains("xcode")
            || bundleID == "com.microsoft.vscode"
            || bundleID.contains("jetbrains")
            || bundleID.contains("sublime") {
            return .codeEditor
        }

        if bundleID == "com.google.chrome"
            || bundleID == "org.chromium.chromium"
            || bundleID == "com.brave.browser"
            || bundleID == "com.microsoft.edgemac"
            || bundleID == "com.tinyspeck.slackmacgap"
            || bundleID.contains("electron") {
            return .chromiumElectron
        }

        if bundleID == "com.apple.safari" || traits.role == "AXWebArea" {
            return .webKit
        }

        if traits.role == "AXTextField" || traits.role == "AXTextArea" || traits.role == "AXComboBox" {
            return .appKitNative
        }

        return .unknown
    }

    func allowsClipboardFallback(for targetClass: TargetAppClass) -> Bool {
        switch targetClass {
        case .webKit, .chromiumElectron, .codeEditor, .unknown:
            return true
        case .appKitNative, .terminalLike, .secure:
            return false
        }
    }

    func geometryFallbackPolicy(for targetClass: TargetAppClass) -> GeometryFallbackPolicy {
        switch targetClass {
        case .appKitNative, .webKit, .chromiumElectron, .unknown:
            return GeometryFallbackPolicy(
                allowsSyntheticCaret: true,
                allowsInputFallback: true,
                allowsMouseFallback: true
            )
        case .codeEditor:
            return GeometryFallbackPolicy(
                allowsSyntheticCaret: true,
                allowsInputFallback: false,
                allowsMouseFallback: false
            )
        case .terminalLike, .secure:
            return GeometryFallbackPolicy(
                allowsSyntheticCaret: false,
                allowsInputFallback: false,
                allowsMouseFallback: false
            )
        }
    }
}
