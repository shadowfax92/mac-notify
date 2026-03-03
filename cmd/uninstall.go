package cmd

import (
	"fmt"
	"os"
	"os/exec"
	"strconv"

	"github.com/spf13/cobra"
)

var uninstallCmd = &cobra.Command{
	Use:         "uninstall",
	Annotations: map[string]string{"group": "Daemon:"},
	Short:       "Remove launchd service and stop daemon",
	RunE: func(cmd *cobra.Command, args []string) error {
		plist := plistPath()

		uid := strconv.Itoa(os.Getuid())
		_ = exec.Command("launchctl", "bootout", "gui/"+uid+"/"+plistLabel).Run()
		_ = exec.Command("launchctl", "unload", plist).Run()

		if err := os.Remove(plist); err != nil && !os.IsNotExist(err) {
			return fmt.Errorf("remove plist: %w", err)
		}

		fmt.Println("Uninstalled. Daemon stopped, plist removed.")
		return nil
	},
}

func init() {
	rootCmd.AddCommand(uninstallCmd)
}
