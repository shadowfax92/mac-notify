package cmd

import (
	"fmt"
	"os"

	"github.com/nickhudkins/mac-notify/ipc"
	"github.com/spf13/cobra"
)

var statusCmd = &cobra.Command{
	Use:         "status",
	Annotations: map[string]string{"group": "Daemon:"},
	Short:       "Check if the daemon is running",
	RunE: func(cmd *cobra.Command, args []string) error {
		// Report the daemon's accepted policy even if the file is now invalid;
		// loading YAML here would hide exactly the reload error users need.
		resp, err := ipc.Send(ipc.Request{Action: "status"})
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
		if !resp.OK {
			return fmt.Errorf("daemon status: %s", resp.Error)
		}

		fmt.Println("Daemon: running")
		fmt.Printf("Messages: %d\n", len(resp.Messages))
		if resp.Config != nil {
			if resp.Config.Error != "" {
				fmt.Printf("Config: error: %s (keeping previous config)\n", resp.Config.Error)
			} else {
				fmt.Println("Config: loaded (reloads every ~2s)")
			}
			fmt.Printf("  system_notifications: %t\n  overlay_notifications: %t\n  menu_flash: %t\n  overlay_timeout: %g\n",
				resp.Config.SystemNotifications, resp.Config.OverlayNotifications,
				resp.Config.MenuFlash, resp.Config.OverlayTimeout)
		}

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
