import AppKit
import SwiftUI
import AVFoundation

// MARK: - Timers & Pomodoro

struct TimerTab: View {
    @ObservedObject private var timers = TimerService.shared
    @State private var custom = 20

    var body: some View {
        HStack(spacing: 18) {
            TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
                let remaining = timers.remaining(at: ctx.date)
                ZStack {
                    Circle().stroke(Color.white.opacity(0.1), lineWidth: 5)
                    Circle().trim(from: 0, to: timers.total > 0 && timers.isActive ? remaining / timers.total : 0)
                        .stroke(Color.orange, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 1) {
                        Text(timers.isActive ? clock(remaining) : "0:00")
                            .font(.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit())
                        Text(timers.isActive ? timers.label : "Ready").font(.system(size: 9)).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                }
                .frame(width: 96, height: 96)
            }

            VStack(alignment: .leading, spacing: 10) {
                if timers.isActive {
                    if timers.pomodoro {
                        Text("Pomodoro · \(timers.cycles) finished").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                    }
                    HStack(spacing: 6) {
                        Pill(text: timers.isPaused ? "Resume" : "Pause", active: true) { timers.isPaused ? timers.resume() : timers.pause() }
                        Pill(text: "Stop") { timers.stop() }
                    }
                } else {
                    HStack(spacing: 5) {
                        ForEach([5, 10, 15, 30], id: \.self) { m in
                            Pill(text: "\(m) m") { timers.begin(seconds: Double(m) * 60, label: "\(m) min") }
                        }
                    }
                    HStack(spacing: 6) {
                        Stepper("\(custom) min", value: $custom, in: 1...600).font(.system(size: 11)).controlSize(.small)
                        Pill(text: "Start", active: true) { timers.begin(seconds: Double(custom) * 60, label: "\(custom) min") }
                    }
                    Pill(text: "Start Pomodoro") { timers.beginPomodoro() }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: .infinity)
    }
}

// MARK: - Mirror

struct MirrorTab: View {
    @State private var allowed = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    @State private var denied = AVCaptureDevice.authorizationStatus(for: .video) == .denied

    var body: some View {
        Group {
            if allowed {
                CameraPreview().clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .frame(width: 210)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "web.camera").font(.system(size: 28)).foregroundStyle(.white.opacity(0.4))
                    Text(denied ? "Camera access is off for Topside. Turn it on in System Settings › Privacy & Security › Camera."
                                : "Check how you look before a call")
                        .font(.system(size: 12)).foregroundStyle(.white.opacity(0.55)).multilineTextAlignment(.center)
                    if !denied {
                        Button("Turn on camera") {
                            AVCaptureDevice.requestAccess(for: .video) { ok in onMain { allowed = ok; denied = !ok } }
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct CameraPreview: NSViewRepresentable {
    final class PreviewView: NSView {
        let session = AVCaptureSession()
        private let queue = DispatchQueue(label: "topside.camera")

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            let preview = AVCaptureVideoPreviewLayer(session: session)
            preview.videoGravity = .resizeAspectFill
            layer = preview
            queue.async { [session] in
                guard let device = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: device),
                      session.canAddInput(input) else { return }
                session.addInput(input)
                session.startRunning()
                DispatchQueue.main.async {
                    if let c = preview.connection, c.isVideoMirroringSupported {
                        c.automaticallyAdjustsVideoMirroring = false
                        c.isVideoMirrored = true
                    }
                }
            }
        }

        required init?(coder: NSCoder) { fatalError() }

        func shutDown() { queue.async { [session] in session.stopRunning() } }
    }

    func makeNSView(context: Context) -> PreviewView { PreviewView(frame: .zero) }
    func updateNSView(_ nsView: PreviewView, context: Context) {}
    static func dismantleNSView(_ nsView: PreviewView, coordinator: ()) { nsView.shutDown() }
}

// MARK: - System

struct SystemTab: View {
    @ObservedObject private var battery = BatteryService.shared
    @ObservedObject private var stats = SystemStats.shared
    private let tick = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 11) {
            if battery.hasBattery {
                gauge("battery.75percent", "Battery", Double(battery.percent) / 100,
                      "\(battery.percent)%" + (battery.pluggedIn ? " ⚡" : ""), battery.percent <= 15 ? .red : .green)
            }
            gauge("cpu", "CPU", stats.cpu, "\(Int(stats.cpu * 100))%", .blue)
            gauge("memorychip", "Memory", stats.memory, "\(Int(stats.memory * 100))%", .purple)
            HStack(spacing: 8) {
                Image(systemName: "internaldrive").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5)).frame(width: 16)
                Text("Storage free").font(.system(size: 12)).foregroundStyle(.white.opacity(0.75))
                Spacer()
                Text(stats.diskFree).font(.system(size: 12, weight: .medium).monospacedDigit())
            }
        }
        .frame(maxHeight: .infinity)
        .onAppear { stats.refresh() }
        .onReceive(tick) { _ in stats.refresh() }
    }

    private func gauge(_ icon: String, _ name: String, _ value: Double, _ text: String, _ color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5)).frame(width: 16)
            Text(name).font(.system(size: 12)).foregroundStyle(.white.opacity(0.75)).frame(width: 54, alignment: .leading)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule().fill(color).frame(width: g.size.width * min(1, max(0.02, value)))
                }
            }
            .frame(height: 5)
            Text(text).font(.system(size: 12, weight: .medium).monospacedDigit()).frame(width: 52, alignment: .trailing)
        }
        .animation(.easeOut(duration: 0.4), value: value)
    }
}

// MARK: - Teleprompter

struct PrompterTab: View {
    @ObservedObject private var prompter = PrompterService.shared
    @AppStorage("prompterWPM") private var wpm = 140.0

    var body: some View {
        if prompter.running {
            VStack(spacing: 4) {
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 5) {
                            ForEach(Array(prompter.lines.enumerated()), id: \.offset) { i, line in
                                lineText(i, line).id(i)
                            }
                            Color.clear.frame(height: 70)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .onChange(of: prompter.index / PrompterService.perLine) { _, line in
                        withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(line, anchor: .top) }
                    }
                }
                HStack(spacing: 8) {
                    IconButton(icon: "chevron.up", size: 10) { prompter.nudge(-1) }
                    IconButton(icon: "chevron.down", size: 10) { prompter.nudge(1) }
                    if prompter.voice {
                        Label(prompter.status.isEmpty ? "Following your voice" : prompter.status, systemImage: "mic.fill")
                            .font(.system(size: 10)).foregroundStyle(.red)
                    } else if !prompter.status.isEmpty {
                        Text(prompter.status).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                    }
                    Spacer()
                    Pill(text: "Stop") { prompter.stop() }
                }
            }
        } else {
            HStack(spacing: 12) {
                Card(padding: 8) {
                    TextEditor(text: $prompter.script).font(.system(size: 12)).scrollContentBackground(.hidden)
                }
                .frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 9) {
                    Text("Teleprompter").font(.system(size: 12, weight: .semibold))
                                        VStack(alignment: .leading, spacing: 2) {
                        Text("\(Int(wpm)) words/min").font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
                        Slider(value: $wpm, in: 60...260, step: 10).controlSize(.small)
                    }
                    Pill(text: "Start", active: true) { prompter.start(voice: false) }
                    Pill(text: "Follow my voice") { prompter.start(voice: true) }
                    Spacer(minLength: 0)
                }
                .frame(width: 128)
            }
        }
    }

    private func lineText(_ i: Int, _ line: [String]) -> some View {
        let start = i * PrompterService.perLine
        var text = Text("")
        for (j, w) in line.enumerated() {
            let spoken = start + j < prompter.index
            text = text + Text(w + " ").foregroundColor(spoken ? .white.opacity(0.3) : .white)
        }
        return text.font(.system(size: 18, weight: .semibold)).multilineTextAlignment(.center)
    }
}

// MARK: - AI coding agents

struct AgentsTab: View {
    @ObservedObject private var agents = AgentsService.shared
    private let tick = Timer.publish(every: 4, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Recent sessions").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
                if agents.scanning { ProgressView().controlSize(.mini) }
                Spacer()
            }
            if agents.sessions.isEmpty {
                Text("No sessions in the last few hours").font(.system(size: 12)).foregroundStyle(.white.opacity(0.45))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 4) {
                        ForEach(agents.sessions) { s in
                            HStack(spacing: 8) {
                                Circle().fill(color(s.state)).frame(width: 7, height: 7)
                                VStack(alignment: .leading, spacing: 1) {
                                    HStack(spacing: 6) {
                                        Text(s.project).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                                        Text(s.tool == "Claude Code" ? "Claude" : s.tool).font(.system(size: 9, weight: .medium)).fixedSize().padding(.horizontal, 5).padding(.vertical, 1)
                                            .background(Capsule().fill(Color.white.opacity(0.12)))
                                        Text(s.state.rawValue).font(.system(size: 10, weight: .medium)).foregroundStyle(color(s.state)).lineLimit(1)
                                    }
                                    Text(s.snippet.isEmpty ? "—" : s.snippet).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                                }
                                Spacer(minLength: 4)
                                Text(ago(s.modified)).font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
                            }
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.06)))
                        }
                    }
                }
            }
        }
        .onAppear { agents.scan() }
        .onReceive(tick) { _ in agents.scan() }
    }

    private func color(_ s: AgentSession.State) -> Color {
        switch s {
        case .working: return .green
        case .tool: return .yellow
        case .waiting: return .orange
        case .idle: return .gray
        }
    }
}
