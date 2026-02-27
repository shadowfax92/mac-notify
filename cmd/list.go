package cmd

import (
	"fmt"

	"github.com/nickhudkins/mac-notify/ipc"
	"github.com/spf13/cobra"
)

var listCmd = &cobra.Command{
	Use:   "list",
	Short: "List current notifications",
	RunE: func(cmd *cobra.Command, args []string) error {
		resp, err := ipc.Send(ipc.Request{Action: "list"})
		if err != nil {
			return err
		}
		if !resp.OK {
			return fmt.Errorf("%s", resp.Error)
		}
		if len(resp.Messages) == 0 {
			fmt.Println("No notifications")
			return nil
		}
		for _, m := range resp.Messages {
			line := m.Text
			if m.Source != "" {
				line = fmt.Sprintf("[%s] %s", m.Source, m.Text)
			}
			if m.ID != "" {
				line = fmt.Sprintf("%s  (id: %s)", line, m.ID)
			}
			fmt.Println(line)
		}
		return nil
	},
}

func init() {
	rootCmd.AddCommand(listCmd)
}
