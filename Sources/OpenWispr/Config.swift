import Foundation

struct Config: Codable {
    var hotkey: HotkeyConfig
    var modelPath: String?
    var modelSize: String
    var language: String
    // "toggle" = tap once to start, tap again to stop; "hold" = push-to-talk.
    // Optional so configs written by older versions still decode.
    var recordingMode: String?
    // Optional for compatibility with existing configuration files.
    var showIdleBar: Bool?
    var overlayPosition: OverlayPosition?

    var isIdleBarEnabled: Bool { showIdleBar ?? false }

    // Defaults to toggle when unset (older configs and fresh installs).
    var isToggleMode: Bool {
        (recordingMode ?? "toggle").lowercased() != "hold"
    }

    static let defaultConfig = Config(
        hotkey: HotkeyConfig(keyCode: 63, modifiers: []),
        modelPath: nil,
        modelSize: "small",
        language: "auto",
        recordingMode: "toggle"
    )

    static var configDir: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/open-wispr")
    }

    static var configFile: URL {
        configDir.appendingPathComponent("config.json")
    }

    static func load() -> Config {
        guard let data = try? Data(contentsOf: configFile),
              let config = try? JSONDecoder().decode(Config.self, from: data) else {
            let config = Config.defaultConfig
            try? config.save()
            return config
        }
        return config
    }

    func save() throws {
        try FileManager.default.createDirectory(at: Config.configDir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(self)
        try data.write(to: Config.configFile)
    }
}

struct HotkeyConfig: Codable {
    var keyCode: UInt16
    var modifiers: [String]

    var modifierFlags: UInt64 {
        var flags: UInt64 = 0
        for mod in modifiers {
            switch mod.lowercased() {
            case "cmd", "command": flags |= UInt64(1 << 20)
            case "shift": flags |= UInt64(1 << 17)
            case "ctrl", "control": flags |= UInt64(1 << 18)
            case "opt", "option", "alt": flags |= UInt64(1 << 19)
            default: break
            }
        }
        return flags
    }
}

/// A screen-relative center point, so the overlay stays in place after login.
struct OverlayPosition: Codable {
    var x: Double
    var y: Double
}
