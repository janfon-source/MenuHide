import AppKit

/// Puts the menu bar's icons in a given order by ⌘-dragging them, as a person would: macOS has
/// no way to move another app's icon otherwise. Posting the mouse events needs Accessibility
/// access. The icons are placed right to left, each just left of the one placed before it,
/// starting from MenuHide's own button.
enum Arranger {
    /// Where an item should go: an icon by its key, or MenuHide's divider.
    enum Slot: Equatable {
        case icon(String)
        case divider
    }

    /// Lays the icons out as `slots`, left to right, ending just left of MenuHide's button, which
    /// must be showing its divider. Runs off the main thread, waiting for the menu bar to settle
    /// after each move. Returns the keys it couldn't place.
    static func arrange(_ slots: [Slot]) -> [String] {
        let cursor = CGEvent(source: nil)?.location
        defer { if let cursor { post(.mouseMoved, at: cursor) } }
        _ = MenuBar.items(rescan: true)
        // Now and then a move knocks an icon placed earlier out of line; a second pass, which
        // skips every icon already in place, puts those right.
        var failed = place(slots)
        if !failed.isEmpty { failed = place(slots) }
        return failed
    }

    /// One pass of `arrange`: returns the keys not in place afterwards.
    private static func place(_ slots: [Slot]) -> [String] {
        // Right to left, each just left of the one placed before it, starting from the button.
        var anchor = Target.toggle
        for slot in slots.reversed() {
            guard currentFrame(of: .slot(slot)) != nil else { continue }   // app not running
            for attempt in 0..<4 {
                guard let now = currentFrame(of: .slot(slot)), let target = currentFrame(of: anchor) else { break }
                if isJustLeft(now, of: target) { break }
                // Where to let go so it lands just left of the anchor. While an icon is dragged
                // the others slide aside, and one dragged rightwards leaves a gap that closes,
                // pulling the anchor left by about the icon's width; so try a few places.
                let rightwards = now.midX < target.minX
                let dropX: CGFloat
                switch attempt {
                case 0: dropX = rightwards ? target.minX - now.width - 4 : target.minX - 3
                case 1: dropX = rightwards ? target.minX - 3 : target.minX - now.width / 2
                case 2: dropX = target.minX - now.width / 2
                default: dropX = target.minX + 2
                }
                drag(from: CGPoint(x: now.midX, y: now.midY), to: CGPoint(x: dropX, y: now.midY))
                Thread.sleep(forTimeInterval: 0.35)
            }
            anchor = .slot(slot)
        }

        // Check the whole row once it has settled: each in place just left of the next.
        Thread.sleep(forTimeInterval: 0.3)
        var failed: [String] = []
        var right = Target.toggle
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

    /// Something to find on the menu bar: MenuHide's button, or a slot.
    private enum Target {
        case toggle
        case slot(Slot)
    }

    private static func currentFrame(of target: Target) -> CGRect? {
        switch target {
        case .toggle: return ownFrames()?.toggle
        case .slot(.divider): return ownFrames()?.divider
        case .slot(.icon(let key)): return MenuBar.items().first { $0.key == key }?.frame
        }
    }

    /// Keeps MenuHide's button right of every other app's icon: any icon that has ended up right
    /// of it (a new app's, or one ⌘-dragged there) moves to just left of it, in among the
    /// always-shown icons, keeping their order. (The button itself won't follow a synthesized
    /// drag, so the icons move instead.) Runs off the main thread. Returns whether all is in place.
    @discardableResult
    static func keepToggleRightmost() -> Bool {
        let cursor = CGEvent(source: nil)?.location
        defer { if let cursor { post(.mouseMoved, at: cursor) } }
        var rescan = true
        // Left to right, each dropped just left of the button, so they keep their order.
        for _ in 0..<12 {
            guard let toggle = ownFrames()?.toggle else { return false }
            guard let next = appIcons(rescan: rescan).filter({ $0.minX > toggle.minX }).min(by: { $0.minX < $1.minX })
            else { return true }
            rescan = false
            drag(from: CGPoint(x: next.midX, y: next.midY), to: CGPoint(x: toggle.minX - 3, y: next.midY))
            Thread.sleep(forTimeInterval: 0.35)
        }
        return false
    }

    /// Where the other apps' icons that are really on the menu bar are (not ones turned off in
    /// System Settings, which still report a frame).
    private static func appIcons(rescan: Bool) -> [CGRect] {
        MenuBar.items(rescan: rescan)
            .filter { !MenuBar.isSystem($0) && $0.pid != getpid() && MenuBar.isShowing($0) }
            .map(\.frame)
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
