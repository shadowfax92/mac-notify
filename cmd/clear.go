package cmd

import (
	"fmt"

	"github.com/nickhudkins/mac-notify/ipc"
	"github.com/nickhudkins/mac-notify/notificationcenter"
	"github.com/spf13/cobra"
)

var clearCmd = newClearCommand(ipc.Send, notificationcenter.Clear)

// The daemon owns its queue, blockers, and native notifications. Cross-app
// Accessibility stays in the CLI so TCC uses the terminal's stable identity,
// rather than the daemon's ad-hoc signature, which changes during installation.
func newClearCommand(send func(ipc.Request) (*ipc.Response, error), clearAll func() error) *cobra.Command {
	var all bool
	command := &cobra.Command{
		Use:         "clear",
		Aliases:     []string{"c"},
		Annotations: map[string]string{"group": "Messages:"},
		Short:       "Clear mac-notify notifications",
		RunE: func(cmd *cobra.Command, args []string) error {
			resp, err := send(ipc.Request{Action: "clear"})
			if err != nil {
				return err
			}
			if !resp.OK {
				return fmt.Errorf("%s", resp.Error)
			}
			if all {
				if err := clearAll(); err != nil {
					return fmt.Errorf("clear Notification Center: %w", err)
				}
			}
			return nil
		},
	}
	command.Flags().BoolVarP(&all, "all", "a", false, "Also clear every app's notifications shown in Notification Center (requires Accessibility)")
	return command
}

func init() {
	rootCmd.AddCommand(clearCmd)
}
