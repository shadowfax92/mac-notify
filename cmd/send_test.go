package cmd

import (
	"strings"
	"testing"

	"github.com/nickhudkins/mac-notify/config"
)

func TestResolveSendRequestKeepsLegacyBehaviorWithoutSendConfig(t *testing.T) {
	runtime := sendRuntime{
		env: map[string]string{"USER": "shadowfax"},
		cwd: "/tmp/project",
	}

	req, err := resolveSendRequestWithRuntime(config.Default(), runtime, "deploy finished", "ci", "deploy")
	if err != nil {
		t.Fatalf("resolveSendRequestWithRuntime() error = %v", err)
	}
	if req.Message != "deploy finished" {
		t.Fatalf("Message = %q, want %q", req.Message, "deploy finished")
	}
	if req.Source != "ci" {
		t.Fatalf("Source = %q, want %q", req.Source, "ci")
	}
	if req.ID != "deploy" {
		t.Fatalf("ID = %q, want %q", req.ID, "deploy")
	}
}

func TestResolveSendRequestUsesBuiltInVariables(t *testing.T) {
	cfg := config.Default()
	cfg.Send = &config.SendConfig{
		Source: "$DIR_NAME:$GIT_BRANCH_NAME",
		ID:     "$DIR_NAME",
	}

	runtime := sendRuntime{
		env: map[string]string{"HOME": "/Users/shadowfax"},
		cwd: "/tmp/worktrees/mac-notify",
		gitBranch: func(string) string {
			return "feature/send-config"
		},
	}

	req, err := resolveSendRequestWithRuntime(cfg, runtime, "build passed", "", "")
	if err != nil {
		t.Fatalf("resolveSendRequestWithRuntime() error = %v", err)
	}
	if req.Source != "mac-notify:feature/send-config" {
		t.Fatalf("Source = %q, want %q", req.Source, "mac-notify:feature/send-config")
	}
	if req.ID != "mac-notify" {
		t.Fatalf("ID = %q, want %q", req.ID, "mac-notify")
	}
}

func TestResolveSendRequestUsesContextCommandOutput(t *testing.T) {
	cfg := config.Default()
	cfg.Send = &config.SendConfig{
		Message:        "$MESSAGE [$TMUX_WINDOW_NAME]",
		Source:         "$TMUX_SESSION_NAME",
		ID:             "$TMUX_SESSION_NAME:$TMUX_WINDOW_NAME",
		ContextCommand: "tmux context",
	}

	runtime := sendRuntime{
		env: map[string]string{},
		cwd: "/tmp/project",
		runContext: func(command string, env map[string]string) (map[string]string, error) {
			if command != "tmux context" {
				t.Fatalf("command = %q, want %q", command, "tmux context")
			}
			if env["MESSAGE"] != "tests passed" {
				t.Fatalf("MESSAGE = %q, want %q", env["MESSAGE"], "tests passed")
			}
			return map[string]string{
				"TMUX_SESSION_NAME": "agent",
				"TMUX_WINDOW_NAME":  "editor",
			}, nil
		},
	}

	req, err := resolveSendRequestWithRuntime(cfg, runtime, "tests passed", "", "")
	if err != nil {
		t.Fatalf("resolveSendRequestWithRuntime() error = %v", err)
	}
	if req.Message != "tests passed [editor]" {
		t.Fatalf("Message = %q, want %q", req.Message, "tests passed [editor]")
	}
	if req.Source != "agent" {
		t.Fatalf("Source = %q, want %q", req.Source, "agent")
	}
	if req.ID != "agent:editor" {
		t.Fatalf("ID = %q, want %q", req.ID, "agent:editor")
	}
}

func TestResolveSendRequestRejectsInvalidContextOutput(t *testing.T) {
	cfg := config.Default()
	cfg.Send = &config.SendConfig{
		Message:        "$MESSAGE",
		ContextCommand: "bad output",
	}

	runtime := sendRuntime{
		env: map[string]string{},
		cwd: "/tmp/project",
		runContext: func(string, map[string]string) (map[string]string, error) {
			return parseContextOutput("not-an-assignment")
		},
	}

	_, err := resolveSendRequestWithRuntime(cfg, runtime, "tests passed", "", "")
	if err == nil {
		t.Fatal("resolveSendRequestWithRuntime() error = nil, want invalid context output")
	}
	if !strings.Contains(err.Error(), "invalid context_command output") {
		t.Fatalf("error = %q, want invalid context output", err)
	}
}
