package config

import (
	"fmt"
	"os"
	"path/filepath"

	"gopkg.in/yaml.v3"
)

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
	cfg := Default()

	data, err := os.ReadFile(Path())
	if err != nil {
		if os.IsNotExist(err) {
			if err := Save(cfg); err != nil {
				return nil, fmt.Errorf("creating default config: %w", err)
			}
			return cfg, nil
		}
		return nil, err
	}

	if err := yaml.Unmarshal(data, cfg); err != nil {
		return nil, fmt.Errorf("parsing config: %w", err)
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
