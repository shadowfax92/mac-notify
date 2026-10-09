package menubar

/*
#cgo CFLAGS: -x objective-c
#cgo LDFLAGS: -framework UserNotifications

#include <stdlib.h>
#include "notify_darwin.h"
*/
import "C"
import (
	"fmt"
	"log"
	"os"
	"slices"
	"sync"
	"time"
	"unsafe"

	"github.com/caseymrm/menuet"
	"github.com/nickhudkins/mac-notify/config"
	"github.com/nickhudkins/mac-notify/ipc"
)

var (
	mu         sync.RWMutex
	messages   []ipc.Message
	nextID     int
	flashTimer *time.Timer
	flashMu    sync.Mutex
	liveConfig = newRuntimeConfig(
		func() { C.setupNotificationDelegate() },
		func() { C.requestNotificationAuth() },
		log.Printf,
	)
)

func HandleRequest(req ipc.Request) ipc.Response {
	switch req.Action {
	case "send":
		return handleSend(req)
	case "clear":
		return handleClear()
	case "list":
		return handleList()
	case "status":
		resp := handleList()
		resp.Config = liveConfig.status()
		return resp
	case "remove":
		return handleRemove(req)
	default:
		return ipc.Response{OK: false, Error: "unknown action: " + req.Action}
	}
}

func handleSend(req ipc.Request) ipc.Response {
	if req.Message == "" {
		return ipc.Response{OK: false, Error: "message is required"}
	}

	mu.Lock()
	defer mu.Unlock()
	settings := liveConfig.snapshot()

	if req.ID != "" {
		for i, m := range messages {
			if m.ID == req.ID {
				messages[i].Text = req.Message
				messages[i].Source = req.Source
				messages[i].Time = time.Now()
				updateTitle()
				sendSystemNotification(settings, req.Message, req.Source, req.ID)
				presentOverlay(settings, req)
				flashTitle(settings, req.Message, req.Source)
				return ipc.Response{OK: true}
			}
		}
	}

	id := req.ID
	if id == "" {
		nextID++
		id = fmt.Sprintf("msg-%d", nextID)
	}

	messages = append(messages, ipc.Message{
		ID:     id,
		Text:   req.Message,
		Source: req.Source,
		Time:   time.Now(),
	})
	updateTitle()
	sendSystemNotification(settings, req.Message, req.Source, id)
	presentOverlay(settings, req)
	flashTitle(settings, req.Message, req.Source)
	return ipc.Response{OK: true}
}

func handleClear() ipc.Response {
	mu.Lock()
	defer mu.Unlock()
	messages = nil
	updateTitle()
	// Cleanup is unconditional: native notifications can outlive a daemon
	// restart or a change that disables system_notifications.
	C.clearDarwinNotifications()
	C.dismissBlocker()
	return ipc.Response{OK: true}
}

func handleList() ipc.Response {
	mu.RLock()
	defer mu.RUnlock()
	msgs := make([]ipc.Message, len(messages))
	copy(msgs, messages)
	return ipc.Response{OK: true, Messages: msgs}
}

func handleRemove(req ipc.Request) ipc.Response {
	if req.ID == "" {
		return ipc.Response{OK: false, Error: "id is required for remove"}
	}
	mu.Lock()
	defer mu.Unlock()
	idx := -1
	for i, m := range messages {
		if m.ID == req.ID {
			idx = i
			break
		}
	}
	if idx == -1 {
		return ipc.Response{OK: false, Error: "message not found: " + req.ID}
	}
	messages = slices.Delete(messages, idx, idx+1)
	updateTitle()
	cID := C.CString(req.ID)
	defer C.free(unsafe.Pointer(cID))
	C.removeDarwinNotification(cID)
	return ipc.Response{OK: true}
}

func sendSystemNotification(settings config.Config, msg, source, id string) {
	if !settings.SystemNotifications {
		return
	}
	title := "mac-notify"
	if source != "" {
		title = source
	}
	cTitle := C.CString(title)
	cBody := C.CString(msg)
	cID := C.CString(id)
	defer C.free(unsafe.Pointer(cTitle))
	defer C.free(unsafe.Pointer(cBody))
	defer C.free(unsafe.Pointer(cID))
	C.sendDarwinNotification(cTitle, cBody, cID)
}

// presentOverlay routes a send to the persistent red blocker panel when
// req.Blocker is set, otherwise to the transient overlay.
func presentOverlay(settings config.Config, req ipc.Request) {
	if req.Blocker {
		showBlocker(req.Message, req.Source)
		return
	}
	showOverlay(settings, req.Message, req.Source)
}

func showOverlay(settings config.Config, msg, source string) {
	if !settings.OverlayNotifications {
		return
	}
	title := "mac-notify"
	if source != "" {
		title = source
	}
	cTitle := C.CString(title)
	cBody := C.CString(msg)
	defer C.free(unsafe.Pointer(cTitle))
	defer C.free(unsafe.Pointer(cBody))
	timeout := settings.OverlayTimeout
	if timeout <= 0 {
		timeout = 5
	}
	C.showOverlayNotification(cTitle, cBody, C.double(timeout))
}

// showBlocker shows the persistent red-glow panel. It is not gated by
// OverlayNotifications: --blocker is an explicit request, not the ambient overlay.
func showBlocker(msg, source string) {
	title := "mac-notify"
	if source != "" {
		title = source
	}
	cTitle := C.CString(title)
	cBody := C.CString(msg)
	defer C.free(unsafe.Pointer(cTitle))
	defer C.free(unsafe.Pointer(cBody))
	C.showBlockerNotification(cTitle, cBody)
}

func flashTitle(settings config.Config, msg, source string) {
	if !settings.MenuFlash {
		return
	}
	text := msg
	if source != "" {
		text = fmt.Sprintf("[%s] %s", source, msg)
	}
	runes := []rune(text)
	if len(runes) > 30 {
		text = string(runes[:27]) + "..."
	}

	flashMu.Lock()
	if flashTimer != nil {
		flashTimer.Stop()
	}
	menuet.App().SetMenuState(&menuet.MenuState{
		Title: "🔔 " + text,
	})
	flashTimer = time.AfterFunc(2*time.Second, func() {
		flashMu.Lock()
		flashTimer = nil
		flashMu.Unlock()
		mu.RLock()
		n := len(messages)
		mu.RUnlock()
		if n == 0 {
			menuet.App().SetMenuState(&menuet.MenuState{Title: "🔔"})
		} else {
			menuet.App().SetMenuState(&menuet.MenuState{
				Title: fmt.Sprintf("🔔 %d", n),
			})
		}
	})
	flashMu.Unlock()
}

func updateTitle() {
	n := len(messages)
	if n == 0 {
		menuet.App().SetMenuState(&menuet.MenuState{Title: "🔔"})
	} else {
		menuet.App().SetMenuState(&menuet.MenuState{
			Title: fmt.Sprintf("🔔 %d", n),
		})
	}
}

func menuItems() []menuet.MenuItem {
	mu.RLock()
	msgs := make([]ipc.Message, len(messages))
	copy(msgs, messages)
	mu.RUnlock()

	var items []menuet.MenuItem

	if len(msgs) == 0 {
		items = append(items, menuet.MenuItem{
			Text: "No notifications",
		})
	} else {
		for _, m := range msgs {
			text := m.Text
			if m.Source != "" {
				text = fmt.Sprintf("[%s] %s", m.Source, m.Text)
			}
			msgID := m.ID
			items = append(items, menuet.MenuItem{
				Text: text,
				Clicked: func() {
					// Use the IPC handler so queue and native notification cleanup
					// stay together under mu, including when sends race menu clicks.
					handleRemove(ipc.Request{ID: msgID})
				},
			})
		}
		items = append(items, menuet.MenuItem{Type: menuet.Separator})
		items = append(items, menuet.MenuItem{
			Text: "Clear All",
			Clicked: func() {
				handleClear()
			},
		})
	}

	return items
}

// Run owns startup ordering: publish policy and initialize native notifications
// before opening IPC. The config watcher follows menuet's shutdown context.
func Run(c *config.Config) {
	liveConfig.apply(c)
	app := menuet.App()
	app.SetMenuState(&menuet.MenuState{Title: "🔔"})
	app.Children = menuItems
	app.Label = "com.nickhudkins.mac-notify"
	wg, ctx := app.GracefulShutdownHandles()
	wg.Add(1)
	go func() {
		defer wg.Done()
		liveConfig.watch(ctx, config.NewWatcher(config.Path()))
	}()
	go func() {
		if err := ipc.ListenAndServe(HandleRequest); err != nil {
			fmt.Fprintf(os.Stderr, "ipc server error: %v\n", err)
			os.Exit(1)
		}
	}()
	app.RunApplication()
}
