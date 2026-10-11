//go:build windows

// flixweb: a small browser window (Microsoft Edge WebView2) for the web players of the streaming
// providers listed in the Flix player.
//
//	flixweb --url https://... [--title T] [--data-dir DIR] [--parent-pid PID]
//
// Exit code 3: WebView2 is not available (the player then opens the default browser instead).
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"html"
	"net/url"
	"os"
	"strings"
	"syscall"
	"unsafe"

	"github.com/jchv/go-webview2"
)

// popups and "open in new tab" tricks of the embedded players are refused; the player's own page
// stays in this window
const initScript = `(function () {
  var refuse = function () { return null; };
  try { window.open = refuse; } catch (e) {}
  document.addEventListener('click', function (e) {
    var a = e.target && e.target.closest ? e.target.closest('a[target]') : null;
    if (a && a.target !== '_self' && a.target !== '') { a.target = '_self'; }
  }, true);
})();`

// Fullscreen: a player's fullscreen button only makes the page fullscreen inside the WebView2
// control, so the page reports it and this program turns the whole window fullscreen.
const fullscreenScript = `(function () {
  function report() {
    try { window.flixFullscreen(!!document.fullscreenElement); } catch (e) {}
  }
  document.addEventListener('fullscreenchange', report, true);
  document.addEventListener('webkitfullscreenchange', report, true);
  document.addEventListener('keydown', function (e) {
    if (e.key === 'F11') { e.preventDefault(); try { window.flixToggleFullscreen(); } catch (x) {} }
  }, true);
})();`

// Progress: players that run in a frame of our page tell it how far they are (several providers
// post "timeupdate" style events); the numbers are passed on to VLC, which keeps "continue watching".
const progressScript = `(function () {
  if (window.top !== window) return;
  window.addEventListener('message', function (e) {
    var d = e.data;
    if (typeof d === 'string') { try { d = JSON.parse(d); } catch (x) { return; } }
    if (!d || typeof d !== 'object') return;
    var p = d.data && typeof d.data === 'object' ? d.data : d;
    var t = p.currentTime !== undefined ? p.currentTime : (p.time !== undefined ? p.time : p.progress);
    var n = p.duration !== undefined ? p.duration : p.total;
    if (typeof t === 'number' && isFinite(t)) {
      try { window.flixProgress(t, typeof n === 'number' && isFinite(n) ? n : 0); } catch (x) {}
    }
  });
})();`

var (
	user32            = syscall.NewLazyDLL("user32.dll")
	procGetWindowLong = user32.NewProc("GetWindowLongPtrW")
	procSetWindowLong = user32.NewProc("SetWindowLongPtrW")
	procGetPlacement  = user32.NewProc("GetWindowPlacement")
	procSetPlacement  = user32.NewProc("SetWindowPlacement")
	procSetWindowPos  = user32.NewProc("SetWindowPos")
	procMonitorFrom   = user32.NewProc("MonitorFromWindow")
	procGetMonitor    = user32.NewProc("GetMonitorInfoW")
	procGetRect       = user32.NewProc("GetWindowRect")
	procShowWindow    = user32.NewProc("ShowWindow")
)

type rect struct{ Left, Top, Right, Bottom int32 }
type point struct{ X, Y int32 }
type windowPlacement struct {
	Length, Flags, ShowCmd   uint32
	MinPosition, MaxPosition point
	NormalPosition           rect
}
type monitorInfo struct {
	Size    uint32
	Monitor rect
	Work    rect
	Flags   uint32
}

const (
	gwlStyle        = ^uintptr(15) // -16
	wsOverlapped    = 0x00CF0000   // caption + frame + sysmenu + min/max
	swpFrameChanged = 0x0020
	swpNoOwnerZ     = 0x0200
	swpShowWindow   = 0x0040
	hwndTop         = 0
	monitorNearest  = 2
	swRestore       = 9
)

var (
	fullscreen   bool
	savedStyle   uintptr
	savedPlace   windowPlacement
	windowHandle uintptr
)

// setFullscreen makes the whole window cover its monitor (or puts it back).
func setFullscreen(on bool) {
	if windowHandle == 0 || on == fullscreen {
		return
	}
	hwnd := windowHandle
	if on {
		savedStyle, _, _ = procGetWindowLong.Call(hwnd, gwlStyle)
		savedPlace.Length = uint32(unsafe.Sizeof(savedPlace))
		procGetPlacement.Call(hwnd, uintptr(unsafe.Pointer(&savedPlace)))
		mon, _, _ := procMonitorFrom.Call(hwnd, monitorNearest)
		var mi monitorInfo
		mi.Size = uint32(unsafe.Sizeof(mi))
		if r, _, _ := procGetMonitor.Call(mon, uintptr(unsafe.Pointer(&mi))); r == 0 {
			return
		}
		procSetWindowLong.Call(hwnd, gwlStyle, savedStyle&^wsOverlapped)
		procSetWindowPos.Call(hwnd, hwndTop, uintptr(mi.Monitor.Left), uintptr(mi.Monitor.Top),
			uintptr(mi.Monitor.Right-mi.Monitor.Left), uintptr(mi.Monitor.Bottom-mi.Monitor.Top),
			swpFrameChanged|swpNoOwnerZ|swpShowWindow)
	} else {
		procSetWindowLong.Call(hwnd, gwlStyle, savedStyle)
		procShowWindow.Call(hwnd, swRestore)
		procSetPlacement.Call(hwnd, uintptr(unsafe.Pointer(&savedPlace)))
		procSetWindowPos.Call(hwnd, 0, 0, 0, 0, 0, 0x0001|0x0002|0x0004|swpFrameChanged|swpNoOwnerZ)
	}
	fullscreen = on
}

// hostPage shows the provider's player in a frame so its progress messages can be heard.
func hostPage(src string) string {
	return `<!doctype html><meta charset=utf-8><title>VLCFlix</title>
<style>html,body{margin:0;height:100%;background:#000;overflow:hidden}iframe{border:0;width:100%;height:100%}</style>
<iframe src="` + html.EscapeString(src) + `" allowfullscreen allow="autoplay; fullscreen; encrypted-media; picture-in-picture"></iframe>`
}

// waitForProcess returns when the process with this id has ended (or cannot be opened).
func waitForProcess(pid int) {
	const synchronize = 0x00100000
	h, err := syscall.OpenProcess(synchronize, false, uint32(pid))
	if err != nil {
		return
	}
	defer syscall.CloseHandle(h)
	syscall.WaitForSingleObject(h, syscall.INFINITE)
}

func main() {
	target := flag.String("url", "", "https page to show")
	title := flag.String("title", "VLCFlix", "window title")
	dataDir := flag.String("data-dir", "", "folder for cookies and settings")
	parent := flag.Int("parent-pid", 0, "close when this process ends")
	frame := flag.Bool("frame", false, "show the page inside a frame and report its playback progress")
	flag.Parse()

	u, err := url.Parse(*target)
	if err != nil || u.Scheme != "https" || u.Host == "" {
		fmt.Fprintln(os.Stderr, "only https pages can be shown")
		os.Exit(2)
	}

	w := webview2.NewWithOptions(webview2.WebViewOptions{
		DataPath:  *dataDir,
		AutoFocus: true,
		WindowOptions: webview2.WindowOptions{
			Title:  strings.TrimSpace(*title) + " - VLCFlix",
			Width:  1280,
			Height: 760,
			Center: true,
		},
	})
	if w == nil {
		fmt.Fprintln(os.Stderr, "Microsoft Edge WebView2 is not available")
		os.Exit(3)
	}
	defer w.Destroy()

	windowHandle = uintptr(w.Window())
	w.Bind("flixFullscreen", func(on bool) { w.Dispatch(func() { setFullscreen(on) }) })
	w.Bind("flixToggleFullscreen", func() { w.Dispatch(func() { setFullscreen(!fullscreen) }) })
	last := 0
	w.Bind("flixProgress", func(t, d float64) {
		// at most about one line per 5 seconds of playback
		if int(t)/5 == last/5 && int(t) != 0 {
			return
		}
		last = int(t)
		b, _ := json.Marshal(map[string]any{"event": "progress", "seconds": t, "duration": d})
		fmt.Println(string(b))
	})
	w.Init(initScript)
	w.Init(fullscreenScript)
	w.SetSize(1280, 760, webview2.HintNone)
	// players tell their page how far they are ("PLAYER_EVENT" with currentTime); shown directly
	// the page is its own parent, so the message arrives here
	w.Init(progressScript)
	if *frame {
		w.SetHtml(hostPage(u.String()))
	} else {
		w.Navigate(u.String())
	}

	if *parent > 0 {
		go func() {
			waitForProcess(*parent)
			w.Dispatch(func() { w.Terminate() })
		}()
	}
	w.Run()
}
