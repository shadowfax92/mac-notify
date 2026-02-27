package ipc

import (
	"encoding/json"
	"net"
	"os"
)

type Handler func(Request) Response

func ListenAndServe(handler Handler) error {
	os.Remove(SocketPath)

	ln, err := net.Listen("unix", SocketPath)
	if err != nil {
		return err
	}
	defer ln.Close()
	defer os.Remove(SocketPath)

	for {
		conn, err := ln.Accept()
		if err != nil {
			continue
		}
		go handleConn(conn, handler)
	}
}

func handleConn(conn net.Conn, handler Handler) {
	defer conn.Close()

	var req Request
	if err := json.NewDecoder(conn).Decode(&req); err != nil {
		resp := Response{OK: false, Error: "invalid request"}
		json.NewEncoder(conn).Encode(resp)
		return
	}

	resp := handler(req)
	json.NewEncoder(conn).Encode(resp)
}
