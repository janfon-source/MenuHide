import AppKit

/// One icon in the menu bar's right-hand side, as the Accessibility API reports it.
struct MenuBarItem {
    let element: AXUIElement
    let pid: pid_t
    let bundleID: String
    let appName: String
    /// What the item calls itself, if anything (often nothing).
    let label: String
    /// Its place among the same app's items, left to right, from 0: an app can have several.
    var index: Int
    let frame: CGRect

    /// Stays the same for the same icon across launches, to remember its place and setting by.
    var key: String { "\(bundleID)#\(index)" }

    var icon: NSImage? { NSRunningApplication(processIdentifier: pid)?.icon }
}

/// Reading the menu bar's icons. On macOS 27 they aren't windows of their own that the window
/// list shows, and the system's (clock, Wi-Fi, Control Center…) all belong to MenuBarAgent, but
/// each app's icons are in its Accessibility tree as the children of AXExtrasMenuBar.
enum MenuBar {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Asks for Accessibility access, which macOS shows as a prompt with a button to Settings.
    static func requestAccess() {
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
    }

    /// The apps found with menu bar icons the last time every app was asked. Asking every running
    /// app takes a while (some answer slowly), too long to do after each move while arranging.
    private static var appsWithIcons: [pid_t]?

    /// Every icon on the menu bar, left to right. `rescan` asks every running app again, for new
    /// apps; otherwise only the apps that had icons are asked.
    static func items(rescan: Bool = false) -> [MenuBarItem] {
        let known = rescan ? nil : appsWithIcons
        let apps = NSWorkspace.shared.runningApplications.filter { known?.contains($0.processIdentifier) ?? true }
        var items: [MenuBarItem] = []
        var found: [pid_t] = []
        for app in apps {
            guard let bundleID = app.bundleIdentifier else { continue }
            let element = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(element, 0.25)   // a busy app shouldn't hold everything up
            guard let bar: AXUIElement = attribute(element, "AXExtrasMenuBar"),
                  let children: [AXUIElement] = attribute(bar, kAXChildrenAttribute) else { continue }
            let mine = children.compactMap { child -> MenuBarItem? in
                guard let frame = frame(of: child) else { return nil }
                let label = (attribute(child, kAXDescriptionAttribute) as String?).flatMap { $0.isEmpty ? nil : $0 }
                    ?? attribute(child, kAXTitleAttribute) ?? ""
                return MenuBarItem(element: child, pid: app.processIdentifier, bundleID: bundleID,
                                   appName: app.localizedName ?? bundleID, label: label, index: 0, frame: frame)
            }.sorted { $0.frame.minX < $1.frame.minX }
            if !mine.isEmpty { found.append(app.processIdentifier) }
            for (i, var item) in mine.enumerated() {
                item.index = i
                items.append(item)
            }
        }
        if known == nil { appsWithIcons = found }
        return items.sorted { $0.frame.minX < $1.frame.minX }
    }

    /// Apple's own icons, which stay where they are: everything from MenuBarAgent, Control Center,
    /// the input menu and the like. Apple's apps (Music, say) count as apps.
    static func isSystem(_ item: MenuBarItem) -> Bool {
        let agents: Set = ["com.apple.MenuBarAgent", "com.apple.controlcenter", "com.apple.systemuiserver",
                           "com.apple.TextInputMenuAgent", "com.apple.Spotlight", "com.apple.Siri",
                           "com.apple.weather.menu", "com.apple.AirPlayUIAgent", "com.apple.wifi.WiFiAgent"]
        return agents.contains(item.bundleID)
    }

    static func frame(of element: AXUIElement) -> CGRect? {
        guard let position: AXValue = attribute(element, kAXPositionAttribute),
              let size: AXValue = attribute(element, kAXSizeAttribute) else { return nil }
        var point = CGPoint.zero, extent = CGSize.zero
        AXValueGetValue(position, .cgPoint, &point)
        AXValueGetValue(size, .cgSize, &extent)
        return CGRect(origin: point, size: extent)
    }

    private static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }
}
