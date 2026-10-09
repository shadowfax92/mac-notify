package cmd

import (
	"fmt"
	"os"
	"os/exec"
	"strconv"
	"strings"

	"github.com/spf13/cobra"
)

var restartCmd = &cobra.Command{
	Use:         "restart",
	Annotations: map[string]string{"group": "Daemon:"},
	Short:       "Restart the installed launchd daemon",
	Args:        cobra.NoArgs,
	RunE: func(cmd *cobra.Command, args []string) error {
		err := restartService(plistPath(), os.Getuid(), func(args ...string) ([]byte, error) {
			return exec.CommandContext(cmd.Context(), "launchctl", args...).CombinedOutput()
		})
		if err != nil {
			return err
		}
		fmt.Fprintln(cmd.OutOrStdout(), "Daemon restarted.")
		return nil
	},
}

// restartService addresses launchd's service rather than killing an arbitrary
// foreground daemon. The command boundary is injectable so tests never restart
// the user's installed service, even when a fixture plist exists.
func restartService(plist string, uid int, run func(...string) ([]byte, error)) error {
	if _, err := os.Stat(plist); err != nil {
		if os.IsNotExist(err) {
			return fmt.Errorf("launchd service is not installed; run mac-notify install (or make install)")
		}
		return fmt.Errorf("check launchd service: %w", err)
	}
	target := "gui/" + strconv.Itoa(uid) + "/" + plistLabel
	output, err := run("kickstart", "-k", target)
	if err != nil {
		return fmt.Errorf("restart %s: %w: %s; check that the service is installed and loaded with mac-notify install",
			target, err, strings.TrimSpace(string(output)))
	}
	return nil
}

func init() {
	rootCmd.AddCommand(restartCmd)
}
