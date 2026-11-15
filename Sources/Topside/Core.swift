import AppKit
import SwiftUI
import Combine

// MARK: - Preferences

enum Prefs {
    static let defaults: [String: Any] = [
        "openOnHover": true,
        "hoverDelay": 0.15,
        "haptics": true,
        "swipeGestures": true,
        "theme": "black",
        "glow": false,
        "virtualNotch": true,
        "allDisplays": false,
        "hideNotchBar": false,
        "menuBarHider": false,
        "autoRehide": 8.0,
        "weatherCity": "",
        "lyrics": false,
        "blockedMediaApps": "",
        "watchDownloads": false,
        "clipboardEnabled": true,
        "disabledTabs": "",
        "pomodoroWork": 25,
        "pomodoroBreak": 5,
        "prompterWPM": 140.0,
    ]

    static func register() { UserDefaults.standard.register(defaults: defaults) }
    static func bool(_ k: String) -> Bool { UserDefaults.standard.bool(forKey: k) }
    static func double(_ k: String) -> Double { UserDefaults.standard.double(forKey: k) }
    static func string(_ k: String) -> String { UserDefaults.standard.string(forKey: k) ?? "" }
    static func list(_ k: String) -> [String] {
        string(k).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}

// MARK: - Tabs

enum Tab: String, CaseIterable, Identifiable {
    case home, today, shelf, clipboard, timer, mirror, devices, prompter, agents
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home: return "music.note"
        case .today: return "calendar"
        case .shelf: return "tray.fill"
        case .clipboard: return "doc.on.clipboard"
        case .timer: return "timer"
        case .mirror: return "web.camera"
        case .devices: return "cpu"
        case .prompter: return "text.bubble"
        case .agents: return "sparkles"
        }
    }

    var short: String {
        switch self {
        case .home: return "Playing"
        case .today: return "Today"
        case .shelf: return "Tray"
        case .clipboard: return "Clips"
        case .timer: return "Timer"
        case .mirror: return "Mirror"
        case .devices: return "System"
        case .prompter: return "Prompt"
        case .agents: return "Agents"
        }
    }

    var title: String {
        switch self {
        case .home: return "Now Playing"
        case .today: return "Calendar & Weather"
        case .shelf: return "File Tray"
        case .clipboard: return "Clipboard"
        case .timer: return "Timers & Pomodoro"
        case .mirror: return "Mirror"
        case .devices: return "System"
        case .prompter: return "Teleprompter"
        case .agents: return "AI Coding Agents"
        }
    }

    static var enabled: [Tab] {
        let off = Set(Prefs.list("disabledTabs"))
        let on = allCases.filter { !off.contains($0.rawValue) }
        return on.isEmpty ? [.home] : on
    }
}

// MARK: - Shell helper

enum Shell {
    @discardableResult
    static func run(_ path: String, _ args: [String], cwd: URL? = nil) -> (status: Int32, out: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        if let cwd { p.currentDirectoryURL = cwd }
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return (-1, "") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}

func onMain(_ work: @escaping () -> Void) {
    if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
}

// MARK: - Transient activities (HUD + toasts)

struct Toast: Equatable {
    var icon: String
    var text: String
    var tint: Color = .white
}

final class ActivityCenter: ObservableObject {
    static let shared = ActivityCenter()
    @Published var toast: Toast?
    private var toastClear: DispatchWorkItem?

    func show(_ t: Toast, seconds: Double = 3.2) {
        onMain {
            self.toast = t
            self.toastClear?.cancel()
            let w = DispatchWorkItem { [weak self] in self?.toast = nil }
            self.toastClear = w
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: w)
        }
    }
}

// MARK: - Per-screen notch state

final class NotchModel: ObservableObject {
    @Published var isOpen = false
    @Published var tab: Tab = .home
    @Published var pinned = false
    @Published var dropTargeted = false

    let notchSize: CGSize
    let hasHardwareNotch: Bool
    /// The window is resized through this, strictly before opening and after closing, never mid-update.
    var onOpenChange: ((Bool) -> Void)?

    init(notchSize: CGSize, hasHardwareNotch: Bool) {
        self.notchSize = notchSize
        self.hasHardwareNotch = hasHardwareNotch
    }

    static let stripHeight: CGFloat = 30
    static let toastHeight: CGFloat = 28
    var openSize: CGSize { CGSize(width: 400, height: notchSize.height + NotchModel.stripHeight + 150) }
    var closedWidth: CGFloat { notchSize.width }

    func open(_ tab: Tab? = nil) {
        if let tab { self.tab = tab }
        if !Tab.enabled.contains(self.tab) { self.tab = Tab.enabled[0] }
        guard !isOpen else { return }
        onOpenChange?(true)
        isOpen = true
        if Prefs.bool("haptics") {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        CalendarService.shared.reload()
        WeatherService.shared.refreshIfStale()
    }

    func close() {
        guard isOpen else { return }
        pinned = false
        // Always reopen on the player, never on whatever list was last left open.
        PlaylistService.shared.browsing = false
        PlaylistService.shared.showingQueue = false
        PlaylistService.shared.closePlaylist()
        isOpen = false
        onOpenChange?(false)
    }

    func step(_ delta: Int) {
        let tabs = Tab.enabled
        guard let i = tabs.firstIndex(of: tab) else { tab = tabs[0]; return }
        tab = tabs[(i + delta + tabs.count) % tabs.count]
    }
}

// MARK: - Small UI helpers

struct Card<Content: View>: View {
    var padding: CGFloat = 10
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.07)))
    }
}

struct IconButton: View {
    let icon: String
    var size: CGFloat = 13
    var tint: Color = .white.opacity(0.85)
    var help: String = ""
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: size + 12, height: size + 12)
                .background(Circle().fill(Color.white.opacity(hover ? 0.14 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(help)
    }
}

struct Pill: View {
    let text: String
    var active = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(Capsule().fill(Color.white.opacity(active ? 0.9 : 0.1)))
                .foregroundStyle(active ? Color.black : Color.white)
        }
        .buttonStyle(.plain)
    }
}

func clock(_ seconds: Double) -> String {
    let s = max(0, Int(seconds.rounded()))
    return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
}

func ago(_ date: Date) -> String {
    let s = Int(Date().timeIntervalSince(date))
    if s < 60 { return "now" }
    if s < 3600 { return "\(s / 60)m" }
    if s < 86400 { return "\(s / 3600)h" }
    return "\(s / 86400)d"
}

/// The notch outline: top corners flare outwards into the menu bar, bottom corners are rounded.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }

    func path(in r: CGRect) -> Path {
        let tr = topRadius, br = min(bottomRadius, r.height / 2)
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX + tr, y: r.minY + tr), control: CGPoint(x: r.minX + tr, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + tr, y: r.maxY - br))
        p.addQuadCurve(to: CGPoint(x: r.minX + tr + br, y: r.maxY), control: CGPoint(x: r.minX + tr, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - tr - br, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.maxX - tr, y: r.maxY - br), control: CGPoint(x: r.maxX - tr, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - tr, y: r.minY + tr))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.maxX - tr, y: r.minY))
        p.closeSubpath()
        return p
    }
}
