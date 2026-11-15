import AppKit
import SwiftUI
import Combine

@main
enum Main {
    static let delegate = AppDelegate()
    static func main() {
        let app = NSApplication.shared
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

// MARK: - Panel

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }
}

// MARK: - One notch per screen

final class NotchController {
    let screen: NSScreen
    let model: NotchModel
    let panel = NotchPanel()
    private var bag = Set<AnyCancellable>()
    private var hoverSince: Date?
    private var outsideSince: Date?
    private var swipeX: CGFloat = 0
    private var swipeY: CGFloat = 0
    private var lastSwipe = Date.distantPast

    init(screen: NSScreen) {
        self.screen = screen
        let hasNotch = screen.safeAreaInsets.top > 0
        let size: CGSize
        if hasNotch {
            let left = screen.auxiliaryTopLeftArea?.width ?? 0
            let right = screen.auxiliaryTopRightArea?.width ?? 0
            let w = screen.frame.width - left - right
            size = CGSize(width: w > 50 ? w : 185, height: screen.safeAreaInsets.top)
        } else {
            let bar = screen.frame.maxY - screen.visibleFrame.maxY
            size = CGSize(width: 185, height: max(24, min(bar, 38)))
        }
        model = NotchModel(notchSize: size, hasHardwareNotch: hasNotch)

        let host = NSHostingView(rootView: NotchRootView(model: model))
        host.sizingOptions = []
        panel.contentView = host
        panel.setFrame(frame(open: false), display: true)
        panel.orderFrontRegardless()

        model.onOpenChange = { [weak self] open in self?.resize(open: open) }
    }

    func teardown() {
        bag.removeAll()
        panel.orderOut(nil)
    }

    private func frame(open: Bool) -> NSRect {
        let s = screen.frame
        let w: CGFloat = open ? model.openSize.width + 90 : model.notchSize.width + 40
        let h: CGFloat = open ? model.openSize.height + 70 : model.notchSize.height + NotchModel.toastHeight + 22
        return NSRect(x: s.midX - w / 2, y: s.maxY - h, width: w, height: h)
    }

    private func resize(open: Bool) {
        if open {
            panel.setFrame(frame(open: true), display: true)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self, !self.model.isOpen else { return }
                // Hand keyboard focus back to whatever app the person was using.
                if self.panel.isKeyWindow {
                    self.panel.makeFirstResponder(nil)
                    self.panel.orderOut(nil)
                }
                self.panel.setFrame(self.frame(open: false), display: true)
                self.panel.orderFrontRegardless()
            }
        }
    }

    private var closedRect: NSRect {
        let s = screen.frame
        let w = model.closedWidth
        return NSRect(x: s.midX - w / 2, y: s.maxY - model.notchSize.height, width: w, height: model.notchSize.height + 4)
    }

    private var openRect: NSRect {
        let s = screen.frame
        let sz = model.openSize
        return NSRect(x: s.midX - sz.width / 2, y: s.maxY - sz.height, width: sz.width, height: sz.height + 4).insetBy(dx: -18, dy: -18)
    }

    /// Called ~15x/second with the global pointer position.
    func tick(mouse: NSPoint, buttons: Int) {
        if !model.isOpen {
            if closedRect.contains(mouse), buttons == 0, Prefs.bool("openOnHover") {
                if hoverSince == nil { hoverSince = Date() }
                if Date().timeIntervalSince(hoverSince!) >= Prefs.double("hoverDelay") {
                    hoverSince = nil
                    model.open()
                }
            } else {
                hoverSince = nil
            }
            outsideSince = nil
        } else {
            if openRect.contains(mouse) || model.pinned || buttons != 0 || model.dropTargeted {
                outsideSince = nil
            } else {
                if outsideSince == nil { outsideSince = Date() }
                if Date().timeIntervalSince(outsideSince!) >= 0.35 {
                    outsideSince = nil
                    model.close()
                }
            }
        }
    }

    /// Two-finger swipes over the notch.
    func scroll(_ e: NSEvent) {
        guard Prefs.bool("swipeGestures") else { return }
        if e.phase == .began { swipeX = 0; swipeY = 0 }
        swipeX += e.scrollingDeltaX
        swipeY += e.scrollingDeltaY
        guard Date().timeIntervalSince(lastSwipe) > 0.45 else { return }
        let inHeader = e.locationInWindow.y >= panel.frame.height - model.notchSize.height - NotchModel.stripHeight - 2
        if abs(swipeX) > 45, abs(swipeX) > abs(swipeY) * 1.5 {
            if !model.isOpen {
                swipeX > 0 ? MediaService.shared.previous() : MediaService.shared.next()
            } else if inHeader {
                model.step(swipeX > 0 ? -1 : 1)
            } else { return }
            fired()
        } else if abs(swipeY) > 45, abs(swipeY) > abs(swipeX) * 1.5 {
            if !model.isOpen, swipeY > 0 { model.open(); fired() }
            else if model.isOpen, inHeader, swipeY < 0 { model.close(); fired() }
        }
    }

    private func fired() {
        lastSwipe = Date()
        swipeX = 0
        swipeY = 0
    }
}

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controllers: [NotchController] = []
    private var pointerTimer: Timer?
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var bag = Set<AnyCancellable>()
    let menuBarHider = MenuBarHider()
    let notchBar = NotchBarHider()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Prefs.register()
        rebuild()
        installStatusItem()

        MediaService.shared.start()
        BatteryService.shared.start()
        ClipboardService.shared.start()
        TimerService.shared.start()
        DownloadsService.shared.start()
        menuBarHider.apply()
        notchBar.apply()

        pointerTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 15.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let m = NSEvent.mouseLocation
            let b = NSEvent.pressedMouseButtons
            for c in self.controllers { c.tick(mouse: m, buttons: b) }
        }
        RunLoop.main.add(pointerTimer!, forMode: .common)

        NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] e in
            if let c = self?.controllers.first(where: { $0.panel === e.window }) { c.scroll(e) }
            return e
        }

        // Scripting hook: post the distributed notification "local.topside.control" with an object of
        // "open", "open:<tab>", "close", "settings", "shelf:<path>", "timer:<seconds>", "stoptimer",
        // "toast:<text>", "media:<play|next|previous>", "playlist:<name>" or
        // "shuffle:<name>" or "playlists" to drive the notch from scripts.
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("local.topside.control"), object: nil, queue: .main) { [weak self] note in
            guard let self, let cmd = note.object as? String, let model = self.controllers.first?.model else { return }
            let parts = cmd.split(separator: ":", maxSplits: 1).map(String.init)
            switch parts[0] {
            case "open":
                model.pinned = true
                model.open(parts.count > 1 ? Tab(rawValue: parts[1]) : nil)
                if parts.count > 1, let t = Tab(rawValue: parts[1]) { model.tab = t }
            case "close": model.close()
            case "settings": self.showSettings()
            case "shelf": if parts.count > 1 { ShelfService.shared.add(URL(fileURLWithPath: parts[1])) }
            case "timer": TimerService.shared.begin(seconds: Double(parts.count > 1 ? parts[1] : "") ?? 60)
            case "stoptimer": TimerService.shared.stop()
            case "toast": ActivityCenter.shared.show(Toast(icon: "bell.fill", text: parts.count > 1 ? parts[1] : "Hello"))
            case "playlists":
                PlaylistService.shared.browsing = true
                model.pinned = true
                model.open(.home)
            case "playlist", "shuffle":
                if parts.count > 1 {
                    PlaylistService.shared.playByName(parts[1], shuffle: parts[0] == "shuffle")
                }
            case "media":
                switch parts.count > 1 ? parts[1] : "" {
                case "next": MediaService.shared.next()
                case "previous", "prev": MediaService.shared.previous()
                default: MediaService.shared.togglePlay()
                }
            default: break
            }
        }

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.rebuild()
            self?.notchBar.apply()
        }
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.prefsChanged() }
            .store(in: &bag)
    }

    private var layoutKey = ""

    private func prefsChanged() {
        let key = "\(Prefs.bool("allDisplays"))\(Prefs.bool("virtualNotch"))"
        if key != layoutKey { rebuild() }
        menuBarHider.apply()
        notchBar.apply()
    }

    private func rebuild() {
        layoutKey = "\(Prefs.bool("allDisplays"))\(Prefs.bool("virtualNotch"))"
        controllers.forEach { $0.teardown() }
        controllers = []
        let virtual = Prefs.bool("virtualNotch")
        var screens = NSScreen.screens.filter { $0.safeAreaInsets.top > 0 }
        if Prefs.bool("allDisplays"), virtual {
            screens = NSScreen.screens
        } else if screens.isEmpty, virtual, let main = NSScreen.main ?? NSScreen.screens.first {
            screens = [main]
        }
        controllers = screens.map { NotchController(screen: $0) }
    }

    // MARK: Status item

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "Topside")
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Notch", action: #selector(openNotch), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Topside", action: #selector(quit), keyEquivalent: "q").target = self
        item.menu = menu
        statusItem = item
    }

    @objc func openNotch() {
        controllers.first?.model.pinned = true
        controllers.first?.model.open()
    }

    @objc func quit() { NSApp.terminate(nil) }

    @objc func showSettings() {
        if settingsWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 620),
                             styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            w.title = "Topside Settings"
            w.isReleasedWhenClosed = false
            w.contentViewController = NSHostingController(rootView: SettingsView())
            w.center()
            settingsWindow = w
        }
        controllers.forEach { $0.model.close() }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Menu bar icon hider

/// Two extra status items: a chevron and a divider. Icons the person ⌘-drags to the left of the
/// divider get pushed off screen when the divider is expanded.
final class MenuBarHider {
    private var toggle: NSStatusItem?
    private var divider: NSStatusItem?
    private var collapsed = false
    private var rehide: DispatchWorkItem?

    func apply() {
        let on = Prefs.bool("menuBarHider")
        if on, toggle == nil {
            let t = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            t.autosaveName = "TopsideHiderToggle"
            t.button?.target = self
            t.button?.action = #selector(flip)
            let d = NSStatusBar.system.statusItem(withLength: 10)
            d.autosaveName = "TopsideHiderDivider"
            d.button?.title = "│"
            d.button?.appearsDisabled = true
            toggle = t
            divider = d
            setCollapsed(true)
        } else if !on, let t = toggle, let d = divider {
            NSStatusBar.system.removeStatusItem(t)
            NSStatusBar.system.removeStatusItem(d)
            toggle = nil
            divider = nil
        }
    }

    @objc private func flip() { setCollapsed(!collapsed) }

    private func setCollapsed(_ c: Bool) {
        collapsed = c
        divider?.length = c ? 10_000 : 10
        toggle?.button?.image = NSImage(systemSymbolName: c ? "chevron.left" : "chevron.right", accessibilityDescription: "Show or hide menu bar icons")
        rehide?.cancel()
        let delay = Prefs.double("autoRehide")
        if !c, delay > 0 {
            let w = DispatchWorkItem { [weak self] in self?.setCollapsed(true) }
            rehide = w
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: w)
        }
    }
}

// MARK: - "Hide the notch" black menu bar strip

/// A black strip that sits just above the wallpaper, behind the (translucent) menu bar,
/// so the notch blends into a black bar.
final class NotchBarHider {
    private var windows: [NSWindow] = []

    func apply() {
        windows.forEach { $0.orderOut(nil) }
        windows = []
        guard Prefs.bool("hideNotchBar") else { return }
        for s in NSScreen.screens where s.safeAreaInsets.top > 0 {
            let h = s.safeAreaInsets.top
            let w = NSWindow(contentRect: NSRect(x: s.frame.minX, y: s.frame.maxY - h, width: s.frame.width, height: h),
                             styleMask: .borderless, backing: .buffered, defer: false)
            w.backgroundColor = .black
            w.isOpaque = true
            w.hasShadow = false
            w.ignoresMouseEvents = true
            w.isReleasedWhenClosed = false
            w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            w.orderFrontRegardless()
            windows.append(w)
        }
    }
}
