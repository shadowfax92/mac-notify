BINARY  := mac-notify
GOBIN   := $(shell go env GOPATH)/bin
APP_DIR := $(HOME)/Applications/mac-notify.app
APP_BIN := $(APP_DIR)/Contents/MacOS/$(BINARY)
FISH_FUNCTIONS ?= $(HOME)/.config/fish/functions
UID := $(shell id -u)
PLIST_LABEL := com.mac-notify.daemon
PLIST_PATH := $(HOME)/Library/LaunchAgents/$(PLIST_LABEL).plist
LEGACY_PLIST := $(HOME)/Library/LaunchAgents/com.nickhudkins.mac-notify.plist
SOCKET := $(HOME)/.mac-notify.sock

.PHONY: build install reinstall uninstall clean fish

build:
	go build -o $(BINARY) .

install: build
	@# Create .app bundle for daemon (required for macOS notifications)
	@mkdir -p $(APP_DIR)/Contents/MacOS $(APP_DIR)/Contents/Resources
	cp $(BINARY) $(APP_BIN)
	cp assets/icon.icns $(APP_DIR)/Contents/Resources/icon.icns
	codesign --force --sign - $(APP_BIN)
	@printf '<?xml version="1.0" encoding="UTF-8"?>\n\
	<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"\n\
	  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n\
	<plist version="1.0">\n\
	<dict>\n\
	    <key>CFBundleIdentifier</key>\n\
	    <string>com.nickhudkins.mac-notify</string>\n\
	    <key>CFBundleName</key>\n\
	    <string>mac-notify</string>\n\
	    <key>CFBundleExecutable</key>\n\
	    <string>mac-notify</string>\n\
	    <key>CFBundleIconFile</key>\n\
	    <string>icon</string>\n\
	    <key>LSUIElement</key>\n\
	    <true/>\n\
	</dict>\n\
	</plist>\n' > $(APP_DIR)/Contents/Info.plist
	@# Symlink CLI to GOBIN
	ln -sf $(APP_BIN) $(GOBIN)/$(BINARY)
	@# Restart daemon (stop old, start new)
	-$(APP_BIN) uninstall 2>/dev/null
	$(APP_BIN) install
	@echo "Installed $(BINARY) to $(APP_DIR) (CLI symlinked to $(GOBIN)/$(BINARY))"

reinstall:
	@$(GOBIN)/$(BINARY) uninstall 2>/dev/null || true
	@launchctl bootout gui/$(UID)/$(PLIST_LABEL) 2>/dev/null || true
	@launchctl bootout gui/$(UID) $(LEGACY_PLIST) 2>/dev/null || true
	@launchctl unload $(LEGACY_PLIST) 2>/dev/null || true
	rm -f $(PLIST_PATH) $(LEGACY_PLIST) $(SOCKET)
	rm -f $(GOBIN)/$(BINARY)
	rm -rf $(APP_DIR)
	$(MAKE) install

uninstall:
	-$(GOBIN)/$(BINARY) uninstall
	rm -f $(GOBIN)/$(BINARY)
	rm -rf $(APP_DIR)
	@echo "Uninstalled $(BINARY)"

fish:
	mkdir -p $(FISH_FUNCTIONS)
	cp mn.fish $(FISH_FUNCTIONS)/mn.fish

clean:
	rm -f $(BINARY)
