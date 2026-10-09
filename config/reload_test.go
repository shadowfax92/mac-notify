package config

import (
	"errors"
	"os"
	"path/filepath"
	"testing"
)

func writeConfig(t *testing.T, path, data string) {
	t.Helper()
	if err := os.WriteFile(path, []byte(data), 0600); err != nil {
		t.Fatal(err)
	}
}

func TestWatcherDetectsRenameWithIdenticalMetadata(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.yaml")
	writeConfig(t, path, "menu_flash: true \n")
	watcher := NewWatcher(path)
	if _, _, err := watcher.Poll(); err != nil {
		t.Fatal(err)
	}
	before, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	next := path + ".next"
	writeConfig(t, next, "menu_flash: false\n")
	if err := os.Chtimes(next, before.ModTime(), before.ModTime()); err != nil {
		t.Fatal(err)
	}
	if err := os.Rename(next, path); err != nil {
		t.Fatal(err)
	}
	after, err := os.Stat(path)
	if err != nil || before.Size() != after.Size() || !before.ModTime().Equal(after.ModTime()) || before.Mode() != after.Mode() {
		t.Fatalf("rename fixture metadata changed: %v", err)
	}
	cfg, changed, err := watcher.Poll()
	if err != nil || !changed || cfg.MenuFlash {
		t.Fatalf("renamed Poll() = %v, changed %v, error %v", cfg, changed, err)
	}
}

func TestWatcherIgnoresMissingFileWithoutWriting(t *testing.T) {
	path := filepath.Join(t.TempDir(), "missing", "config.yaml")
	watcher := NewWatcher(path)
	if _, changed, err := watcher.Poll(); err != nil || changed {
		t.Fatalf("missing Poll() = changed %v, error %v", changed, err)
	}
	if _, err := os.Stat(filepath.Dir(path)); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("watcher created missing parent: %v", err)
	}
}

func TestWatcherKeepsDeletedFileMissingAndDetectsReturn(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.yaml")
	writeConfig(t, path, "menu_flash: true\n")
	watcher := NewWatcher(path)
	if _, _, err := watcher.Poll(); err != nil {
		t.Fatal(err)
	}
	if err := os.Remove(path); err != nil {
		t.Fatal(err)
	}
	if _, changed, err := watcher.Poll(); err != nil || changed {
		t.Fatalf("deleted Poll() = changed %v, error %v", changed, err)
	}
	if _, err := os.Stat(path); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("watcher replaced deleted file: %v", err)
	}
	writeConfig(t, path, "menu_flash: false\n")
	cfg, changed, err := watcher.Poll()
	if err != nil || !changed || cfg.MenuFlash {
		t.Fatalf("restored Poll() = %v, changed %v, error %v", cfg, changed, err)
	}
}

func TestWatcherDiscardsSavesRacingRead(t *testing.T) {
	for _, content := range []string{"menu_flash: true\n", "menu_flash: [\n"} {
		t.Run(content, func(t *testing.T) {
			path := filepath.Join(t.TempDir(), "config.yaml")
			writeConfig(t, path, content)
			watcher := NewWatcher(path)
			watcher.load = func(path string) (*Config, error) {
				cfg, err := LoadFrom(path)
				writeConfig(t, path+".next", "menu_flash: false\n")
				if err := os.Rename(path+".next", path); err != nil {
					t.Fatal(err)
				}
				return cfg, err
			}
			if _, changed, err := watcher.Poll(); err != nil || changed {
				t.Fatalf("raced Poll() = changed %v, error %v", changed, err)
			}
			watcher.load = LoadFrom
			cfg, changed, err := watcher.Poll()
			if err != nil || !changed || cfg.MenuFlash {
				t.Fatalf("retry Poll() = %v, changed %v, error %v", cfg, changed, err)
			}
		})
	}
}

func TestWatcherDiscardsFileRemovedDuringRead(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.yaml")
	writeConfig(t, path, "menu_flash: true\n")
	watcher := NewWatcher(path)
	watcher.load = func(path string) (*Config, error) {
		cfg, err := LoadFrom(path)
		if err := os.Remove(path); err != nil {
			t.Fatal(err)
		}
		return cfg, err
	}
	if _, changed, err := watcher.Poll(); err != nil || changed {
		t.Fatalf("removed-during-read Poll() = changed %v, error %v", changed, err)
	}
}

func TestWatcherRetriesTransientReadFailureWithoutEdit(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.yaml")
	writeConfig(t, path, "menu_flash: false\n")
	watcher := NewWatcher(path)
	watcher.load = func(string) (*Config, error) { return nil, os.ErrPermission }
	if _, changed, err := watcher.Poll(); !errors.Is(err, os.ErrPermission) || changed {
		t.Fatalf("failed Poll() = changed %v, error %v", changed, err)
	}
	watcher.load = LoadFrom
	cfg, changed, err := watcher.Poll()
	if err != nil || !changed || cfg.MenuFlash {
		t.Fatalf("recovered Poll() = %v, changed %v, error %v", cfg, changed, err)
	}
}

func TestWatcherDetectsModeChange(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.yaml")
	writeConfig(t, path, "menu_flash: false\n")
	watcher := NewWatcher(path)
	if _, _, err := watcher.Poll(); err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(path, 0400); err != nil {
		t.Fatal(err)
	}
	if _, changed, err := watcher.Poll(); err != nil || !changed {
		t.Fatalf("mode-change Poll() = changed %v, error %v", changed, err)
	}
}

func TestWatcherAppliesValidEdit(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.yaml")
	writeConfig(t, path, "menu_flash: true\n")
	watcher := NewWatcher(path)
	if _, changed, err := watcher.Poll(); err != nil || !changed {
		t.Fatalf("initial Poll() = changed %v, error %v", changed, err)
	}
	writeConfig(t, path, "menu_flash: false\noverlay_timeout: 9\n")
	cfg, changed, err := watcher.Poll()
	if err != nil || !changed || cfg.MenuFlash || cfg.OverlayTimeout != 9 {
		t.Fatalf("edited Poll() = %v, changed %v, error %v", cfg, changed, err)
	}
	if _, changed, err := watcher.Poll(); err != nil || changed {
		t.Fatalf("unchanged Poll() = changed %v, error %v", changed, err)
	}
}
