package config

import (
	"errors"
	"fmt"
	"os"
)

// Watcher observes one config path on one goroutine. Identity, size, mtime, and
// mode catch both in-place edits and rename saves; stat/load are testable seams.
type Watcher struct {
	path        string
	stat        func(string) (os.FileInfo, error)
	load        func(string) (*Config, error)
	last        os.FileInfo
	initialized bool
}

func NewWatcher(path string) *Watcher {
	return &Watcher{path: path, stat: os.Stat, load: LoadFrom}
}

func sameConfigFile(a, b os.FileInfo) bool {
	return a != nil && b != nil && os.SameFile(a, b) &&
		a.Size() == b.Size() && a.ModTime().Equal(b.ModTime()) && a.Mode() == b.Mode()
}

// Poll returns a new config only after a stable read. Missing files are ignored,
// and failed reads remain retryable even if their metadata never changes.
func (w *Watcher) Poll() (*Config, bool, error) {
	info, err := w.stat(w.path)
	if errors.Is(err, os.ErrNotExist) {
		return nil, false, nil
	}
	if err != nil {
		w.initialized = false
		return nil, false, fmt.Errorf("stat config: %w", err)
	}
	if w.initialized && sameConfigFile(w.last, info) {
		return nil, false, nil
	}
	cfg, loadErr := w.load(w.path)
	after, err := w.stat(w.path)
	if errors.Is(err, os.ErrNotExist) {
		return nil, false, nil
	}
	if err != nil {
		w.initialized = false
		return nil, false, fmt.Errorf("stat config after read: %w", err)
	}
	if !sameConfigFile(info, after) {
		// An editor raced the read: neither stale settings nor a transient parse
		// failure should reach users. Retry the new file on the next poll.
		return nil, false, nil
	}
	w.last, w.initialized = after, loadErr == nil
	if loadErr != nil {
		return nil, false, loadErr
	}
	return cfg, true, nil
}
