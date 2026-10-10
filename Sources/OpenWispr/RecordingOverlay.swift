import AppKit

/// A floating indicator that never takes keyboard focus. All calls are
/// made on the main queue, including microphone-level updates.
class RecordingOverlay: NSObject, NSWindowDelegate {
    var onCloseIdleBar: (() -> Void)?
    private var window: NSPanel?
    private var visualizer: VisualizerView?
    private var idleView: IdleBarView?
    private var isReady = false
    private var idleBarEnabled = false
    private var isRecording = false
    private var screenObserver: NSObjectProtocol?
    private var positionSaveTimer: Timer?
    private var isPositioning = false

    private static let overlaySize = NSSize(width: 148, height: 44)
    private static let idleSize = NSSize(width: 56, height: 14)
    private static let dockGap: CGFloat = 10

    override init() {
        super.init()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
    }

    deinit {
        positionSaveTimer?.invalidate()
        if let observer = screenObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func setReady(_ ready: Bool) {
        isReady = ready
        refresh()
    }

    func setIdleBarEnabled(_ enabled: Bool) {
        idleBarEnabled = enabled
        refresh()
    }

    func show() {
        isRecording = true
        visualizer?.reset()
        refresh()
    }

    /// Ending recording restores the optional standby indicator immediately,
    /// including while transcription is finishing.
    func hide() {
        isRecording = false
        refresh()
    }

    func update(level: Float) {
        guard isRecording else { return }
        visualizer?.push(level: level)
    }

    func resetPosition() {
        positionSaveTimer?.invalidate()
        positionSaveTimer = nil
        var config = Config.load()
        config.overlayPosition = nil
        do {
            try config.save()
            refresh()
        } catch {
            NSLog("OpenWispr: Could not reset overlay position: %@", error.localizedDescription)
        }
    }

    private func refresh() {
        guard isRecording || isReady else {
            visualizer?.isActive = false
            window?.orderOut(nil)
            return
        }
        buildIfNeeded()
        guard let window = window, let screen = window.screen ?? NSScreen.main else { return }
        let isVisible = isRecording || idleBarEnabled
        let size = isRecording ? Self.overlaySize : Self.idleSize
        let frame = screen.visibleFrame
        let saved = Config.load().overlayPosition
        let defaultCenterY = frame.minY + Self.dockGap + size.height / 2
        let centerX = saved.map { frame.minX + CGFloat($0.x) * frame.width } ?? frame.midX
        let centerY = saved.map { frame.minY + CGFloat($0.y) * frame.height } ?? defaultCenterY
        let x = min(max(centerX - size.width / 2, frame.minX), frame.maxX - size.width)
        let y = min(max(centerY - size.height / 2, frame.minY + Self.dockGap), frame.maxY - size.height)
        isPositioning = true
        window.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: false)
        isPositioning = false
        window.hasShadow = isRecording
        window.alphaValue = isVisible ? 1 : 0
        window.ignoresMouseEvents = !isVisible
        if isRecording {
            visualizer?.frame = NSRect(origin: .zero, size: size)
            window.contentView = visualizer
        } else {
            idleView?.frame = NSRect(origin: .zero, size: size)
            window.contentView = idleView
        }
        visualizer?.isActive = isRecording
        // Keep the transparent panel in every Space even when standby is off.
        // Reordering a closed panel during recording can miss a full-screen Space.
        window.orderFrontRegardless()
        window.contentView?.needsDisplay = true
    }

    func windowDidMove(_ notification: Notification) {
        guard !isPositioning, let panel = window,
              let screen = panel.screen ?? NSScreen.main else { return }
        // AppKit lets a borderless panel move beyond the usable screen.
        // Bring it back before saving, so both idle and recording states stay
        // clear of the Dock throughout and after a drag.
        let lowestY = screen.visibleFrame.minY + Self.dockGap
        if panel.frame.minY < lowestY {
            isPositioning = true
            panel.setFrameOrigin(NSPoint(x: panel.frame.minX, y: lowestY))
            isPositioning = false
        }
        positionSaveTimer?.invalidate()
        positionSaveTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
            self?.savePosition()
        }
    }

    private func savePosition() {
        guard let panel = window, let screen = panel.screen else { return }
        let visible = screen.visibleFrame
        guard visible.width > 0, visible.height > 0 else { return }
        var config = Config.load()
        config.overlayPosition = OverlayPosition(
            x: Double((panel.frame.midX - visible.minX) / visible.width),
            y: Double((panel.frame.midY - visible.minY) / visible.height)
        )
        do {
            try config.save()
        } catch {
            NSLog("OpenWispr: Could not save overlay position: %@", error.localizedDescription)
        }
    }

    private func buildIfNeeded() {
        guard window == nil else { return }
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.overlaySize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isFloatingPanel = true
        // Full-screen apps sit above status-bar windows on macOS. Keep the
        // indicator visible without making it activate or leave their Space.
        panel.level = .screenSaver
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.alphaValue = 0
        panel.ignoresMouseEvents = true
        panel.isMovableByWindowBackground = true
        panel.delegate = self
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [
            .canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .stationary
        ]
        window = panel
        visualizer = VisualizerView(frame: NSRect(origin: .zero, size: Self.overlaySize))
        idleView = IdleBarView(frame: NSRect(origin: .zero, size: Self.idleSize))
        visualizer?.onDoubleClick = { [weak self] in self?.resetPosition() }
        idleView?.onDoubleClick = { [weak self] in self?.resetPosition() }
        idleView?.onClose = { [weak self] in self?.onCloseIdleBar?() }
    }
}

/// A static, translucent pill. No timer or microphone is active for standby.
private class IdleBarView: NSView {
    var onDoubleClick: (() -> Void)?
    var onClose: (() -> Void)?
    private var isHovered = false
    private var trackingArea: NSTrackingArea?

    override var mouseDownCanMoveWindow: Bool { false }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if isHovered && point.x >= bounds.maxX - 17 {
            onClose?()
        } else if event.clickCount >= 2 {
            onDoubleClick?()
        } else {
            window?.performDrag(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let pill = NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7)
        NSColor(calibratedWhite: 0.14, alpha: 0.20).setFill()
        pill.fill()
        let mark = NSRect(x: isHovered ? 11 : bounds.midX - 13,
                          y: bounds.midY - 1.5,
                          width: isHovered ? 21 : 26, height: 3)
        NSColor(calibratedWhite: 1, alpha: 0.58).setFill()
        NSBezierPath(roundedRect: mark, xRadius: 1.5, yRadius: 1.5).fill()
        if isHovered {
            let button = NSRect(x: bounds.maxX - 14, y: 2, width: 10, height: 10)
            NSColor(calibratedWhite: 0.12, alpha: 0.42).setFill()
            NSBezierPath(ovalIn: button).fill()
            let cross = NSBezierPath()
            cross.move(to: NSPoint(x: button.minX + 3, y: button.minY + 3))
            cross.line(to: NSPoint(x: button.maxX - 3, y: button.maxY - 3))
            cross.move(to: NSPoint(x: button.minX + 3, y: button.maxY - 3))
            cross.line(to: NSPoint(x: button.maxX - 3, y: button.minY + 3))
            cross.lineWidth = 1.2
            NSColor.white.setStroke()
            cross.stroke()
        }
    }
}

/// Draws a rounded translucent pill with a row of bars that react to the mic
/// level. When inactive the bars settle to a flat resting state.
private class VisualizerView: NSView {
    var onDoubleClick: (() -> Void)?
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2 {
            onDoubleClick?()
        } else {
            window?.performDrag(with: event)
        }
    }
    private let barCount = 13
    private var heights: [CGFloat]
    private var targets: [CGFloat]
    private var timer: Timer?
    private var currentLevel: CGFloat = 0
    // Rotates the per-bar noise so the wave shifts sideways over time.
    private var phase: CGFloat = 0

    var isActive: Bool = false {
        didSet {
            if isActive { startTimer() } else { stopTimer(); reset() }
        }
    }

    override init(frame frameRect: NSRect) {
        heights = Array(repeating: 0.12, count: barCount)
        targets = Array(repeating: 0.12, count: barCount)
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been used") }

    func reset() {
        currentLevel = 0
        for i in 0..<barCount {
            heights[i] = 0.12
            targets[i] = 0.12
        }
        needsDisplay = true
    }

    func push(level: Float) {
        currentLevel = CGFloat(max(0, min(1, level)))
    }

    private func startTimer() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        phase += 0.35

        // Bars taper toward the edges so the center is liveliest.
        let mid = CGFloat(barCount - 1) / 2
        var allResting = true
        for i in 0..<barCount {
            let distance = abs(CGFloat(i) - mid) / mid
            let taper = 1.0 - distance * 0.55
            let wobble = 0.5 + 0.5 * sin(phase + CGFloat(i) * 0.9)
            let rest: CGFloat = 0.10
            if isActive {
                let target = rest + currentLevel * taper * (0.45 + 0.85 * wobble)
                targets[i] = max(rest, min(1.0, target))
            } else {
                targets[i] = rest
            }
            // Ease current toward target (snappy enough to show peaks).
            heights[i] += (targets[i] - heights[i]) * 0.45
            if abs(heights[i] - rest) > 0.02 { allResting = false }
        }

        // Decay the level so bars fall when the mic goes quiet.
        currentLevel *= 0.82

        needsDisplay = true

        // Once faded out and settled, stop the timer to save CPU.
        if !isActive && allResting {
            stopTimer()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let bounds = self.bounds

        // Pill background.
        let bg = NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        NSColor(calibratedWhite: 0.10, alpha: 0.82).setFill()
        bg.fill()

        let inset: CGFloat = 16
        let usableWidth = bounds.width - inset * 2
        let barSpacing = usableWidth / CGFloat(barCount)
        let barWidth: CGFloat = 3
        let maxBarHeight = bounds.height - 14
        let centerY = bounds.midY

        NSColor.white.setFill()
        for i in 0..<barCount {
            let h = max(barWidth, heights[i] * maxBarHeight)
            let x = inset + barSpacing * CGFloat(i) + (barSpacing - barWidth) / 2
            let y = centerY - h / 2
            let barRect = NSRect(x: x, y: y, width: barWidth, height: h)
            NSBezierPath(roundedRect: barRect, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
        }
    }
}
