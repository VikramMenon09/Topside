import AppKit
import SwiftUI
import EventKit

// MARK: - Calendar & Reminders

struct DayEvent: Identifiable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let allDay: Bool
    let color: Color
}

struct ReminderItem: Identifiable {
    let id: String
    let title: String
    let due: Date?
}

final class CalendarService: ObservableObject {
    static let shared = CalendarService()
    private let store = EKEventStore()
    @Published var events: [DayEvent] = []
    @Published var reminders: [ReminderItem] = []
    @Published var eventAccess = EKEventStore.authorizationStatus(for: .event) == .fullAccess
    @Published var reminderAccess = EKEventStore.authorizationStatus(for: .reminder) == .fullAccess

    private init() {
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in self?.reload() }
    }

    func requestEvents() {
        store.requestFullAccessToEvents { ok, _ in onMain { self.eventAccess = ok; self.reload() } }
    }

    func requestReminders() {
        store.requestFullAccessToReminders { ok, _ in onMain { self.reminderAccess = ok; self.reload() } }
    }

    func reload() {
        if eventAccess {
            let start = Date()
            let end = Calendar.current.date(byAdding: .day, value: 2, to: Calendar.current.startOfDay(for: start))!
            let found = store.events(matching: store.predicateForEvents(withStart: start.addingTimeInterval(-3600), end: end, calendars: nil))
                .filter { $0.endDate > start }
                .sorted { $0.startDate < $1.startDate }
                .prefix(8)
            events = found.map {
                DayEvent(id: ($0.eventIdentifier ?? UUID().uuidString) + "\($0.startDate.timeIntervalSince1970)",
                         title: $0.title ?? "Event", start: $0.startDate, end: $0.endDate, allDay: $0.isAllDay,
                         color: Color(nsColor: $0.calendar.color))
            }
        }
        if reminderAccess {
            let pred = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
            store.fetchReminders(matching: pred) { list in
                let items = (list ?? []).prefix(30).map {
                    ReminderItem(id: $0.calendarItemIdentifier, title: $0.title ?? "Reminder", due: $0.dueDateComponents?.date)
                }
                onMain { self.reminders = Array(items) }
            }
        }
    }

    func complete(_ r: ReminderItem) {
        guard let item = store.calendarItem(withIdentifier: r.id) as? EKReminder else { return }
        item.isCompleted = true
        try? store.save(item, commit: true)
        reminders.removeAll { $0.id == r.id }
    }
}

// MARK: - Weather (open-meteo.com, no account needed)

final class WeatherService: ObservableObject {
    static let shared = WeatherService()
    @Published var summary = ""
    @Published var temperature = ""
    @Published var range = ""
    @Published var icon = "cloud"
    @Published var place = ""
    private var lastFetch = Date.distantPast
    private var lastCity = ""

    func refreshIfStale() {
        let city = Prefs.string("weatherCity").trimmingCharacters(in: .whitespaces)
        guard !city.isEmpty else { temperature = ""; place = ""; return }
        guard city != lastCity || Date().timeIntervalSince(lastFetch) > 900 else { return }
        lastCity = city
        lastFetch = Date()
        var geo = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        geo.queryItems = [URLQueryItem(name: "name", value: city), URLQueryItem(name: "count", value: "1")]
        URLSession.shared.dataTask(with: geo.url!) { data, _, _ in
            guard let data, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let r = (obj["results"] as? [[String: Any]])?.first,
                  let lat = r["latitude"] as? Double, let lon = r["longitude"] as? Double else {
                onMain { self.temperature = ""; self.place = "City not found" }
                return
            }
            self.forecast(lat: lat, lon: lon, name: r["name"] as? String ?? city)
        }.resume()
    }

    private func forecast(lat: Double, lon: Double, name: String) {
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        let fahrenheit = Locale.current.measurementSystem == .us
        c.queryItems = [
            URLQueryItem(name: "latitude", value: String(lat)),
            URLQueryItem(name: "longitude", value: String(lon)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "forecast_days", value: "1"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "temperature_unit", value: fahrenheit ? "fahrenheit" : "celsius"),
        ]
        URLSession.shared.dataTask(with: c.url!) { data, _, _ in
            guard let data, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let cur = obj["current"] as? [String: Any], let t = cur["temperature_2m"] as? Double else { return }
            let code = cur["weather_code"] as? Int ?? 0
            let daily = obj["daily"] as? [String: Any]
            let hi = (daily?["temperature_2m_max"] as? [Double])?.first
            let lo = (daily?["temperature_2m_min"] as? [Double])?.first
            let (sym, text) = Self.describe(code)
            onMain {
                self.temperature = "\(Int(t.rounded()))°"
                self.range = hi != nil && lo != nil ? "H \(Int(hi!.rounded()))°  L \(Int(lo!.rounded()))°" : ""
                self.icon = sym
                self.summary = text
                self.place = name
            }
        }.resume()
    }

    static func describe(_ code: Int) -> (String, String) {
        switch code {
        case 0: return ("sun.max.fill", "Clear")
        case 1, 2: return ("cloud.sun.fill", "Partly cloudy")
        case 3: return ("cloud.fill", "Overcast")
        case 45, 48: return ("cloud.fog.fill", "Fog")
        case 51...57: return ("cloud.drizzle.fill", "Drizzle")
        case 61...67, 80...82: return ("cloud.rain.fill", "Rain")
        case 71...77, 85, 86: return ("cloud.snow.fill", "Snow")
        case 95...99: return ("cloud.bolt.rain.fill", "Thunderstorm")
        default: return ("cloud.fill", "Cloudy")
        }
    }
}

// MARK: - File tray

final class ShelfService: ObservableObject {
    static let shared = ShelfService()
    @Published var items: [URL] = []
    @Published var busy = ""

    private init() {
        let paths = UserDefaults.standard.stringArray(forKey: "shelfPaths") ?? []
        items = paths.map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func save() { UserDefaults.standard.set(items.map(\.path), forKey: "shelfPaths") }

    func add(_ url: URL) {
        onMain {
            guard !self.items.contains(url) else { return }
            self.items.insert(url, at: 0)
            self.save()
        }
    }

    func remove(_ url: URL) { items.removeAll { $0 == url }; save() }
    func clear() { items = []; save() }

    func trash(_ url: URL) {
        try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        remove(url)
    }

    func airDrop(_ urls: [URL]) {
        guard !urls.isEmpty, let s = NSSharingService(named: .sendViaAirDrop) else { return }
        NSApp.activate(ignoringOtherApps: true)
        s.perform(withItems: urls)
    }

    func quickLook(_ url: URL) {
        DispatchQueue.global().async { Shell.run("/usr/bin/qlmanage", ["-p", url.path]) }
    }

    func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }

    func share(_ url: URL, from view: NSView?) {
        guard let view else { return }
        let picker = NSSharingServicePicker(items: [url])
        let p = view.convert(view.window?.mouseLocationOutsideOfEventStream ?? .zero, from: nil)
        picker.show(relativeTo: NSRect(x: p.x, y: p.y, width: 1, height: 1), of: view, preferredEdge: .minY)
    }

    private func freeURL(_ base: URL) -> URL {
        var u = base
        var n = 2
        while FileManager.default.fileExists(atPath: u.path) {
            let stem = base.deletingPathExtension().lastPathComponent + " \(n)"
            u = base.deletingLastPathComponent().appendingPathComponent(stem).appendingPathExtension(base.pathExtension)
            n += 1
        }
        return u
    }

    func zip(_ url: URL) {
        busy = "Compressing…"
        let dest = freeURL(url.deletingPathExtension().appendingPathExtension("zip"))
        DispatchQueue.global().async {
            let r = Shell.run("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", url.path, dest.path])
            onMain {
                self.busy = ""
                if r.status == 0 { self.add(dest) }
            }
        }
    }

    func unzip(_ url: URL) {
        busy = "Expanding…"
        let dest = freeURL(url.deletingPathExtension())
        DispatchQueue.global().async {
            let r = Shell.run("/usr/bin/ditto", ["-x", "-k", url.path, dest.path])
            onMain {
                self.busy = ""
                if r.status == 0 { self.add(dest) }
            }
        }
    }
}

// MARK: - Clipboard history (kept in memory only)

struct Clip: Identifiable, Equatable {
    let id = UUID()
    var text: String?
    var image: NSImage?
    var date = Date()
    var app = ""
    static func == (a: Clip, b: Clip) -> Bool { a.id == b.id }
}

final class ClipboardService: ObservableObject {
    static let shared = ClipboardService()
    @Published var clips: [Clip] = []
    private var change = NSPasteboard.general.changeCount
    private var timer: Timer?

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in self?.poll() }
    }

    private func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != change else { return }
        change = pb.changeCount
        guard Prefs.bool("clipboardEnabled") else { return }
        // Respect password managers and other apps that mark content as private.
        let types = (pb.types ?? []).map(\.rawValue)
        if types.contains(where: { $0.contains("ConcealedType") || $0.contains("TransientType") || $0.contains("AutoGeneratedType") }) { return }
        let app = NSWorkspace.shared.frontmostApplication?.localizedName ?? ""
        if let s = pb.string(forType: .string), !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            clips.removeAll { $0.text == s }
            clips.insert(Clip(text: s, app: app), at: 0)
        } else if types.contains(NSPasteboard.PasteboardType.png.rawValue) || types.contains(NSPasteboard.PasteboardType.tiff.rawValue),
                  let img = NSImage(pasteboard: pb) {
            clips.insert(Clip(image: img, app: app), at: 0)
        }
        if clips.count > 200 { clips.removeLast(clips.count - 200) }
    }

    func copy(_ c: Clip) {
        let pb = NSPasteboard.general
        pb.clearContents()
        if let t = c.text { pb.setString(t, forType: .string) } else if let i = c.image { pb.writeObjects([i]) }
        change = pb.changeCount
        if let idx = clips.firstIndex(of: c), idx != 0 {
            let moved = clips.remove(at: idx)
            clips.insert(moved, at: 0)
        }
    }

    func remove(_ c: Clip) { clips.removeAll { $0.id == c.id } }
}

// MARK: - Timers & Pomodoro

final class TimerService: ObservableObject {
    static let shared = TimerService()
    enum Phase: String { case work = "Focus", rest = "Break" }

    @Published var end: Date?
    @Published var pausedRemaining: Double?
    @Published var total: Double = 0
    @Published var label = "Timer"
    @Published var pomodoro = false
    @Published var phase: Phase = .work
    @Published var cycles = 0
    private var ticker: Timer?

    var isActive: Bool { end != nil || pausedRemaining != nil }
    var isPaused: Bool { pausedRemaining != nil }

    func remaining(at now: Date = Date()) -> Double {
        if let p = pausedRemaining { return p }
        if let e = end { return max(0, e.timeIntervalSince(now)) }
        return 0
    }

    func start() {
        ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, let e = self.end, Date() >= e else { return }
            self.finish()
        }
        RunLoop.main.add(ticker!, forMode: .common)
    }

    func begin(seconds: Double, label: String = "Timer") {
        pomodoro = false
        run(seconds, label)
    }

    private func run(_ seconds: Double, _ name: String) {
        total = seconds
        label = name
        pausedRemaining = nil
        end = Date().addingTimeInterval(seconds)
    }

    func beginPomodoro() {
        pomodoro = true
        phase = .work
        cycles = 0
        run(Prefs.double("pomodoroWork") * 60, Phase.work.rawValue)
    }

    func pause() {
        guard let e = end else { return }
        pausedRemaining = max(0, e.timeIntervalSinceNow)
        end = nil
    }

    func resume() {
        guard let p = pausedRemaining else { return }
        pausedRemaining = nil
        end = Date().addingTimeInterval(p)
    }

    func stop() {
        end = nil
        pausedRemaining = nil
        pomodoro = false
    }

    private func finish() {
        NSSound(named: "Glass")?.play()
        if pomodoro {
            if phase == .work {
                cycles += 1
                phase = .rest
                ActivityCenter.shared.show(Toast(icon: "cup.and.saucer.fill", text: "Break time", tint: .green), seconds: 5)
                run(Prefs.double("pomodoroBreak") * 60, Phase.rest.rawValue)
            } else {
                phase = .work
                ActivityCenter.shared.show(Toast(icon: "brain.head.profile", text: "Focus time", tint: .orange), seconds: 5)
                run(Prefs.double("pomodoroWork") * 60, Phase.work.rawValue)
            }
        } else {
            let name = label
            end = nil
            ActivityCenter.shared.show(Toast(icon: "bell.fill", text: "\(name) done", tint: .orange), seconds: 6)
        }
    }
}
