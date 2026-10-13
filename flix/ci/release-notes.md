VLCFlix 1.0.2 adds the FrameXTV provider to "Watch online", and the provider list now updates itself, so a dead or new site no longer needs a new release.

### Download
- **VLCFlix-1.0.2-win64-setup.exe**: installer (Windows 10/11, 64-bit)
- **VLCFlix-1.0.2-win64.zip**: the same files, no installer. Unpack and run `vlcflix.exe`.

Check them against `SHA256SUMS`. The installer is not code-signed yet, so SmartScreen will warn the first time: *More info → Run anyway*.

### Changed
- **Watch online providers** are fetched from this project's GitHub once a day (the same switch as the update check, in Settings) and only https pages on each provider's own host are accepted. Offline, the built-in list is used.
- **FrameXTV** is a new provider.
- **Your own `flix-providers.json`** now adds to or replaces entries by name (`"disabled": true` hides one) instead of being the whole list. Old copies are ignored so they do not hide updates.

### Before you start
- TMDB artwork and OpenSubtitles need **your own** keys, entered in Settings (each has a Test button). Nothing is fetched until they are set.
- Torrent peers see your IP address. You are responsible for what you stream.
- Settings and the library live in `%APPDATA%\VLCFlix`, separate from any VLC you have installed.

Based on VLC 4.0.0-dev (GPL-2.0-or-later). See `NOTICE.md` in the source for third-party notices.
