package config

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestLoadFromMissingFileDoesNotWrite(t *testing.T) {
	path := filepath.Join(t.TempDir(), "missing", "config.yaml")
	if _, err := LoadFrom(path); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("LoadFrom() error = %v, want missing file", err)
	}
	if _, err := os.Stat(filepath.Dir(path)); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("reload created a directory: %v", err)
	}
}

func TestLoadPreservesExistingCommentsAndDefaults(t *testing.T) {
	t.Setenv("HOME", t.TempDir())
	if err := os.MkdirAll(Dir(), 0700); err != nil {
		t.Fatal(err)
	}
	content := "# owner's settings\nmenu_flash: false\nsend:\n  source: '$DIR_NAME' # keep this\n"
	writeConfig(t, Path(), content)
	cfg, err := Load()
	if err != nil || cfg.MenuFlash || !cfg.OverlayNotifications || cfg.OverlayTimeout != 5 || cfg.Send.Source != "$DIR_NAME" {
		t.Fatalf("Load() = %v, error %v", cfg, err)
	}
	data, err := os.ReadFile(Path())
	if err != nil || string(data) != content {
		t.Fatalf("Load rewrote config: %q, error %v", data, err)
	}
}

func TestLoadCreatesStartupDefaults(t *testing.T) {
	t.Setenv("HOME", t.TempDir())
	cfg, err := Load()
	if err != nil || !cfg.SystemNotifications || cfg.OverlayTimeout != 5 {
		t.Fatalf("startup Load() = %v, error %v", cfg, err)
	}
	if _, err := os.Stat(Path()); err != nil {
		t.Fatalf("startup defaults missing: %v", err)
	}
}

func TestLoadFromRejectsBrokenSettings(t *testing.T) {
	for name, content := range map[string]string{
		"yaml":     "menu_flash: [\n",
		"boolean":  "menu_flash: definitely\n",
		"timeout":  "overlay_timeout: forever\n",
		"nan":      "overlay_timeout: .nan\n",
		"infinity": "overlay_timeout: .inf\n",
	} {
		t.Run(name, func(t *testing.T) {
			path := filepath.Join(t.TempDir(), "config.yaml")
			writeConfig(t, path, content)
			if _, err := LoadFrom(path); err == nil {
				t.Fatal("LoadFrom accepted broken settings")
			}
		})
	}
}

func TestLoadFromKeepsNonpositiveTimeoutFallback(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.yaml")
	writeConfig(t, path, "overlay_timeout: -1\n")
	cfg, err := LoadFrom(path)
	if err != nil || cfg.OverlayTimeout != -1 {
		t.Fatalf("LoadFrom() = %v, error %v; preserve the existing display fallback", cfg, err)
	}
}

func TestLoadFromReturnsPathErrors(t *testing.T) {
	_, err := LoadFrom(t.TempDir())
	if err == nil || !strings.Contains(err.Error(), "directory") {
		t.Fatalf("LoadFrom(directory) error = %v", err)
	}
}
