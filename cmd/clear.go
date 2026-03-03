package cmd

import (
	"fmt"

	"github.com/nickhudkins/mac-notify/ipc"
	"github.com/spf13/cobra"
)

var clearCmd = &cobra.Command{
	Use:         "clear",
	Aliases:     []string{"c"},
	Annotations: map[string]string{"group": "Messages:"},
	Short:       "Clear all notifications",
	RunE: func(cmd *cobra.Command, args []string) error {
		resp, err := ipc.Send(ipc.Request{Action: "clear"})
		if err != nil {
			return err
		}
		if !resp.OK {
			return fmt.Errorf("%s", resp.Error)
		}
		return nil
	},
}

func init() {
	rootCmd.AddCommand(clearCmd)
}
