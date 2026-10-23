import AppKit
import ServiceManagement

/// Menu bar app that tucks other apps' menu bar icons out of sight. Two items of its own do it:
/// a divider, and to its right a button. Icons left of the divider are the hidden ones; icons
/// between the divider and the button always show.
///
/// The menu bar lays its icons out from the right, and from the first one that doesn't fit,
/// that icon and every one left of it go into the system's « overflow menu. So to hide, the
/// divider grows wider than any free space could be, and takes the icons left of it along.
/// It mustn't be too wide, though: an icon wider than about half the screen is just left out,
/// and the ones beside it lay out as if it weren't there (measured on macOS 27: 650pt of a
/// 1440pt screen overflowed, 700pt was left out).
@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    // NSApplication holds its delegate weakly, so keep it alive here.
    private static var instance: AppDelegate?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        instance = delegate
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    private enum Keys {
        static let collapsed = "menuhide.collapsed"
    }

    /// Wider than the free space beside the app's menus usually is, and under the width at which
    /// the menu bar leaves an icon out.
    private var collapsedLength: CGFloat {
        let screen = toggle.button?.window?.screen ?? NSScreen.main
        return (screen?.frame.width ?? 1440) * 0.42
    }

    private var toggle: NSStatusItem!
    private var divider: NSStatusItem!
    private lazy var settings: SettingsWindow = {
        let window = SettingsWindow()
        window.onApply = { [weak self] entries, done in self?.arrange(entries, done: done) }
        return window
    }()

    private var collapsed = UserDefaults.standard.object(forKey: Keys.collapsed) as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(collapsed, forKey: Keys.collapsed)
            applyCollapsed()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A new item goes left of the existing ones, so the button comes first and the divider
        // lands to its left. The autosave names keep wherever they're ⌘-dragged to.
        toggle = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        toggle.autosaveName = "menuhide.toggle"
        if let button = toggle.button {
            button.target = self
            button.action = #selector(toggleClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        divider = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        divider.autosaveName = "menuhide.divider"
        divider.button?.image = Self.symbol("line.diagonal")
        Arranger.ownItems = (toggle, divider)

        applyCollapsed()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.applyCollapsed()
        }
        // MenuHide's button ends the other apps' icons: check once the menu bar has filled in,
        // and again whenever an app comes or goes, since a new icon may land right of it.
        keepToggleRightmost(after: 3)
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.keepToggleRightmost(after: 3)
            }
        }
        applyLanguage()
        NotificationCenter.default.addObserver(forName: Language.didChange, object: nil, queue: .main) { [weak self] _ in
            self?.applyLanguage()
        }
    }

    private func applyCollapsed() {
        divider.length = collapsed ? collapsedLength : NSStatusItem.variableLength
        divider.button?.image = collapsed ? nil : Self.symbol("line.diagonal")
        toggle.button?.image = Self.symbol(collapsed ? "chevron.left.circle" : "chevron.right.circle")
    }

    private func applyLanguage() {
        let tip = tr("隨手藏：按一下顯示或隱藏選單列圖示", "MenuHide: click to show or hide menu bar icons")
        toggle.button?.toolTip = tip
        toggle.button?.setAccessibilityLabel(tr("隨手藏", "MenuHide"))
        divider.button?.toolTip = tr("左邊的圖示會被隱藏；按住 ⌘ 拖曳圖示來調整", "Icons left of this are hidden; ⌘-drag icons to arrange them")
    }

    private static func symbol(_ name: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .medium))
        image?.isTemplate = true
        return image
    }

    // MARK: Clicks

    @objc private func toggleClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            collapsed.toggle()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        let item = menu.addItem(withTitle: collapsed ? tr("顯示隱藏的圖示", "Show Hidden Icons") : tr("隱藏圖示", "Hide Icons"),
                                action: #selector(toggleFromMenu), keyEquivalent: "")
        item.target = self
        menu.addItem(withTitle: tr("排序與設定…", "Arrange Icons…"), action: #selector(showSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        let languages = NSMenu()
        for language in Language.allCases {
            let item = languages.addItem(withTitle: language.title, action: #selector(selectLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = language.rawValue
            item.state = language == Language.current ? .on : .off
        }
        menu.addItem(withTitle: tr("語言", "Language"), action: nil, keyEquivalent: "").submenu = languages
        let login = menu.addItem(withTitle: tr("登入時自動開啟", "Open at Login"), action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(.separator())
        menu.addItem(withTitle: tr("結束隨手藏", "Quit MenuHide"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        toggle.menu = menu
        toggle.button?.performClick(nil)
        toggle.menu = nil
    }

    @objc private func toggleFromMenu() { collapsed.toggle() }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        try? service.status == .enabled ? service.unregister() : service.register()
    }

    // MARK: Arranging

    private var pendingCheck: DispatchWorkItem?
    private var arranging = false

    /// Moves the button right of the other apps' icons, `delay` seconds from now. Calls close
    /// together come to one check; none happens while arranging, or without Accessibility access.
    private func keepToggleRightmost(after delay: TimeInterval) {
        pendingCheck?.cancel()
        let check = DispatchWorkItem { [weak self] in
            guard let self, !self.arranging, MenuBar.isTrusted else { return }
            DispatchQueue.global(qos: .utility).async { Arranger.keepToggleRightmost() }
        }
        pendingCheck = check
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: check)
    }

    /// The settings list shows every icon, so the hidden ones come out of the « menu first.
    @objc private func showSettings() {
        collapsed = false
        if !MenuBar.isTrusted { MenuBar.requestAccess() }
        // Give the menu bar a moment to lay the icons out before reading where they are.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.settings.show() }
    }

    /// Moves the icons to match `entries`: shown, so every icon can be dragged, then put back
    /// the way it was.
    private func arrange(_ entries: [Entry], done: @escaping ([String]) -> Void) {
        let wasCollapsed = collapsed
        collapsed = false
        arranging = true
        let slots = Layout.slots(for: entries)
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.5) {
            let failed = Arranger.arrange(slots)
            Arranger.keepToggleRightmost()
            DispatchQueue.main.async {
                self.collapsed = wasCollapsed
                self.arranging = false
                done(failed)
            }
        }
    }

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let language = Language(rawValue: raw) else { return }
        Language.current = language
    }
}
