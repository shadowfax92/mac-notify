package cmd

import (
	"fmt"
	"os"
	"os/exec"

	"github.com/nickhudkins/mac-notify/config"
	"github.com/spf13/cobra"
)

var configCmd = &cobra.Command{
	Use:   "config",
	Short: "Open config file in default editor",
	RunE: func(cmd *cobra.Command, args []string) error {
		cfg := config.Path()
		if _, err := os.Stat(cfg); os.IsNotExist(err) {
			if _, err := config.Load(); err != nil {
				return err
			}
		}

		editor := os.Getenv("EDITOR")
		if editor == "" {
			editor = "open"
		}

		c := exec.Command(editor, cfg)
		c.Stdin = os.Stdin
		c.Stdout = os.Stdout
		c.Stderr = os.Stderr
		if err := c.Run(); err != nil {
			return fmt.Errorf("editor failed: %w", err)
		}
		return nil
	},
}

func init() {
	rootCmd.AddCommand(configCmd)
}
