import AppKit
import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @AppStorage("openOnHover") private var openOnHover = true
    @AppStorage("hoverDelay") private var hoverDelay = 0.15
    @AppStorage("haptics") private var haptics = true
    @AppStorage("swipeGestures") private var swipeGestures = true
    @AppStorage("theme") private var theme = "black"
    @AppStorage("glow") private var glow = false
    @AppStorage("mediaActivity") private var mediaActivity = true
    @AppStorage("hudEnabled") private var hudEnabled = true
    @AppStorage("replaceSystemHUD") private var replaceSystemHUD = false
    @AppStorage("virtualNotch") private var virtualNotch = true
    @AppStorage("allDisplays") private var allDisplays = false
    @AppStorage("hideNotchBar") private var hideNotchBar = false
    @AppStorage("menuBarHider") private var menuBarHider = false
    @AppStorage("autoRehide") private var autoRehide = 8.0
    @AppStorage("weatherCity") private var weatherCity = ""
    @AppStorage("lyrics") private var lyrics = false
    @AppStorage("blockedMediaApps") private var blockedMediaApps = ""
    @AppStorage("watchDownloads") private var watchDownloads = false
    @AppStorage("clipboardEnabled") private var clipboardEnabled = true
    @AppStorage("bluetoothEnabled") private var bluetoothEnabled = false
    @AppStorage("disabledTabs") private var disabledTabs = ""
    @AppStorage("pomodoroWork") private var pomodoroWork = 25
    @AppStorage("pomodoroBreak") private var pomodoroBreak = 5
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var trusted = AXIsProcessTrusted()

    var body: some View {
        Form {
            Section("Opening the notch") {
                Toggle("Open when the pointer hovers over the notch", isOn: $openOnHover)
                if openOnHover {
                    Slider(value: $hoverDelay, in: 0...1, step: 0.05) { Text("Hover delay: \(hoverDelay, specifier: "%.2f") s") }
                } else {
                    Text("Click the notch to open it.").font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Two-finger swipes (skip tracks on the closed notch, switch tabs on the icon row)", isOn: $swipeGestures)
                Toggle("Haptic tap when it opens", isOn: $haptics)
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
                        catch { launchAtLogin = SMAppService.mainApp.status == .enabled }
                    }
            }

            Section("Look") {
                Picker("Background", selection: $theme) {
                    Text("Black").tag("black")
                    Text("Glass").tag("glass")
                }
                Toggle("Glow around the notch", isOn: $glow)
                Toggle("Show a notch on displays that don't have one", isOn: $virtualNotch)
                Toggle("Show on every display", isOn: $allDisplays).disabled(!virtualNotch)
                Toggle("Hide the notch with a black menu bar", isOn: $hideNotchBar)
                Text("Works best in Dark Mode, where menu bar text is already white.").font(.caption).foregroundStyle(.secondary)
            }

            Section("Tabs") {
                ForEach(Tab.allCases) { t in
                    Toggle(isOn: Binding(
                        get: { !Prefs.list("disabledTabs").contains(t.rawValue) },
                        set: { on in
                            var off = Set(Prefs.list("disabledTabs"))
                            if on { off.remove(t.rawValue) } else { off.insert(t.rawValue) }
                            disabledTabs = off.sorted().joined(separator: ",")
                        })) {
                        Label(t.title, systemImage: t.icon)
                    }
                }
            }

            Section("Music") {
                Toggle("Lyrics (sends the song title and artist to lrclib.net)", isOn: $lyrics)
                TextField("Ignore these apps", text: $blockedMediaApps, prompt: Text("e.g. com.google.Chrome, Safari"))
                Text("Comma-separated app names or bundle IDs that should never show in the player.").font(.caption).foregroundStyle(.secondary)
            }

            Section("Pomodoro") {
                Stepper("Focus: \(pomodoroWork) min", value: $pomodoroWork, in: 1...120)
                Stepper("Break: \(pomodoroBreak) min", value: $pomodoroBreak, in: 1...60)
            }

            Section("Today") {
                TextField("Weather city", text: $weatherCity, prompt: Text("e.g. Chicago"))
                Text("Weather comes from open-meteo.com; only the city name is sent.").font(.caption).foregroundStyle(.secondary)
            }

            Section("Activity") {
                Toggle("Keep clipboard history (in memory only, skips password managers)", isOn: $clipboardEnabled)
                Toggle("Watch the Downloads folder for downloads in progress", isOn: $watchDownloads)
            }

            Section("Menu bar icons") {
                Toggle("Add a chevron that hides menu bar icons", isOn: $menuBarHider)
                if menuBarHider {
                    Text("Hold ⌘ and drag any icon to the left of the │ divider. Click the chevron to show or hide those icons.")
                        .font(.caption).foregroundStyle(.secondary)
                    Slider(value: $autoRehide, in: 0...30, step: 1) {
                        Text(autoRehide == 0 ? "Hide again: never" : "Hide again after \(Int(autoRehide)) s")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 520, minHeight: 560)
    }
}
