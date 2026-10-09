package notificationcenter

/*
#cgo CFLAGS: -x objective-c -fobjc-arc
#cgo LDFLAGS: -framework AppKit -framework ApplicationServices
#include <stdlib.h>
#include "clear_darwin.h"
*/
import "C"

import (
	"errors"
	"unsafe"
)

func nativeClear() clearResult {
	var message *C.char
	status := C.mnClearNotifications(&message)
	if message != nil {
		defer C.free(unsafe.Pointer(message))
	}
	if status == C.MNClearPermissionDenied {
		return clearResult{permissionDenied: true}
	}
	if status != C.MNClearOK {
		if message == nil {
			return clearResult{err: errors.New("Notification Center could not be cleared")}
		}
		return clearResult{err: errors.New(C.GoString(message))}
	}
	return clearResult{}
}

func nativeTerminalApplication() string {
	name := C.mnTerminalApplication()
	if name == nil {
		return ""
	}
	defer C.free(unsafe.Pointer(name))
	return C.GoString(name)
}
