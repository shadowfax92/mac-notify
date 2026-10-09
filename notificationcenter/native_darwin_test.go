package notificationcenter

import (
	"context"
	"os/exec"
	"path/filepath"
	"testing"
	"time"
)

func TestNativeAccessibilityFailureAndRestoration(t *testing.T) {
	// The standalone fixture substitutes public AX calls and a virtual clock.
	// This exercises the actual native entrypoint with loading/layout failures
	// and delayed actions, without requesting permission or changing the desktop.
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	binary := filepath.Join(t.TempDir(), "ax-fixture")
	compile := exec.CommandContext(ctx, "xcrun", "clang", "-fobjc-arc", "-framework", "AppKit", "-framework", "ApplicationServices", "testdata/ax_fixture.m", "-o", binary)
	if output, err := compile.CombinedOutput(); err != nil {
		t.Fatalf("compile native AX fixture: %v\n%s", err, output)
	}
	if output, err := exec.CommandContext(ctx, binary).CombinedOutput(); err != nil {
		t.Fatalf("native AX behavior: %v\n%s", err, output)
	}
}
