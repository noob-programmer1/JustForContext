import AppKit

/// Captures and restores browser tabs in Safari and Chrome via AppleScript.
enum BrowserService {

    // MARK: - Capture

    /// Capture all open tabs from Safari.
    static func captureSafariTabs() -> [BrowserTab] {
        let script = """
        tell application "System Events"
            if not (exists process "Safari") then return ""
        end tell
        tell application "Safari"
            set tabList to ""
            repeat with w in windows
                repeat with t in tabs of w
                    set tabList to tabList & URL of t & "|||" & name of t & "\\n"
                end repeat
            end repeat
            return tabList
        end tell
        """
        return runAppleScript(script).compactMap { line in
            let parts = line.components(separatedBy: "|||")
            guard parts.count == 2, !parts[0].isEmpty else { return nil }
            return BrowserTab(browser: "Safari", url: parts[0], title: parts[1])
        }
    }

    /// Capture all open tabs from Chrome.
    static func captureChromeTabs() -> [BrowserTab] {
        let script = """
        tell application "System Events"
            if not (exists process "Google Chrome") then return ""
        end tell
        tell application "Google Chrome"
            set tabList to ""
            repeat with w in windows
                repeat with t in tabs of w
                    set tabList to tabList & URL of t & "|||" & title of t & "\\n"
                end repeat
            end repeat
            return tabList
        end tell
        """
        return runAppleScript(script).compactMap { line in
            let parts = line.components(separatedBy: "|||")
            guard parts.count == 2, !parts[0].isEmpty else { return nil }
            return BrowserTab(browser: "Chrome", url: parts[0], title: parts[1])
        }
    }

    /// Capture tabs from all supported browsers.
    static func captureAllTabs() -> [BrowserTab] {
        captureSafariTabs() + captureChromeTabs()
    }

    // MARK: - Restore

    /// Restore tabs in Safari.
    static func restoreSafariTabs(_ tabs: [BrowserTab]) {
        let safariTabs = tabs.filter { $0.browser == "Safari" }
        guard !safariTabs.isEmpty else { return }

        let urls = safariTabs.map { $0.url.replacingOccurrences(of: "\"", with: "\\\"") }

        // Open first URL in a new window, rest as new tabs
        var script = """
        tell application "Safari"
            activate
            make new document with properties {URL:"\(urls[0])"}
        """

        for url in urls.dropFirst() {
            script += """

                tell window 1
                    set current tab to (make new tab with properties {URL:"\(url)"})
                end tell
            """
        }

        script += "\nend tell"

        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
    }

    /// Restore tabs in Chrome.
    static func restoreChromeTabs(_ tabs: [BrowserTab]) {
        let chromeTabs = tabs.filter { $0.browser == "Chrome" }
        guard !chromeTabs.isEmpty else { return }

        let urls = chromeTabs.map { $0.url.replacingOccurrences(of: "\"", with: "\\\"") }

        var script = """
        tell application "Google Chrome"
            activate
            make new window
            set URL of active tab of window 1 to "\(urls[0])"
        """

        for url in urls.dropFirst() {
            script += """

                tell window 1
                    make new tab with properties {URL:"\(url)"}
                end tell
            """
        }

        script += "\nend tell"

        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
    }

    /// Restore all tabs grouped by browser.
    static func restoreAllTabs(_ tabs: [BrowserTab]) {
        restoreSafariTabs(tabs)
        restoreChromeTabs(tabs)
    }

    // MARK: - Helper

    private static func runAppleScript(_ source: String) -> [String] {
        var error: NSDictionary?
        guard let result = NSAppleScript(source: source)?.executeAndReturnError(&error) else {
            return []
        }
        let output = result.stringValue ?? ""
        return output.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }
}
