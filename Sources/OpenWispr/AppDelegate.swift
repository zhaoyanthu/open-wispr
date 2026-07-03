import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBar: StatusBarController!
    var hotkeyManager: HotkeyManager?
    var recorder: AudioRecorder!
    var transcriber: Transcriber!
    var inserter: TextInserter!
    var overlay = RecordingOverlay()
    var isPressed = false
    var isReady = false
    var isToggleMode = true
    // In toggle mode, tracks whether we're mid-recording between two taps.
    var isRecordingActive = false
    // Safety net so a forgotten toggle recording doesn't run forever.
    var maxDurationTimer: Timer?
    private let maxRecordingSeconds: TimeInterval = 5 * 60

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBar = StatusBarController()
        recorder = AudioRecorder()
        recorder.onLevel = { [weak self] level in
            self?.overlay.update(level: level)
        }
        inserter = TextInserter()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.setup()
        }
    }

    private func setup() {
        do {
            try setupInner()
        } catch {
            print("Fatal setup error: \(error.localizedDescription)")
        }
    }

    private func setupInner() throws {
        let config = Config.load()
        transcriber = Transcriber(modelSize: config.modelSize, language: config.language)

        DispatchQueue.main.async { self.statusBar.buildMenu() }

        if Transcriber.findWhisperBinary() == nil {
            print("Error: whisper-cpp not found. Install it with: brew install whisper-cpp")
            return
        }

        Permissions.ensureMicrophone()

        if !AXIsProcessTrusted() {
            DispatchQueue.main.async {
                self.statusBar.state = .waitingForPermission
                self.statusBar.buildMenu()
            }
            print("Accessibility: not granted")
            Permissions.promptAccessibility()
            Permissions.openAccessibilitySettings()
            print("Waiting for Accessibility permission...")
            while !AXIsProcessTrusted() {
                Thread.sleep(forTimeInterval: 2)
            }
            print("Accessibility: granted")
        } else {
            print("Accessibility: granted")
        }

        if !Transcriber.modelExists(modelSize: config.modelSize) {
            DispatchQueue.main.async {
                self.statusBar.state = .downloading
                self.statusBar.updateDownloadProgress("Downloading \(config.modelSize) model...")
            }
            print("Downloading \(config.modelSize) model...")
            try ModelDownloader.download(modelSize: config.modelSize)
            DispatchQueue.main.async {
                self.statusBar.updateDownloadProgress(nil)
            }
        }

        DispatchQueue.main.async { [weak self] in
            self?.startListening(config: config)
        }
    }

    private func startListening(config: Config) {
        isToggleMode = config.isToggleMode
        hotkeyManager = HotkeyManager(
            keyCode: config.hotkey.keyCode,
            modifiers: config.hotkey.modifierFlags
        )

        hotkeyManager?.start(
            onKeyDown: { [weak self] in
                self?.handleKeyDown()
            },
            onKeyUp: { [weak self] in
                self?.handleKeyUp()
            }
        )

        isReady = true
        statusBar.state = .idle
        statusBar.buildMenu()

        let hotkeyDesc = KeyCodes.describe(keyCode: config.hotkey.keyCode, modifiers: config.hotkey.modifiers)
        print("open-wispr v\(OpenWispr.version)")
        print("Hotkey: \(hotkeyDesc)")
        print("Mode: \(isToggleMode ? "toggle" : "hold")")
        print("Model: \(config.modelSize)")
        print("Ready.")
    }

    // MARK: - Hotkey handling

    private func handleKeyDown() {
        guard isReady else { return }

        if isToggleMode {
            // First tap starts, next tap stops.
            if isRecordingActive {
                stopAndTranscribe()
            } else {
                beginRecording()
            }
        } else {
            guard !isPressed else { return }
            isPressed = true
            beginRecording()
        }
    }

    private func handleKeyUp() {
        // In toggle mode the key release does nothing; stopping happens on the
        // next press instead.
        guard !isToggleMode else { return }
        guard isPressed else { return }
        isPressed = false
        stopAndTranscribe()
    }

    // MARK: - Recording lifecycle

    private func beginRecording() {
        NSSound(named: .init("Tink"))?.play()
        statusBar.state = .recording
        do {
            try recorder.startRecording()
            isRecordingActive = true
            overlay.show()
            scheduleMaxDurationSafety()
        } catch {
            print("Error: \(error.localizedDescription)")
            isPressed = false
            isRecordingActive = false
            statusBar.state = .idle
        }
    }

    private func scheduleMaxDurationSafety() {
        maxDurationTimer?.invalidate()
        maxDurationTimer = Timer.scheduledTimer(withTimeInterval: maxRecordingSeconds, repeats: false) { [weak self] _ in
            guard let self = self, self.isRecordingActive else { return }
            print("Max recording duration reached — stopping.")
            self.stopAndTranscribe()
        }
    }

    private func stopAndTranscribe() {
        guard isRecordingActive else { return }
        isRecordingActive = false
        isPressed = false
        maxDurationTimer?.invalidate()
        maxDurationTimer = nil

        NSSound(named: .init("Pop"))?.play()
        overlay.hide()

        guard let audioURL = recorder.stopRecording() else {
            statusBar.state = .idle
            return
        }

        statusBar.state = .transcribing

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                let text = try self.transcriber.transcribe(audioURL: audioURL)
                DispatchQueue.main.async {
                    if !text.isEmpty {
                        self.inserter.insert(text: text)
                    }
                    self.statusBar.state = .idle
                }
            } catch {
                DispatchQueue.main.async {
                    print("Error: \(error.localizedDescription)")
                    self.statusBar.state = .idle
                }
            }
        }
    }
}
