BINARY := mac-notify
GOBIN  := $(shell go env GOPATH)/bin

.PHONY: build install uninstall clean

build:
	go build -o $(BINARY) .

install: build
	cp $(BINARY) $(GOBIN)/$(BINARY)
	codesign --force --sign - $(GOBIN)/$(BINARY)
	$(GOBIN)/$(BINARY) install
	@echo "Installed $(BINARY) to $(GOBIN)/$(BINARY) (daemon started)"

uninstall:
	-$(GOBIN)/$(BINARY) uninstall
	rm -f $(GOBIN)/$(BINARY)
	@echo "Uninstalled $(BINARY)"

clean:
	rm -f $(BINARY)
