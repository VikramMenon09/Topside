# Topside

A macOS notch app. Hover over the notch and a compact panel drops down.

| Tab | What it does |
| --- | --- |
| **Playing** | Now playing from any app, with scrubber, controls, album art and optional lyrics. Your Music playlists, their tracks, and a queue are one click away |
| **Today** | Upcoming calendar events and weather |
| **Tray** | Park files by dragging them onto the notch; AirDrop, zip/unzip, Quick Look, share |
| **Clips** | Searchable clipboard history (in memory only) |
| **Timer** | Timers and Pomodoro |
| **Mirror** | Camera preview |
| **System** | Battery, CPU, memory, free storage |
| **Prompt** | Teleprompter with steady scroll or voice follow |
| **Agents** | Recent Claude Code and Codex sessions (read-only) |

Collapsed, it is exactly the size of the camera housing, so nothing spills into the
menu bar. Short alerts drop down beneath it.

On a Mac without a notch, it draws a virtual one in the middle of the menu bar.

## Documentation

[`docs/Topside-Build-Guide.pdf`](docs/Topside-Build-Guide.pdf) is a 26-page reproduction
guide: architecture, the platform techniques behind the notch window and Now Playing
access, the design system, screenshots of every screen and of the two discarded designs,
a list of the traps worth knowing, and a prompt for rebuilding the app from scratch.

Regenerate it after editing `docs/guide.html`:

```bash
cd docs && "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  --headless --disable-gpu --no-pdf-header-footer \
  --print-to-pdf=Topside-Build-Guide.pdf "file://$PWD/guide.html"
```

## Build

Requires macOS 14 or later and the Swift toolchain (Xcode or the Command Line Tools).

```bash
./build.sh --run
```

That produces `Topside.app` next to the script and launches it. Settings and Quit live
in the menu bar icon.

## Scripting

```bash
./topside-ctl open:shelf
./topside-ctl "toast:Build finished"
./topside-ctl media:next
./topside-ctl "playlist:deep focus"
./topside-ctl "queue:deep focus|Lune"
```

See the comments at the top of `topside-ctl` for the full list.

## Permissions

Each of these is asked for only when you first use the feature it belongs to: Calendar,
Camera, Microphone and Speech Recognition, and controlling your music player for album
art and for the play, pause and skip buttons. Controlling a player that has no scripting
support — a video in a browser, say — falls back to a system media key, which needs
Accessibility access granted in System Settings.

## Notes

Playlists, tracks and the queue are Music only — Spotify's scripting interface cannot
list playlists. The queue is Topside's own, because Music exposes no Up Next: entries
play as the current track gives way, and are kept in memory only.

Now Playing is read through the private MediaRemote framework via the system scripting
host, so it may break in a future macOS release. That framework is read-only for an app
without Apple's private entitlements, so play, pause, skip and seek are sent to the
player itself instead. Album art falls back to the player's app icon when neither the
system nor the player hands one over.

Weather comes from open-meteo.com and lyrics from lrclib.net; both are off until you
turn them on, and only a city name or a song title and artist are sent.
