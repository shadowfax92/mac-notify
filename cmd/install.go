package cmd

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"text/template"

	"github.com/spf13/cobra"
)

const plistLabel = "com.mac-notify.daemon"

const plistTemplate = `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.mac-notify.daemon</string>
    <key>ProgramArguments</key>
    <array>
        <string>{{.BinaryPath}}</string>
        <string>daemon</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>{{.LogPath}}</string>
    <key>StandardErrorPath</key>
    <string>{{.LogPath}}</string>
</dict>
</plist>
`

func plistPath() string {
	home, _ := os.UserHomeDir()
	return filepath.Join(home, "Library", "LaunchAgents", plistLabel+".plist")
}

func logPath() string {
	home, _ := os.UserHomeDir()
	return filepath.Join(home, "Library", "Logs", "mac-notify.log")
}

var installCmd = &cobra.Command{
	Use:   "install",
	Short: "Install launchd service for auto-start on login",
	RunE: func(cmd *cobra.Command, args []string) error {
		exe, err := os.Executable()
		if err != nil {
			return fmt.Errorf("cannot determine binary path: %w", err)
		}
		exe, err = filepath.EvalSymlinks(exe)
		if err != nil {
			return fmt.Errorf("resolve symlinks: %w", err)
		}

		plist := plistPath()
		if err := os.MkdirAll(filepath.Dir(plist), 0755); err != nil {
			return err
		}

		tmpl, err := template.New("plist").Parse(plistTemplate)
		if err != nil {
			return err
		}

		f, err := os.Create(plist)
		if err != nil {
			return err
		}
		defer f.Close()

		if err := tmpl.Execute(f, struct {
			BinaryPath string
			LogPath    string
		}{
			BinaryPath: exe,
			LogPath:    logPath(),
		}); err != nil {
			return err
		}

		uid := strconv.Itoa(os.Getuid())
		if err := exec.Command("launchctl", "bootstrap", "gui/"+uid, plist).Run(); err != nil {
			if err2 := exec.Command("launchctl", "load", plist).Run(); err2 != nil {
				return fmt.Errorf("launchctl load failed: %w", err2)
			}
		}

		fmt.Println("Installed and started.")
		fmt.Printf("  Plist: %s\n", plist)
		fmt.Printf("  Log:   %s\n", logPath())
		return nil
	},
}

func init() {
	rootCmd.AddCommand(installCmd)
}
