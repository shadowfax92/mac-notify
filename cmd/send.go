package cmd

import (
	"fmt"
	"strings"

	"github.com/nickhudkins/mac-notify/ipc"
	"github.com/spf13/cobra"
)

var (
	sendSource string
	sendID     string
)

var sendCmd = &cobra.Command{
	Use:         "send [message]",
	Aliases:     []string{"s"},
	Annotations: map[string]string{"group": "Messages:"},
	Short:       "Send a notification",
	Args:        cobra.MinimumNArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		msg := strings.Join(args, " ")
		resp, err := ipc.Send(ipc.Request{
			Action:  "send",
			Message: msg,
			Source:  sendSource,
			ID:      sendID,
		})
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
	sendCmd.Flags().StringVar(&sendSource, "source", "", "Source/origin of the notification (e.g. ci, build)")
	sendCmd.Flags().StringVar(&sendID, "id", "", "Message ID for upsert (replaces existing message with same ID)")
	rootCmd.AddCommand(sendCmd)
}
