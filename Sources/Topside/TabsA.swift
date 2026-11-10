import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Now playing

struct PlayerView: View {
    @ObservedObject private var media = MediaService.shared
    @AppStorage("lyrics") private var lyricsOn = false

    var body: some View {
        if let t = media.track {
            VStack(spacing: 9) {
                HStack(spacing: 11) {
                    artwork
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        Text(t.artist.isEmpty ? t.appName : t.artist)
                            .font(.system(size: 12)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    Waveform(playing: media.isPlaying)
                }
                Scrubber()
                HStack {
                    IconButton(icon: "quote.bubble" + (lyricsOn ? ".fill" : ""), size: 12,
                               tint: lyricsOn ? .white : .white.opacity(0.4),
                               help: lyricsOn ? "Hide lyrics" : "Show lyrics (looks the song up on lrclib.net)") {
                        lyricsOn.toggle()
                        media.reloadLyrics()
                    }
                    Spacer()
                    IconButton(icon: "backward.fill", size: 14, help: "Previous") { media.previous() }
                    IconButton(icon: media.isPlaying ? "pause.fill" : "play.fill", size: 20, help: "Play/Pause") { media.togglePlay() }
                        .padding(.horizontal, 12)
                    IconButton(icon: "forward.fill", size: 14, help: "Next") { media.next() }
                    Spacer()
                    IconButton(icon: "arrow.up.forward.app", size: 12, tint: .white.opacity(0.4), help: "Open \(t.appName)") { media.activatePlayer() }
                }
                if lyricsOn { LyricLineView() }
            }
        } else {
            VStack(spacing: 6) {
                Image(systemName: "music.note").font(.system(size: 22)).foregroundStyle(.white.opacity(0.3))
                Text("Nothing playing").font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.45))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var artwork: some View {
        Group {
            if let art = media.artwork {
                Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack { Color.white.opacity(0.08); Image(systemName: "music.note").font(.system(size: 18)).foregroundStyle(.white.opacity(0.35)) }
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

struct Scrubber: View {
    @ObservedObject private var media = MediaService.shared
    @State private var dragValue: Double?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            let duration = media.track?.duration ?? 0
            let elapsed = dragValue ?? media.elapsed(at: ctx.date)
            let fraction = duration > 0 ? min(1, elapsed / duration) : 0
            HStack(spacing: 8) {
                Text(clock(elapsed)).frame(width: 34, alignment: .leading)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.16))
                        Capsule().fill(Color.white.opacity(0.75)).frame(width: g.size.width * fraction)
                    }
                    .frame(height: dragValue == nil ? 4 : 7)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            guard duration > 0 else { return }
                            dragValue = max(0, min(1, v.location.x / g.size.width)) * duration
                        }
                        .onEnded { _ in
                            if let d = dragValue { media.seek(to: d) }
                            dragValue = nil
                        })
                    .animation(.easeOut(duration: 0.15), value: dragValue == nil)
                }
                .frame(height: 12)
                Text(duration > 0 ? "-" + clock(duration - elapsed) : "--:--").frame(width: 34, alignment: .trailing)
            }
            .font(.system(size: 10, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.45))
        }
    }
}

struct LyricLineView: View {
    @ObservedObject private var media = MediaService.shared
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.4)) { ctx in
            let line = media.currentLyric(at: ctx.date) ?? (media.lyrics.first.map { $0.time < 0 ? $0.text : "♪" } ?? media.lyricsStatus)
            Text(line.isEmpty ? "♪" : line)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .id(line)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.25), value: line)
        }
    }
}

struct TodayView: View {
    @ObservedObject private var cal = CalendarService.shared
    @ObservedObject private var weather = WeatherService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Date(), format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if !weather.temperature.isEmpty {
                    Image(systemName: weather.icon).symbolRenderingMode(.multicolor).font(.system(size: 12))
                    Text("\(weather.temperature) \(weather.place)").font(.system(size: 12, weight: .medium))
                        .help("\(weather.summary) · \(weather.range)")
                } else {
                    Text(weather.place.isEmpty ? "Set a city in Settings" : weather.place)
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.35))
                }
            }
            if !cal.eventAccess {
                Button("Show my calendar") { cal.requestEvents() }
                    .buttonStyle(.bordered).controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if cal.events.isEmpty {
                Text("Nothing else today or tomorrow").font(.system(size: 12)).foregroundStyle(.white.opacity(0.4))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(cal.events) { e in
                            HStack(spacing: 8) {
                                Capsule().fill(e.color).frame(width: 3, height: 26)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(e.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                    Text(when(e)).font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func when(_ e: DayEvent) -> String {
        let day = Calendar.current.isDateInToday(e.start) ? "" : "Tomorrow · "
        if e.allDay { return day + "All day" }
        let f = Date.FormatStyle.dateTime.hour().minute()
        return day + e.start.formatted(f) + " – " + e.end.formatted(f)
    }
}

// MARK: - File tray

struct ShelfTab: View {
    @ObservedObject private var shelf = ShelfService.shared
    @ObservedObject private var downloads = DownloadsService.shared
    @State private var airDropTargeted = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 6) {
                Image(systemName: "dot.radiowaves.up.forward").font(.system(size: 17))
                Text("AirDrop").font(.system(size: 11, weight: .semibold))
                Text("Drop to send").font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
            }
            .frame(width: 84).frame(maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .foregroundStyle(airDropTargeted ? Color.accentColor : Color.white.opacity(0.25)))
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.accentColor.opacity(airDropTargeted ? 0.2 : 0)))
            .contentShape(Rectangle())
            .onDrop(of: [UTType.fileURL], isTargeted: $airDropTargeted) { providers in
                collect(providers) { shelf.airDrop($0) }
                return true
            }
            .onTapGesture { shelf.airDrop(shelf.items) }
            .help("Drop files to AirDrop them, or click to AirDrop everything in the tray")

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(shelf.items.isEmpty ? "Tray" : "Tray · \(shelf.items.count)").font(.system(size: 12, weight: .semibold))
                    if !shelf.busy.isEmpty { ProgressView().controlSize(.mini); Text(shelf.busy).font(.system(size: 10)).foregroundStyle(.secondary) }
                    ForEach(downloads.active) { d in
                        Label("\(d.name) · \(ByteCountFormatter.string(fromByteCount: d.bytes, countStyle: .file))", systemImage: "arrow.down.circle")
                            .font(.system(size: 10)).foregroundStyle(.blue).lineLimit(1)
                    }
                    Spacer()
                    if !shelf.items.isEmpty { Pill(text: "Clear") { shelf.clear() } }
                }
                if shelf.items.isEmpty {
                    VStack(spacing: 5) {
                        Image(systemName: "tray.and.arrow.down").font(.system(size: 20)).foregroundStyle(.white.opacity(0.3))
                        Text("Drag files onto the notch").font(.system(size: 12)).foregroundStyle(.white.opacity(0.45))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) { ForEach(shelf.items, id: \.self) { ShelfItemView(url: $0) } }
                    }
                    .frame(maxHeight: .infinity)
                }
            }
        }
    }

    private func collect(_ providers: [NSItemProvider], done: @escaping ([URL]) -> Void) {
        var urls: [URL] = []
        let group = DispatchGroup()
        for p in providers {
            group.enter()
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                if let url { DispatchQueue.main.async { urls.append(url) } }
                DispatchQueue.main.async { group.leave() }
            }
        }
        group.notify(queue: .main) { done(urls) }
    }
}

struct ShelfItemView: View {
    let url: URL
    @ObservedObject private var shelf = ShelfService.shared
    @State private var hover = false

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 36, height: 36)
            Text(url.lastPathComponent).font(.system(size: 10)).lineLimit(2).multilineTextAlignment(.center).frame(width: 66)
        }
        .padding(6)
        .frame(width: 76).frame(maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(hover ? 0.14 : 0.07)))
        .overlay(alignment: .topTrailing) {
            if hover {
                Button {
                    if NSEvent.modifierFlags.contains(.option) { shelf.trash(url) } else { shelf.remove(url) }
                } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 14)).foregroundStyle(.white.opacity(0.8))
                }
                .buttonStyle(.plain).padding(4)
                .help("Remove from tray. Hold Option to move the file to the Trash.")
            }
        }
        .onHover { hover = $0 }
        .onTapGesture { NSWorkspace.shared.open(url) }
        .onDrag { NSItemProvider(object: url as NSURL) }
        .contextMenu {
            Button("Open") { NSWorkspace.shared.open(url) }
            Button("Quick Look") { shelf.quickLook(url) }
            Button("Show in Finder") { shelf.reveal(url) }
            Divider()
            Button("AirDrop") { shelf.airDrop([url]) }
            Button("Share…") { shelf.share(url, from: NSApp.windows.first(where: { $0 is NotchPanel && $0.frame.height > 100 })?.contentView) }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.path, forType: .string)
            }
            Divider()
            if url.pathExtension.lowercased() == "zip" {
                Button("Unzip") { shelf.unzip(url) }
            } else {
                Button("Compress to Zip") { shelf.zip(url) }
            }
            Divider()
            Button("Remove from Tray") { shelf.remove(url) }
            Button("Move to Trash") { shelf.trash(url) }
        }
    }
}

// MARK: - Clipboard

struct ClipboardTab: View {
    @ObservedObject private var clipboard = ClipboardService.shared
    @State private var query = ""
    @State private var copied: UUID?
    @AppStorage("clipboardEnabled") private var enabled = true

    private var results: [Clip] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? clipboard.clips : clipboard.clips.filter { ($0.text ?? "image").lowercased().contains(q) }
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.5))
                    TextField("Search", text: $query).textFieldStyle(.plain)
                }
                .font(.system(size: 12))
                .padding(.horizontal, 9).padding(.vertical, 6)
                .background(Capsule().fill(Color.white.opacity(0.08)))
                IconButton(icon: enabled ? "record.circle.fill" : "pause.circle", size: 13, tint: enabled ? .red : .white.opacity(0.5), help: enabled ? "Recording copies. Click to pause." : "Paused. Click to record copies.") { enabled.toggle() }
                IconButton(icon: "trash", size: 12, tint: .white.opacity(0.5), help: "Clear history") { clipboard.clips = [] }
            }
            if results.isEmpty {
                Text(clipboard.clips.isEmpty ? "Things you copy will show up here" : "No matches")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.45))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 4) {
                        ForEach(results) { c in
                            HStack(spacing: 8) {
                                if let img = c.image {
                                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fit).frame(height: 26)
                                    Text("Image").font(.system(size: 12))
                                } else {
                                    Text((c.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
                                        .font(.system(size: 12)).lineLimit(1)
                                }
                                Spacer(minLength: 6)
                                Text(copied == c.id ? "Copied" : ago(c.date))
                                    .font(.system(size: 10)).foregroundStyle(copied == c.id ? Color.green : Color.white.opacity(0.4))
                                IconButton(icon: "xmark", size: 9, tint: .white.opacity(0.4)) { clipboard.remove(c) }
                            }
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.06)))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                clipboard.copy(c)
                                copied = c.id
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { if copied == c.id { copied = nil } }
                            }
                        }
                    }
                }
            }
        }
    }
}

