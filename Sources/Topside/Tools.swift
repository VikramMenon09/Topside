import AppKit
import SwiftUI
import Speech
import AVFoundation

// MARK: - Teleprompter

final class PrompterService: ObservableObject {
    static let shared = PrompterService()
    @Published var script: String { didSet { UserDefaults.standard.set(script, forKey: "prompterScript") } }
    @Published var words: [String] = []
    @Published var index = 0
    @Published var running = false
    @Published var voice = false
    @Published var status = ""

    private var timer: Timer?
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let recognizer = SFSpeechRecognizer()
    private var normalized: [String] = []

    static let perLine = 6

    private init() {
        script = UserDefaults.standard.string(forKey: "prompterScript")
            ?? "Paste your script here. Press play and it scrolls right under the camera, so you keep eye contact while you read. Turn on voice follow and it keeps pace with you as you speak."
    }

    var lines: [[String]] {
        stride(from: 0, to: words.count, by: Self.perLine).map { Array(words[$0..<min($0 + Self.perLine, words.count)]) }
    }

    private static func norm(_ s: String) -> String {
        s.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    func start(voice useVoice: Bool) {
        words = script.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        normalized = words.map(Self.norm)
        guard !words.isEmpty else { return }
        index = 0
        running = true
        voice = useVoice
        status = ""
        if useVoice { startVoice() } else { startClock() }
    }

    func stop() {
        running = false
        timer?.invalidate()
        timer = nil
        stopVoice()
    }

    private func startClock() {
        timer?.invalidate()
        let wpm = max(40, Prefs.double("prompterWPM"))
        timer = Timer.scheduledTimer(withTimeInterval: 60 / wpm, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.index < self.words.count - 1 { self.index += 1 } else { self.stop() }
        }
    }

    func nudge(_ delta: Int) { index = max(0, min(words.count - 1, index + delta * Self.perLine)) }

    // MARK: Voice follow

    private func startVoice() {
        status = "Asking for microphone…"
        SFSpeechRecognizer.requestAuthorization { auth in
            guard auth == .authorized else {
                onMain { self.status = "Speech recognition not allowed, using steady scroll"; self.voice = false; self.startClock() }
                return
            }
            AVCaptureDevice.requestAccess(for: .audio) { ok in
                onMain {
                    guard self.running else { return }
                    if ok { self.beginRecognition() } else {
                        self.status = "Microphone not allowed, using steady scroll"
                        self.voice = false
                        self.startClock()
                    }
                }
            }
        }
    }

    private func beginRecognition() {
        guard let recognizer, recognizer.isAvailable else {
            status = "Speech recognition unavailable, using steady scroll"
            voice = false
            startClock()
            return
        }
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
        request = req
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in req.append(buffer) }
        engine.prepare()
        do { try engine.start() } catch {
            status = "Could not open the microphone, using steady scroll"
            voice = false
            startClock()
            return
        }
        status = "Listening…"
        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            if let result {
                let heard = result.bestTranscription.segments.suffix(3).map { Self.norm($0.substring) }.filter { !$0.isEmpty }
                onMain { self?.follow(heard) }
            }
            if error != nil || (result?.isFinal ?? false) {
                onMain {
                    guard let self, self.running, self.voice else { return }
                    self.stopVoice()
                    self.beginRecognition() // recognition sessions time out; start a fresh one
                }
            }
        }
    }

    /// Move to just past wherever the last couple of spoken words appear in the upcoming script.
    private func follow(_ heard: [String]) {
        guard running, !heard.isEmpty else { return }
        let window = index..<min(normalized.count, index + 18)
        let tail = Array(heard.suffix(2))
        if tail.count == 2 {
            for i in window where i + 1 < normalized.count && normalized[i] == tail[0] && normalized[i + 1] == tail[1] {
                index = min(words.count - 1, i + 2)
                return
            }
        }
        if let last = heard.last, last.count >= 4 {
            for i in index..<min(normalized.count, index + 6) where normalized[i] == last {
                index = min(words.count - 1, i + 1)
                return
            }
        }
    }

    private func stopVoice() {
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
    }
}

// MARK: - AI coding agent sessions (read-only view of local session logs)

struct AgentSession: Identifiable, Equatable {
    enum State: String { case working = "Working", tool = "Tool running", waiting = "Waiting", idle = "Idle" }
    var id: String
    var tool: String
    var project: String
    var state: State
    var snippet: String
    var modified: Date
}

final class AgentsService: ObservableObject {
    static let shared = AgentsService()
    @Published var sessions: [AgentSession] = []
    @Published var scanning = false

    func scan() {
        guard !scanning else { return }
        scanning = true
        DispatchQueue.global(qos: .utility).async {
            let home = FileManager.default.homeDirectoryForCurrentUser
            var found: [AgentSession] = []
            found += Self.collect(root: home.appendingPathComponent(".claude/projects"), tool: "Claude Code", depth: 2)
            found += Self.collect(root: home.appendingPathComponent(".codex/sessions"), tool: "Codex", depth: 5)
            found.sort { $0.modified > $1.modified }
            onMain {
                self.sessions = Array(found.prefix(14))
                self.scanning = false
            }
        }
    }

    private static func collect(root: URL, tool: String, depth: Int) -> [AgentSession] {
        let fm = FileManager.default
        guard let en = fm.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else { return [] }
        let cutoff = Date().addingTimeInterval(-6 * 3600)
        var files: [(URL, Date)] = []
        for case let u as URL in en {
            if en.level > depth { en.skipDescendants(); continue }
            guard u.pathExtension == "jsonl",
                  let m = try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, m > cutoff else { continue }
            files.append((u, m))
        }
        return files.sorted { $0.1 > $1.1 }.prefix(10).compactMap { parse($0.0, modified: $0.1, tool: tool) }
    }

    private static func tail(_ url: URL, bytes: UInt64 = 96_000) -> [String] {
        guard let h = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? h.close() }
        let size = (try? h.seekToEnd()) ?? 0
        try? h.seek(toOffset: size > bytes ? size - bytes : 0)
        let data = (try? h.readToEnd()) ?? Data()
        return String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init)
    }

    private static func parse(_ url: URL, modified: Date, tool: String) -> AgentSession? {
        let lines = tail(url)
        var project = ""
        var snippet = ""
        var pendingTool = false
        var lastRole = ""
        for line in lines.reversed() {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }
            if project.isEmpty {
                let cwd = obj["cwd"] as? String ?? (obj["payload"] as? [String: Any])?["cwd"] as? String
                if let cwd { project = URL(fileURLWithPath: cwd).lastPathComponent }
            }
            if snippet.isEmpty {
                let type = obj["type"] as? String ?? ""
                if tool == "Claude Code", type == "assistant" || type == "user",
                   let msg = obj["message"] as? [String: Any] {
                    if lastRole.isEmpty { lastRole = type }
                    if let parts = msg["content"] as? [[String: Any]] {
                        for part in parts.reversed() {
                            let kind = part["type"] as? String ?? ""
                            if kind == "text", let t = part["text"] as? String, type == "assistant" { snippet = t; break }
                            if kind == "tool_use", type == "assistant" {
                                let input = part["input"] as? [String: Any] ?? [:]
                                let detail = input["command"] as? String ?? input["description"] as? String ?? input["file_path"] as? String ?? ""
                                snippet = "\(part["name"] as? String ?? "Tool"): \(detail)"
                                if lastRole == "assistant" { pendingTool = true }
                                break
                            }
                        }
                    } else if let t = msg["content"] as? String, type == "assistant" {
                        snippet = t
                    }
                } else if tool == "Codex", let payload = obj["payload"] as? [String: Any] {
                    if let t = payload["message"] as? String { snippet = t }
                    else if let parts = payload["content"] as? [[String: Any]], let t = parts.last?["text"] as? String { snippet = t }
                    else if let c = payload["command"] as? [String] { snippet = c.joined(separator: " ") }
                }
            }
            if !project.isEmpty, !snippet.isEmpty { break }
        }
        if project.isEmpty { project = url.deletingLastPathComponent().lastPathComponent }
        let age = Date().timeIntervalSince(modified)
        let state: AgentSession.State
        if pendingTool, age < 1800 { state = age > 6 ? .tool : .working }
        else if age < 20 { state = .working }
        else if lastRole == "assistant", age < 1800 { state = .waiting }
        else { state = .idle }
        let clean = snippet.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        return AgentSession(id: url.path, tool: tool, project: project, state: state,
                            snippet: String(clean.prefix(160)), modified: modified)
    }
}
