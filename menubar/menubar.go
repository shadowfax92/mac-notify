package menubar

import (
	"fmt"
	"os/exec"
	"slices"
	"sync"
	"time"

	"github.com/caseymrm/menuet"
	"github.com/nickhudkins/mac-notify/config"
	"github.com/nickhudkins/mac-notify/ipc"
)

var (
	mu       sync.RWMutex
	messages []ipc.Message
	nextID   int
	cfg      *config.Config
)

func HandleRequest(req ipc.Request) ipc.Response {
	switch req.Action {
	case "send":
		return handleSend(req)
	case "clear":
		return handleClear()
	case "list":
		return handleList()
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

	// If ID provided, upsert (replace existing message with same ID)
	if req.ID != "" {
		for i, m := range messages {
			if m.ID == req.ID {
				messages[i].Text = req.Message
				messages[i].Source = req.Source
				messages[i].Time = time.Now()
				updateTitle()
				sendSystemNotification(req.Message, req.Source)
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
	sendSystemNotification(req.Message, req.Source)
	return ipc.Response{OK: true}
}

func handleClear() ipc.Response {
	mu.Lock()
	defer mu.Unlock()
	messages = nil
	updateTitle()
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
	return ipc.Response{OK: true}
}

func sendSystemNotification(msg, source string) {
	if cfg == nil || !cfg.SystemNotifications {
		return
	}
	title := "mac-notify"
	if source != "" {
		title = source
	}
	script := fmt.Sprintf(`display notification %q with title %q`, msg, title)
	exec.Command("osascript", "-e", script).Start()
}

// updateTitle sets the menu bar title. Must be called with mu held.
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
					mu.Lock()
					for i, msg := range messages {
						if msg.ID == msgID {
							messages = slices.Delete(messages, i, i+1)
							break
						}
					}
					updateTitle()
					mu.Unlock()
				},
			})
		}
		items = append(items, menuet.MenuItem{Type: menuet.Separator})
		items = append(items, menuet.MenuItem{
			Text: "Clear All",
			Clicked: func() {
				mu.Lock()
				messages = nil
				updateTitle()
				mu.Unlock()
			},
		})
	}

	return items
}

func Run(c *config.Config) {
	cfg = c
	app := menuet.App()
	app.SetMenuState(&menuet.MenuState{Title: "🔔"})
	app.Children = menuItems
	app.Label = "com.nickhudkins.mac-notify"
	app.RunApplication()
}
