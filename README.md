# Topside

A macOS notch app. Hover over the notch and a compact panel drops down.

| Tab | What it does |
| --- | --- |
| **Playing** | Now playing from any app, with scrubber, controls, album art and optional lyrics |
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
```

See the comments at the top of `topside-ctl` for the full list.

## Permissions

Each of these is asked for only when you first use the feature it belongs to: Calendar,
Camera, Microphone and Speech Recognition, and controlling Music for album art.
Replacing Apple's own volume and brightness popups needs Accessibility access, granted
in System Settings.

## Notes

Now Playing is read through the private MediaRemote framework via the system scripting
host, so it may break in a future macOS release. Album art falls back to the player's
app icon when neither the system nor the player hands one over.

Weather comes from open-meteo.com and lyrics from lrclib.net; both are off until you
turn them on, and only a city name or a song title and artist are sent.
