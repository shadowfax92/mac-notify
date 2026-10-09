package cmd

import (
	"errors"
	"io"
	"strings"
	"testing"

	"github.com/nickhudkins/mac-notify/ipc"
)

func TestClearCommandScopes(t *testing.T) {
	for _, tc := range []struct {
		name string
		args []string
		all  bool
	}{
		{name: "plain"},
		{name: "all", args: []string{"--all"}, all: true},
		{name: "shorthand", args: []string{"-a"}, all: true},
		{name: "explicit false", args: []string{"--all=false"}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			var ownCleared, centerCleared bool
			command := newClearCommand(func(req ipc.Request) (*ipc.Response, error) {
				if req != (ipc.Request{Action: "clear"}) {
					t.Fatalf("request = %#v, want the existing clear IPC request", req)
				}
				ownCleared = true
				return &ipc.Response{OK: true}, nil
			}, func() error {
				if !ownCleared {
					t.Fatal("Notification Center cleanup ran before the daemon cleanup")
				}
				centerCleared = true
				return nil
			})
			command.SetOut(io.Discard)
			command.SetErr(io.Discard)
			command.SetArgs(tc.args)
			if err := command.Execute(); err != nil {
				t.Fatalf("clear %v: %v", tc.args, err)
			}
			if !ownCleared || centerCleared != tc.all {
				t.Fatalf("own cleared = %v, Notification Center cleared = %v; want true, %v", ownCleared, centerCleared, tc.all)
			}
		})
	}
}

func TestClearCommandReportsFailures(t *testing.T) {
	transportError := errors.New("daemon not running")
	accessibilityError := errors.New("Accessibility permission is required: enable System Settings → Privacy & Security → Accessibility → Ghostty, then retry mac-notify clear --all")
	for _, tc := range []struct {
		name       string
		response   *ipc.Response
		sendError  error
		clearError error
		want       string
		wantCause  error
	}{
		{name: "transport", sendError: transportError, want: "daemon not running", wantCause: transportError},
		{name: "daemon rejection", response: &ipc.Response{Error: "cleanup rejected"}, want: "cleanup rejected"},
		{name: "Accessibility denied", response: &ipc.Response{OK: true}, clearError: accessibilityError,
			want: "clear Notification Center: Accessibility permission is required: enable System Settings → Privacy & Security → Accessibility → Ghostty", wantCause: accessibilityError},
	} {
		t.Run(tc.name, func(t *testing.T) {
			command := newClearCommand(func(ipc.Request) (*ipc.Response, error) {
				return tc.response, tc.sendError
			}, func() error {
				if tc.sendError != nil || !tc.response.OK {
					t.Fatal("Accessibility ran after daemon cleanup failed")
				}
				return tc.clearError
			})
			command.SetOut(io.Discard)
			command.SetErr(io.Discard)
			command.SetArgs([]string{"--all"})
			err := command.Execute()
			if err == nil || !strings.Contains(err.Error(), tc.want) {
				t.Fatalf("error = %v, want %q", err, tc.want)
			}
			if tc.wantCause != nil && !errors.Is(err, tc.wantCause) {
				t.Fatalf("error %v lost cause %v", err, tc.wantCause)
			}
		})
	}
}
