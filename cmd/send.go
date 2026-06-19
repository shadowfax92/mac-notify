package cmd

import (
	"fmt"
	"strings"

	"github.com/nickhudkins/mac-notify/config"
	"github.com/nickhudkins/mac-notify/ipc"
	"github.com/spf13/cobra"
)

var (
	sendSource  string
	sendID      string
	sendBlocker bool
)

var sendCmd = &cobra.Command{
	Use:         "send [message]",
	Aliases:     []string{"s"},
	Annotations: map[string]string{"group": "Messages:"},
	Short:       "Send a notification",
	Args:        cobra.MinimumNArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		cfg, err := config.Load()
		if err != nil {
			return fmt.Errorf("load config: %w", err)
		}

		req, err := resolveSendRequest(cfg, strings.Join(args, " "), sendSource, sendID)
		if err != nil {
			return err
		}
		req.Blocker = sendBlocker

		resp, err := ipc.Send(req)
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
	sendCmd.Flags().BoolVar(&sendBlocker, "blocker", false, "Show a persistent red-glow overlay on the right edge until dismissed with ×")
	rootCmd.AddCommand(sendCmd)
}
