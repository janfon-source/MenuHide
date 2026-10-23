import AppKit

/// One icon in the menu bar's right-hand side, as the Accessibility API reports it.
struct MenuBarItem {
    let element: AXUIElement
    let pid: pid_t
    let bundleID: String
    let appName: String
    /// What the item calls itself, if anything (often nothing for an app's icon).
    let label: String
    /// The system's name for one of its own icons, such as com.apple.menuextra.wifi.
    let identifier: String?
    /// Its place among the same app's items, left to right, from 0: an app can have several.
    var index: Int
    let frame: CGRect

    /// Stays the same for the same icon across launches, to remember its place and setting by.
    var key: String { identifier ?? "\(bundleID)#\(index)" }

    var isSystem: Bool { MenuBar.isSystem(self) }

    /// The app's icon, or for one of Apple's own a symbol like the one on the menu bar.
    var icon: NSImage? {
        if isSystem {
            let name = identifier.flatMap { id in MenuBar.symbols.first { id.contains($0.key) }?.value } ?? "gearshape"
            return NSImage(systemSymbolName: name, accessibilityDescription: nil)
        }
        return NSRunningApplication(processIdentifier: pid)?.icon
    }
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
                // The system's icons are groups with the named item inside.
                let named = (attribute(child, kAXChildrenAttribute) as [AXUIElement]?)?.first.flatMap {
                    (attribute($0, "AXIdentifier") as String?) == nil ? nil : $0
                } ?? child
                let identifier: String? = attribute(named, "AXIdentifier")
                // "Wi‑Fi，已連接，3格": the name, without the state after it.
                let description = (attribute(named, kAXDescriptionAttribute) as String?)?
                    .components(separatedBy: CharacterSet(charactersIn: "，,")).first ?? ""
                let label = description.isEmpty ? attribute(named, kAXTitleAttribute) ?? "" : description
                return MenuBarItem(element: child, pid: app.processIdentifier, bundleID: bundleID,
                                   appName: app.localizedName ?? bundleID, label: label,
                                   identifier: identifier.flatMap { $0.isEmpty ? nil : $0 }, index: 0, frame: frame)
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

    /// Whether the icon is really on the menu bar. An icon turned off in System Settings still
    /// reports a frame, wherever it last was, on top of some other icon; what's actually at the
    /// middle of that frame tells them apart.
    static func isShowing(_ item: MenuBarItem) -> Bool {
        var hit: AXUIElement?
        let systemWide = AXUIElementCreateSystemWide()
        guard AXUIElementCopyElementAtPosition(systemWide, Float(item.frame.midX), Float(item.frame.midY), &hit) == .success,
              var element = hit else { return false }
        // The hit may be something inside the icon; walk up to it.
        for _ in 0..<4 {
            if CFEqual(element, item.element) { return true }
            guard let parent: AXUIElement = attribute(element, kAXParentAttribute) else { return false }
            element = parent
        }
        return false
    }

    /// Apple's icons that can't be moved: the clock and Control Center stay at the right end, and
    /// the « menu (no name) is where the hidden icons go.
    static func isFixed(_ item: MenuBarItem) -> Bool {
        guard item.isSystem else { return false }
        guard let id = item.identifier else { return item.bundleID == "com.apple.MenuBarAgent" }
        return id.hasSuffix(".clock") || id.hasSuffix(".controlcenter")
    }

    /// Symbols for Apple's icons in the settings list, by part of their identifier.
    static let symbols: [String: String] = [
        "wifi": "wifi", "sound": "speaker.wave.2", "volume": "speaker.wave.2", "bluetooth": "dot.radiowaves.left.and.right",
        "battery": "battery.100", "now-playing": "play.circle", "focus": "moon", "screen-mirroring": "rectangle.on.rectangle",
        "display": "display", "airdrop": "airplayaudio", "keyboard": "keyboard", "spotlight": "magnifyingglass",
        "siri": "mic", "timemachine": "clock.arrow.circlepath", "user": "person.crop.circle", "vpn": "network",
        "accessibility": "accessibility", "stage": "rectangle.3.group", "weather": "cloud.sun",
    ]

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
