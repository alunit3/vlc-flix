//go:build windows

package main

import "syscall"

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
