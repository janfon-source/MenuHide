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
        var failed: [String] = []
        let cursor = CGEvent(source: nil)?.location
        defer { if let cursor { post(.mouseMoved, at: cursor) } }

        _ = MenuBar.items(rescan: true)
        guard var anchor = ownFrames()?.toggle else { return [] }
        for slot in slots.reversed() {
            guard let frame = currentFrame(of: slot) else { continue }   // app not running
            if !isJustLeft(frame, of: anchor) {
                // Dropped on the anchor's left edge it lands just left of it; failing that, try
                // half an icon further left.
                for dropX in [anchor.minX - 3, anchor.minX - frame.width / 2] {
                    guard let now = currentFrame(of: slot) else { break }
                    drag(from: CGPoint(x: now.midX, y: now.midY), to: CGPoint(x: dropX, y: now.midY))
                    Thread.sleep(forTimeInterval: 0.35)
                    if let moved = currentFrame(of: slot),
                       isJustLeft(moved, of: anchor) { break }
                }
            }
            guard let placed = currentFrame(of: slot) else { continue }
            if !isJustLeft(placed, of: anchor), case .icon(let key) = slot {
                failed.append(key)
            }
            anchor = placed
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

    private static func currentFrame(of slot: Slot) -> CGRect? {
        switch slot {
        case .divider: return ownFrames()?.divider
        case .icon(let key): return MenuBar.items().first { $0.key == key }?.frame
        }
    }

    /// Whether `frame` sits right next to the anchor, on its left. Icons are a few points apart;
    /// anything between them would leave a wider gap. Other icons' frames aren't consulted, since
    /// an app's icon turned off in System Settings still reports a frame, wherever it last was.
    private static func isJustLeft(_ frame: CGRect, of anchor: CGRect) -> Bool {
        frame.maxX <= anchor.minX + 3 && anchor.minX - frame.maxX < 18
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
