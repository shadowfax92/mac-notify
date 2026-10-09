package ipc

import (
	"os"
	"path/filepath"
	"time"
)

var SocketPath = filepath.Join(os.Getenv("HOME"), ".mac-notify.sock")

type Message struct {
	ID     string    `json:"id"`
	Text   string    `json:"message"`
	Source string    `json:"source,omitempty"`
	Time   time.Time `json:"time"`
}

type Request struct {
	Action  string `json:"action"`
	Message string `json:"message,omitempty"`
	Source  string `json:"source,omitempty"`
	ID      string `json:"id,omitempty"`
	Blocker bool   `json:"blocker,omitempty"`
}

type Response struct {
	OK       bool          `json:"ok"`
	Error    string        `json:"error,omitempty"`
	Messages []Message     `json:"messages,omitempty"`
	Config   *ConfigStatus `json:"config,omitempty"`
}

// ConfigStatus describes the daemon's active policy, not the current file. A
// rejected edit remains visible in Error while notifications use these settings.
type ConfigStatus struct {
	SystemNotifications  bool    `json:"system_notifications"`
	OverlayNotifications bool    `json:"overlay_notifications"`
	MenuFlash            bool    `json:"menu_flash"`
	OverlayTimeout       float64 `json:"overlay_timeout"`
	Error                string  `json:"error,omitempty"`
}
