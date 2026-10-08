import AppKit

class StatusBarController: NSObject {
    var onIdleBarChanged: ((Bool) -> Void)?
    var onHotkeyChanged: ((HotkeyConfig) -> Void)?
    var onModelSelected: ((String) -> Void)?
    private var statusItem: NSStatusItem
    private var animationTimer: Timer?
    private var animationFrame = 0
    private var animationFrames: [NSImage] = []
    private var downloadProgress: String?
    private let hotkeyChoices: [(title: String, key: String)] = [
        ("Fn / Globe", "fn"),
        ("Right Option", "rightoption"),
        ("F5", "f5"),
        ("Right Command", "rightcmd"),
    ]
    private let modelChoices = ["tiny.en", "tiny", "base.en", "base",
                                "small.en", "small", "medium.en", "medium", "large"]

    enum State {
        case idle
        case recording
        case transcribing
        case downloading
        case waitingForPermission
    }

    var state: State = .idle {
        didSet { updateIcon(); buildMenu() }
    }

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.image = StatusBarController.drawLogo(active: false)
            button.image?.isTemplate = true
        }

        buildMenu()
    }

    func updateDownloadProgress(_ text: String?) {
        downloadProgress = text
        buildMenu()
    }

    func buildMenu() {
        let config = Config.load()
        let hotkeyDesc = hotkeyChoices.first { choice in
            guard let parsed = KeyCodes.parse(choice.key) else { return false }
            return parsed.keyCode == config.hotkey.keyCode && parsed.modifiers == config.hotkey.modifiers
        }?.title ?? KeyCodes.describe(keyCode: config.hotkey.keyCode, modifiers: config.hotkey.modifiers)

        let menu = NSMenu()

        let titleItem = NSMenuItem(title: "OpenWispr v\(OpenWispr.version)", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        menu.addItem(NSMenuItem.separator())

        if let progress = downloadProgress {
            let dlItem = NSMenuItem(title: progress, action: nil, keyEquivalent: "")
            dlItem.isEnabled = false
            menu.addItem(dlItem)
            menu.addItem(NSMenuItem.separator())
        }

        let stateText: String
        switch state {
        case .idle: stateText = "Ready"
        case .recording: stateText = "Recording..."
        case .transcribing: stateText = "Transcribing..."
        case .downloading: stateText = "Downloading model..."
        case .waitingForPermission: stateText = "Waiting for Accessibility permission..."
        }
        let stateItem = NSMenuItem(title: stateText, action: nil, keyEquivalent: "")
        stateItem.isEnabled = false
        menu.addItem(stateItem)

        menu.addItem(NSMenuItem.separator())

        let hotkeyItem = NSMenuItem(title: "Hotkey: \(hotkeyDesc)", action: nil, keyEquivalent: "")
        let hotkeyMenu = NSMenu(title: "Hotkey")
        let hasSelectedChoice = hotkeyChoices.contains { choice in
            guard let parsed = KeyCodes.parse(choice.key) else { return false }
            return parsed.keyCode == config.hotkey.keyCode && parsed.modifiers == config.hotkey.modifiers
        }
        if !hasSelectedChoice {
            let customItem = NSMenuItem(title: "Current: \(hotkeyDesc)", action: nil, keyEquivalent: "")
            customItem.state = .on
            hotkeyMenu.addItem(customItem)
            hotkeyMenu.addItem(.separator())
        }
        for choice in hotkeyChoices {
            guard let parsed = KeyCodes.parse(choice.key) else { continue }
            let item = NSMenuItem(title: choice.title, action: #selector(selectHotkey(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = choice.key
            item.state = parsed.keyCode == config.hotkey.keyCode && parsed.modifiers == config.hotkey.modifiers ? .on : .off
            item.isEnabled = state == .idle
            hotkeyMenu.addItem(item)
        }
        menu.setSubmenu(hotkeyMenu, for: hotkeyItem)
        menu.addItem(hotkeyItem)

        let modelItem = NSMenuItem(title: "Model: \(config.modelSize)", action: nil, keyEquivalent: "")
        let modelMenu = NSMenu(title: "Model")
        for size in modelChoices {
            let installed = Transcriber.modelExists(modelSize: size)
            let languageNote = size.hasSuffix(".en") ? " (English only)" : ""
            let label = "\(size)\(languageNote)" + (installed ? "" : " — download")
            let item = NSMenuItem(title: label, action: #selector(selectModel(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = size
            item.state = size == config.modelSize ? .on : .off
            item.isEnabled = state == .idle && downloadProgress == nil
            modelMenu.addItem(item)
        }
        menu.setSubmenu(modelMenu, for: modelItem)
        menu.addItem(modelItem)

        menu.addItem(NSMenuItem.separator())
        let idleBarItem = NSMenuItem(title: "Show Standby Bar", action: #selector(toggleIdleBar), keyEquivalent: "")
        idleBarItem.target = self
        idleBarItem.state = config.isIdleBarEnabled ? .on : .off
        menu.addItem(idleBarItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    @objc private func toggleIdleBar() {
        setIdleBarEnabled(!Config.load().isIdleBarEnabled)
    }

    @objc private func selectHotkey(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String,
              let parsed = KeyCodes.parse(key) else { return }
        var config = Config.load()
        config.hotkey = HotkeyConfig(keyCode: parsed.keyCode, modifiers: parsed.modifiers)
        do {
            try config.save()
            onHotkeyChanged?(config.hotkey)
            buildMenu()
        } catch {
            showSettingError(error)
        }
    }

    @objc private func selectModel(_ sender: NSMenuItem) {
        guard let size = sender.representedObject as? String else { return }
        onModelSelected?(size)
    }

    func setIdleBarEnabled(_ enabled: Bool) {
        var config = Config.load()
        guard config.isIdleBarEnabled != enabled else { return }
        config.showIdleBar = enabled
        do {
            try config.save()
            onIdleBarChanged?(config.isIdleBarEnabled)
            buildMenu()
        } catch {
            showSettingError(error)
        }
    }

    func showSettingError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Unable to change OpenWispr settings"
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }

    private func updateIcon() {
        stopAnimation()

        switch state {
        case .idle:
            setIcon(StatusBarController.drawLogo(active: false))
        case .recording:
            startRecordingAnimation()
        case .transcribing:
            startTranscribingAnimation()
        case .downloading:
            startDownloadingAnimation()
        case .waitingForPermission:
            setIcon(StatusBarController.drawLockIcon())
        }
    }

    // MARK: - Recording animation: logo bounce

    private static let bounceFrameCount = 24

    private static func prerenderBounceFrames() -> [NSImage] {
        let count = bounceFrameCount
        let maxOffset: CGFloat = 3.0
        return (0..<count).map { frame in
            let t = Double(frame) / Double(count)
            let offset = maxOffset * CGFloat(sin(t * 2.0 * .pi))

            let size = NSSize(width: 18, height: 18)
            let image = NSImage(size: size, flipped: false) { rect in
                NSColor.black.setFill()

                let barWidth: CGFloat = 2.0
                let gap: CGFloat = 2.5
                let centerX = rect.midX
                let centerY = rect.midY + offset

                let heights: [CGFloat] = [4, 8, 12, 8, 4]
                let totalWidth = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
                let startX = centerX - totalWidth / 2

                for (i, height) in heights.enumerated() {
                    let x = startX + CGFloat(i) * (barWidth + gap)
                    let y = centerY - height / 2
                    let barRect = NSRect(x: x, y: y, width: barWidth, height: height)
                    NSBezierPath(roundedRect: barRect, xRadius: 1, yRadius: 1).fill()
                }
                return true
            }
            image.isTemplate = true
            return image
        }
    }

    private func startRecordingAnimation() {
        animationFrame = 0
        animationFrames = StatusBarController.prerenderBounceFrames()
        setIcon(animationFrames[0])

        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.animationFrame = (self.animationFrame + 1) % StatusBarController.bounceFrameCount
            self.setIcon(self.animationFrames[self.animationFrame])
        }
    }

    // MARK: - Transcribing animation: smooth wave dots

    private static let transcribeFrameCount = 30

    private static func prerenderTranscribeFrames() -> [NSImage] {
        let count = transcribeFrameCount
        let maxBounce: CGFloat = 3.0
        return (0..<count).map { frame in
            let t = Double(frame) / Double(count)

            let size = NSSize(width: 18, height: 18)
            let image = NSImage(size: size, flipped: false) { rect in
                NSColor.black.setFill()

                let dotSize: CGFloat = 3
                let gap: CGFloat = 3.0
                let centerY = rect.midY - dotSize / 2
                let totalWidth = 3 * dotSize + 2 * gap
                let startX = rect.midX - totalWidth / 2

                for i in 0..<3 {
                    let phase = t - Double(i) * 0.15
                    let bounce = maxBounce * CGFloat(max(0, sin(phase * 2.0 * .pi)))
                    let x = startX + CGFloat(i) * (dotSize + gap)
                    let y = centerY + bounce
                    let dotRect = NSRect(x: x, y: y, width: dotSize, height: dotSize)
                    NSBezierPath(ovalIn: dotRect).fill()
                }
                return true
            }
            image.isTemplate = true
            return image
        }
    }

    private func startTranscribingAnimation() {
        animationFrame = 0
        animationFrames = StatusBarController.prerenderTranscribeFrames()
        setIcon(animationFrames[0])

        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.animationFrame = (self.animationFrame + 1) % StatusBarController.transcribeFrameCount
            self.setIcon(self.animationFrames[self.animationFrame])
        }
    }

    // MARK: - Downloading animation: arrow moves down

    private func startDownloadingAnimation() {
        animationFrame = 0
        setIcon(StatusBarController.drawDownloadingFrame(0))

        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.animationFrame = (self.animationFrame + 1) % 3
            self.setIcon(StatusBarController.drawDownloadingFrame(self.animationFrame))
        }
    }

    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
        animationFrames = []
    }

    private func setIcon(_ image: NSImage) {
        DispatchQueue.main.async {
            if let button = self.statusItem.button {
                button.image = image
                button.image?.isTemplate = true
            }
        }
    }

    // MARK: - Custom drawn icons

    static func drawLogo(active: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            NSColor.black.setStroke()

            let barWidth: CGFloat = 2.0
            let gap: CGFloat = 2.5
            let centerX = rect.midX
            let centerY = rect.midY

            let heights: [CGFloat] = [4, 8, 12, 8, 4]
            let totalWidth = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
            let startX = centerX - totalWidth / 2

            for (i, height) in heights.enumerated() {
                let x = startX + CGFloat(i) * (barWidth + gap)
                let y = centerY - height / 2
                let barRect = NSRect(x: x, y: y, width: barWidth, height: height)
                if active {
                    NSBezierPath(roundedRect: barRect, xRadius: 1, yRadius: 1).fill()
                } else {
                    let path = NSBezierPath(roundedRect: barRect, xRadius: 1, yRadius: 1)
                    path.lineWidth = 1.2
                    path.stroke()
                }
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    static func drawDownloadingFrame(_ frame: Int) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setStroke()
            NSColor.black.setFill()

            let centerX = rect.midX

            let basePath = NSBezierPath()
            basePath.move(to: NSPoint(x: centerX - 5, y: 3))
            basePath.line(to: NSPoint(x: centerX + 5, y: 3))
            basePath.lineWidth = 1.5
            basePath.lineCapStyle = .round
            basePath.stroke()

            let arrowY: CGFloat = 14 - CGFloat(frame) * 2
            let arrowPath = NSBezierPath()
            arrowPath.move(to: NSPoint(x: centerX, y: arrowY))
            arrowPath.line(to: NSPoint(x: centerX, y: 6))
            arrowPath.lineWidth = 1.5
            arrowPath.lineCapStyle = .round
            arrowPath.stroke()

            let headPath = NSBezierPath()
            headPath.move(to: NSPoint(x: centerX - 3, y: 9))
            headPath.line(to: NSPoint(x: centerX, y: 5))
            headPath.line(to: NSPoint(x: centerX + 3, y: 9))
            headPath.lineWidth = 1.5
            headPath.lineCapStyle = .round
            headPath.lineJoinStyle = .round
            headPath.stroke()

            return true
        }
        image.isTemplate = true
        return image
    }

    static func drawLockIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setStroke()
            NSColor.black.setFill()

            let centerX = rect.midX

            let bodyRect = NSRect(x: centerX - 4, y: 2, width: 8, height: 7)
            NSBezierPath(roundedRect: bodyRect, xRadius: 1.5, yRadius: 1.5).fill()

            let shacklePath = NSBezierPath()
            shacklePath.move(to: NSPoint(x: centerX - 2.5, y: 9))
            shacklePath.curve(to: NSPoint(x: centerX + 2.5, y: 9),
                              controlPoint1: NSPoint(x: centerX - 2.5, y: 15),
                              controlPoint2: NSPoint(x: centerX + 2.5, y: 15))
            shacklePath.lineWidth = 1.8
            shacklePath.lineCapStyle = .round
            shacklePath.stroke()

            return true
        }
        image.isTemplate = true
        return image
    }
}
