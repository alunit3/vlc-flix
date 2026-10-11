package main

import (
	"fmt"
	"io"
	"mime"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"

	"github.com/anacrolix/torrent"
	"github.com/anacrolix/torrent/types"
)

var reMagnet = regexp.MustCompile(`^magnet:\?xt=urn:btih:([0-9a-fA-F]{40}|[A-Za-z2-7]{32})(&.*)?$`)

var videoExt = map[string]bool{
	".mkv": true, ".mp4": true, ".avi": true, ".mov": true, ".m4v": true, ".webm": true,
	".ts": true, ".wmv": true, ".mpg": true, ".mpeg": true, ".flv": true,
}

const (
	headBytes = 12 << 20 // buffered before playback starts
	tailBytes = 3 << 20  // mp4 moov / mkv cues often live at the end
)

func fail(msg string) int {
	emit(map[string]any{"event": "error", "message": msg})
	return 1
}

// pieces of the file that cover [from, to) bytes of it
func pieceRange(t *torrent.Torrent, f *torrent.File, from, to int64) (int, int) {
	pl := t.Info().PieceLength
	begin := int((f.Offset() + from) / pl)
	end := int((f.Offset() + to - 1) / pl)
	if end >= t.NumPieces() {
		end = t.NumPieces() - 1
	}
	return begin, end
}

func piecesComplete(t *torrent.Torrent, begin, end int) (done, total int) {
	for i := begin; i <= end; i++ {
		total++
		if t.Piece(i).State().Complete {
			done++
		}
	}
	return
}

func runStream(magnet, torrentFile string, fileIdx int, dataDir string, keep bool, parentPid int) int {
	if torrentFile == "" && !reMagnet.MatchString(magnet) {
		return fail("bad magnet link")
	}
	if dataDir == "" {
		return fail("missing --data-dir")
	}
	if err := os.MkdirAll(dataDir, 0o700); err != nil {
		return fail("cannot create data dir: " + err.Error())
	}

	cfg := torrent.NewDefaultClientConfig()
	cfg.DataDir = dataDir
	cfg.ListenPort = 0
	cfg.Seed = false
	client, err := torrent.NewClient(cfg)
	if err != nil {
		return fail("cannot start torrent client: " + err.Error())
	}
	defer func() {
		client.Close()
		if !keep {
			os.RemoveAll(dataDir)
		}
	}()

	// we end when the player goes away: its process exits (parent pid), or - without a pid -
	// when it closes our stdin
	quit := make(chan struct{})
	if parentPid > 0 {
		go func() {
			waitForProcess(parentPid)
			close(quit)
		}()
	} else {
		go func() {
			io.Copy(io.Discard, os.Stdin)
			close(quit)
		}()
	}

	emit(map[string]any{"event": "connecting"})
	var t *torrent.Torrent
	if torrentFile != "" {
		t, err = client.AddTorrentFromFile(torrentFile)
	} else {
		t, err = client.AddMagnet(magnet)
	}
	if err != nil {
		return fail("cannot add torrent: " + err.Error())
	}
	addTrackers(t)
	select {
	case <-t.GotInfo():
	case <-quit:
		return 0
	case <-time.After(90 * time.Second):
		return fail("no metadata after 90 s (no peers?)")
	}

	// pick the file
	var file *torrent.File
	files := t.Files()
	if fileIdx >= 0 && fileIdx < len(files) {
		file = files[fileIdx]
	} else {
		for _, f := range files {
			if !videoExt[strings.ToLower(filepath.Ext(f.Path()))] {
				continue
			}
			if file == nil || f.Length() > file.Length() {
				file = f
			}
		}
	}
	if file == nil {
		return fail("no video file in this torrent")
	}
	emit(map[string]any{"event": "metadata", "name": file.DisplayPath(), "size": file.Length(), "files": len(files)})

	// download only this file, start with its head and tail
	for _, f := range files {
		if f != file {
			f.SetPriority(types.PiecePriorityNone)
		}
	}
	file.SetPriority(types.PiecePriorityNormal)
	length := file.Length()
	head := int64(headBytes)
	if head > length {
		head = length
	}
	tail := int64(tailBytes)
	if tail > length {
		tail = length
	}
	hb, he := pieceRange(t, file, 0, head)
	tb, te := pieceRange(t, file, length-tail, length)
	for i := hb; i <= he; i++ {
		t.Piece(i).SetPriority(types.PiecePriorityHigh)
	}
	for i := tb; i <= te; i++ {
		t.Piece(i).SetPriority(types.PiecePriorityHigh)
	}

	// local HTTP server (range requests => seeking)
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return fail("cannot listen: " + err.Error())
	}
	ext := strings.ToLower(filepath.Ext(file.Path()))
	mux := http.NewServeMux()
	mux.HandleFunc("/stream"+ext, func(w http.ResponseWriter, r *http.Request) {
		reader := file.NewReader()
		defer reader.Close()
		reader.SetResponsive()
		reader.SetReadahead(32 << 20)
		if ct := mime.TypeByExtension(ext); ct != "" {
			w.Header().Set("Content-Type", ct)
		}
		http.ServeContent(w, r, "stream"+ext, time.Time{}, reader)
	})
	server := &http.Server{Handler: mux}
	go server.Serve(listener)
	defer server.Close()
	url := fmt.Sprintf("http://%s/stream%s", listener.Addr().String(), ext)

	// report progress until the head and tail are in, then announce the stream
	ready := false
	ticker := time.NewTicker(700 * time.Millisecond)
	defer ticker.Stop()
	var lastBytes, lastUp int64
	lastTime := time.Now()
	for {
		select {
		case <-quit:
			return 0
		case <-ticker.C:
		}
		hd, ht := piecesComplete(t, hb, he)
		td, tt := piecesComplete(t, tb, te)
		have := hd + td
		need := ht + tt
		pct := 100
		if need > 0 {
			pct = have * 100 / need
		}
		stats := t.Stats()
		now := time.Now()
		done := t.BytesCompleted()
		dt := now.Sub(lastTime).Seconds()
		speed := int64(float64(done-lastBytes) / dt)
		up := stats.BytesWrittenData.Int64()
		upSpeed := int64(float64(up-lastUp) / dt)
		lastBytes, lastUp, lastTime = done, up, now
		emit(map[string]any{
			"event": "progress", "bufferPct": pct, "downloaded": done, "total": length,
			"peers": stats.ActivePeers, "seeders": stats.ConnectedSeeders,
			"speedBps": speed, "upBps": upSpeed, "uploaded": up,
		})
		if !ready && have >= need {
			ready = true
			emit(map[string]any{"event": "ready", "url": url, "name": file.DisplayPath()})
		}
	}
}
