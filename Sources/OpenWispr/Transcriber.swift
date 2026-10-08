import Foundation

class Transcriber {
    private let modelSize: String
    private let language: String

    init(modelSize: String = "small", language: String = "en") {
        self.modelSize = modelSize
        self.language = language
    }

    func transcribe(audioURL: URL) throws -> String {
        guard let whisperPath = Transcriber.findWhisperBinary() else {
            throw TranscriberError.whisperNotFound
        }

        guard let modelPath = Transcriber.findModel(modelSize: modelSize) else {
            throw TranscriberError.modelNotFound(modelSize)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: whisperPath)
        var args = [
            "-m", modelPath,
            "-f", audioURL.path,
            "--no-timestamps",
            "-nt",
        ]

        // auto 模式显式传 -l auto，否则 whisper-cpp 默认英文
        args += ["-l", language]

        // 中文或自动检测模式：用 initial prompt 引导输出简体中文和标点符号
        if language == "zh" || language == "auto" {
            args += ["--prompt", "以下是简体中文的句子，包含标点符号。"]
        }

        process.arguments = args

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if process.terminationStatus != 0 {
            throw TranscriberError.transcriptionFailed
        }

        // 追加一个尾随空格，使连续多次听写之间自然分隔
        return output.isEmpty ? output : output + " "
    }

    static func findWhisperBinary() -> String? {
        let candidates = [
            "/opt/homebrew/bin/whisper-cli",
            "/usr/local/bin/whisper-cli",
            "/opt/homebrew/bin/whisper-cpp",
            "/usr/local/bin/whisper-cpp",
        ]

        for path in candidates {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        for name in ["whisper-cli", "whisper-cpp"] {
            let which = Process()
            which.executableURL = URL(fileURLWithPath: "/usr/bin/which")
            which.arguments = [name]
            let pipe = Pipe()
            which.standardOutput = pipe
            which.standardError = Pipe()
            try? which.run()
            which.waitUntilExit()

            let result = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if let result = result, !result.isEmpty {
                return result
            }
        }

        return nil
    }

    static func modelExists(modelSize: String) -> Bool {
        return findModel(modelSize: modelSize) != nil
    }

    static func findModel(modelSize: String) -> String? {
        let modelFileName = "ggml-\(modelSize).bin"

        let candidates = [
            "\(Config.configDir.path)/models/\(modelFileName)",
            "/opt/homebrew/share/whisper-cpp/models/\(modelFileName)",
            "/usr/local/share/whisper-cpp/models/\(modelFileName)",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.cache/whisper/\(modelFileName)",
        ]

        for path in candidates {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        return nil
    }
}

enum TranscriberError: LocalizedError {
    case whisperNotFound
    case modelNotFound(String)
    case transcriptionFailed

    var errorDescription: String? {
        switch self {
        case .whisperNotFound:
            return "whisper-cpp not found. Install it with: brew install whisper-cpp"
        case .modelNotFound(let size):
            return "Whisper model '\(size)' not found. Download it with: open-wispr download-model \(size)"
        case .transcriptionFailed:
            return "Transcription failed"
        }
    }
}
