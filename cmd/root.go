package cmd

import (
	"github.com/spf13/cobra"
)

var rootCmd = &cobra.Command{
	Use:          "mac-notify",
	Short:        "macOS menu bar notification queue",
	Long:         "A CLI that displays notification messages in the macOS menu bar.\nRun 'mac-notify daemon' to start, then send messages with 'mac-notify send'.",
	SilenceUsage: true,
}

func Execute() error {
	return rootCmd.Execute()
}
