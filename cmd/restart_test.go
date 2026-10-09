package cmd

import (
	"errors"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

func TestRestartReportsUninstalledService(t *testing.T) {
	called := false
	err := restartService(filepath.Join(t.TempDir(), "missing.plist"), 501, func(...string) ([]byte, error) {
		called = true
		return nil, nil
	})
	if err == nil || !strings.Contains(err.Error(), "not installed") || called {
		t.Fatalf("restart = error %v, launchctl called %v", err, called)
	}
}

func TestRestartUsesLaunchdServiceTarget(t *testing.T) {
	plist := filepath.Join(t.TempDir(), "daemon.plist")
	if err := os.WriteFile(plist, []byte("fixture"), 0600); err != nil {
		t.Fatal(err)
	}
	var args []string
	err := restartService(plist, 501, func(command ...string) ([]byte, error) {
		args = command
		return nil, nil
	})
	if err != nil || !reflect.DeepEqual(args, []string{"kickstart", "-k", "gui/501/com.mac-notify.daemon"}) {
		t.Fatalf("restart = args %v, error %v", args, err)
	}
}

func TestRestartSurfacesUnloadedServiceError(t *testing.T) {
	plist := filepath.Join(t.TempDir(), "daemon.plist")
	if err := os.WriteFile(plist, []byte("fixture"), 0600); err != nil {
		t.Fatal(err)
	}
	launchErr := errors.New("exit status 113")
	err := restartService(plist, 501, func(...string) ([]byte, error) {
		return []byte("Could not find service com.mac-notify.daemon"), launchErr
	})
	if !errors.Is(err, launchErr) || !strings.Contains(err.Error(), "Could not find service") ||
		!strings.Contains(err.Error(), "installed and loaded") {
		t.Fatalf("restart hid launchctl diagnostics: %v", err)
	}
}
