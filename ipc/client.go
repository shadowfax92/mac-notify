package ipc

import (
	"encoding/json"
	"fmt"
	"net"
	"time"
)

func Send(req Request) (*Response, error) {
	conn, err := net.Dial("unix", SocketPath)
	if err != nil {
		return nil, fmt.Errorf("daemon not running (start with: mac-notify daemon)")
	}
	defer conn.Close()
	conn.SetDeadline(time.Now().Add(5 * time.Second))

	if err := json.NewEncoder(conn).Encode(req); err != nil {
		return nil, fmt.Errorf("failed to send request: %w", err)
	}

	var resp Response
	if err := json.NewDecoder(conn).Decode(&resp); err != nil {
		return nil, fmt.Errorf("failed to read response: %w", err)
	}
	return &resp, nil
}
