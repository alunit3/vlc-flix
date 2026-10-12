VLCFlix 1.0.1 fixes resuming a torrent stream and a stream that kept running after you left the player.

### Download
- **VLCFlix-1.0.1-win64-setup.exe**: installer (Windows 10/11, 64-bit)
- **VLCFlix-1.0.1-win64.zip**: the same files, no installer. Unpack and run `vlcflix.exe`.

Check them against `SHA256SUMS`. The installer is not code-signed yet, so SmartScreen will warn the first time: *More info → Run anyway*.

### Fixed
- **Continue Watching on a torrent**: the seek bar now shows the real time against the whole film. Before, it started at 0:00 at the point you resumed from, showed only the time left, and you could not go back before it.
- **"Start over"** after a resume goes back to the beginning, not to where you resumed.
- **The saved position** no longer moves backwards. Each resume used to count from the last resume point, so you landed earlier every time. Titles saved by 1.0.0 may start a little early once, then save correctly.
- **The torrent stopped with the player**: going back from a stream left it running in the background until VLCFlix was closed. The next "Choose a source" then showed its "Buffering 100 % · 0 peers" with a Cancel button and a locked list.

### Before you start
- TMDB artwork and OpenSubtitles need **your own** keys, entered in Settings (each has a Test button). Nothing is fetched until they are set.
- Torrent peers see your IP address. You are responsible for what you stream.
- Settings and the library live in `%APPDATA%\VLCFlix`, separate from any VLC you have installed.

Based on VLC 4.0.0-dev (GPL-2.0-or-later). See `NOTICE.md` in the source for third-party notices.
