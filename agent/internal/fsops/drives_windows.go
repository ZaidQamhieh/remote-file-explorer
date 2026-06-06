//go:build windows

package fsops

import (
	"syscall"
	"unsafe"
)

func platformDrives() ([]Drive, error) {
	kernel32 := syscall.NewLazyDLL("kernel32.dll")
	getLogicalDrives := kernel32.NewProc("GetLogicalDrives")
	getDiskFreeSpaceEx := kernel32.NewProc("GetDiskFreeSpaceExW")

	ret, _, _ := getLogicalDrives.Call()
	mask := uint32(ret)

	var drives []Drive
	for i := 0; i < 26; i++ {
		if mask&(1<<uint(i)) != 0 {
			letter := string(rune('A'+i)) + ":\\"
			d := Drive{Path: letter, Label: letter}
			lpFreeBytesAvailable := uint64(0)
			lpTotalNumberOfBytes := uint64(0)
			lpTotalNumberOfFreeBytes := uint64(0)
			p, _ := syscall.UTF16PtrFromString(letter)
			getDiskFreeSpaceEx.Call(
				uintptr(unsafe.Pointer(p)),
				uintptr(unsafe.Pointer(&lpFreeBytesAvailable)),
				uintptr(unsafe.Pointer(&lpTotalNumberOfBytes)),
				uintptr(unsafe.Pointer(&lpTotalNumberOfFreeBytes)),
			)
			d.TotalBytes = int64(lpTotalNumberOfBytes)
			d.FreeBytes = int64(lpTotalNumberOfFreeBytes)
			drives = append(drives, d)
		}
	}
	return drives, nil
}
