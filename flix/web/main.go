//go:build windows

// flixweb: a small browser window (Microsoft Edge WebView2) for the web players of the streaming
// providers listed in the Flix player.
//
//	flixweb --url https://... [--title T] [--data-dir DIR] [--parent-pid PID]
//
// Exit code 3: WebView2 is not available (the player then opens the default browser instead).
package main

import (
	"flag"
	"fmt"
	"net/url"
	"os"
	"strings"
	"syscall"

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
	title := flag.String("title", "Flix", "window title")
	dataDir := flag.String("data-dir", "", "folder for cookies and settings")
	parent := flag.Int("parent-pid", 0, "close when this process ends")
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
			Title:  strings.TrimSpace(*title) + " - Flix",
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

	w.Init(initScript)
	w.SetSize(1280, 760, webview2.HintNone)
	w.Navigate(u.String())

	if *parent > 0 {
		go func() {
			waitForProcess(*parent)
			w.Dispatch(func() { w.Terminate() })
		}()
	}
	w.Run()
}
