package main

import (
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/anacrolix/torrent/types/infohash"
)

// makeFolder creates root/name holding size bytes, last used age ago.
func makeFolder(t *testing.T, root, name string, size int, age time.Duration) {
	t.Helper()
	dir := filepath.Join(root, name)
	if err := os.MkdirAll(filepath.Join(dir, "film"), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "film", "part"), make([]byte, size), 0o600); err != nil {
		t.Fatal(err)
	}
	when := time.Now().Add(-age)
	if err := os.Chtimes(dir, when, when); err != nil {
		t.Fatal(err)
	}
}

func exists(root, name string) bool {
	_, err := os.Stat(filepath.Join(root, name))
	return err == nil
}

func TestPruneCacheRemovesOldestFirst(t *testing.T) {
	root := t.TempDir()
	makeFolder(t, root, "old", 400, 3*time.Hour)
	makeFolder(t, root, "mid", 400, 2*time.Hour)
	makeFolder(t, root, "new", 400, 1*time.Hour)

	if err := pruneCache(root, "new", 800); err != nil {
		t.Fatal(err)
	}
	if exists(root, "old") {
		t.Error("the least recently used folder should have gone")
	}
	if !exists(root, "mid") || !exists(root, "new") {
		t.Error("pruning went further than the cap needed")
	}
}

func TestPruneCacheNeverRemovesTheFolderInUse(t *testing.T) {
	root := t.TempDir()
	makeFolder(t, root, "playing", 1000, 5*time.Hour) // oldest, and alone over the cap
	makeFolder(t, root, "other", 100, 1*time.Hour)

	if err := pruneCache(root, "playing", 500); err != nil {
		t.Fatal(err)
	}
	if !exists(root, "playing") {
		t.Fatal("the folder about to be played was removed")
	}
	if exists(root, "other") {
		t.Error("everything else should go when the one in use alone is over the cap")
	}
}

func TestPruneCacheUnderCapKeepsAll(t *testing.T) {
	root := t.TempDir()
	makeFolder(t, root, "a", 100, 2*time.Hour)
	makeFolder(t, root, "b", 100, 1*time.Hour)

	if err := pruneCache(root, "b", 1000); err != nil {
		t.Fatal(err)
	}
	if !exists(root, "a") || !exists(root, "b") {
		t.Error("nothing should be removed under the cap")
	}
}

func TestPruneCacheMissingRoot(t *testing.T) {
	if err := pruneCache(filepath.Join(t.TempDir(), "absent"), "x", 1); err != nil {
		t.Fatalf("a cache that does not exist yet is not an error: %v", err)
	}
}

func TestInfoRoundTripAndHashCheck(t *testing.T) {
	dir := t.TempDir()
	info := []byte("d4:name4:testxe") // any bytes: only their hash matters here
	saveInfo(dir, info)

	if got := loadInfo(dir, infohash.HashBytes(info)); string(got) != string(info) {
		t.Fatalf("saved metadata not read back: %q", got)
	}
	var other infohash.T
	other[0] = 1
	if got := loadInfo(dir, other); got != nil {
		t.Error("metadata of another torrent must not be accepted")
	}
	if got := loadInfo(t.TempDir(), infohash.HashBytes(info)); got != nil {
		t.Error("an empty folder has no metadata")
	}
}
