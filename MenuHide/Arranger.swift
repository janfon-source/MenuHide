import AppKit

/// Puts the menu bar's icons in a given order by ⌘-dragging them, as a person would: macOS has
/// no way to move another app's icon otherwise. Posting the mouse events needs Accessibility
/// access. The icons are placed right to left, each just left of the one placed before it:
/// Apple's always-shown icons starting from Control Center (or the clock), which can't move;
/// then everything else starting from MenuHide's own button, which can't be moved by a drag
/// either but stays left of Control Center, so it ends up between the two.
enum Arranger {
    /// Where an item should go: an icon by its key, or MenuHide's divider.
    enum Slot: Equatable {
        case icon(String)
        case divider
    }

    /// Lays the icons out: `left`, left to right, ending just left of MenuHide's button (which
    /// must be showing its divider); then right of the button, `right`, ending just left of
    /// Control Center. Runs off the main thread, waiting for the menu bar to settle after each
    /// move. Returns the keys it couldn't place.
    static func arrange(left: [Slot], right: [String]) -> [String] {
        let cursor = CGEvent(source: nil)?.location
        defer { if let cursor { post(.mouseMoved, at: cursor) } }
        _ = MenuBar.items(rescan: true)
        let rightSlots = right.map(Slot.icon)
        // Now and then a move knocks an icon placed earlier out of line; a second pass, which
        // skips every icon already in place, puts those right.
        func pass() -> [String] { place(rightSlots, endingAt: .fixed) + place(left, endingAt: .toggle) }
        var failed = pass()
        if !failed.isEmpty { failed = pass() }
        return failed
    }

    /// One pass of `arrange` for one side: returns the keys not in place afterwards.
    private static func place(_ slots: [Slot], endingAt end: Target) -> [String] {
        // Right to left, each just left of the one placed before it.
        var anchor = end
        for slot in slots.reversed() {
            guard currentFrame(of: .slot(slot)) != nil else { continue }   // app not running
            for attempt in 0..<4 {
                guard let now = currentFrame(of: .slot(slot)), let target = currentFrame(of: anchor) else { break }
                if isJustLeft(now, of: target) { break }
                // Let go on the anchor's left edge; failing that, a little further either way.
                let dropX = target.minX + [-3, -now.width / 2, 2, -now.width][attempt]
                drag(from: CGPoint(x: now.midX, y: now.midY), to: CGPoint(x: dropX, y: now.midY))
                settle()
            }
            anchor = .slot(slot)
        }

        // Check the whole row once it has settled: each in place just left of the next.
        settle()
        var failed: [String] = []
        var right = end
        for slot in slots.reversed() {
            guard let frame = currentFrame(of: .slot(slot)) else { continue }
            if let next = currentFrame(of: right), !isJustLeft(frame, of: next), case .icon(let key) = slot {
                failed.append(key)
            }
            right = .slot(slot)
        }
        return failed
    }

    /// MenuHide's own button and divider, set at launch.
    static var ownItems: (toggle: NSStatusItem, divider: NSStatusItem)?

    /// Where MenuHide's own two items are, in the Accessibility API's coordinates (from the top
    /// left of the main screen) like everyone else's. An app can't read its own items through
    /// the Accessibility API, so this goes by their windows, on the main thread where they live.
    static func ownFrames() -> (toggle: CGRect, divider: CGRect)? {
        func read() -> (toggle: CGRect, divider: CGRect)? {
            guard let items = ownItems, let toggle = items.toggle.button?.window?.frame,
                  let divider = items.divider.button?.window?.frame,
                  let top = NSScreen.screens.first?.frame.maxY else { return nil }
            func flip(_ r: CGRect) -> CGRect { CGRect(x: r.minX, y: top - r.maxY, width: r.width, height: r.height) }
            return (flip(toggle), flip(divider))
        }
        return Thread.isMainThread ? read() : DispatchQueue.main.sync(execute: read)
    }

    /// Waits for the menu bar to stop moving after a drag: the icons slide into their new places,
    /// and read mid-slide they're in the wrong places, or not found at all. Two readings alike
    /// in a row means it has settled; a couple of seconds at most.
    private static func settle() {
        var last: [CGFloat] = []
        for _ in 0..<14 {
            Thread.sleep(forTimeInterval: 0.15)
            let now = MenuBar.items().map(\.frame.minX) + [ownFrames()?.toggle.minX ?? 0, ownFrames()?.divider.minX ?? 0]
            if now == last { return }
            last = now
        }
    }

    /// Something to find on the menu bar: MenuHide's button, or a slot.
    private enum Target {
        case toggle
        /// Control Center, or the clock: the leftmost of Apple's icons that can't move.
        case fixed
        case slot(Slot)
    }

    private static func currentFrame(of target: Target) -> CGRect? {
        switch target {
        case .toggle: return ownFrames()?.toggle
        case .fixed: return MenuBar.items().filter(MenuBar.isFixed).filter { $0.identifier != nil }.first?.frame
        case .slot(.divider): return ownFrames()?.divider
        case .slot(.icon(let key)): return MenuBar.items().first { $0.key == key }?.frame
        }
    }

    /// Keeps MenuHide's button between the apps' icons and Apple's: an app's icon that has ended
    /// up right of it (a new app's, or one ⌘-dragged there) moves to just left of it, and one of
    /// Apple's showing between the divider and the button moves to just right of it. Each keeps
    /// its order among the rest. (The button itself won't follow a synthesized drag, so the icons
    /// move instead.) Runs off the main thread. Returns whether all is in place.
    @discardableResult
    static func keepToggleBetween() -> Bool {
        let cursor = CGEvent(source: nil)?.location
        defer { if let cursor { post(.mouseMoved, at: cursor) } }
        _ = MenuBar.items(rescan: true)
        for _ in 0..<16 {
            guard let own = ownFrames() else { return false }
            let toggle = own.toggle
            let showing = MenuBar.items().filter { $0.pid != getpid() && !MenuBar.isFixed($0) && MenuBar.isShowing($0) }
            // Apps' icons right of the button: the leftmost first, dropped on the button's left edge.
            if let app = showing.filter({ !$0.isSystem && $0.frame.midX > toggle.midX }).min(by: { $0.frame.minX < $1.frame.minX }) {
                drag(from: CGPoint(x: app.frame.midX, y: app.frame.midY), to: CGPoint(x: toggle.minX - 3, y: app.frame.midY))
                settle()
                continue
            }
            // Apple's icons between the divider and the button (only while it shows its divider:
            // collapsed, it's off in the « menu): the rightmost first, dropped on the left edge of
            // whatever is just right of the button.
            let expanded = own.divider.width < 60
            if expanded, let apple = showing.filter({ $0.isSystem && $0.frame.midX > own.divider.midX && $0.frame.midX < toggle.midX })
                .max(by: { $0.frame.minX < $1.frame.minX }),
               let next = (showing.map(\.frame) + MenuBar.items().filter(MenuBar.isFixed).map(\.frame))
                .filter({ $0.minX > toggle.maxX - 1 }).min(by: { $0.minX < $1.minX }) {
                drag(from: CGPoint(x: apple.frame.midX, y: apple.frame.midY), to: CGPoint(x: next.minX - 3, y: apple.frame.midY))
                settle()
                continue
            }
            return true
        }
        return false
    }

    /// Whether `frame` is the icon immediately left of the anchor, among the icons really showing.
    private static func isJustLeft(_ frame: CGRect, of anchor: CGRect) -> Bool {
        guard frame.maxX <= anchor.minX + 3 else { return false }
        let between = showingFrames().filter { $0.midX > frame.midX + 1 && $0.midX < anchor.midX - 1 }
        return between.isEmpty
    }

    /// Every icon on the menu bar that is really showing, MenuHide's own included.
    private static func showingFrames() -> [CGRect] {
        var frames = MenuBar.items().filter { $0.pid != getpid() && MenuBar.isShowing($0) }.map(\.frame)
        if let own = ownFrames() { frames += [own.toggle, own.divider] }
        return frames
    }

    // MARK: Mouse events

    private static let source = CGEventSource(stateID: .hidSystemState)

    private static func drag(from start: CGPoint, to end: CGPoint) {
        post(.mouseMoved, at: start)
        post(.leftMouseDown, at: start, flags: .maskCommand)
        Thread.sleep(forTimeInterval: 0.12)
        let steps = 16
        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            post(.leftMouseDragged, at: CGPoint(x: start.x + (end.x - start.x) * t, y: start.y), flags: .maskCommand)
        }
        Thread.sleep(forTimeInterval: 0.12)
        post(.leftMouseUp, at: end, flags: .maskCommand)
    }

    private static func post(_ type: CGEventType, at point: CGPoint, flags: CGEventFlags = []) {
        guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else { return }
        event.flags = flags
        event.post(tap: .cghidEventTap)
        usleep(12_000)
    }
}
