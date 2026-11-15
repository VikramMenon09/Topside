import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Now playing

struct PlayerView: View {
    @ObservedObject private var media = MediaService.shared
    @AppStorage("lyrics") private var lyricsOn = false
    @ObservedObject private var playlists = PlaylistService.shared

    var body: some View {
        if playlists.browsing {
            PlaylistsView(close: { playlists.browsing = false })
        } else {
            player
        }
    }

    @ViewBuilder
    private var player: some View {
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
                // Transport sits in its own centred layer, so the side buttons never pull
                // it off the panel's midline however many of them there are.
                ZStack {
                    HStack(spacing: 0) {
                        IconButton(icon: "music.note.list", size: 12, tint: .white.opacity(0.4),
                                   help: "Playlists") { playlists.browsing = true }
                        IconButton(icon: "quote.bubble" + (lyricsOn ? ".fill" : ""), size: 12,
                                   tint: lyricsOn ? .white : .white.opacity(0.4),
                                   help: lyricsOn ? "Hide lyrics" : "Show lyrics (looks the song up on lrclib.net)") {
                            lyricsOn.toggle()
                            media.reloadLyrics()
                        }
                        Spacer(minLength: 0)
                        IconButton(icon: "arrow.up.forward.app", size: 12, tint: .white.opacity(0.4), help: "Open \(t.appName)") { media.activatePlayer() }
                    }
                    HStack(spacing: 0) {
                        IconButton(icon: "backward.fill", size: 14, help: "Previous") { media.previous() }
                        IconButton(icon: media.isPlaying ? "pause.fill" : "play.fill", size: 20, help: "Play/Pause") { media.togglePlay() }
                            .padding(.horizontal, 12)
                        IconButton(icon: "forward.fill", size: 14, help: "Next") { media.next() }
                    }
                }
                if lyricsOn { LyricLineView() }
            }
        } else {
            VStack(spacing: 9) {
                Image(systemName: "music.note").font(.system(size: 20)).foregroundStyle(.white.opacity(0.3))
                Text("Nothing playing").font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.45))
                Pill(text: "Playlists") { playlists.browsing = true }
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

/// Browses Music inside the Playing tab, rather than as a tab of its own: starting
/// something is what you do instead of, or just before, looking at what is playing.
/// Three screens share one chrome — the playlists, one playlist's tracks, and the queue.
struct PlaylistsView: View {
    let close: () -> Void
    @ObservedObject private var service = PlaylistService.shared
    @ObservedObject private var queue = QueueService.shared
    @AppStorage("shufflePlaylists") private var shuffle = false
    @State private var query = ""

    var body: some View {
        VStack(spacing: 7) {
            header
            body(for: screen)
        }
        .onAppear {
            // Only ask Music once the list is actually on screen, so nothing launches it
            // merely because the notch was opened.
            if service.playerIsRunning || !service.items.isEmpty { service.reloadIfStale() }
        }
    }

    private enum Screen { case playlists, tracks, queue }

    private var screen: Screen {
        if service.showingQueue { return .queue }
        return service.openPlaylist == nil ? .playlists : .tracks
    }

    // MARK: Chrome

    private var header: some View {
        HStack(spacing: 7) {
            IconButton(icon: "chevron.left", size: 11, tint: .white.opacity(0.55), help: back.help) {
                query = ""
                back.action()
            }
            if screen == .queue {
                Text("Up next").font(.system(size: 12, weight: .semibold))
                Text("\(queue.items.count)")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.4))
                Spacer(minLength: 4)
                if !queue.items.isEmpty {
                    IconButton(icon: "play.fill", size: 11, tint: .white.opacity(0.6),
                               help: "Play the next one now") { queue.playNow() }
                    IconButton(icon: "trash", size: 11, tint: .white.opacity(0.35),
                               help: "Clear the queue") { queue.clear() }
                }
            } else {
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass").font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.35))
                    TextField(searchPrompt, text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11.5))
                }
                .padding(.horizontal, 8).frame(height: 24)
                .background(Capsule().fill(Color.white.opacity(0.08)))
                if let open = service.openPlaylist {
                    IconButton(icon: "shuffle", size: 11, tint: .white.opacity(0.6),
                               help: "Shuffle this playlist") { service.play(open, shuffle: true) }
                } else {
                    IconButton(icon: "shuffle", size: 11,
                               tint: shuffle ? .white : .white.opacity(0.35),
                               help: shuffle ? "Playlists start shuffled" : "Playlists start in order") { shuffle.toggle() }
                    IconButton(icon: "arrow.clockwise", size: 10, tint: .white.opacity(0.35),
                               help: "Reload from Music") { service.reload() }
                }
            }
            if !queue.items.isEmpty && screen != .queue { queueBadge }
        }
    }

    private var searchPrompt: String {
        service.openPlaylist.map { "Search \($0.name)" } ?? "Search playlists"
    }

    private var back: (help: String, action: () -> Void) {
        switch screen {
        case .queue: return ("Back", { service.showingQueue = false })
        case .tracks: return ("All playlists", { service.closePlaylist() })
        case .playlists: return ("Back to the player", close)
        }
    }

    private var queueBadge: some View {
        Button { service.showingQueue = true } label: {
            HStack(spacing: 3) {
                Image(systemName: "text.append").font(.system(size: 9, weight: .semibold))
                Text("\(queue.items.count)").font(.system(size: 10, weight: .semibold).monospacedDigit())
            }
            .foregroundStyle(.white.opacity(0.75))
            .padding(.horizontal, 7).frame(height: 20)
            .background(Capsule().fill(Color.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .help("\(queue.items.count) queued")
    }

    // MARK: Screens

    @ViewBuilder
    private func body(for screen: Screen) -> some View {
        switch screen {
        case .playlists: playlists
        case .tracks: trackList
        case .queue: queueList
        }
    }

    private var matchingPlaylists: [Playlist] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? service.items : service.items.filter { $0.name.lowercased().contains(q) }
    }

    @ViewBuilder
    private var playlists: some View {
        if service.loading && service.items.isEmpty {
            centred("Reading your library…")
        } else if !service.message.isEmpty && service.items.isEmpty {
            centred(service.message)
        } else if matchingPlaylists.isEmpty {
            centred(query.isEmpty ? "No playlists." : "Nothing matches “\(query)”.")
        } else {
            scroller {
                ForEach(matchingPlaylists) { item in
                    RowButton(
                        icon: "music.note.list",
                        title: item.name,
                        trailing: "\(item.count)",
                        tap: { service.open(item) })
                }
            }
        }
    }

    private var matchingTracks: [PlaylistTrack] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return service.tracks }
        return service.tracks.filter { $0.name.lowercased().contains(q) || $0.artist.lowercased().contains(q) }
    }

    @ViewBuilder
    private var trackList: some View {
        if service.loadingTracks {
            centred("Reading the playlist…")
        } else if matchingTracks.isEmpty {
            centred(query.isEmpty ? "This playlist is empty." : "Nothing matches “\(query)”.")
        } else if let open = service.openPlaylist {
            scroller {
                ForEach(matchingTracks) { track in
                    RowButton(
                        icon: "play.fill",
                        title: track.name,
                        subtitle: track.artist,
                        accessory: ("plus", "Add to the queue", { queue.add(track, from: open) }),
                        tap: { service.play(track, in: open) })
                }
            }
        }
    }

    @ViewBuilder
    private var queueList: some View {
        if queue.items.isEmpty {
            centred("Nothing queued. Add tracks with the + beside them.")
        } else {
            scroller {
                ForEach(queue.items) { item in
                    RowButton(
                        icon: "music.note",
                        title: item.track.name,
                        subtitle: item.track.artist,
                        accessory: ("xmark", "Remove from the queue", { queue.remove(item) }),
                        tap: { queue.playNow(item) })
                }
            }
        }
    }

    // MARK: Pieces

    private func scroller<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 2) { content() }
        }
        // The list is taller than the panel, so fade the last row out rather than
        // slicing it in half.
        .mask(LinearGradient(stops: [.init(color: .black, location: 0),
                                     .init(color: .black, location: 0.86),
                                     .init(color: .clear, location: 1)],
                             startPoint: .top, endPoint: .bottom))
    }

    private func centred(_ text: String) -> some View {
        VStack(spacing: 8) {
            Text(text)
                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            if !service.playerIsRunning && service.items.isEmpty && !service.loading {
                Pill(text: "Open Music") { service.reload() }
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One row of any of the three lists: an icon that turns into a play arrow on hover, a
/// title, an optional dimmed subtitle, and either a trailing figure or a button.
struct RowButton: View {
    let icon: String
    let title: String
    var subtitle: String = ""
    var trailing: String = ""
    var accessory: (icon: String, help: String, action: () -> Void)?
    let tap: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: hover ? "play.fill" : icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(hover ? 0.9 : 0.35))
                .frame(width: 14)
            Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1).layoutPriority(-1)
            }
            Spacer(minLength: 6)
            if !trailing.isEmpty {
                Text(trailing)
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.35))
            }
            if let accessory {
                Button(action: accessory.action) {
                    Image(systemName: accessory.icon)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(hover ? 0.8 : 0.3))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(accessory.help)
            }
        }
        .padding(.horizontal, 9).frame(height: 26)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.white.opacity(hover ? 0.12 : 0.05)))
        .contentShape(Rectangle())
        .onTapGesture(perform: tap)
        .onHover { hover = $0 }
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

