BINARY := mac-notify
GOBIN  := $(shell go env GOPATH)/bin

.PHONY: build install clean

build:
	go build -o $(BINARY) .

install: build
	cp $(BINARY) $(GOBIN)/$(BINARY)
	codesign --force --sign - $(GOBIN)/$(BINARY)
	@echo "Installed $(BINARY) to $(GOBIN)/$(BINARY)"

clean:
	rm -f $(BINARY)
