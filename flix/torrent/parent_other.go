//go:build !windows

package main

import (
	"os"
	"syscall"
	"time"
)

// waitForProcess returns when the process with this id has ended.
func waitForProcess(pid int) {
	p, err := os.FindProcess(pid)
	if err != nil {
		return
	}
	for p.Signal(syscall.Signal(0)) == nil {
		time.Sleep(time.Second)
	}
}
