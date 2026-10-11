// flixtorrent: helper for the Flix player.
//
//	flixtorrent sources --imdb tt1234567 [--season S --episode E] [--cache DIR]
//	flixtorrent stream  --magnet MAGNET|--torrent-file F [--file-idx N] --data-dir DIR [--keep]
//	flixtorrent files   --magnet MAGNET|--torrent-file F --data-dir DIR
//
// "sources" prints a JSON list of torrents for a title (the same public Stremio addons the
// Heartive torrents page uses). "stream" downloads a torrent in playback order and serves the
// chosen file on http://127.0.0.1:<port>/ (range requests supported); progress is reported as one
// JSON object per line on stdout. The process ends when stdin is closed.
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"net/url"
	"os"
)

func emit(v any) {
	b, _ := json.Marshal(v)
	fmt.Println(string(b))
}

func urlEscape(s string) string { return url.QueryEscape(s) }

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "usage: flixtorrent sources|stream ...")
		os.Exit(2)
	}
	switch os.Args[1] {
	case "sources":
		fs := flag.NewFlagSet("sources", flag.ExitOnError)
		imdb := fs.String("imdb", "", "IMDb id (tt...)")
		season := fs.Int("season", 0, "season (series)")
		episode := fs.Int("episode", 0, "episode (series)")
		cache := fs.String("cache", "", "cache directory")
		fs.Parse(os.Args[2:])
		os.Exit(runSources(*imdb, *season, *episode, *cache))
	case "stream":
		fs := flag.NewFlagSet("stream", flag.ExitOnError)
		magnet := fs.String("magnet", "", "magnet link")
		torrentFile := fs.String("torrent-file", "", "path of a .torrent file (instead of --magnet)")
		fileIdx := fs.Int("file-idx", -1, "file index inside the torrent (-1: largest video)")
		dataDir := fs.String("data-dir", "", "download directory")
		keep := fs.Bool("keep", false, "keep downloaded data on exit")
		parent := fs.Int("parent-pid", 0, "exit when this process ends (default: when stdin closes)")
		fs.Parse(os.Args[2:])
		os.Exit(runStream(*magnet, *torrentFile, *fileIdx, *dataDir, *keep, *parent))
	case "files":
		fs := flag.NewFlagSet("files", flag.ExitOnError)
		magnet := fs.String("magnet", "", "magnet link")
		torrentFile := fs.String("torrent-file", "", "path of a .torrent file")
		dataDir := fs.String("data-dir", "", "scratch directory")
		fs.Parse(os.Args[2:])
		os.Exit(runFiles(*magnet, *torrentFile, *dataDir))
	default:
		fmt.Fprintln(os.Stderr, "unknown command", os.Args[1])
		os.Exit(2)
	}
}
