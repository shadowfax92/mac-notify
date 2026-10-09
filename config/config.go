package config

import (
	"fmt"
	"math"
	"os"
	"path/filepath"

	"gopkg.in/yaml.v3"
)

// Config holds startup defaults and the user's notification policy. Daemon
// reloads publish a whole value; send formatting is still loaded by each CLI send.
type Config struct {
	SystemNotifications  bool        `yaml:"system_notifications"`
	OverlayNotifications bool        `yaml:"overlay_notifications"`
	MenuFlash            bool        `yaml:"menu_flash"`
	OverlayTimeout       float64     `yaml:"overlay_timeout"`
	Send                 *SendConfig `yaml:"send,omitempty"`
}

type SendConfig struct {
	Message        string `yaml:"message,omitempty"`
	Source         string `yaml:"source,omitempty"`
	ID             string `yaml:"id,omitempty"`
	ContextCommand string `yaml:"context_command,omitempty"`
}

func Default() *Config {
	return &Config{
		SystemNotifications:  true,
		OverlayNotifications: true,
		MenuFlash:            true,
		OverlayTimeout:       5,
	}
}

func Dir() string {
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".config", "mac-notify")
}

func Path() string {
	return filepath.Join(Dir(), "config.yaml")
}

func Load() (*Config, error) {
	cfg, err := LoadFrom(Path())
	if err != nil {
		if os.IsNotExist(err) {
			cfg = Default()
			if err := Save(cfg); err != nil {
				return nil, fmt.Errorf("creating default config: %w", err)
			}
			return cfg, nil
		}
		return nil, err
	}
	return cfg, nil
}

// LoadFrom only reads: an editor may temporarily remove the path while saving.
// Only startup Load may create defaults; a reload must never replace a user's file.
func LoadFrom(path string) (*Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	cfg := Default()

	if err := yaml.Unmarshal(data, cfg); err != nil {
		return nil, fmt.Errorf("parsing config: %w", err)
	}
	// YAML accepts NaN/Inf, but neither JSON status nor native timer deadlines
	// can represent them. Nonpositive finite values keep the existing fallback.
	if math.IsNaN(cfg.OverlayTimeout) || math.IsInf(cfg.OverlayTimeout, 0) {
		return nil, fmt.Errorf("overlay_timeout must be a finite number")
	}
	return cfg, nil
}

func Save(cfg *Config) error {
	if err := os.MkdirAll(Dir(), 0755); err != nil {
		return err
	}
	data, err := yaml.Marshal(cfg)
	if err != nil {
		return err
	}
	tmp := Path() + ".tmp"
	if err := os.WriteFile(tmp, data, 0644); err != nil {
		return err
	}
	return os.Rename(tmp, Path())
}
