package menubar

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"

	"github.com/nickhudkins/mac-notify/config"
	"github.com/nickhudkins/mac-notify/ipc"
)

func TestSystemNotificationsEnableInitializesOnce(t *testing.T) {
	var setups, authorizations int
	runtime := newRuntimeConfig(func() { setups++ }, func() { authorizations++ }, func(string, ...any) {})
	cfg := config.Default()
	cfg.SystemNotifications = false
	runtime.apply(cfg)
	if setups != 0 || authorizations != 0 {
		t.Fatal("disabled startup initialized native notifications")
	}
	cfg.SystemNotifications = true
	runtime.apply(cfg)
	if setups != 1 || authorizations != 1 || !runtime.snapshot().SystemNotifications {
		t.Fatalf("enable = setup %d, auth %d, config %v", setups, authorizations, runtime.snapshot())
	}
	cfg.SystemNotifications = false
	runtime.apply(cfg)
	cfg.SystemNotifications = true
	runtime.apply(cfg)
	if setups != 1 || authorizations != 1 {
		t.Fatalf("re-enable repeated setup: setup %d, auth %d", setups, authorizations)
	}
}

func writeRuntimeConfig(t *testing.T, path, content string) {
	t.Helper()
	if err := os.WriteFile(path, []byte(content), 0600); err != nil {
		t.Fatal(err)
	}
}

func TestRuntimeReloadKeepsInvalidEditAndSurfacesErrorOnce(t *testing.T) {
	var logs []string
	runtime := newRuntimeConfig(func() {}, func() {}, func(format string, args ...any) {
		logs = append(logs, fmt.Sprintf(format, args...))
	})
	path := filepath.Join(t.TempDir(), "config.yaml")
	watcher := config.NewWatcher(path)
	writeRuntimeConfig(t, path, "system_notifications: false\nmenu_flash: false\noverlay_timeout: 7\n")
	runtime.reload(watcher)
	writeRuntimeConfig(t, path, "menu_flash: [\n")
	runtime.reload(watcher)
	runtime.reload(watcher)
	status := runtime.status()
	if status.Error == "" || status.MenuFlash || status.OverlayTimeout != 7 {
		t.Fatalf("rejected edit status = %+v", status)
	}
	if len(logs) != 2 || !strings.Contains(logs[1], "keeping previous config") {
		t.Fatalf("reload did not log once per error transition: %v", logs)
	}
	// A valid save recovers without restarting and clears the old error.
	writeRuntimeConfig(t, path, "system_notifications: false\nmenu_flash: true\noverlay_timeout: 3\n")
	runtime.reload(watcher)
	status = runtime.status()
	if status.Error != "" || !status.MenuFlash || status.OverlayTimeout != 3 {
		t.Fatalf("recovered status = %+v", status)
	}
	writeRuntimeConfig(t, path, "menu_flash: [\n")
	runtime.reload(watcher)
	if len(logs) != 4 {
		t.Fatalf("new error transition was not logged: %v", logs)
	}
}

func TestRuntimeReloadMissingKeepsPolicyWithoutWriting(t *testing.T) {
	runtime := newRuntimeConfig(func() {}, func() {}, func(string, ...any) {})
	cfg := config.Default()
	cfg.MenuFlash = false
	runtime.apply(cfg)
	path := filepath.Join(t.TempDir(), "missing.yaml")
	runtime.reload(config.NewWatcher(path))
	if runtime.snapshot().MenuFlash || runtime.status().Error != "" {
		t.Fatalf("missing file changed runtime state: %+v", runtime.status())
	}
	if _, err := os.Stat(path); !os.IsNotExist(err) {
		t.Fatalf("reload wrote the missing file: %v", err)
	}
}

func TestRuntimeFirstPollClosesStartupSaveGap(t *testing.T) {
	runtime := newRuntimeConfig(func() {}, func() {}, func(string, ...any) {})
	cfg := config.Default()
	cfg.MenuFlash = false
	runtime.apply(cfg)
	path := filepath.Join(t.TempDir(), "config.yaml")
	writeRuntimeConfig(t, path, "menu_flash: true\noverlay_timeout: 8\n")
	runtime.reload(config.NewWatcher(path))
	if !runtime.snapshot().MenuFlash || runtime.snapshot().OverlayTimeout != 8 {
		t.Fatalf("first poll skipped save after startup: %+v", runtime.status())
	}
}

func TestRuntimeOwnsPublishedConfigValue(t *testing.T) {
	runtime := newRuntimeConfig(func() {}, func() {}, func(string, ...any) {})
	cfg := config.Default()
	runtime.apply(cfg)
	cfg.MenuFlash = false
	if !runtime.snapshot().MenuFlash {
		t.Fatal("caller mutated an already published policy")
	}
}

func TestRuntimeConcurrentPublicationAndReaders(t *testing.T) {
	var setups, authorizations int
	runtime := newRuntimeConfig(func() { setups++ }, func() { authorizations++ }, func(string, ...any) {})
	runtime.apply(&config.Config{OverlayTimeout: 1})
	var wg sync.WaitGroup
	for worker := 0; worker < 8; worker++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for iteration := 0; iteration < 300; iteration++ {
				enabled := iteration%2 == 0
				timeout := float64(1)
				if enabled {
					timeout = 2
				}
				runtime.apply(&config.Config{
					SystemNotifications: enabled, OverlayNotifications: enabled,
					MenuFlash: enabled, OverlayTimeout: timeout,
				})
				cfg := runtime.snapshot()
				if cfg.SystemNotifications != cfg.MenuFlash || cfg.OverlayNotifications != cfg.MenuFlash ||
					(cfg.MenuFlash && cfg.OverlayTimeout != 2) || (!cfg.MenuFlash && cfg.OverlayTimeout != 1) {
					t.Errorf("reader saw mixed config versions: %+v", cfg)
					return
				}
				_ = runtime.status()
			}
		}()
	}
	wg.Wait()
	if setups != 1 || authorizations != 1 {
		t.Fatalf("concurrent enable setup = %d, auth = %d", setups, authorizations)
	}
}

func TestReloadErrorIsExposedThroughStatusIPC(t *testing.T) {
	original := liveConfig
	t.Cleanup(func() { liveConfig = original })
	liveConfig = newRuntimeConfig(func() {}, func() {}, func(string, ...any) {})
	cfg := config.Default()
	cfg.MenuFlash = false
	liveConfig.apply(cfg)
	path := filepath.Join(t.TempDir(), "config.yaml")
	writeRuntimeConfig(t, path, "overlay_timeout: forever\n")
	liveConfig.reload(config.NewWatcher(path))
	resp := HandleRequest(ipc.Request{Action: "status"})
	if !resp.OK || resp.Config == nil || resp.Config.Error == "" || resp.Config.MenuFlash {
		t.Fatalf("status IPC lost active settings or reload error: %+v", resp)
	}
}

func TestConfigWatcherStopsWithApplicationContext(t *testing.T) {
	runtime := newRuntimeConfig(func() {}, func() {}, func(string, ...any) {})
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	runtime.watch(ctx, config.NewWatcher(filepath.Join(t.TempDir(), "missing.yaml")))
}
