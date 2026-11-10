import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Root

struct NotchRootView: View {
    @ObservedObject var model: NotchModel
    @ObservedObject private var act = ActivityCenter.shared
    @AppStorage("theme") private var theme = "black"
    @AppStorage("glow") private var glow = false

    var body: some View {
        // Collapsed, the app is exactly the camera housing: nothing spills into the menu bar.
        // Short alerts drop down underneath it instead.
        let toast = act.toast
        let closed = CGSize(width: model.notchSize.width, height: model.notchSize.height + (toast == nil ? 0 : NotchModel.toastHeight))
        let size = model.isOpen ? model.openSize : closed
        let topR: CGFloat = model.isOpen ? 9 : 0
        let shape = NotchShape(topRadius: topR, bottomRadius: model.isOpen ? 30 : (toast == nil ? 9 : 14))

        ZStack(alignment: .top) {
            if glow {
                GlowView(shape: shape).frame(width: size.width + 2 * topR, height: size.height)
            }
            ZStack(alignment: .top) {
                if model.isOpen {
                    OpenView(model: model)
                        .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .top)))
                } else {
                    ClosedView(toast: toast, notchHeight: model.notchSize.height)
                        .transition(.opacity)
                }
            }
            .frame(width: size.width, height: size.height)
            .padding(.horizontal, topR)
            .background {
                if theme == "glass" {
                    ZStack { Rectangle().fill(.ultraThinMaterial); Color.black.opacity(0.35) }
                } else {
                    Color.black
                }
            }
            .clipShape(shape)
            .overlay {
                if model.dropTargeted { shape.stroke(Color.accentColor, lineWidth: 2) }
            }
            .shadow(color: .black.opacity(model.isOpen ? 0.4 : 0), radius: 16, y: 8)
            .contentShape(shape)
            .onTapGesture { if !model.isOpen { model.open() } }
            .onDrop(of: [UTType.fileURL], isTargeted: $model.dropTargeted) { providers in
                model.tab = .shelf
                for p in providers {
                    _ = p.loadObject(ofClass: URL.self) { url, _ in
                        if let url { ShelfService.shared.add(url) }
                    }
                }
                return true
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.38, dampingFraction: 0.8), value: model.isOpen)
        .animation(.spring(response: 0.34, dampingFraction: 0.78), value: toast)
        .onChange(of: model.dropTargeted) { _, targeted in
            if targeted, !model.isOpen { model.open(.shelf) }
        }
        .environment(\.colorScheme, .dark)
    }
}

struct GlowView: View {
    let shape: NotchShape
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            shape
                .stroke(AngularGradient(colors: [.purple, .blue, .cyan, .pink, .orange, .purple], center: .center,
                                        angle: .degrees(t.truncatingRemainder(dividingBy: 6) * 60)), lineWidth: 5)
                .blur(radius: 7)
                .opacity(0.9)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Collapsed notch

struct ClosedView: View {
    let toast: Toast?
    let notchHeight: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: notchHeight)
            if let t = toast {
                HStack(spacing: 6) {
                    Image(systemName: t.icon).font(.system(size: 11, weight: .semibold)).foregroundStyle(t.tint)
                    Text(t.text).font(.system(size: 11, weight: .medium)).foregroundStyle(.white).lineLimit(1)
                }
                .padding(.horizontal, 12)
                .frame(height: NotchModel.toastHeight - 4)
                .transition(.opacity)
            }
            Spacer(minLength: 0)
        }
    }
}

struct Waveform: View {
    let playing: Bool

    static func barHeight(_ i: Int, _ t: Double, _ playing: Bool) -> CGFloat {
        guard playing else { return 3 }
        let speed: Double = 3.1 + Double(i) * 0.9
        let phase: Double = Double(i) * 1.7
        return CGFloat(3.0 + 11.0 * abs(sin(t * speed + phase)))
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.12, paused: !playing)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { i in
                    Capsule().fill(Color.white.opacity(0.75)).frame(width: 2, height: Self.barHeight(i, t, playing))
                }
            }
            .frame(height: 16)
            .animation(.easeInOut(duration: 0.12), value: t)
        }
    }
}

// MARK: - Expanded notch

struct OpenView: View {
    @ObservedObject var model: NotchModel
    @AppStorage("disabledTabs") private var disabledTabs = ""

    var body: some View {
        VStack(spacing: 0) {
            // The row level with the camera housing stays empty, so the panel reads as the notch growing.
            Color.clear.frame(height: model.notchSize.height)
            strip.frame(height: NotchModel.stripHeight)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 16)
        }
    }

    private var strip: some View {
        HStack(spacing: 1) {
            ForEach(Tab.enabled) { t in
                let selected = model.tab == t
                Button {
                    withAnimation(.snappy(duration: 0.22)) { model.tab = t }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: t.icon).font(.system(size: 11, weight: .medium))
                        if selected { Text(t.short).font(.system(size: 11, weight: .semibold)).fixedSize() }
                    }
                    .foregroundStyle(selected ? Color.white : Color.white.opacity(0.45))
                    .padding(.horizontal, selected ? 10 : 7)
                    .frame(height: 24)
                    .background(Capsule().fill(Color.white.opacity(selected ? 0.14 : 0)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(t.title)
            }
            Spacer(minLength: 0)
            IconButton(icon: model.pinned ? "pin.fill" : "pin", size: 10, tint: model.pinned ? .yellow : .white.opacity(0.4),
                       help: "Keep open") { model.pinned.toggle() }
            IconButton(icon: "gearshape", size: 10, tint: .white.opacity(0.4), help: "Settings") { Main.delegate.showSettings() }
        }
        .padding(.horizontal, 14)
    }

    @ViewBuilder private var content: some View {
        switch model.tab {
        case .home: PlayerView()
        case .today: TodayView()
        case .shelf: ShelfTab()
        case .clipboard: ClipboardTab()
        case .timer: TimerTab()
        case .mirror: MirrorTab()
        case .devices: SystemTab()
        case .prompter: PrompterTab()
        case .agents: AgentsTab()
        }
    }
}
