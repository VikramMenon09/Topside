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

    private func poll() {
        guard !busy else { return }
        busy = true
        queue.async {
            let out = Shell.run("/usr/bin/osascript", ["-l", "JavaScript", "-e", Self.infoScript]).out
            let info = try? JSONDecoder().decode(Info.self, from: Data(out.utf8))
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

    private func command(_ args: [String]) {
        queue.async {
            Shell.run("/usr/bin/osascript", ["-l", "JavaScript", "-e", Self.commandScript] + args)
            onMain { DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.poll() } }
        }
    }

    func togglePlay() {
        isPlaying.toggle()
        if isPlaying { baseDate = Date() } else { elapsedBase = elapsed() }
        command(["2"])
    }

    func next() { command(["4"]) }
    func previous() { command(["5"]) }

    func seek(to seconds: Double) {
        elapsedBase = seconds
        baseDate = Date()
        objectWillChange.send()
        command(["seek", String(seconds)])
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
