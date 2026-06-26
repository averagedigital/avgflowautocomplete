import ApplicationServices
import Foundation

final class AccessibilityObserver {
    private var axObserver: AXObserver?
    private var observedPID: pid_t = 0

    var onTextChanged: (() -> Void)?
    var onFocusChanged: (() -> Void)?

    // MARK: - Lifecycle

    func observe(pid: pid_t) {
        stopObserving()
        observedPID = pid

        var observer: AXObserver?
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        let result = AXObserverCreate(pid, axObserverCallback, &observer)
        guard result == .success, let observer else {
            return
        }
        self.axObserver = observer

        let appElement = AXUIElementCreateApplication(pid)

        let notifications: [String] = [
            kAXFocusedUIElementChangedNotification as String,
            kAXValueChangedNotification as String,
            kAXSelectedTextChangedNotification as String
        ]

        for notification in notifications {
            AXObserverAddNotification(
                observer,
                appElement,
                notification as CFString,
                refcon
            )
        }

        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )
    }

    func stopObserving() {
        guard let observer = axObserver else {
            return
        }
        CFRunLoopRemoveSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )
        axObserver = nil
        observedPID = 0
    }

    deinit {
        stopObserving()
    }

    // MARK: - Internal (called from C callback)

    fileprivate func handleNotification(_ name: String) {
        let focusNotification = kAXFocusedUIElementChangedNotification as String
        if name == focusNotification {
            onFocusChanged?()
        } else {
            onTextChanged?()
        }
    }
}

// C-function callback required by AXObserverCreate
private func axObserverCallback(
    observer: AXObserver,
    element: AXUIElement,
    notification: CFString,
    refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    let instance = Unmanaged<AccessibilityObserver>.fromOpaque(refcon).takeUnretainedValue()
    let name = notification as String
    instance.handleNotification(name)
}
