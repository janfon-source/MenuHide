import AppKit

/// Lists the other apps' menu bar icons in two groups, hidden and always shown, each left to
/// right as on the menu bar. Drag a row to reorder it or to move it to the other group, or tick
/// Always Show; Apply moves the icons on the menu bar to match.
final class SettingsWindow: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    /// Moves the icons into place, then calls back on the main thread with the keys it couldn't place.
    var onApply: ((_ entries: [Entry], _ done: @escaping ([String]) -> Void) -> Void)?

    private enum Row {
        case header(alwaysShown: Bool)
        case entry(Entry)
    }

    private var rows: [Row] = []
    private let table = NSTableView()
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let permission = NSStackView()
    private let permissionLabel = NSTextField(wrappingLabelWithString: "")
    private let permissionButton = NSButton()
    private let hint = NSTextField(wrappingLabelWithString: "")
    private let reloadButton = NSButton()
    private let applyButton = NSButton()
    private static let rowType = NSPasteboard.PasteboardType("com.jeff.menuhide.row")

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 480),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.minSize = NSSize(width: 380, height: 320)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        build()
        relabel()
        NotificationCenter.default.addObserver(forName: Language.didChange, object: nil, queue: .main) { [weak self] _ in
            self?.relabel()
            self?.table.reloadData()
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        reload()
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: Building

    private func build() {
        hint.textColor = .secondaryLabelColor
        hint.font = .systemFont(ofSize: 12)

        permissionLabel.font = .systemFont(ofSize: 12)
        permissionButton.bezelStyle = .rounded
        permissionButton.target = self
        permissionButton.action = #selector(askPermission(_:))
        permission.orientation = .vertical
        permission.alignment = .leading
        permission.setViews([permissionLabel, permissionButton], in: .leading)

        let column = NSTableColumn(identifier: .init("icon"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 28
        table.style = .inset
        table.dataSource = self
        table.delegate = self
        table.registerForDraggedTypes([Self.rowType])
        table.draggingDestinationFeedbackStyle = .gap
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        for (button, action) in [(reloadButton, #selector(reloadClicked(_:))), (applyButton, #selector(applyClicked(_:)))] {
            button.bezelStyle = .rounded
            button.target = self
            button.action = action
        }
        applyButton.keyEquivalent = "\r"
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let buttons = NSStackView(views: [statusLabel, NSView(), reloadButton, applyButton])

        let stack = NSStackView(views: [hint, permission, scroll, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            hint.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32),
            permission.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32),
        ])
        scroll.setContentHuggingPriority(.init(1), for: .vertical)
        window?.contentView = content
    }

    private func relabel() {
        window?.title = tr("隨手藏設定", "MenuHide Settings")
        hint.stringValue = tr("由左到右對應選單列上的順序。拖曳可以調整順序，或拖到另一區；「隱藏」的圖示收起時會收進系統的 « 選單，「一直顯示」的不會。按「套用到選單列」後，隨手藏會用 ⌘ 拖曳把圖示一個個移到位，過程中請不要移動滑鼠。",
                              "Left to right as on the menu bar. Drag to reorder, or into the other group. When collapsed, hidden icons go into the system’s « menu; always-shown ones stay. Apply to Menu Bar ⌘-drags each icon into place, so leave the mouse alone while it works.")
        permissionLabel.stringValue = tr("隨手藏需要「輔助使用」權限，才能讀取和移動選單列上的圖示。允許後請按「重新讀取」。",
                                         "MenuHide needs Accessibility access to read and move menu bar icons. Once it’s allowed, click Reload.")
        permissionButton.title = tr("開啟「輔助使用」設定…", "Open Accessibility Settings…")
        reloadButton.title = tr("重新讀取", "Reload")
        applyButton.title = tr("套用到選單列", "Apply to Menu Bar")
    }

    // MARK: Data

    private func reload() {
        permission.isHidden = MenuBar.isTrusted
        applyButton.isEnabled = MenuBar.isTrusted
        let entries = MenuBar.isTrusted ? Layout.entries() : []
        setRows(entries)
        statusLabel.stringValue = MenuBar.isTrusted && entries.isEmpty
            ? tr("選單列上沒有其他 App 的圖示。", "No other apps’ icons on the menu bar.") : ""
    }

    private func setRows(_ entries: [Entry]) {
        rows = [.header(alwaysShown: false)] + entries.filter { !$0.alwaysShown }.map(Row.entry)
            + [.header(alwaysShown: true)] + entries.filter(\.alwaysShown).map(Row.entry)
        table.reloadData()
    }

    /// The entries as listed, with each one's group taken from the header above it.
    private var entries: [Entry] {
        var shown = false
        return rows.compactMap { row in
            switch row {
            case .header(let alwaysShown): shown = alwaysShown; return nil
            case .entry(var entry): entry.alwaysShown = shown; return entry
            }
        }
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        if case .header = rows[row] { return true }
        return false
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        if case .header = rows[row] { return false }
        return true
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch rows[row] {
        case .header(let alwaysShown):
            let label = NSTextField(labelWithString: alwaysShown ? tr("一直顯示", "Always Shown")
                                                                 : tr("隱藏", "Hidden"))
            label.font = .boldSystemFont(ofSize: 12)
            return label
        case .entry(let entry):
            let icon = NSImageView(image: entry.icon ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil)!)
            icon.widthAnchor.constraint(equalToConstant: 18).isActive = true
            icon.heightAnchor.constraint(equalToConstant: 18).isActive = true
            let name = NSTextField(labelWithString: entry.title)
            name.lineBreakMode = .byTruncatingTail
            name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            let check = NSButton(checkboxWithTitle: tr("一直顯示", "Always Show"), target: self, action: #selector(alwaysShowClicked(_:)))
            check.state = entry.alwaysShown ? .on : .off
            check.tag = row
            let spacer = NSView()
            spacer.setContentHuggingPriority(.init(1), for: .horizontal)
            return NSStackView(views: [icon, name, spacer, check])
        }
    }

    @objc private func alwaysShowClicked(_ sender: NSButton) {
        guard rows.indices.contains(sender.tag), case .entry(var entry) = rows[sender.tag] else { return }
        // Ticking moves it to the end of the other group.
        var list = entries
        list.removeAll { $0.key == entry.key }
        entry.alwaysShown = sender.state == .on
        list.append(entry)
        setRows(list.filter { !$0.alwaysShown } + list.filter(\.alwaysShown))
    }

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard case .entry = rows[row] else { return nil }
        let item = NSPasteboardItem()
        item.setString(String(row), forType: Self.rowType)
        return item
    }

    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int,
                   proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        // Between rows, and never above the first group's header.
        guard dropOperation == .above, row >= 1 else { return [] }
        return .move
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int,
                   dropOperation: NSTableView.DropOperation) -> Bool {
        guard let string = info.draggingPasteboard.pasteboardItems?.first?.string(forType: Self.rowType),
              let from = Int(string), rows.indices.contains(from) else { return false }
        let moving = rows.remove(at: from)
        rows.insert(moving, at: from < row ? row - 1 : row)
        setRows(entries)   // takes each row's group from the header above it
        return true
    }

    // MARK: Actions

    @objc private func askPermission(_ sender: Any?) {
        MenuBar.requestAccess()
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func reloadClicked(_ sender: Any?) { reload() }

    @objc private func applyClicked(_ sender: Any?) {
        let list = entries
        Layout.save(list)
        applyButton.isEnabled = false
        reloadButton.isEnabled = false
        statusLabel.stringValue = tr("正在移動圖示，請不要移動滑鼠…", "Moving icons; leave the mouse alone…")
        onApply?(list) { [weak self] failed in
            guard let self else { return }
            self.applyButton.isEnabled = true
            self.reloadButton.isEnabled = true
            self.reload()
            let names = failed.compactMap { key in list.first { $0.key == key }?.appName }.joined(separator: tr("、", ", "))
            self.statusLabel.stringValue = failed.isEmpty ? tr("已套用。", "Done.")
                : tr("\(names) 的圖示沒能移到位（在系統設定裡關掉了顯示的圖示無法移動），可以再按一次「套用到選單列」。",
                     "Couldn’t move \(names) into place (icons turned off in System Settings can’t be moved); try Apply again.")
        }
    }
}
