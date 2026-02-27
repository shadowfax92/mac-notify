BINARY  := mac-notify
GOBIN   := $(shell go env GOPATH)/bin
APP_DIR := $(HOME)/Applications/mac-notify.app
APP_BIN := $(APP_DIR)/Contents/MacOS/$(BINARY)

.PHONY: build install uninstall clean

build:
	go build -o $(BINARY) .

install: build
	@# Create .app bundle for daemon (required for macOS notifications)
	@mkdir -p $(APP_DIR)/Contents/MacOS
	cp $(BINARY) $(APP_BIN)
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
	    <key>LSUIElement</key>\n\
	    <true/>\n\
	</dict>\n\
	</plist>\n' > $(APP_DIR)/Contents/Info.plist
	@# Symlink CLI to GOBIN
	ln -sf $(APP_BIN) $(GOBIN)/$(BINARY)
	@# Install and start daemon
	$(APP_BIN) install
	@echo "Installed $(BINARY) to $(APP_DIR) (CLI symlinked to $(GOBIN)/$(BINARY))"

uninstall:
	-$(GOBIN)/$(BINARY) uninstall
	rm -f $(GOBIN)/$(BINARY)
	rm -rf $(APP_DIR)
	@echo "Uninstalled $(BINARY)"

clean:
	rm -f $(BINARY)
