package main

import (
	"context"
	"fmt"
	"io"
	"mime"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/anacrolix/torrent"
	"github.com/anacrolix/torrent/types"
	"golang.org/x/time/rate"
)

var reMagnet = regexp.MustCompile(`^magnet:\?xt=urn:btih:([0-9a-fA-F]{40}|[A-Za-z2-7]{32})(&.*)?$`)

var videoExt = map[string]bool{
	".mkv": true, ".mp4": true, ".avi": true, ".mov": true, ".m4v": true, ".webm": true,
	".ts": true, ".wmv": true, ".mpg": true, ".mpeg": true, ".flv": true,
}

const (
	headBytes = 12 << 20 // buffered before playback starts
	tailBytes = 3 << 20  // mp4 moov / mkv cues often live at the end
	// smallest token bucket we hand to a limiter: the socket buffer size the torrent
	// library assumes, so even a small cap refills in chunks worth sending
	minRateBurst = 1 << 20

	// how long to wait before asking the swarm again for a piece that had not
	// arrived. Short enough to stay invisible against a piece arriving in a moment,
	// long enough not to spin.
	readRetryDelay = 20 * time.Millisecond
	// how long a connection may go without a single byte before it is given up on.
	// Only reached when the swarm is gone; anything shorter than this and a merely
	// slow piece would cost the player the whole stream.
	readGiveUpAfter = 60 * time.Second
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

// contentType for a video extension.
//
// mime.TypeByExtension comes back empty on Windows for several of these, and an empty
// Content-Type makes net/http sniff the first bytes of the body and hand the demuxer
// whatever it guesses - which is how the same file plays locally and streams as
// octet-stream here.
func contentType(ext string) string {
	switch ext {
	case ".mkv":
		return "video/x-matroska"
	case ".mp4", ".m4v":
		return "video/mp4"
	case ".mov":
		return "video/quicktime"
	case ".avi":
		return "video/x-msvideo"
	case ".webm":
		return "video/webm"
	case ".ts":
		return "video/mp2t"
	case ".wmv":
		return "video/x-ms-wmv"
	case ".mpg", ".mpeg":
		return "video/mpeg"
	case ".flv":
		return "video/x-flv"
	}
	if ct := mime.TypeByExtension(ext); ct != "" {
		return ct
	}
	return "application/octet-stream"
}

// parseRange turns a Range header into an inclusive [start, end] of the file. The
// third result says whether the request was a range request at all.
//
// Only the "bytes=" single-range forms are honoured, which is the whole of what VLC
// sends. Anything unrecognised falls back to the entire file, the same as
// http.ServeContent.
func parseRange(header string, length int64) (start, end int64, partial bool) {
	whole := func() (int64, int64, bool) {
		if length <= 0 {
			return 0, 0, false
		}
		return 0, length - 1, false
	}

	const prefix = "bytes="
	if !strings.HasPrefix(header, prefix) {
		return whole()
	}
	spec := strings.TrimSpace(strings.TrimPrefix(header, prefix))
	if i := strings.IndexByte(spec, ','); i >= 0 {
		spec = spec[:i] // several ranges asked for: the first one, as ServeContent does
	}
	dash := strings.IndexByte(spec, '-')
	if dash < 0 {
		return whole()
	}
	from := strings.TrimSpace(spec[:dash])
	to := strings.TrimSpace(spec[dash+1:])

	if from == "" {
		// "bytes=-N" is the last N bytes
		n, err := strconv.ParseInt(to, 10, 64)
		if err != nil || n <= 0 {
			return whole()
		}
		if n > length {
			n = length
		}
		return length - n, length - 1, true
	}

	start, err := strconv.ParseInt(from, 10, 64)
	if err != nil || start < 0 || start >= length {
		return whole()
	}
	if to == "" {
		return start, length - 1, true
	}
	end, err = strconv.ParseInt(to, 10, 64)
	if err != nil || end < start {
		return start, length - 1, true
	}
	if end >= length {
		end = length - 1
	}
	return start, end, true
}

// serveRange answers one request for the file.
//
// This replaces http.ServeContent, which cannot be used here. It copies until the
// first error and returns, and the torrent reader returns an error whenever the piece
// it needs has not arrived yet - together with the bytes it did manage to read before
// hitting it. A short body against a declared Content-Length makes net/http close the
// connection, and VLC's http access reacts to a closed connection by *silently*
// opening a fresh Range request against a fresh reader (access/http/file.c retries
// automatically). That new reader has to negotiate and fill its whole readahead before
// a single byte flows again. Stall, burst, stall: this loop is the crackle and the
// doubling that comes with it.
//
// So an error here means "not yet". The position is kept, the write is retried, and the
// declared length is honoured exactly. The response either delivers every byte it
// promised or is cut off by the player going away.
func serveRange(w http.ResponseWriter, req *http.Request, rd *playingReader, length int64) {
	start, end, partial := parseRange(req.Header.Get("Range"), length)

	h := w.Header()
	h.Set("Accept-Ranges", "bytes")
	h.Set("Cache-Control", "no-store")
	h.Set("Content-Type", contentType(strings.ToLower(filepath.Ext(req.URL.Path))))
	if partial {
		h.Set("Content-Range", fmt.Sprintf("bytes %d-%d/%d", start, end, length))
	}
	h.Set("Content-Length", strconv.FormatInt(end-start+1, 10))
	if partial {
		w.WriteHeader(http.StatusPartialContent)
	} else {
		w.WriteHeader(http.StatusOK)
	}
	if req.Method == http.MethodHead {
		return
	}

	ctx := req.Context()
	flusher, _ := w.(http.Flusher)
	buf := make([]byte, 1<<18)
	lastData := time.Now()

	for pos := start; pos <= end; {
		want := int64(len(buf))
		if remaining := end - pos + 1; want > remaining {
			want = remaining
		}
		got, err := rd.readAt(ctx, buf[:want], pos)
		if got > 0 {
			if _, werr := w.Write(buf[:got]); werr != nil {
				return // the player stopped reading; there is nothing left to do
			}
			pos += int64(got)
			lastData = time.Now()
			if flusher != nil {
				flusher.Flush()
			}
		}
		if err != nil {
			select {
			case <-ctx.Done():
				return
			case <-time.After(readRetryDelay):
			}
			if time.Since(lastData) > readGiveUpAfter {
				// the swarm is gone. Giving up short of the promised length is the one
				// thing that must not happen lightly, so it takes a minute of nothing.
				emit(map[string]any{"event": "error",
					"message": "the torrent stopped sending data"})
				return
			}
		}
	}
}

// playingReader wraps the torrent reader and publishes how far the player has read.
//
// It has to report while the request is still running: the player holds one connection
// open for the whole film, so a position read only when the request finally ends would
// never arrive during normal playback and the fetch window would sit at byte 0.
//
// The reader has a single position, so every read seeks first. That also means one
// reader cannot serve two connections at once, which is why the handler creates one
// per request rather than sharing one.
type playingReader struct {
	r      torrent.Reader
	length int64

	pos atomic.Int64
}

// readAt fills p with file bytes starting at off.
//
// The torrent reader returns an error whenever the piece it needs has not finished
// arriving, *and* returns whatever bytes it did manage to read before hitting it.
// Those bytes are kept; the error is passed on so the caller can come back for the
// rest rather than treating a piece that is still downloading as the end of the file.
//
// A piece that never arrives must not keep this loop (and the request) alive for ever:
// after readGiveUpAfter without a single byte it returns io.ErrNoProgress, which is what
// lets serveRange report that the swarm is gone.
func (r *playingReader) readAt(ctx context.Context, p []byte, off int64) (int, error) {
	got := 0
	lastData := time.Now()
	for got < len(p) {
		if _, err := r.r.Seek(off+int64(got), io.SeekStart); err != nil {
			return got, err
		}
		n, err := r.r.Read(p[got:])
		if n > 0 {
			got += n
			r.pos.Store(off + int64(got))
			lastData = time.Now()
		}
		if err == nil {
			continue
		}
		if got == len(p) {
			// the error only says there was nothing past what we already have
			break
		}
		if err == io.EOF {
			return got, io.ErrUnexpectedEOF
		}
		// a piece that is still in flight: not fatal, just not ready
		if time.Since(lastData) > readGiveUpAfter {
			return got, io.ErrNoProgress
		}
		select {
		case <-ctx.Done():
			return got, ctx.Err()
		case <-time.After(readRetryDelay):
		}
	}
	return got, nil
}

func (r *playingReader) Seek(offset int64, whence int) (int64, error) {
	pos, err := r.r.Seek(offset, whence)
	if err != nil {
		return pos, err
	}
	if whence == io.SeekEnd || pos >= r.length {
		return pos, nil
	}
	r.pos.Store(pos)
	return pos, nil
}

func runStream(magnet, torrentFile string, fileIdx int, dataDir string, keep bool, parentPid int, startFrac float64, rateLimit, uploadLimit int64, streamOnly bool, window int64) int {
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
	// speed caps from the player settings (bytes/s); 0 keeps the library default
	if rateLimit > 0 {
		cfg.DownloadRateLimiter = rate.NewLimiter(rate.Limit(rateLimit), int(max(rateLimit, minRateBurst)))
	}
	if uploadLimit > 0 {
		cfg.UploadRateLimiter = rate.NewLimiter(rate.Limit(uploadLimit), int(max(uploadLimit, minRateBurst)))
	}
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
	// resuming: the player will seek to startFrac right away, so that part must be in before "ready"
	// (otherwise the seek waits for the download and the seek bar stays at the start)
	sb, se := -1, -2
	if startFrac > 0.01 && startFrac < 0.99 {
		off := int64(float64(length) * startFrac)
		if off -= int64(headBytes) / 4; off < 0 {
			off = 0
		}
		end := off + int64(headBytes)
		if end > length {
			end = length
		}
		sb, se = pieceRange(t, file, off, end)
		for i := sb; i <= se; i++ {
			t.Piece(i).SetPriority(types.PiecePriorityHigh)
		}
	}

	// Not streaming: the whole file is wanted, so let the client fetch it in order.
	if !streamOnly {
		file.SetPriority(types.PiecePriorityNormal)
	}

	// Streaming: only the window ahead of the playhead is wanted, so the whole file is
	// held at PiecePriorityNone and the window is moved along by hand as the player
	// reads. This has to be set explicitly: a piece's effective priority is the highest
	// of its file priority, the reader's readahead and any piece override, so leaving
	// the file alone would keep its default of PiecePriorityNormal and the client would
	// go on fetching the whole film. head, tail and the resume point stay High
	// throughout: the player reads the container structure from there whatever it plays.
	if streamOnly {
		file.SetPriority(types.PiecePriorityNone)
		// Too small a window and every read waits on the next piece to arrive, which
		// is heard as stutter; the head alone is 12 MB, so stay under that.
		if window < 8<<20 {
			window = 8 << 20
		}
		if window > length {
			window = length
		}
	}
	// Where each connection has read to. This is for reporting only: the fetch
	// itself is driven by each reader's own readahead (see the handler), which is
	// per connection by construction. It used to be one shared playhead driving a
	// single window, and that broke playback: VLC opens a second range request to
	// read an mp4's index at the end of the file, that probe moved the shared
	// playhead to the end, and the client then stopped fetching ahead of the actual
	// playback position and starved.
	var readersMu sync.Mutex
	readers := map[*playingReader]struct{}{}

	// a contiguous run of complete pieces starting at the playhead: how far the player can
	// read through without stopping to wait for the network
	bufferedAhead := func(from int64) int64 {
		if from < 0 {
			from = 0
		}
		if from >= length {
			return 0
		}
		begin, _ := pieceRange(t, file, from, from+1)
		fbase := file.Offset()
		pl := int64(t.Info().PieceLength)
		var got int64
		for i := begin; i < t.NumPieces(); i++ {
			if !t.Piece(i).State().Complete {
				break
			}
			b := int64(i)*pl - fbase
			e := b + pl
			if e > length {
				e = length
			}
			if e <= from {
				continue
			}
			if b < from {
				b = from
			}
			if e <= b {
				break
			}
			got = e - from
		}
		return got
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

		// Hand each verified chunk over as soon as it lands, in both modes.
		//
		// A non-responsive reader refuses to return anything at all out of a piece
		// that is not complete yet, so it stops dead at every piece boundary. With
		// multi-megabyte pieces that is a hard stall every second or two of playback,
		// and the audio decoder hears every one of them. Being responsive only lowers
		// the hand-over granularity to a chunk that has been checked against its
		// hash; it never returns data that has not been verified.
		reader.SetResponsive()

		// The reader's readahead is raised on top of whatever priority we set, so it
		// sets the floor for how far ahead we fetch. Following the configured window
		// keeps the buffer setting meaningful; in download mode the whole file is
		// wanted anyway and keeps the old fixed figure.
		readahead := window
		if !streamOnly {
			readahead = 32 << 20
		}
		reader.SetReadahead(readahead)

		live := &playingReader{r: reader, length: length}
		readersMu.Lock()
		readers[live] = struct{}{}
		readersMu.Unlock()
		defer func() {
			readersMu.Lock()
			delete(readers, live)
			readersMu.Unlock()
		}()
		serveRange(w, r, live, length)
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
		if se >= sb {
			sd, st := piecesComplete(t, sb, se)
			have += sd
			need += st
		}
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

		// where the player is, for the progress line. The furthest connection is used
		// because the playback stream is the one that runs longest; the short index
		// probe at the end of an mp4 finishes and is dropped again.
		pos := int64(0)
		readersMu.Lock()
		for rd := range readers {
			if p := rd.pos.Load(); p > pos {
				pos = p
			}
		}
		readersMu.Unlock()
		ahead := bufferedAhead(pos)

		emit(map[string]any{
			"event": "progress", "bufferPct": pct, "downloaded": done, "total": length,
			"peers": stats.ActivePeers, "seeders": stats.ConnectedSeeders,
			"speedBps": speed, "upBps": upSpeed, "uploaded": up,
			"position": pos, "buffered": ahead, "stream": streamOnly,
		})
		if !ready && have >= need {
			ready = true
			emit(map[string]any{"event": "ready", "url": url, "name": file.DisplayPath()})
		}
	}
}
