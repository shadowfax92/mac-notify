package cmd

import (
	"fmt"
	"os"

	"github.com/nickhudkins/mac-notify/config"
	"github.com/nickhudkins/mac-notify/ipc"
	"github.com/nickhudkins/mac-notify/menubar"
	"github.com/spf13/cobra"
)

var daemonCmd = &cobra.Command{
	Use:   "daemon",
	Short: "Start the menu bar notification daemon",
	RunE: func(cmd *cobra.Command, args []string) error {
		cfg, err := config.Load()
		if err != nil {
			return fmt.Errorf("load config: %w", err)
		}

		go func() {
			if err := ipc.ListenAndServe(menubar.HandleRequest); err != nil {
				fmt.Fprintf(os.Stderr, "ipc server error: %v\n", err)
				os.Exit(1)
			}
		}()

		menubar.Run(cfg)
		return nil
	},
}

func init() {
	rootCmd.AddCommand(daemonCmd)
}
