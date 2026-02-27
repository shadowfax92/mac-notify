package cmd

import (
	"fmt"
	"os"

	"github.com/nickhudkins/mac-notify/ipc"
	"github.com/spf13/cobra"
)

var statusCmd = &cobra.Command{
	Use:   "status",
	Short: "Check if the daemon is running",
	RunE: func(cmd *cobra.Command, args []string) error {
		resp, err := ipc.Send(ipc.Request{Action: "list"})
		if err != nil {
			fmt.Println("Daemon: not running")
			_, statErr := os.Stat(plistPath())
			if statErr == nil {
				fmt.Println("Plist:  installed")
			} else {
				fmt.Println("Plist:  not installed")
			}
			return nil
		}

		fmt.Println("Daemon: running")
		fmt.Printf("Messages: %d\n", len(resp.Messages))

		_, statErr := os.Stat(plistPath())
		if statErr == nil {
			fmt.Println("Plist:  installed")
		} else {
			fmt.Println("Plist:  not installed")
		}
		return nil
	},
}

func init() {
	rootCmd.AddCommand(statusCmd)
}
