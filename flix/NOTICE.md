# VLCFlix notices

This fork of VLC (GPL-2.0-or-later) includes work derived from other projects.

## Online subtitles
- `modules/lua/libs/http.c` (HTTP/HTTPS client for Lua) is adapted from **PowerVLC**
  (https://github.com/Olsro/powervlc), GPL-2.0-or-later.
- `share/lua/modules/flix_opensubtitles.lua` and the manual search window
  `share/lua/extensions/FlixSubs.lua` follow the approach of PowerVLC's
  `pvlc_opensubtitles.lua` / `PowerVLSub.lua` (GPL-2.0-or-later) and the ideas of
  **VLsub for OpenSubtitles.com** (https://github.com/opensubtitles/vlsub-opensubtitles-com, GPL-3.0;
  no code copied: file hash, name search and language priority are described by the OpenSubtitles API).
- Subtitles come from **OpenSubtitles.com**. You need your own API key and account
  (Preferences > Interface > Main interfaces > Lua).

## Movie information and artwork
- Posters, backdrops, synopses and the weekly Top 10 come from **The Movie Database (TMDB)**.
  *This product uses the TMDB API but is not endorsed or certified by TMDB.*
  You need your own TMDB API read access token (Preferences > Interface > Main interfaces > Lua).
  Nothing is fetched while the token is empty.

## Fonts
- **Inter** (SIL Open Font License 1.1), see `modules/gui/qt/fonts/`.

## Trademarks
- "VLC" and the traffic cone are trademarks of VideoLAN. Rename and re-brand before publishing builds.
- No Netflix logo, name or fonts are used.

## Torrent streaming
- `flix/torrent` (Go) uses **anacrolix/torrent** (MPL-2.0, https://github.com/anacrolix/torrent) to stream a torrent
  to the player over http://127.0.0.1. Peers see the IP address of the machine; use a VPN if that matters.
- Sources are looked up from the public Stremio addons that the Heartive torrents page uses
  (Torrentio, Comet, StremThru, PirateBay+) and the ngosang/trackerslist tracker list. Nothing is searched or
  downloaded until the user picks a source and presses Stream. You are responsible for what you stream.

## Web player
- `flix/web` (Go) hosts a **Microsoft Edge WebView2** window (https://github.com/jchv/go-webview2, MIT) that shows the
  web player of a streaming provider chosen in "Watch online". It needs the WebView2 runtime (part of Windows 11 / Edge).
  The provider list is `flix-providers.json` in the user data folder and can be edited. The player only shows the
  provider's own page; nothing is extracted from it.
