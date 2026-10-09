package menubar

import (
	"context"
	"sync"
	"time"

	"github.com/nickhudkins/mac-notify/config"
	"github.com/nickhudkins/mac-notify/ipc"
)

const configPollInterval = 2 * time.Second

// runtimeConfig owns the daemon's last valid policy and reload error, separately
// from the message queue. Each send takes one value snapshot for all its effects.
// Native setup completes before publishing enabled settings to IPC goroutines.
type runtimeConfig struct {
	mu                 sync.RWMutex
	current            config.Config
	configError        string
	notificationsReady bool
	setup              func()
	authorize          func()
	logf               func(string, ...any)
}

func newRuntimeConfig(setup, authorize func(), logf func(string, ...any)) *runtimeConfig {
	return &runtimeConfig{setup: setup, authorize: authorize, logf: logf}
}

func (r *runtimeConfig) apply(next *config.Config) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if next.SystemNotifications && !r.notificationsReady {
		r.setup()
		r.authorize()
		r.notificationsReady = true
	}
	// Keep our own value: a caller changing its config must not mutate a
	// published policy behind the readers' lock. The daemon never uses Send.
	r.current = *next
	r.current.Send = nil
	r.configError = ""
}

func (r *runtimeConfig) snapshot() config.Config {
	r.mu.RLock()
	defer r.mu.RUnlock()
	return r.current
}

func (r *runtimeConfig) status() *ipc.ConfigStatus {
	r.mu.RLock()
	defer r.mu.RUnlock()
	return &ipc.ConfigStatus{
		SystemNotifications:  r.current.SystemNotifications,
		OverlayNotifications: r.current.OverlayNotifications,
		MenuFlash:            r.current.MenuFlash,
		OverlayTimeout:       r.current.OverlayTimeout,
		Error:                r.configError,
	}
}

func (r *runtimeConfig) reload(watcher *config.Watcher) {
	// Filesystem I/O stays outside the state lock so an editor or slow read
	// cannot stall notification sends or status requests.
	next, changed, err := watcher.Poll()
	if err != nil {
		r.mu.Lock()
		if r.configError != err.Error() {
			r.logf("mac-notify config error: %v (keeping previous config)", err)
		}
		r.configError = err.Error()
		r.mu.Unlock()
		return
	}
	if changed {
		r.apply(next)
		r.logf("mac-notify config reloaded")
	}
}

func (r *runtimeConfig) watch(ctx context.Context, watcher *config.Watcher) {
	ticker := time.NewTicker(configPollInterval)
	defer ticker.Stop()
	// Re-read at handoff: a save between startup Load and the first stat must
	// not become an unnoticed baseline. Only this goroutine owns the watcher.
	r.reload(watcher)
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			r.reload(watcher)
		}
	}
}
