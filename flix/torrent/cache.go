package main

import (
	"errors"
	"io/fs"
	"math/rand/v2"
	"os"
	"path/filepath"
	"sort"
	"time"

	"github.com/anacrolix/torrent"
	"github.com/anacrolix/torrent/metainfo"
	"github.com/anacrolix/torrent/types/infohash"
)

// The kept-data cache: one folder per torrent, named by its info hash, under --cache-root.
//
// Resuming used to be a cold start every time: the metadata was asked of the swarm again
// (ten seconds to a minute and a half) and the data from the last session had been deleted,
// so the head, the tail and the resume point all came down a second time. Keeping the
// folder means the piece-completion database the library writes inside it already knows
// what is on disk, and the info dictionary saved next to it skips the metadata exchange.

// infoFile holds the torrent's info dictionary, so a magnet does not have to fetch it again.
const infoFile = ".flix-info"

// torrentSpec builds what the client is given for a magnet or a .torrent file.
func torrentSpec(magnet, torrentFile string) (*torrent.TorrentSpec, error) {
	if torrentFile != "" {
		mi, err := metainfo.LoadFromFile(torrentFile)
		if err != nil {
			return nil, err
		}
		return torrent.TorrentSpecFromMetaInfoErr(mi)
	}
	return torrent.TorrentSpecFromMagnetUri(magnet)
}

// loadInfo returns the saved info dictionary of the torrent with this hash, or nil when there
// is none or it does not belong to that hash.
func loadInfo(dir string, hash infohash.T) []byte {
	b, err := os.ReadFile(filepath.Join(dir, infoFile))
	if err != nil || len(b) == 0 {
		return nil
	}
	if infohash.HashBytes(b) != hash {
		return nil
	}
	return b
}

// saveInfo keeps the info dictionary for the next start. It is written once: the bytes of a
// given hash never change.
func saveInfo(dir string, info []byte) {
	if len(info) == 0 {
		return
	}
	p := filepath.Join(dir, infoFile)
	if _, err := os.Stat(p); err == nil {
		return
	}
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return
	}
	tmp := p + ".tmp"
	if os.WriteFile(tmp, info, 0o600) == nil {
		os.Rename(tmp, p)
	}
}

// touch marks a cache folder as just used; pruning goes by this time.
func touch(dir string) {
	now := time.Now()
	os.Chtimes(dir, now, now)
}

func dirBytes(dir string) (total int64) {
	filepath.WalkDir(dir, func(_ string, d fs.DirEntry, err error) error {
		if err != nil {
			return nil
		}
		if !d.IsDir() {
			if info, err := d.Info(); err == nil {
				total += info.Size()
			}
		}
		return nil
	})
	return
}

// pruneCache removes the least recently used torrent folders under root until everything
// together fits in capBytes. The folder named keep is the one about to be used: it is counted
// but never removed, so a single film bigger than the cap still plays.
func pruneCache(root, keep string, capBytes int64) error {
	entries, err := os.ReadDir(root)
	if err != nil {
		if errors.Is(err, fs.ErrNotExist) {
			return nil
		}
		return err
	}
	type folder struct {
		name  string
		bytes int64
		used  time.Time
	}
	var folders []folder
	var total int64
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		info, err := e.Info()
		if err != nil {
			continue
		}
		f := folder{e.Name(), dirBytes(filepath.Join(root, e.Name())), info.ModTime()}
		total += f.bytes
		folders = append(folders, f)
	}
	sort.Slice(folders, func(i, j int) bool { return folders[i].used.Before(folders[j].used) })
	for _, f := range folders {
		if total <= capBytes {
			break
		}
		if f.name == keep {
			continue
		}
		if err := os.RemoveAll(filepath.Join(root, f.name)); err == nil {
			total -= f.bytes
		}
	}
	return nil
}

// newClient starts the torrent client on a port Windows will actually let us bind.
//
// With ListenPort 0 the library takes a free TCP port from the system and then needs the
// same number for UDP. Hyper-V, WSL and Docker reserve blocks of ports (see "netsh int ipv4
// show excludedportrange"), and on a machine running them the UDP half of that pair lands
// in a reserved block often enough - about one start in ten here - that the helper failed
// with "bind: An attempt was made to access a socket in a way forbidden by its access
// permissions" before the stream had even begun. Try a few explicit ports instead; the
// range below sits clear of the blocks Windows hands out for its own use.
func newClient(cfg *torrent.ClientConfig) (cl *torrent.Client, err error) {
	for attempt := 0; attempt < 12; attempt++ {
		cfg.ListenPort = 20000 + rand.IntN(20000)
		if cl, err = torrent.NewClient(cfg); err == nil {
			return cl, nil
		}
	}
	return nil, err
}
