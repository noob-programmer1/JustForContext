import AppKit
import CoreGraphics
import ApplicationServices

/// Captures and restores window positions using CGWindowList and AXUIElement.
enum WindowCaptureService {

    /// Capture positions of all windows across ALL desktops/Spaces.
    static func captureAllWindows() -> [WindowState] {
        // Use .optionAll to capture windows from ALL Spaces, not just the current one
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionAll, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }

        var states: [WindowState] = []
        var seenWindowIds = Set<Int>()

        // System apps/services to skip — these aren't user-visible apps
        let skipApps: Set<String> = [
            "Window Server", "SystemUIServer", "Control Center",
            "Notification Center", "Dock", "Spotlight",
            "AXVisualSupportAgent", "universalAccessAuthWarn",
            "CursorUIViewService", "AutoFill", "loginwindow",
            "Open and Save Panel Service", "SiriNCService",
            "Writing Tools", "PhotosPicker", "Wi-Fi",
            "Wallpaper", "TextInputMenuAgent", "talagent",
            "SharedWebCredentialViewService"
        ]
        let skipBundlePrefixes = [
            "com.apple.TextInputUI",
            "com.apple.SafariPlatformSupport",
            "com.apple.appkit.xpc",
            "com.apple.SiriNCService",
            "com.apple.WritingTools",
            "com.apple.mobileslideshow.photospicker",
            "com.apple.wifi",
            "com.apple.loginwindow",
            "com.apple.controlcenter",
            "com.apple.notificationcenterui",
            "com.apple.Spotlight",
            "com.apple.dock",
        ]

        // Don't capture DevSwitch itself
        let selfBundleId = Bundle.main.bundleIdentifier ?? "com.devswitch.app"

        for window in windowList {
            guard let ownerPID = window[kCGWindowOwnerPID as String] as? Int32,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let layer = window[kCGWindowLayer as String] as? Int,
                  layer == 0 else { // layer 0 = normal windows
                continue
            }

            // Deduplicate by window ID
            if let windowId = window[kCGWindowNumber as String] as? Int {
                guard !seenWindowIds.contains(windowId) else { continue }
                seenWindowIds.insert(windowId)
            }

            let ownerName = window[kCGWindowOwnerName as String] as? String ?? ""
            let windowTitle = window[kCGWindowName as String] as? String ?? ""

            if skipApps.contains(ownerName) { continue }

            // Get bundle ID from PID
            let bundleId = NSRunningApplication(processIdentifier: ownerPID)?.bundleIdentifier ?? ""
            if skipBundlePrefixes.contains(where: { bundleId.hasPrefix($0) }) { continue }
            // Skip settings extensions
            if bundleId.contains(".settings.") || bundleId.hasSuffix(".extension") { continue }
            // Skip DevSwitch itself
            if bundleId == selfBundleId { continue }

            let x = bounds["X"] ?? 0
            let y = bounds["Y"] ?? 0
            let width = bounds["Width"] ?? 0
            let height = bounds["Height"] ?? 0

            // Skip tiny windows (tooltips, popups, status items)
            guard width > 50 && height > 50 else { continue }

            let state = WindowState(
                appBundleId: bundleId,
                appName: ownerName,
                windowTitle: windowTitle,
                x: Double(x),
                y: Double(y),
                width: Double(width),
                height: Double(height)
            )
            states.append(state)
        }

        return states
    }

    /// Restore window positions from a saved snapshot.
    static func restoreWindows(from states: [WindowState]) {
        for state in states {
            guard !state.appBundleId.isEmpty else { continue }

            // Find running app
            let apps = NSRunningApplication.runningApplications(
                withBundleIdentifier: state.appBundleId
            )
            guard let app = apps.first else {
                // Try to launch the app
                if let url = NSWorkspace.shared.urlForApplication(
                    withBundleIdentifier: state.appBundleId
                ) {
                    NSWorkspace.shared.openApplication(
                        at: url,
                        configuration: NSWorkspace.OpenConfiguration()
                    )
                }
                continue
            }

            let pid = app.processIdentifier
            let axApp = AXUIElementCreateApplication(pid)

            // Get all windows
            var windowsRef: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef)
            guard result == .success, let windows = windowsRef as? [AXUIElement] else { continue }

            // Find matching window by title, or use first window
            let targetWindow: AXUIElement
            if let match = windows.first(where: { axWindow in
                var titleRef: CFTypeRef?
                AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef)
                return (titleRef as? String) == state.windowTitle
            }) {
                targetWindow = match
            } else if let first = windows.first {
                targetWindow = first
            } else {
                continue
            }

            // Set position
            var position = CGPoint(x: state.x, y: state.y)
            if let posValue = AXValueCreate(.cgPoint, &position) {
                AXUIElementSetAttributeValue(targetWindow, kAXPositionAttribute as CFString, posValue)
            }

            // Set size
            var size = CGSize(width: state.width, height: state.height)
            if let sizeValue = AXValueCreate(.cgSize, &size) {
                AXUIElementSetAttributeValue(targetWindow, kAXSizeAttribute as CFString, sizeValue)
            }
        }
    }
}
