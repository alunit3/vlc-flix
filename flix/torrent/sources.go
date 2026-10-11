package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
)

// the public Stremio addons the Heartive torrents page asks, in the same order
var addons = []struct{ name, base string }{
	{"Torrentio", "https://torrentio.strem.fun"},
	{"Comet", "https://comet.feels.legal"},
	{"StremThru", "https://stremthru.13377001.xyz/stremio/torz/eyJpbmRleGVycyI6bnVsbCwic3RvcmVzIjpbeyJjIjoicDJwIiwidCI6IiJ9XX0="},
	{"PirateBay+", "https://thepiratebay-plus.strem.fun"},
}

const trackersURL = "https://cdn.jsdelivr.net/gh/ngosang/trackerslist@master/trackers_best.txt"
const trackersAllURL = "https://cdn.jsdelivr.net/gh/ngosang/trackerslist@master/trackers_all_udp.txt"

// Source is one torrent offered for a title.
type Source struct {
	ID        string   `json:"id"`
	Name      string   `json:"name"`      // release name
	Title     string   `json:"title"`     // description text
	Quality   string   `json:"quality"`   // 4K, 1080p, 720p, 480p, SD, CAM
	Seeders   int      `json:"seeders"`   // -1 when unknown
	SizeBytes int64    `json:"sizeBytes"` // 0 when unknown
	SizeText  string   `json:"sizeText"`
	Source    string   `json:"source"` // addon / tracker site
	InfoHash  string   `json:"infoHash"`
	FileIdx   int      `json:"fileIdx"` // -1 when unknown
	Trackers  []string `json:"trackers"`
	Languages string   `json:"languages"`
	Magnet    string   `json:"magnet"`
}

type stremioStream struct {
	Name          string   `json:"name"`
	Title         string   `json:"title"`
	Description   string   `json:"description"`
	InfoHash      string   `json:"infoHash"`
	FileIdx       *int     `json:"fileIdx"`
	Sources       []string `json:"sources"`
	BehaviorHints struct {
		Filename string `json:"filename"`
	} `json:"behaviorHints"`
}

var (
	reSeeders = regexp.MustCompile(`👤\s*(\d+)`)
	reSize    = regexp.MustCompile(`(?i)💾\s*(\d+(?:[.,]\d+)?)\s*(TB|GB|MB|KB)`)
	reHash    = regexp.MustCompile(`^[0-9a-fA-F]{40}$`)
	reSite    = regexp.MustCompile(`⚙️\s*([^\n\r]+)`)
	reImdb    = regexp.MustCompile(`^tt\d{5,10}$`)
)

var reCam = regexp.MustCompile(`(?i)(^|[^a-z0-9])(cam|camrip|hdcam|telesync|hdts|hd-ts|tsrip|ts-rip|telecine|tc-rip|hdtc)([^a-z0-9]|$)`)

func qualityOf(parts ...string) string {
	joined := strings.Join(parts, " ")
	// screener / cinema recordings come first: "1080p CAMRip" is still a camera copy
	if reCam.MatchString(joined) {
		return "CAM"
	}
	s := " " + strings.ToLower(joined) + " "
	switch {
	case strings.Contains(s, "2160") || strings.Contains(s, "4k") || strings.Contains(s, "uhd"):
		return "4K"
	case strings.Contains(s, "1080"):
		return "1080p"
	case strings.Contains(s, "720"):
		return "720p"
	case strings.Contains(s, "480") || strings.Contains(s, "576"):
		return "480p"
	}
	return "SD"
}

func parseSize(text string) (int64, string) {
	m := reSize.FindStringSubmatch(text)
	if m == nil {
		return 0, ""
	}
	v, _ := strconv.ParseFloat(strings.Replace(m[1], ",", ".", 1), 64)
	mult := map[string]float64{"KB": 1 << 10, "MB": 1 << 20, "GB": 1 << 30, "TB": 1 << 40}[strings.ToUpper(m[2])]
	return int64(v * mult), m[1] + " " + strings.ToUpper(m[2])
}

func httpGet(ctx context.Context, url string) ([]byte, error) {
	req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", "flixtorrent/1.0")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return nil, fmt.Errorf("http %d", resp.StatusCode)
	}
	return io.ReadAll(io.LimitReader(resp.Body, 8<<20))
}

func cached(cacheDir, key string, maxAge time.Duration, fetch func() ([]byte, error)) ([]byte, error) {
	var path string
	if cacheDir != "" {
		os.MkdirAll(cacheDir, 0o700)
		path = filepath.Join(cacheDir, key)
		if st, err := os.Stat(path); err == nil && time.Since(st.ModTime()) < maxAge {
			if b, err := os.ReadFile(path); err == nil {
				return b, nil
			}
		}
	}
	b, err := fetch()
	if err == nil && path != "" {
		os.WriteFile(path, b, 0o600)
	}
	return b, err
}

// loadTrackers: the user's trackers, the built-in list and ngosang's "best" and "all udp" lists
func loadTrackers(cacheDir string) []string {
	read := func(name, url string) []string {
		ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
		defer cancel()
		b, err := cached(cacheDir, name, 24*time.Hour, func() ([]byte, error) { return httpGet(ctx, url) })
		if err != nil {
			return nil
		}
		var list []string
		for _, l := range strings.Split(string(b), "\n") {
			if l = strings.TrimSpace(l); reTracker.MatchString(l) {
				list = append(list, l)
			}
		}
		return list
	}
	var best, all []string
	var wg sync.WaitGroup
	wg.Add(2)
	go func() { defer wg.Done(); best = read("trackers.txt", trackersURL) }()
	go func() { defer wg.Done(); all = read("trackers-all-udp.txt", trackersAllURL) }()
	wg.Wait()
	return mergeTrackers(80, best, defaultTrackers, all)
}

func fetchAddon(cacheDir, name, base, path string) []Source {
	ctx, cancel := context.WithTimeout(context.Background(), 6*time.Second)
	defer cancel()
	key := strings.NewReplacer("/", "_", ":", "_").Replace(name + "-" + path)
	raw, err := cached(cacheDir, key, 20*time.Minute, func() ([]byte, error) {
		return httpGet(ctx, base+path)
	})
	if err != nil {
		return nil
	}
	var doc struct {
		Streams []stremioStream `json:"streams"`
	}
	if json.Unmarshal(raw, &doc) != nil {
		return nil
	}
	var out []Source
	for _, st := range doc.Streams {
		hash := strings.ToLower(st.InfoHash)
		if !reHash.MatchString(hash) {
			continue
		}
		text := st.Title
		if text == "" {
			text = st.Description
		}
		release := strings.TrimSpace(strings.SplitN(strings.TrimPrefix(text, "📄 "), "\n", 2)[0])
		if st.BehaviorHints.Filename != "" {
			release = st.BehaviorHints.Filename
		}
		seeders := -1
		if m := reSeeders.FindStringSubmatch(text); m != nil {
			seeders, _ = strconv.Atoi(m[1])
		}
		size, sizeText := parseSize(text)
		site := name
		if m := reSite.FindStringSubmatch(text); m != nil {
			site = name + " / " + strings.TrimSpace(m[1])
		}
		nameLines := strings.Split(st.Name, "\n")
		qhint := ""
		if len(nameLines) > 1 {
			qhint = nameLines[len(nameLines)-1]
		} else if len(nameLines) == 1 {
			qhint = strings.TrimPrefix(nameLines[0], name)
		}
		var trackers []string
		for _, s := range st.Sources {
			if strings.HasPrefix(s, "tracker:") {
				trackers = append(trackers, strings.TrimPrefix(s, "tracker:"))
			}
		}
		idx := -1
		if st.FileIdx != nil {
			idx = *st.FileIdx
		}
		// the last line of Torrentio / Comet descriptions lists flags; keep it as the language hint
		lines := strings.Split(strings.TrimSpace(text), "\n")
		langs := ""
		if len(lines) > 2 {
			langs = strings.TrimSpace(lines[len(lines)-1])
		}
		out = append(out, Source{
			Name: release, Title: text, Quality: qualityOf(qhint, release),
			Seeders: seeders, SizeBytes: size, SizeText: sizeText, Source: site,
			InfoHash: hash, FileIdx: idx, Trackers: trackers, Languages: langs,
		})
	}
	return out
}

func runSources(imdb string, season, episode int, cacheDir string) int {
	if !reImdb.MatchString(imdb) {
		emit(map[string]any{"error": "bad IMDb id"})
		return 1
	}
	path := "/stream/movie/" + imdb + ".json"
	if season > 0 && episode > 0 {
		path = fmt.Sprintf("/stream/series/%s:%d:%d.json", imdb, season, episode)
	}

	var wg sync.WaitGroup
	var mu sync.Mutex
	var all []Source
	for _, a := range addons {
		wg.Add(1)
		go func(name, base string) {
			defer wg.Done()
			list := fetchAddon(cacheDir, name, base, path)
			mu.Lock()
			all = append(all, list...)
			mu.Unlock()
		}(a.name, a.base)
	}
	var trackers []string
	wg.Add(1)
	go func() { defer wg.Done(); trackers = loadTrackers(cacheDir) }()
	wg.Wait()

	// one entry per torrent: keep the one that knows the most
	best := map[string]*Source{}
	var order []string
	for i := range all {
		s := &all[i]
		if cur, ok := best[s.InfoHash]; !ok {
			best[s.InfoHash] = s
			order = append(order, s.InfoHash)
		} else if s.Seeders > cur.Seeders || (cur.SizeBytes == 0 && s.SizeBytes > 0) {
			if s.Seeders < cur.Seeders {
				s.Seeders = cur.Seeders
			}
			best[s.InfoHash] = s
		}
	}
	list := []Source{}
	for _, h := range order {
		s := best[h]
		if s.Seeders == 0 {
			continue
		}
		seen := map[string]bool{}
		var tr []string
		for _, t := range append(append([]string{}, s.Trackers...), trackers...) {
			if !seen[t] {
				seen[t] = true
				tr = append(tr, t)
			}
		}
		s.Trackers = tr
		magnet := "magnet:?xt=urn:btih:" + s.InfoHash
		for _, t := range tr {
			magnet += "&tr=" + urlEscape(t)
		}
		s.Magnet = magnet
		s.ID = s.InfoHash
		list = append(list, *s)
	}
	sort.SliceStable(list, func(i, j int) bool { return list[i].Seeders > list[j].Seeders })
	emit(map[string]any{"sources": list})
	return 0
}
