package main

import (
	"os"

	"github.com/nickhudkins/mac-notify/cmd"
)

func main() {
	if err := cmd.Execute(); err != nil {
		os.Exit(1)
	}
}
