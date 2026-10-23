import AppKit

/// An icon as the settings list shows it.
struct Entry {
    let key: String
    let bundleID: String
    let appName: String
    let label: String
    let icon: NSImage?
    let isSystem: Bool
    var alwaysShown: Bool

    var title: String { label.isEmpty || label == appName ? appName : "\(appName) — \(label)" }
}

/// The order and settings people chose for the icons, kept by each icon's key.
enum Layout {
    private enum Keys {
        static let order = "menuhide.order"
        static let alwaysShown = "menuhide.alwaysShown"
    }

    /// Every icon key seen, left to right, hidden ones and shown ones mixed as they were listed.
    static var order: [String] {
        get { UserDefaults.standard.stringArray(forKey: Keys.order) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: Keys.order) }
    }

    static var alwaysShown: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: Keys.alwaysShown) ?? []) }
        set { UserDefaults.standard.set(newValue.sorted(), forKey: Keys.alwaysShown) }
    }

    /// The menu bar's icons now, other apps' and Apple's (but not the ones that can't move): those
    /// already arranged in their saved order, then new ones where they are. An icon not arranged
    /// before starts as always shown if it's showing now (right of the divider, which must be
    /// expanded), so nothing vanishes unasked.
    static func entries() -> [Entry] {
        // Icons turned off in System Settings can't be moved, so they aren't listed.
        let items = MenuBar.items(rescan: true).filter { !MenuBar.isFixed($0) && $0.pid != getpid() && MenuBar.isShowing($0) }
        let saved = order, shown = alwaysShown
        let dividerRight = Arranger.ownFrames()?.divider.maxX ?? 0
        let placed = items.sorted { a, b in
            let i = saved.firstIndex(of: a.key) ?? Int.max, j = saved.firstIndex(of: b.key) ?? Int.max
            return i != j ? i < j : a.frame.minX < b.frame.minX
        }
        return placed.map { item in
            Entry(key: item.key, bundleID: item.bundleID, appName: item.isSystem ? item.label : item.appName,
                  label: item.isSystem ? "" : item.label, icon: item.icon, isSystem: item.isSystem,
                  alwaysShown: saved.contains(item.key) ? shown.contains(item.key) : item.frame.minX >= dividerRight)
        }
    }

    /// Remembers `entries` as the chosen layout, keeping the places of icons not running now.
    static func save(_ entries: [Entry]) {
        let keys = entries.map(\.key)
        order = keys + order.filter { !keys.contains($0) }
        alwaysShown = Set(entries.filter(\.alwaysShown).map(\.key))
            .union(alwaysShown.subtracting(keys))
    }

    /// Left to right on the menu bar: the hidden icons, the divider, then the always-shown ones.
    static func slots(for entries: [Entry]) -> [Arranger.Slot] {
        entries.filter { !$0.alwaysShown }.map { .icon($0.key) } + [.divider]
            + entries.filter(\.alwaysShown).map { .icon($0.key) }
    }
}
