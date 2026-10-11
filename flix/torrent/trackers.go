package main

import (
	"os"
	"regexp"
	"strings"

	"github.com/anacrolix/torrent"
)

// public trackers added to every torrent (dead ones just time out; the swarm also finds peers over DHT)
var defaultTrackers = []string{
	"udp://tracker.opentrackr.org:1337/announce",
	"udp://open.stealth.si:80/announce",
	"udp://tracker.torrent.eu.org:451/announce",
	"udp://open.demonii.com:1337/announce",
	"udp://exodus.desync.com:6969/announce",
	"udp://explodie.org:6969/announce",
	"udp://tracker.tiny-vps.com:6969/announce",
	"udp://tracker.moeking.me:6969/announce",
	"udp://tracker.dler.org:6969/announce",
	"udp://open.tracker.cl:1337/announce",
	"udp://tracker.theoks.net:6969/announce",
	"udp://tracker-udp.gbitt.info:80/announce",
	"udp://tracker1.bt.moack.co.kr:80/announce",
	"udp://opentracker.io:6969/announce",
	"udp://p4p.arenabg.com:1337/announce",
	"udp://tracker.cyberia.is:6969/announce",
	"udp://retracker.lanta-net.ru:2710/announce",
	"udp://tracker.internetwarriors.net:1337/announce",
	"udp://movies.zsw.ca:6969/announce",
	"udp://ipv4.tracker.harry.lu:80/announce",
	"udp://tracker.army:6969/announce",
	"udp://tracker.birkenwald.de:6969/announce",
	"udp://tracker.bittor.pw:1337/announce",
	"udp://tracker.filemail.com:6969/announce",
	"udp://tracker.publictracker.xyz:6969/announce",
	"udp://tracker.srv00.com:6969/announce",
	"udp://tracker.qu.ax:6969/announce",
	"udp://tracker.t-1.org:6969/announce",
	"udp://tracker.0x7c0.com:6969/announce",
	"udp://run.publictracker.xyz:6969/announce",
	"udp://wepzone.net:6969/announce",
	"udp://martin-gebhardt.eu:25/announce",
	"udp://isk.richardsw.club:6969/announce",
	"udp://evan.im:6969/announce",
	"https://tracker.tamersunion.org:443/announce",
	"https://tracker.gbitt.info:443/announce",
	"https://tracker1.520.jp:443/announce",
	"http://tracker.opentrackr.org:1337/announce",
}

var reTracker = regexp.MustCompile(`(?i)^(udp|https?|wss?)://[^\s/]+(:\d{1,5})?(/\S*)?$`)

// trackersFile is the user's own list (--trackers-file): one URL per line, # starts a comment
var trackersFile string

// userTrackers reads the user's own trackers; invalid lines are ignored.
func userTrackers() []string {
	if trackersFile == "" {
		return nil
	}
	b, err := os.ReadFile(trackersFile)
	if err != nil {
		return nil
	}
	var list []string
	for _, l := range strings.Split(string(b), "\n") {
		if l = strings.TrimSpace(l); l != "" && !strings.HasPrefix(l, "#") && reTracker.MatchString(l) {
			list = append(list, l)
		}
	}
	return list
}

// mergeTrackers: the user's trackers first, then the given lists, without duplicates, at most max.
func mergeTrackers(max int, lists ...[]string) []string {
	seen := map[string]bool{}
	var out []string
	for _, list := range append([][]string{userTrackers()}, lists...) {
		for _, t := range list {
			key := strings.ToLower(strings.TrimRight(t, "/"))
			if !seen[key] && len(out) < max {
				seen[key] = true
				out = append(out, t)
			}
		}
	}
	return out
}

// addTrackers puts the user's and the default trackers on a torrent (also for magnets that carry none).
func addTrackers(t *torrent.Torrent) {
	list := mergeTrackers(80, defaultTrackers)
	tiers := make([][]string, 0, len(list))
	for _, tr := range list {
		tiers = append(tiers, []string{tr})
	}
	t.AddTrackers(tiers)
}
