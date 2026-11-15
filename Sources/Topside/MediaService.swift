import AppKit
import Combine

struct Track: Equatable {
    var title: String
    var artist: String
    var album: String
    var duration: Double
    var bundleID: String
    var appName: String
}

struct LyricLine: Equatable, Identifiable {
    let id: Int
    let time: Double
    let text: String
}

/// Reads the system-wide Now Playing session (any player: Music, Spotify, browsers, podcasts…)
/// by asking the system scripting host, which is allowed to talk to MediaRemote.
final class MediaService: ObservableObject {
    static let shared = MediaService()

    @Published var track: Track?
    @Published var isPlaying = false
    @Published var artwork: NSImage?
    @Published var lyrics: [LyricLine] = []
    @Published var lyricsStatus = ""

    private var elapsedBase = 0.0
    private var baseDate = Date()
    private var rate = 1.0
    private let queue = DispatchQueue(label: "topside.media")
    private var timer: Timer?
    private var busy = false
    private var artKey = ""

    private static let prelude = """
    ObjC.import('Foundation');
    const b=$.NSBundle.bundleWithPath('/System/Library/PrivateFrameworks/MediaRemote.framework/');b.load;
    """

    private static let infoScript = """
    function run(){\(prelude)
    const R=$.NSClassFromString('MRNowPlayingRequest'); if(!R) return '{}';
    const i=R.localNowPlayingItem; const p=R.localNowPlayingPlayerPath;
    if(!i||i.isNil()) return '{}';
    const d=i.nowPlayingInfo; if(!d||d.isNil()) return '{}';
    function g(k){const v=d.valueForKey('kMRMediaRemoteNowPlayingInfo'+k);return (v&&!v.isNil())?v:null}
    function s(k){const v=g(k);return v?ObjC.unwrap(v):null}
    const ts=g('Timestamp');
    let bid=null,app=null,parent=null;
    try{bid=ObjC.unwrap(p.client.bundleIdentifier);}catch(e){}
    try{app=ObjC.unwrap(p.client.displayName);}catch(e){}
    try{const pp=p.client.parentApplicationBundleIdentifier; if(pp&&!pp.isNil()) parent=ObjC.unwrap(pp);}catch(e){}
    return JSON.stringify({title:s('Title'),artist:s('Artist'),album:s('Album'),duration:s('Duration'),
      elapsed:s('ElapsedTime'),rate:s('PlaybackRate'),ts:ts?ts.timeIntervalSince1970:null,
      bid:parent||bid,app:app,playing:!!R.localIsPlaying});
    }
    """

    private static let artScript = """
    function run(){\(prelude)
    const R=$.NSClassFromString('MRNowPlayingRequest'); if(!R) return '';
    const i=R.localNowPlayingItem; if(!i||i.isNil()) return '';
    try{const a=i.artwork; if(a&&!a.isNil()){const d=a.imageData; if(d&&!d.isNil()) return ObjC.unwrap(d.base64EncodedStringWithOptions(0));}}catch(e){}
    try{const d=i.nowPlayingInfo.valueForKey('kMRMediaRemoteNowPlayingInfoArtworkData'); if(d&&!d.isNil()) return ObjC.unwrap(d.base64EncodedStringWithOptions(0));}catch(e){}
    return '';
    }
    """

    private static let commandScript = """
    function run(argv){\(prelude)
    if(argv[0]=='seek'){ObjC.bindFunction('MRMediaRemoteSetElapsedTime',['void',['double']]);$.MRMediaRemoteSetElapsedTime(parseFloat(argv[1]));return 'ok';}
    ObjC.bindFunction('MRMediaRemoteSendCommand',['bool',['int','id']]);
    return ''+$.MRMediaRemoteSendCommand(parseInt(argv[0]),$());
    }
    """

    private static let positionPlayers: Set<String> = [
        "com.apple.Music", "com.apple.TV", "com.apple.iTunes", "com.spotify.client",
    ]

    /// Reads the player's own position, for the players whose elapsed time MediaRemote
    /// reports as 0 until something changes the playback state.
    private static let positionScript = """
    tell application id "%@"
        if player state is stopped then return "stopped"
        return (player position as text) & "|" & (player state as text)
    end tell
    """

    private struct Info: Decodable {
        var title: String?
        var artist: String?
        var album: String?
        var duration: Double?
        var elapsed: Double?
        var rate: Double?
        var ts: Double?
        var bid: String?
        var app: String?
        var playing: Bool?
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in self?.poll() }
        poll()
    }

    func elapsed(at now: Date = Date()) -> Double {
        guard let t = track else { return 0 }
        let e = elapsedBase + (isPlaying ? now.timeIntervalSince(baseDate) * rate : 0)
        return t.duration > 0 ? min(max(e, 0), t.duration) : max(e, 0)
    }

    /// Re-reads the session now, rather than waiting for the next tick.
    func refresh() { poll() }

    private func poll() {
        guard !busy else { return }
        busy = true
        queue.async {
            let out = Shell.run("/usr/bin/osascript", ["-l", "JavaScript", "-e", Self.infoScript]).out
            var info = try? JSONDecoder().decode(Info.self, from: Data(out.utf8))
            // MediaRemote reports an elapsed time of 0 until something changes the playback
            // state, which leaves the scrubber pinned at the start. Ask the player instead.
            if let i = info, i.playing == true, (i.elapsed ?? 0) == 0,
               let id = i.bid, Self.positionPlayers.contains(id) {
                let script = String(format: Self.positionScript, id)
                let field = Shell.run("/usr/bin/osascript", ["-e", script]).out
                    .split(separator: "|").first.map(String.init) ?? ""
                if let position = Double(field.trimmingCharacters(in: .whitespacesAndNewlines)), position > 0 {
                    info?.elapsed = position
                    info?.ts = nil  // True as of now, not as of MediaRemote's timestamp.
                }
            }
            onMain {
                self.busy = false
                self.apply(info)
            }
        }
    }

    private func apply(_ info: Info?) {
        let blocked = Set(Prefs.list("blockedMediaApps").map { $0.lowercased() })
        guard let info, let title = info.title, !title.isEmpty,
              !blocked.contains((info.bid ?? "").lowercased()),
              !blocked.contains((info.app ?? "").lowercased()) else {
            if track != nil { track = nil; artwork = nil; lyrics = []; artKey = "" }
            if isPlaying { isPlaying = false }
            return
        }
        let t = Track(title: title, artist: info.artist ?? "", album: info.album ?? "",
                      duration: info.duration ?? 0, bundleID: info.bid ?? "", appName: info.app ?? "")
        let playing = info.playing ?? false
        rate = (info.rate ?? 1) > 0 ? (info.rate ?? 1) : 1
        if let e = info.elapsed {
            // The reported elapsed time was true at `ts`; project it to now.
            let stamp = info.ts.map { Date(timeIntervalSince1970: $0) } ?? Date()
            elapsedBase = e
            baseDate = playing ? stamp : Date()
        }
        if isPlaying != playing { isPlaying = playing }
        if track != t {
            let changed = track?.title != t.title || track?.artist != t.artist
            track = t
            if changed {
                loadArtwork(for: t)
                loadLyrics(for: t)
            }
        }
    }

    // MARK: Controls

    /// MediaRemote is read-only for an app without Apple's private entitlements:
    /// MRMediaRemoteSendCommand reports success and changes nothing, and
    /// MRMediaRemoteSetElapsedTime behaves the same way. So a command goes to the player
    /// itself where it can be scripted, and falls back to a system media key — which the
    /// frontmost audio app handles, browsers included — and only then to MediaRemote.
    private enum Command {
        case playPause, next, previous
        case seek(Double)

        /// MRMediaRemoteCommand: 2 = toggle, 4 = next, 5 = previous.
        var remote: [String] {
            switch self {
            case .playPause: return ["2"]
            case .next: return ["4"]
            case .previous: return ["5"]
            case .seek(let s): return ["seek", String(s)]
            }
        }

        /// NX_KEYTYPE_PLAY / _NEXT / _PREVIOUS.
        var mediaKey: Int32? {
            switch self {
            case .playPause: return 16
            case .next: return 17
            case .previous: return 18
            case .seek: return nil
            }
        }
    }

    /// Players that take transport commands over Apple events, by bundle identifier.
    /// Music, TV and Spotify share iTunes' vocabulary; VLC has its own.
    private static func script(for command: Command, player id: String) -> String? {
        let body: String
        switch id {
        case "com.apple.Music", "com.apple.TV", "com.apple.iTunes", "com.spotify.client":
            switch command {
            case .playPause: body = "playpause"
            case .next: body = "next track"
            case .previous: body = "previous track"
            case .seek(let s): body = "set player position to \(Int(s.rounded()))"
            }
        case "org.videolan.vlc":
            switch command {
            case .playPause: body = "play"  // VLC's `play` toggles.
            case .next: body = "next"
            case .previous: body = "previous"
            case .seek(let s): body = "set current time to \(Int(s.rounded()))"
            }
        case "com.apple.QuickTimePlayerX":
            switch command {
            case .playPause: body = "if playing of document 1 then pause document 1 else play document 1"
            case .seek(let s): body = "set current time of document 1 to \(Int(s.rounded()))"
            case .next, .previous: return nil
            }
        default:
            return nil
        }
        return "tell application id \"\(id)\" to \(body)"
    }

    private func send(_ command: Command) {
        let id = track?.bundleID ?? ""
        queue.async {
            var done = false
            if let script = Self.script(for: command, player: id) {
                done = Shell.run("/usr/bin/osascript", ["-e", script]).status == 0
            }
            if !done, let key = command.mediaKey {
                done = Self.pressMediaKey(key)
            }
            if !done {
                Shell.run("/usr/bin/osascript", ["-l", "JavaScript", "-e", Self.commandScript] + command.remote)
            }
            onMain { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.poll() } }
        }
    }

    /// Posts a media key to the system. Needs Accessibility access, so it is only ever a
    /// fallback for players that cannot be scripted.
    private static func pressMediaKey(_ key: Int32) -> Bool {
        guard AXIsProcessTrusted() else { return false }
        for down in [true, false] {
            let flags = NSEvent.ModifierFlags(rawValue: UInt(down ? 0xa00 : 0xb00))
            let data1 = Int((key << 16) | ((down ? 0xa : 0xb) << 8))
            guard let event = NSEvent.otherEvent(with: .systemDefined, location: .zero,
                                                 modifierFlags: flags, timestamp: 0, windowNumber: 0,
                                                 context: nil, subtype: 8, data1: data1, data2: -1),
                  let cg = event.cgEvent else { return false }
            cg.post(tap: .cghidEventTap)
        }
        return true
    }

    func togglePlay() {
        isPlaying.toggle()
        if isPlaying { baseDate = Date() } else { elapsedBase = elapsed() }
        send(.playPause)
    }

    func next() { send(.next) }
    func previous() { send(.previous) }

    func seek(to seconds: Double) {
        elapsedBase = seconds
        baseDate = Date()
        objectWillChange.send()
        send(.seek(seconds))
    }

    func activatePlayer() {
        guard let id = track?.bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: Artwork

    private func loadArtwork(for t: Track) {
        let key = t.title + "|" + t.artist
        artKey = key
        artwork = nil
        queue.async {
            var image: NSImage?
            // The system sometimes publishes artwork a moment after the title, so retry briefly.
            for attempt in 0..<2 where image == nil {
                if attempt > 0 { Thread.sleep(forTimeInterval: 0.8) }
                let b64 = Shell.run("/usr/bin/osascript", ["-l", "JavaScript", "-e", Self.artScript]).out
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if let d = Data(base64Encoded: b64), !d.isEmpty { image = NSImage(data: d) }
            }
            // The system feed often carries no picture, so ask the player itself.
            if image == nil { image = Self.artworkFromPlayer(t.bundleID) }
            if image == nil, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: t.bundleID) {
                image = NSWorkspace.shared.icon(forFile: url.path)
            }
            onMain { if self.artKey == key { self.artwork = image } }
        }
    }

    private static func artworkFromPlayer(_ bundleID: String) -> NSImage? {
        if bundleID == "com.apple.Music" {
            // Comes back as «data tdtaFFD8…» (hex-encoded image bytes).
            let out = Shell.run("/usr/bin/osascript", ["-e", "tell application id \"com.apple.Music\" to get raw data of artwork 1 of current track"]).out
            guard let start = out.range(of: "«data ")?.upperBound, let end = out.lastIndex(of: "»") else { return nil }
            let hex = Array(out[start..<end].dropFirst(4).utf8)
            var bytes = [UInt8]()
            bytes.reserveCapacity(hex.count / 2)
            func nibble(_ c: UInt8) -> UInt8? {
                switch c {
                case 48...57: return c - 48
                case 65...70: return c - 55
                case 97...102: return c - 87
                default: return nil
                }
            }
            var i = 0
            while i + 1 < hex.count {
                guard let hi = nibble(hex[i]), let lo = nibble(hex[i + 1]) else { break }
                bytes.append(hi << 4 | lo)
                i += 2
            }
            return bytes.isEmpty ? nil : NSImage(data: Data(bytes))
        }
        if bundleID == "com.spotify.client" {
            let link = Shell.run("/usr/bin/osascript", ["-e", "tell application id \"com.spotify.client\" to get artwork url of current track"]).out
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let url = URL(string: link), url.scheme == "https", let data = try? Data(contentsOf: url) { return NSImage(data: data) }
        }
        return nil
    }

    // MARK: Lyrics (opt-in; looks the song up on lrclib.net)

    func reloadLyrics() {
        if let t = track { loadLyrics(for: t) } else { lyrics = [] }
    }

    private func loadLyrics(for t: Track) {
        lyrics = []
        lyricsStatus = ""
        guard Prefs.bool("lyrics"), !t.artist.isEmpty else { return }
        var c = URLComponents(string: "https://lrclib.net/api/get")!
        c.queryItems = [
            URLQueryItem(name: "track_name", value: t.title),
            URLQueryItem(name: "artist_name", value: t.artist),
        ]
        if t.duration > 0 { c.queryItems?.append(URLQueryItem(name: "duration", value: String(Int(t.duration.rounded())))) }
        guard let url = c.url else { return }
        lyricsStatus = "Looking for lyrics…"
        var req = URLRequest(url: url)
        req.setValue("Topside notch app", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { data, _, _ in
            var lines: [LyricLine] = []
            if let data, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let synced = obj["syncedLyrics"] as? String {
                    lines = Self.parseLRC(synced)
                } else if let plain = obj["plainLyrics"] as? String {
                    lines = plain.split(separator: "\n").enumerated().map { LyricLine(id: $0.offset, time: -1, text: String($0.element)) }
                }
            }
            onMain {
                guard self.track == t else { return }
                self.lyrics = lines
                self.lyricsStatus = lines.isEmpty ? "No lyrics found" : ""
            }
        }.resume()
    }

    static func parseLRC(_ s: String) -> [LyricLine] {
        var out: [LyricLine] = []
        for raw in s.split(separator: "\n") {
            guard raw.hasPrefix("["), let close = raw.firstIndex(of: "]") else { continue }
            let stamp = raw[raw.index(after: raw.startIndex)..<close].split(separator: ":")
            guard stamp.count == 2, let m = Double(stamp[0]), let sec = Double(stamp[1]) else { continue }
            let text = raw[raw.index(after: close)...].trimmingCharacters(in: .whitespaces)
            out.append(LyricLine(id: out.count, time: m * 60 + sec, text: text))
        }
        return out
    }

    func currentLyric(at now: Date = Date()) -> String? {
        guard !lyrics.isEmpty, lyrics[0].time >= 0 else { return nil }
        let e = elapsed(at: now)
        return lyrics.last(where: { $0.time <= e })?.text
    }
}

// MARK: - Playlists

struct Playlist: Identifiable, Equatable {
    let id: String  // Music's persistent ID, which survives renaming and is unique.
    let name: String
    let count: Int
}

struct PlaylistTrack: Identifiable, Equatable {
    let id: String  // Music's persistent ID for the track.
    let name: String
    let artist: String
    let duration: Double
}

/// The user's Music playlists, read over Apple events.
///
/// Loaded only when the list is actually opened: the query takes a couple of seconds on a
/// large library, and asking Music anything launches it, which should never happen behind
/// the user's back.
final class PlaylistService: ObservableObject {
    static let shared = PlaylistService()
    static let player = "com.apple.Music"

    /// Whether the Playing tab is showing the list rather than the player.
    @Published var browsing = false
    /// The playlist whose tracks are open, if any.
    @Published var openPlaylist: Playlist?
    /// Whether the browser is showing the queue rather than a list of music.
    @Published var showingQueue = false
    @Published private(set) var tracks: [PlaylistTrack] = []
    @Published private(set) var loadingTracks = false
    @Published private(set) var items: [Playlist] = []
    @Published private(set) var loading = false
    @Published private(set) var message = ""

    private var loadedAt: Date?

    /// Checked without Apple events, so it cannot launch Music as a side effect.
    var playerIsRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: Self.player).isEmpty
    }

    private static let listScript = """
    tell application id "com.apple.Music"
        set out to ""
        repeat with p in (every user playlist whose special kind is none)
            try
                set out to out & (persistent ID of p) & tab & (name of p) & tab & (count of tracks of p) & linefeed
            end try
        end repeat
        return out
    end tell
    """

    func reloadIfStale() {
        guard let at = loadedAt else { return reload() }
        if Date().timeIntervalSince(at) > 300 { reload() }
    }

    func reload() {
        guard !loading else { return }
        loading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Shell.run("/usr/bin/osascript", ["-e", Self.listScript])
            let rows: [Playlist] = result.out.split(separator: "\n").compactMap { line in
                let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                guard f.count >= 3, !f[1].isEmpty else { return nil }
                return Playlist(id: f[0], name: f[1], count: Int(f[2]) ?? 0)
            }
            onMain {
                self.loading = false
                self.loadedAt = Date()
                self.items = rows.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                if result.status != 0 {
                    // Almost always a declined or never-asked Automation prompt.
                    self.message = "Music would not answer. Allow Topside to control Music in System Settings › Privacy & Security › Automation."
                } else {
                    self.message = rows.isEmpty ? "No playlists in Music." : ""
                }
            }
        }
    }

    /// Reads one playlist's tracks. Four bulk property fetches rather than a loop over
    /// tracks: on a 425-track playlist that is a tenth of a second instead of half a
    /// minute. The lists come back joined by control characters, which cannot occur in a
    /// track name.
    private static func tracksScript(_ playlistID: String) -> String {
        """
        tell application id "com.apple.Music"
            set p to first playlist whose persistent ID is "\(playlistID)"
            set ids to (get persistent ID of every track of p)
            set ns to (get name of every track of p)
            set ars to (get artist of every track of p)
            set ds to (get duration of every track of p)
            set AppleScript's text item delimiters to (ASCII character 1)
            set r to (ids as text) & (ASCII character 2) & (ns as text) & ¬
                (ASCII character 2) & (ars as text) & (ASCII character 2) & (ds as text)
            set AppleScript's text item delimiters to ""
            return r
        end tell
        """
    }

    private func fetchTracks(_ id: String, then done: @escaping ([PlaylistTrack]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let out = Shell.run("/usr/bin/osascript", ["-e", Self.tracksScript(id)]).out
            let blocks = out.components(separatedBy: "\u{02}")
            var rows: [PlaylistTrack] = []
            if blocks.count >= 4 {
                let cols = blocks.map { $0.components(separatedBy: "\u{01}") }
                let n = cols.map(\.count).min() ?? 0
                rows = (0..<n).compactMap { i in
                    let name = cols[1][i].trimmingCharacters(in: .newlines)
                    guard !name.isEmpty else { return nil }
                    return PlaylistTrack(id: cols[0][i], name: name,
                                         artist: cols[2][i].trimmingCharacters(in: .newlines),
                                         duration: Double(cols[3][i].trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0)
                }
            }
            onMain { done(rows) }
        }
    }

    func open(_ playlist: Playlist) {
        openPlaylist = playlist
        tracks = []
        loadingTracks = true
        fetchTracks(playlist.id) { [weak self] rows in
            guard let self, self.openPlaylist?.id == playlist.id else { return }
            self.loadingTracks = false
            self.tracks = rows
        }
    }

    /// Queues a track by name for the scripting channel: "<playlist>|<track>", both
    /// matched case-insensitively, the track by substring.
    func queueByName(_ playlistName: String, _ trackQuery: String) {
        withPlaylist(named: playlistName) { playlist in
            self.fetchTracks(playlist.id) { rows in
                let q = trackQuery.lowercased()
                guard let hit = rows.first(where: { $0.name.lowercased().contains(q) }) else {
                    ActivityCenter.shared.show(Toast(icon: "questionmark.circle",
                                                     text: "No track matching “\(trackQuery)”"))
                    return
                }
                QueueService.shared.add(hit, from: playlist)
            }
        }
    }

    /// Runs a block with a named playlist, reading the list first if it is not loaded.
    private func withPlaylist(named name: String, then use: @escaping (Playlist) -> Void) {
        func resolve() {
            guard let match = self.playlist(named: name) else {
                ActivityCenter.shared.show(Toast(icon: "questionmark.circle", text: "No playlist called “\(name)”"))
                return
            }
            use(match)
        }
        guard items.isEmpty else { return resolve() }
        reload()
        var waits = 0
        func retry() {
            guard waits < 40 else { return }
            waits += 1
            if loading {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: retry)
            } else {
                resolve()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: retry)
    }

    func closePlaylist() {
        openPlaylist = nil
        tracks = []
    }

    /// Opens a playlist's tracks by name, for the scripting channel.
    func openByName(_ name: String) {
        withPlaylist(named: name) { self.open($0) }
    }

    /// Starts one track with its playlist as the context, so playback carries on through
    /// the rest of the playlist afterwards.
    func play(_ track: PlaylistTrack, in playlist: Playlist, shuffle: Bool = false) {
        let script = """
        tell application id "com.apple.Music"
            set shuffle enabled to \(shuffle)
            set p to first playlist whose persistent ID is "\(playlist.id)"
            play (first track of p whose persistent ID is "\(track.id)")
        end tell
        """
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = Shell.run("/usr/bin/osascript", ["-e", script]).status == 0
            onMain {
                self.browsing = false
                self.closePlaylist()
                if !ok {
                    ActivityCenter.shared.show(Toast(icon: "exclamationmark.triangle.fill",
                                                     text: "Could not play \(track.name)"))
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { MediaService.shared.refresh() }
            }
        }
    }

    func play(_ playlist: Playlist, shuffle: Bool) {
        // The identifier is Music's own hexadecimal persistent ID, so it needs no quoting.
        let script = """
        tell application id "com.apple.Music"
            set shuffle enabled to \(shuffle)
            play (first playlist whose persistent ID is "\(playlist.id)")
        end tell
        """
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = Shell.run("/usr/bin/osascript", ["-e", script]).status == 0
            onMain {
                self.browsing = false
                self.closePlaylist()
                ActivityCenter.shared.show(ok
                    ? Toast(icon: shuffle ? "shuffle" : "play.fill", text: playlist.name)
                    : Toast(icon: "exclamationmark.triangle.fill", text: "Could not play \(playlist.name)"))
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { MediaService.shared.refresh() }
            }
        }
    }

    /// Starts a playlist by name, for the scripting channel. Loads the list first when it
    /// has not been read yet, so a script works on a cold start.
    func playByName(_ name: String, shuffle: Bool) {
        withPlaylist(named: name) { self.play($0, shuffle: shuffle) }
    }

    /// Resolves a name for the scripting channel: exact first, then a prefix, then any
    /// playlist containing the text. All case-insensitive.
    func playlist(named name: String) -> Playlist? {
        let n = name.lowercased()
        return items.first { $0.name.lowercased() == n }
            ?? items.first { $0.name.lowercased().hasPrefix(n) }
            ?? items.first { $0.name.lowercased().contains(n) }
    }
}

// MARK: - Queue

struct QueuedTrack: Identifiable, Equatable {
    let id = UUID()
    let track: PlaylistTrack
    let playlist: Playlist
}

/// A play queue kept by Topside rather than by Music.
///
/// Music's scripting interface exposes no Up Next, so there is nothing to add to: the
/// queue lives here, and the next entry is started when the current track gives way.
/// A track change caused by the queue itself must not consume the following entry, so
/// starting one suppresses the handler briefly.
final class QueueService: ObservableObject {
    static let shared = QueueService()

    @Published private(set) var items: [QueuedTrack] = []

    private var suppressUntil = Date.distantPast
    private var bag = Set<AnyCancellable>()

    func start() {
        MediaService.shared.$track
            .map { $0?.title ?? "" }
            .removeDuplicates()
            .dropFirst()  // The current track is not a change.
            .sink { [weak self] _ in self?.advance() }
            .store(in: &bag)
    }

    func add(_ track: PlaylistTrack, from playlist: Playlist) {
        items.append(QueuedTrack(track: track, playlist: playlist))
        ActivityCenter.shared.show(Toast(icon: "text.append", text: "Queued \(track.name)"))
    }

    func remove(_ item: QueuedTrack) {
        items.removeAll { $0.id == item.id }
    }

    func clear() { items.removeAll() }

    /// Plays a queued track now, skipping whatever is on, and drops it from the queue.
    func playNow(_ item: QueuedTrack? = nil) {
        guard let next = item ?? items.first else { return }
        items.removeAll { $0.id == next.id }
        start(next)
    }

    private func advance() {
        guard Date() > suppressUntil, !items.isEmpty else { return }
        start(items.removeFirst())
    }

    private func start(_ item: QueuedTrack) {
        suppressUntil = Date().addingTimeInterval(5)
        PlaylistService.shared.play(item.track, in: item.playlist)
    }
}
