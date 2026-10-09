package notificationcenter

import (
	"errors"
	"strings"
	"testing"
)

func TestPermissionDenialNamesTheTerminalAndSettingsPath(t *testing.T) {
	err := clearWithBackend(func() clearResult {
		return clearResult{permissionDenied: true}
	}, func() string { return "Ghostty" })
	want := "Accessibility permission is required: enable System Settings → Privacy & Security → Accessibility → Ghostty, then retry mac-notify clear --all"
	if err == nil || err.Error() != want {
		t.Fatalf("error = %v, want %q", err, want)
	}
}

func TestUnknownLauncherUsesTheSystemPermissionPrompt(t *testing.T) {
	err := clearWithBackend(func() clearResult {
		return clearResult{permissionDenied: true}
	}, func() string { return "" })
	if err == nil || !strings.Contains(err.Error(), "Accessibility → the terminal or launcher named in the macOS permission prompt") {
		t.Fatalf("error = %v, want guidance to the app named by macOS", err)
	}
}

func TestNativeFailureIsReturnedWithoutPermissionGuidance(t *testing.T) {
	failure := errors.New("Notification Center did not open")
	err := clearWithBackend(func() clearResult {
		return clearResult{err: failure}
	}, func() string {
		t.Fatal("terminal identity requested for a UI error")
		return ""
	})
	if !errors.Is(err, failure) {
		t.Fatalf("error = %v, want %v", err, failure)
	}
}
