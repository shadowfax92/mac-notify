package ipc

import (
	"os"
	"path/filepath"
	"time"
)

var SocketPath = filepath.Join(os.Getenv("HOME"), ".mac-notify.sock")

type Message struct {
	ID      string    `json:"id"`
	Text    string    `json:"message"`
	Source  string    `json:"source,omitempty"`
	Time    time.Time `json:"time"`
}

type Request struct {
	Action  string `json:"action"`
	Message string `json:"message,omitempty"`
	Source  string `json:"source,omitempty"`
	ID      string `json:"id,omitempty"`
}

type Response struct {
	OK       bool      `json:"ok"`
	Error    string    `json:"error,omitempty"`
	Messages []Message `json:"messages,omitempty"`
}
