import AppKit

/// The About panel: who made it, and a link to the repository with GitHub's mark before it.
enum About {
    static func show() {
        NSApp.activate(ignoringOtherApps: true)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let credits = NSMutableAttributedString(string: "Created by : Jeff Lee\n", attributes: [
            .font: font,
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph,
        ])
        let icon = NSTextAttachment()
        icon.image = githubMark
        // Sits the mark on the baseline at about the height of a capital letter.
        let side = font.capHeight + 3
        icon.bounds = NSRect(x: 0, y: (font.capHeight - side) / 2, width: side, height: side)
        let iconString = NSMutableAttributedString(attachment: icon)
        iconString.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: iconString.length))
        credits.append(iconString)
        // "account / repo", as GitHub shows it, with only the repository name linked.
        credits.append(NSAttributedString(string: " janfon-source / ", attributes: [
            .font: font,
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph,
        ]))
        credits.append(NSAttributedString(string: "MenuHide", attributes: [
            .font: font,
            .link: URL(string: "https://github.com/janfon-source/MenuHide")!,
            .paragraphStyle: paragraph,
        ]))
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: tr("隨手藏", "MenuHide"), .credits: credits])
    }

    /// GitHub's mark (the Octicon mark-github, 16×16), drawn in the label color so it follows
    /// light and dark appearance.
    private static let githubMark: NSImage = {
        let svg = "M8 0c4.42 0 8 3.58 8 8a8.013 8.013 0 0 1-5.45 7.59c-.4.08-.55-.17-.55-.38 0-.27.01-1.13.01-2.2 0-.75-.25-1.23-.54-1.48 1.78-.2 3.65-.88 3.65-3.95 0-.88-.31-1.59-.82-2.15.08-.2.36-1.02-.08-2.12 0 0-.67-.22-2.2.82-.64-.18-1.32-.27-2-.27-.68 0-1.36.09-2 .27-1.53-1.03-2.2-.82-2.2-.82-.44 1.1-.16 1.92-.08 2.12-.51.56-.82 1.28-.82 2.15 0 3.06 1.86 3.75 3.64 3.95-.23.2-.44.55-.51 1.07-.46.21-1.61.55-2.33-.66-.15-.24-.6-.83-1.23-.82-.67.01-.27.38.01.53.34.19.73.9.82 1.13.16.45.68 1.31 2.69.94 0 .67.01 1.3.01 1.49 0 .21-.15.45-.55.38A7.995 7.995 0 0 1 0 8c0-4.42 3.58-8 8-8Z"
        let path = svgPath(svg)
        return NSImage(size: NSSize(width: 16, height: 16), flipped: true) { _ in
            NSColor.labelColor.setFill()
            path.fill()
            return true
        }
    }()

    /// Builds a path from SVG path data, enough for the GitHub mark: M, C, A and Z, absolute or
    /// relative, with repeated arguments.
    private static func svgPath(_ data: String) -> NSBezierPath {
        let path = NSBezierPath()
        let scanner = Scanner(string: data)
        scanner.charactersToBeSkipped = CharacterSet(charactersIn: " ,\n")
        var command: Character = "M"
        var current = NSPoint.zero
        var start = NSPoint.zero
        func number() -> CGFloat { CGFloat(scanner.scanDouble() ?? 0) }
        // Arc flags may run together with the next number ("0 1-5.45"), so read them one digit at a time.
        func flag() -> Bool {
            _ = scanner.scanCharacters(from: CharacterSet(charactersIn: " ,"))
            return scanner.scanCharacter() == "1"
        }
        while !scanner.isAtEnd {
            let index = scanner.currentIndex
            if let c = scanner.scanCharacter(), c.isLetter {
                command = c
            } else {
                scanner.currentIndex = index
            }
            let relative = command.isLowercase
            let base = relative ? current : .zero
            switch command.uppercased() {
            case "M":
                current = NSPoint(x: base.x + number(), y: base.y + number())
                start = current
                path.move(to: current)
                command = relative ? "l" : "L"
            case "L":
                current = NSPoint(x: base.x + number(), y: base.y + number())
                path.line(to: current)
            case "C":
                let c1 = NSPoint(x: base.x + number(), y: base.y + number())
                let c2 = NSPoint(x: base.x + number(), y: base.y + number())
                current = NSPoint(x: base.x + number(), y: base.y + number())
                path.curve(to: current, controlPoint1: c1, controlPoint2: c2)
            case "A":
                var r = number()
                _ = number()  // The mark's arcs are circles, so the second radius and rotation are ignored.
                _ = number()
                let large = flag(), sweep = flag()
                let end = NSPoint(x: base.x + number(), y: base.y + number())
                // The center, from the SVG endpoint parameterization for a circle.
                let mid = NSPoint(x: (current.x + end.x) / 2, y: (current.y + end.y) / 2)
                let dx = end.x - current.x, dy = end.y - current.y
                let half = hypot(dx, dy) / 2
                r = max(r, half)
                let h = sqrt(max(r * r - half * half, 0)) * (large == sweep ? -1 : 1)
                let center = NSPoint(x: mid.x - h * dy / (2 * half), y: mid.y + h * dx / (2 * half))
                let a1 = atan2(current.y - center.y, current.x - center.x) * 180 / .pi
                let a2 = atan2(end.y - center.y, end.x - center.x) * 180 / .pi
                path.appendArc(withCenter: center, radius: r, startAngle: a1, endAngle: a2, clockwise: !sweep)
                current = end
            case "Z":
                path.close()
                current = start
            default:
                return path
            }
        }
        return path
    }
}
