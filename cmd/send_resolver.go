package cmd

import (
	"bufio"
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/nickhudkins/mac-notify/config"
	"github.com/nickhudkins/mac-notify/ipc"
)

type sendRuntime struct {
	env        map[string]string
	cwd        string
	gitBranch  func(string) string
	runContext func(string, map[string]string) (map[string]string, error)
}

func resolveSendRequest(cfg *config.Config, message, source, id string) (ipc.Request, error) {
	runtime, err := newSendRuntime()
	if err != nil {
		return ipc.Request{}, err
	}
	return resolveSendRequestWithRuntime(cfg, runtime, message, source, id)
}

func newSendRuntime() (sendRuntime, error) {
	cwd, err := os.Getwd()
	if err != nil {
		return sendRuntime{}, fmt.Errorf("get working directory: %w", err)
	}
	return sendRuntime{
		env:        envMap(os.Environ()),
		cwd:        cwd,
		gitBranch:  currentGitBranch,
		runContext: runContextCommand,
	}, nil
}

func resolveSendRequestWithRuntime(cfg *config.Config, runtime sendRuntime, message, source, id string) (ipc.Request, error) {
	sendCfg := configuredSend(cfg)
	context := buildSendContext(runtime, message, source, id)
	if err := mergeContext(sendCfg.ContextCommand, runtime.runContext, context); err != nil {
		return ipc.Request{}, err
	}

	req := ipc.Request{
		Action:  "send",
		Message: expandField(sendCfg.Message, message, context),
		Source:  expandField(sendCfg.Source, source, context),
		ID:      expandField(sendCfg.ID, id, context),
	}
	if strings.TrimSpace(req.Message) == "" {
		return ipc.Request{}, fmt.Errorf("message is required")
	}
	return req, nil
}

func configuredSend(cfg *config.Config) config.SendConfig {
	if cfg == nil || cfg.Send == nil {
		return config.SendConfig{}
	}
	return *cfg.Send
}

func buildSendContext(runtime sendRuntime, message, source, id string) map[string]string {
	context := cloneEnv(runtime.env)
	context["MESSAGE"] = message
	context["SOURCE"] = source
	context["ID"] = id
	context["CWD"] = runtime.cwd
	context["DIR_NAME"] = filepath.Base(runtime.cwd)
	context["GIT_BRANCH_NAME"] = gitBranch(runtime.gitBranch, runtime.cwd)
	return context
}

func gitBranch(resolve func(string) string, cwd string) string {
	if resolve == nil {
		return ""
	}
	return resolve(cwd)
}

func cloneEnv(env map[string]string) map[string]string {
	cloned := make(map[string]string, len(env)+6)
	for key, value := range env {
		cloned[key] = value
	}
	return cloned
}

func envMap(environ []string) map[string]string {
	env := make(map[string]string, len(environ))
	for _, entry := range environ {
		key, value, ok := strings.Cut(entry, "=")
		if ok {
			env[key] = value
		}
	}
	return env
}

func mergeContext(command string, run func(string, map[string]string) (map[string]string, error), context map[string]string) error {
	if strings.TrimSpace(command) == "" {
		return nil
	}
	if run == nil {
		return fmt.Errorf("context_command is configured but no runner is available")
	}
	values, err := run(command, context)
	if err != nil {
		return err
	}
	for key, value := range values {
		context[key] = value
	}
	return nil
}

func expandField(template, fallback string, env map[string]string) string {
	if template == "" {
		return fallback
	}
	return os.Expand(template, func(key string) string {
		return env[key]
	})
}

func currentGitBranch(cwd string) string {
	cmd := exec.Command("git", "-C", cwd, "rev-parse", "--abbrev-ref", "HEAD")
	output, err := cmd.Output()
	if err != nil {
		return ""
	}
	branch := strings.TrimSpace(string(output))
	if branch == "" || branch == "HEAD" {
		return ""
	}
	return branch
}

func runContextCommand(command string, env map[string]string) (map[string]string, error) {
	cmd := exec.Command("/bin/sh", "-c", command)
	cmd.Dir = env["CWD"]
	cmd.Env = envList(env)

	var stdout bytes.Buffer
	var stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	if err := cmd.Run(); err != nil {
		msg := strings.TrimSpace(stderr.String())
		if msg == "" {
			return nil, fmt.Errorf("context_command failed: %w", err)
		}
		return nil, fmt.Errorf("context_command failed: %s", msg)
	}
	return parseContextOutput(stdout.String())
}

func envList(env map[string]string) []string {
	list := make([]string, 0, len(env))
	for key, value := range env {
		list = append(list, key+"="+value)
	}
	return list
}

func parseContextOutput(output string) (map[string]string, error) {
	values := map[string]string{}
	scanner := bufio.NewScanner(strings.NewReader(output))
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" {
			continue
		}
		key, value, ok := strings.Cut(line, "=")
		key = strings.TrimSpace(key)
		if !ok || key == "" {
			return nil, fmt.Errorf("invalid context_command output: %q", line)
		}
		values[key] = value
	}
	if err := scanner.Err(); err != nil {
		return nil, fmt.Errorf("read context_command output: %w", err)
	}
	return values, nil
}
