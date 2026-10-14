VLCFlix 1.0.3 starts faster, always closes properly, and adds movie folders reliably. A new welcome screen walks you through the first setup.

### Download
- **VLCFlix-1.0.3-win64-setup.exe**: installer (Windows 10/11, 64-bit)
- **VLCFlix-1.0.3-win64.zip**: the same files, no installer. Unpack and run `vlcflix.exe`.

Check them against `SHA256SUMS`. The installer is not code-signed yet, so SmartScreen will warn the first time: *More info → Run anyway*.

### Fixed
- **Closing VLCFlix** no longer leaves it running in the background. Previously it could hold the library and block the next start.
- **Opening it twice** (a double-click, or launching while it is still closing) no longer starts a second copy. The open window is brought to the front instead.
- **Adding a movie folder** works every time. Files that previously failed to appear are picked up again automatically. A folder that cannot be read now shows an error instead of nothing.
- **Subtitles for torrent and web streams** download again. Before, the first download could fail with "Could not save the subtitle file".
- **Startup is faster**, especially for the zip and portable copies.

### New
- **Welcome screen** on first start: add your movie folder, connect TMDB and OpenSubtitles. Every step can be skipped, and the welcome can be run again from Settings › Accounts.
- **Library folders** in Settings › Library & metadata: see your folders, rescan them, or remove them. Removing a folder only takes its films out of the library; the files stay on your disk.
- A **setup card** on the empty home page shows what is left to do.
- **Seasonal app icon** for Halloween and Christmas.

### Changed
- **Subtitles:** there is one "Find Subtitles Online…" entry, in the right-click menu, the Subtitle menu and the View menu. The old VLSub extension is removed; it used OpenSubtitles' retired API.
- **Watch online providers** are fetched from this project's GitHub once a day (the same switch as the update check, in Settings). Only https pages on each provider's own host are accepted. **FrameXTV** is a new provider. Your own `flix-providers.json` now adds to or replaces entries by name (`"disabled": true` hides one).

### Before you start
- TMDB artwork and OpenSubtitles need **your own** keys. The welcome screen and Settings › Accounts explain where to get them.
  - OpenSubtitles: the API key is enough to search; your account login is needed to download.
- Torrent peers see your IP address. You are responsible for what you stream.
- Settings and the library live in `%APPDATA%\VLCFlix`, separate from any VLC you have installed.

Based on VLC 4.0.0-dev (GPL-2.0-or-later). See `NOTICE.md` in the source for third-party notices.
