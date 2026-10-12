First release of VLCFlix: VLC 4 with a home screen for your films, online subtitles and artwork, and torrent streaming that resumes where you left off.

### Download
- **VLCFlix-1.0.0-win64-setup.exe**: installer (Windows 10/11, 64-bit)
- **VLCFlix-1.0.0-win64.zip**: the same files, no installer. Unpack and run `vlcflix.exe`.

Check them against `SHA256SUMS`. The installer is not code-signed yet, so SmartScreen will warn the first time: *More info → Run anyway*.

### What's in it
- **Home** with Continue Watching, your library, trending titles and the weekly Top 10. Artwork and synopses come from TMDB.
- **Stream a torrent**: pick a source for a title, or paste a magnet link or a `.torrent` file. Playback starts while it downloads. Resuming picks up at the same second and reuses what is already on disk.
- **Online subtitles** from OpenSubtitles.com: offered automatically when a film has none, or searched by hand. A subtitle you download comes back by itself next time.
- **Player**: a pause screen with the title and synopsis, an age-rating banner, "Resuming from 12:34 / Start over", seek-bar thumbnails, and live torrent stats.
- **Watch online**: opens a streaming provider's own web player in its own window.
- Fixes on the VLC side, including crackling 5.1 audio through WASAPI on Windows.

### Before you start
- TMDB artwork and OpenSubtitles need **your own** keys, entered in Settings (each has a Test button). Nothing is fetched until they are set.
- Torrent peers see your IP address. You are responsible for what you stream.
- Settings and the library live in `%APPDATA%\VLCFlix`, separate from any VLC you have installed.

Based on VLC 4.0.0-dev (GPL-2.0-or-later). See `NOTICE.md` in the source for third-party notices.
