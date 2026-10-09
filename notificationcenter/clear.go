// Package notificationcenter clears other apps' visible notifications through
// the public macOS Accessibility API, in the calling CLI process.
package notificationcenter

import "fmt"

// Clear dismisses everything Notification Center exposes, preserving whether
// its panel was open. It requires Accessibility permission for the CLI's launcher.
func Clear() error {
	return clearWithBackend(nativeClear, nativeTerminalApplication)
}

// clearResult separates a TCC denial from UI failures so the permission guidance
// can be tested without prompting the user or manipulating their desktop.
type clearResult struct {
	permissionDenied bool
	err              error
}

func clearWithBackend(clear func() clearResult, terminal func() string) error {
	result := clear()
	if result.permissionDenied {
		app := terminal()
		if app == "" {
			app = "the terminal or launcher named in the macOS permission prompt"
		}
		return fmt.Errorf("Accessibility permission is required: enable System Settings → Privacy & Security → Accessibility → %s, then retry mac-notify clear --all", app)
	}
	return result.err
}
