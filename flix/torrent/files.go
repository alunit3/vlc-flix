package main

import (
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/anacrolix/torrent"
	"github.com/anacrolix/torrent/types"
)

// runFiles prints the name and the files of a torrent (metadata only, nothing is downloaded).
func runFiles(magnet, torrentFile, dataDir string) int {
	if torrentFile == "" && !reMagnet.MatchString(magnet) {
		emit(map[string]any{"error": "bad magnet link"})
		return 1
	}
	if dataDir == "" {
		emit(map[string]any{"error": "missing --data-dir"})
		return 1
	}
	os.MkdirAll(dataDir, 0o700)
	defer os.RemoveAll(dataDir)

	cfg := torrent.NewDefaultClientConfig()
	cfg.DataDir = dataDir
	cfg.ListenPort = 0
	cfg.Seed = false
	client, err := torrent.NewClient(cfg)
	if err != nil {
		emit(map[string]any{"error": "cannot start torrent client: " + err.Error()})
		return 1
	}
	defer client.Close()

	var t *torrent.Torrent
	if torrentFile != "" {
		t, err = client.AddTorrentFromFile(torrentFile)
	} else {
		t, err = client.AddMagnet(magnet)
	}
	if err != nil {
		emit(map[string]any{"error": "cannot add torrent: " + err.Error()})
		return 1
	}
	select {
	case <-t.GotInfo():
	case <-time.After(60 * time.Second):
		emit(map[string]any{"error": "no metadata after 60 s (no peers?)"})
		return 1
	}
	// nothing is wanted from this torrent: stop downloading right away
	for _, f := range t.Files() {
		f.SetPriority(types.PiecePriorityNone)
	}

	type item struct {
		Idx   int    `json:"idx"`
		Name  string `json:"name"`
		Size  int64  `json:"size"`
		Video bool   `json:"video"`
	}
	files := []item{}
	for i, f := range t.Files() {
		files = append(files, item{i, f.DisplayPath(), f.Length(), videoExt[strings.ToLower(filepath.Ext(f.Path()))]})
	}
	emit(map[string]any{"name": t.Name(), "files": files})
	return 0
}
