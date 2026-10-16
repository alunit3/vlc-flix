VLCFlix 1.0.4 fixes the picture freezing after a pause and gives the player a cleaner, Netflix-style look.

### Download
- **VLCFlix-1.0.4-win64-setup.exe**: installer (Windows 10/11, 64-bit)
- **VLCFlix-1.0.4-win64.zip**: the same files, no installer. Unpack and run `vlcflix.exe`.

Check them against `SHA256SUMS`. The installer is not code-signed yet, so SmartScreen will warn the first time: *More info → Run anyway*.

### Fixed
- **Picture frozen after a pause.** After pausing a film played faster or slower than normal (or at normal speed after the speed had been changed once), the picture could stay still while the sound played on, until you clicked the seekbar. The longer the pause, the more likely. It now resumes properly. Should anything still stall, VLCFlix notices and puts it right by itself within a couple of seconds.

### New
- **Audio & subtitles picker** in the style of Netflix: "Audio" and "Subtitles" side by side, a check on what is playing, "Off" for no subtitles, and the subtitle size at the bottom. Sync, video tracks and the rest are under "More options".
- **Playback speed picker**: 0.5x to 2x on one line, opened from the new speedometer button. Right-click the button to go back to normal speed.

### Changed
- **Player controls** look like Netflix: larger icons, the remaining time next to the seekbar, a round red knob on the seekbar, and the volume slider only appears when you point at the speaker. The "Next" button only shows when something follows, and the play queue button has moved off the bar (the play queue is still in the menus). Your control bar layout is reset to the new one once.
- **VLCFlix everywhere:** the About box, tray icon, update messages, preferences and the program's file properties now say VLCFlix. VLC and VideoLAN are credited as what VLCFlix is built on.

### Before you start
- TMDB artwork and OpenSubtitles need **your own** keys. The welcome screen and Settings › Accounts explain where to get them.
  - OpenSubtitles: the API key is enough to search; your account login is needed to download.
- Torrent peers see your IP address. You are responsible for what you stream.
- Settings and the library live in `%APPDATA%\VLCFlix`, separate from any VLC you have installed.

Based on VLC 4.0.0-dev (GPL-2.0-or-later). See `NOTICE.md` in the source for third-party notices.
